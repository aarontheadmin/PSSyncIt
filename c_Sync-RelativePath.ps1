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
        [switch]$ResyncAll,

        [Parameter()]
        [switch]$Notify
    )

    [pscustomobject]$config               = Get-PSPathSyncConfiguration
    [string]         $referenceDirectory  = $config.Path.ReferenceDirectory
    [string]         $differenceDirectory = $config.Path.DifferenceDirectory
    [pscustomobject] $message             = $config.Message

    # Check to see if the reference and difference directories are available; if unavailable,
    # email notification and stop script.
    try {
        Test-Path -Path $referenceDirectory -PathType Container -ErrorAction Stop | Out-Null
        Test-Path -Path $differenceDirectory -PathType Container -ErrorAction Stop | Out-Null
        [string]$differenceDirectoryDriveLetter = $differenceDirectory.Substring(0, 2)

        Write-Verbose "ReferenceDirectory is $referenceDirectory"
        Write-Verbose "DifferenceDirectory is $differenceDirectory"

    } # try
    catch {
        Write-Error -Message $_

        [string]$subject     = $message.TargetMissing.Title
        [string]$messageBody = $message.TargetMissing.Data -f $differenceDirectory

        if ($Notify.IsPresent) {
            Send-EmailNotification -Subject $subject -MessageBody $messageBody
        }

        Remove-Variable -Name differenceDirectoryDriveLetter, messageBody,
        differenceDirectory, referenceDirectory, subject
        Exit
    } # catch


    # Get filesystem objects within ReferenceDirectory and DifferenceDirectory
    [pscustomobject]$fileSystemObjects            = Compare-RelativePath -ReferenceDirectory $referenceDirectory -DifferenceDirectory $differenceDirectory
    [pscustomobject]$fsoOnlyInReferenceDirectory  = $fileSystemObjects | Where-Object -FilterScript { $_.SideIndicator -match '^<=$' }
    [pscustomobject]$fsoOnlyInDifferenceDirectory = $fileSystemObjects | Where-Object -FilterScript { $_.SideIndicator -match '^=>$' }


    # If Resync specified, include all filesystem objects in ReferenceDirectory
    # even if already existing in DifferenceDirectory (forces overwriting)
    if ($ResyncAll.IsPresent) {
        Write-Verbose -Message "Resync is specified"

        [pscustomobject]$fileSystemObjectsToSync = $fileSystemObjects | Where-Object -FilterScript { $_.SideIndicator -match '^[<=]=$' }
    } # if
    else {
        # Sync filesystem objects existing only in ReferenceDirectory
        Write-Verbose -Message "Resync not specified"

        [pscustomobject]$fileSystemObjectsToSync = $fsoOnlyInReferenceDirectory
    } # else

    Remove-Variable -Name fileSystemObjects, fsoOnlyInReferenceDirectory, ResyncAll -ErrorAction SilentlyContinue


    # Send email notification that sync process has started
    [string]$diffDirectoryVolumeLabel = Get-VolumeName -DriveLetter $differenceDirectoryDriveLetter
    [string]$subject                  = $message.SyncStarted.Title
    [string]$messageBody              = $message.SyncStarted.Data -f $diffDirectoryVolumeLabel

    if ($Notify.IsPresent) {
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
        } # try
        catch {
            Write-Error -Message $_
            break
        } # catch
    } # if

    <#
    If filesystem objects exist only in the DifferenceDirectory, remove them
    from DifferenceDirectory and log it. This ensures the DifferenceDirectory
    is in sync with the ReferenceDirectory and prevents orphaned filesystem
    objects from consuming DifferenceDirectory disk space.
    #>
    [uint32]$orphanedFileSystemObjectCount = 0

    if ($fsoOnlyInDifferenceDirectory.Count -gt 0) {

        [hashtable]$contentProps = @{ Path = $logFileFullName }

        # Line below sorts directory objects at end of collection. Once all
        # orphaned files are removed from DifferenceDirectory, any empty folders
        # they were in can be deleted.
        ($fsoOnlyInDifferenceDirectory | Sort-Object -Property isContainer) | & {
            process {
                Remove-OrphanedFSObject -InputObject $_ -Confirm:$false
                $contentProps['Value'] = "[$(Get-Date -UFormat %c)]:`tDeleted`t$($_.InputObject.Trim())"

                Add-Content @contentProps
            } # process
        } # invocation

        if ($?) {
            [uint32]$orphanedFileSystemObjectCount = $fsoOnlyInDifferenceDirectory.Count
        } # if
        else {
            [string]$orphanedFileSystemObjectCount = "$($fsoOnlyInDifferenceDirectory.Count) with errors"
        } # else
    } # if
    Remove-Variable -Name fsoOnlyInDifferenceDirectory


    # Counters
    [uint16]$completedSyncCount = 0
    [uint16] $failedSyncCount   = 0
    [string]$msgDetail          = $null

    # Copy filesystem objects to DifferenceDirectory
    foreach ($item in $fileSystemObjectsToSync) {

        [string]$sourceFullName       = Get-Item -Path $item.InputObject
        [string] $destinationFullName = ($sourceFullName).Replace($referenceDirectory, $differenceDirectory)

        if (($sourceFullName.PSIsContainer) -and
            (-not (Test-Path -Path $destinationFullName -PathType Container))) {

            try { New-Item -Path $destinationFullName -ItemType Directory } # try
            catch {
                [uint16]$failedSyncCount  += 1
                [string]$failedFileSize    = "{0:N2} GB" -f ((Get-ChildItem -Path $sourceFullName).Length / 1GB)
                [string]$offsiteFreeSpace  = "{0:N2} GB" -f ((Get-Volume -DriveLetter ($differenceDirectoryDriveLetter -replace ':')).SizeRemaining / 1GB)
                [string]$msgDetail         = $_

                Write-Error $_
                break
            } # catch
        } # if
        else {
            Write-Output "Copying $sourceFullName to $destinationFullName"

            try { Copy-Item -Path $sourceFullName -Destination $destinationFullName -Force } # try
            catch [System.IO.IOException] {

                [uint16]$failedSyncCount  += 1
                [string]$failedFileSize    = "{0:N2} GB" -f ((Get-ChildItem -Path $sourceFullName).Length / 1GB)
                [string]$offsiteFreeSpace  = "{0:N2} GB" -f ((Get-Volume -DriveLetter ($differenceDirectoryDriveLetter -replace ':')).SizeRemaining / 1GB)
                [string]$msgDetail         = $message.IOException.Data -f $sourceFullName, $failedFileSize, $diffDirectoryVolumeLabel, $offsiteFreeSpace

                Remove-Variable -Name differenceDirectoryDriveLetter, failedFileSize, offsiteFreeSpace

                Write-Error "Failed to copy $sourceFullName to $destinationFullName. Copy process stopped."
                break
            } # catch IOException
            catch [System.Exception] {

                [uint16]$failedSyncCount += 1
                [string]$msgDetail        = $_

                Write-Error "Could not copy $sourceFullName to $destinationFullName"
                break
            } # catch
        } # else


        if ($?) {
            [uint16]$completedSyncCount += 1
            [string]$copyEndTime         = Get-Date -UFormat %c

            Add-Content -Path $logFileFullName -Value "[$copyEndTime]:`tCopied`t$($destinationFullName.Trim())"

            Remove-Variable -Name copyEndTime
        } # if
        Remove-Variable -Name sourceFullName, destinationFullName

    } # foreach

    Remove-Variable -Name differenceDirectoryDriveLetter, hostName,
    fileSystemObjectsToSync, logFileFullName,
    logHeader, logPath, differenceDirectory,
    referenceDirectory, moduleVersion

    # Send notification indicating sync process has completed.
    [string]$subject     = $message.SyncComplete.Title
    [string]$messageBody = $message.SyncComplete.Data -f $diffDirectoryVolumeLabel,
    $completedSyncCount, $failedSyncCount, $orphanedFileSystemObjectCount, $msgDetail

    if ($Notify.IsPresent) {
        Send-EmailNotification -Subject $subject -MessageBody $messageBody
    }

    Remove-Variable -Name config, completedSyncCount,
    failedSyncCount, message, messageBody, msgDetail,
    orphanedFileSystemObjectCount, subject, diffDirectoryVolumeLabel
} # function