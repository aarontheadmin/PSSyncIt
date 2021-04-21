function Sync-RelativePath {
    <#
    .SYNOPSIS
        Controller script to sync two relative paths.

    .DESCRIPTION
        Controller script to sync two relative paths. Paths can be resynced which
        will overwrite any existing objects on the target. Email notifications can
        be enabled to notify when the sync starts and ends.

        The notification contains the target label, total items to sync, removed
        stale items, and failed items.

        If there are any System.IO.Exceptions, the script is terminated and the
        exception is included in the email notification. This can indicate that there
        is not enough space on the target for the current file being copied.

        Paths and other settings can be modified in the PSPathSync.json file in the
        module root.

    .PARAMETER ResyncAll
        Force-copy of all items in source to target, overwriting any existing files
        on target.

    .PARAMETER Notify
        Enable email notification.

    .INPUTS
        None

    .OUTPUTS
        None
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]
        $ResyncAll,

        [Parameter()]
        [switch]
        $Notify,

        [Parameter()]
        [switch]
        $EjectDisk
    )


    [pscustomobject]$config               = Get-PSPathSyncConfiguration
    [string]         $referenceDirectory  = $config.Path.ReferenceDirectory
    [string]         $differenceDirectory = $config.Path.DifferenceDirectory
    [System.Array]   $directories         = @($referenceDirectory, $differenceDirectory)
    [pscustomobject] $notifier            = $config.Notification


    # test if reference and difference directories exist
    foreach ($index in (1..($directories.Count))) {

        $item = $directories[$index -1]

        if (-not (Test-Path -Path $item -PathType Container)) {

            Write-Output "Could not resolve $item"

            [string]$subject     = $notifier.DirectoryNotFound.Title
            [string]$messageBody = $notifier.DirectoryNotFound.Data -f $item

            if ($Notify.IsPresent -and [bool]$notifier.DirectoryNotFound.Active) {
                Send-EmailNotification -Subject $subject -MessageBody $messageBody
            }

            Exit
        }#if
    }#foreach

    Write-Output "All required paths found"




    Write-Verbose "ReferenceDirectory is $referenceDirectory"
    Write-Verbose "DifferenceDirectory is $differenceDirectory"


    # Get filesystem objects within ReferenceDirectory and DifferenceDirectory
    [pscustomobject]$fileSystemObjects               = Compare-RelativePath -ReferenceDirectory $referenceDirectory -DifferenceDirectory $differenceDirectory
    [pscustomobject]$fsoOnlyInReferenceDirectory     = $fileSystemObjects | Where-Object -FilterScript { $_.SideIndicator -match '^<=$' }
    [pscustomobject]$fsoOnlyInDifferenceDirectory    = $fileSystemObjects | Where-Object -FilterScript { $_.SideIndicator -match '^=>$' }
    [string]         $differenceDirectoryDriveLetter = $differenceDirectory.Substring(0, 2)
    [string]         $diffDirectoryVolumeLabel       = Get-VolumeName -DriveLetter $differenceDirectoryDriveLetter
    [pscustomobject] $syncStartedNotifier            = $notifier.SyncStartedNotifier
    [pscustomobject] $syncCompletedNotifier          = $notifier.SyncCompletedNotifier



    # If Resync specified, include all filesystem objects in ReferenceDirectory
    # even if already existing in DifferenceDirectory (forces overwriting)
    if ($ResyncAll.IsPresent) {
        Write-Verbose -Message "Resync is specified"

        [pscustomobject]$fileSystemObjectsToSync = $fileSystemObjects | Where-Object -FilterScript { $_.SideIndicator -match '^[<=]=$' }
    }#if
    else {
        # Sync filesystem objects existing only in ReferenceDirectory
        Write-Verbose -Message "Resync not specified"

        [pscustomobject]$fileSystemObjectsToSync = $fsoOnlyInReferenceDirectory
    }#else


    Remove-Variable -Name fileSystemObjects, fsoOnlyInReferenceDirectory, ResyncAll -ErrorAction SilentlyContinue



    # if enabled, send email notification that sync process has started
    if ($Notify.IsPresent -and $syncStartedNotifier.Active) {

        [string]$subject     = $syncStartedNotifier.Title
        [string]$messageBody = $syncStartedNotifier.Data -f $diffDirectoryVolumeLabel

        Send-EmailNotification -Subject $subject -MessageBody $messageBody
    }



    # Log file specifics
    [string]$moduleVersion   = Get-Module -Name PSPathSync | Select-Object -ExpandProperty Version
    [string]$hostName        = [System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName
    [string]$dateFormat      = Get-Date -UFormat %Y%m%d%H%M%S
    [string]$logPath         = $config.Path.LogPath
    [string]$logFileFullName = $logPath -f $hostName, $dateFormat
    [string]$logHeader       = @"
OFFSITE BACKUP SYNC $moduleVersion

Date`t`t: $(Get-Date)
Host`t`t: $hostName
Items to Sync`t: $($fileSystemObjectsToSync.Count)
Reference Parent`t`t: $referenceDirectory
Difference Parent`t: $differenceDirectory
**************************************************
"@

    Remove-Variable -Name dateFormat

    # Create the log file
    if (-not (Test-Path -Path $logFileFullName)) {
        try {
            New-Item -Path $logFileFullName -Value $logHeader -ErrorAction Stop
        }#try
        catch {
            Write-Error -Message $_
            break
        }#catch
    }#if



    <#
    If filesystem objects exist only in the DifferenceDirectory, remove them
    from DifferenceDirectory and log it. This ensures the DifferenceDirectory
    is in sync with the ReferenceDirectory and prevents orphaned filesystem
    objects from consuming DifferenceDirectory disk space.
    #>
    [int]$orphanedFileSystemObjectCount = 0

    if ($fsoOnlyInDifferenceDirectory.Count -gt 0) {

        [hashtable]$contentProps = @{ Path = $logFileFullName }


        # Sort collection so orphaned files are at top and directories at bottom.
        # Once all 'orphaned' files in collection are removed from DifferenceDirectory,
        # any empty folders they were in can be deleted.
        ($fsoOnlyInDifferenceDirectory | Sort-Object -Property isContainer) | & {
            process {
                try {
                    Remove-OrphanedFSObject -InputObject $_ -Confirm:$false
                }
                catch {
                    $contentProps['Value'] = "[$(Get-Date -UFormat %c)]:`tCould not deleted`t$($_.InputObject.Trim())"
                    Add-Content @contentProps
                    Continue
                }

                $contentProps['Value'] = "[$(Get-Date -UFormat %c)]:`tDeleted`t$($_.InputObject.Trim())"

                Add-Content @contentProps
            }#process
        }#invocation


        if ($?) {
            [int]$orphanedFileSystemObjectCount = $fsoOnlyInDifferenceDirectory.Count
        }#if
        else {
            [string]$orphanedFileSystemObjectCount = "$($fsoOnlyInDifferenceDirectory.Count) with errors"
        }#else
    }#if
    Remove-Variable -Name fsoOnlyInDifferenceDirectory



    # Counters
    [int]   $completedSyncCount = 0
    [int]    $failedSyncCount   = 0
    [string]$msgDetail          = $null


    # Copy filesystem objects to DifferenceDirectory
    foreach ($item in $fileSystemObjectsToSync) {

        [string]$sourceFullName       = Get-Item -Path $item.InputObject
        [string] $destinationFullName = ($sourceFullName).Replace($referenceDirectory, $differenceDirectory)

        if (($sourceFullName.PSIsContainer) -and
            (-not (Test-Path -Path $destinationFullName -PathType Container))) {

            try { New-Item -Path $destinationFullName -ItemType Directory }#try
            catch {
                [int]   $failedSyncCount  += 1
                [string]$failedFileSize    = "{0:N2} GB" -f ((Get-ChildItem -Path $sourceFullName).Length / 1GB)
                [string]$offsiteFreeSpace  = "{0:N2} GB" -f ((Get-Volume -DriveLetter ($differenceDirectoryDriveLetter -replace ':')).SizeRemaining / 1GB)
                [string]$msgDetail         = $_

                Write-Error $_
                break
            }#catch
        }#if
        else {
            Write-Output "Copying $sourceFullName to $destinationFullName"

            try { Copy-Item -Path $sourceFullName -Destination $destinationFullName -Force }#try
            catch [System.IO.IOException] {

                [int]   $failedSyncCount  += 1
                [string]$failedFileSize    = "{0:N2} GB" -f ((Get-ChildItem -Path $sourceFullName).Length / 1GB)
                [string]$offsiteFreeSpace  = "{0:N2} GB" -f ((Get-Volume -DriveLetter ($differenceDirectoryDriveLetter -replace ':')).SizeRemaining / 1GB)
                [string]$msgDetail         = $notifier.IOException.Data -f $sourceFullName, $failedFileSize, $diffDirectoryVolumeLabel, $offsiteFreeSpace

                Remove-Variable -Name differenceDirectoryDriveLetter, failedFileSize, offsiteFreeSpace

                Write-Error "Failed to copy $sourceFullName to $destinationFullName. Copy process stopped."
                break
            }#catch IOException
            catch [System.Exception] {

                [int]   $failedSyncCount += 1
                [string]$msgDetail        = $_

                Write-Error "Could not copy $sourceFullName to $destinationFullName"
                break
            }#catch
        }#else


        if ($?) {
            [int]   $completedSyncCount += 1
            [string]$copyEndTime         = Get-Date -UFormat %c

            Add-Content -Path $logFileFullName -Value "[$copyEndTime]:`tCopied`t$($destinationFullName.Trim())"

            Remove-Variable -Name copyEndTime
        }#if
        Remove-Variable -Name sourceFullName, destinationFullName

    }#foreach

    Remove-Variable -Name hostName,
    fileSystemObjectsToSync, logFileFullName,
    logHeader, logPath, differenceDirectory,
    referenceDirectory, moduleVersion
    
    # force safe removal of difference disk
    if ($EjectDisk.IsPresent) {
        $removeDriveExePath = Join-Path -Path $PSScriptRoot -ChildPath tools -AdditionalChildPath RemoveDrive.exe

        [string] $differenceDirectoryVolume = ("{0}:" -f $differenceDirectoryDriveLetter)

        & $removeDriveExePath $differenceDirectoryVolume '-f'

        if (-not (Test-Path -Path $differenceDirectoryVolume)) {
            $msgDetail += '<p>Disk safely ejected</p>'
        }
    }

    # if enabled, send notification indicating sync process has completed.
    if ($Notify.IsPresent -and $syncCompletedNotifier.Active) {

        [string]$subject     = $syncCompletedNotifier.Title
        [string]$messageBody = $syncCompletedNotifier.Data -f $diffDirectoryVolumeLabel,
        $completedSyncCount, $failedSyncCount, $orphanedFileSystemObjectCount, $msgDetail

        Send-EmailNotification -Subject $subject -MessageBody $messageBody
    }

    Remove-Variable -Name config, completedSyncCount, differenceDirectoryDriveLetter,
    failedSyncCount, message, messageBody, msgDetail,
    orphanedFileSystemObjectCount, subject, diffDirectoryVolumeLabel
}#function