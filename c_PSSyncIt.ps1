function Get-PSSyncItSetting {
    <#
    .SYNOPSIS
        Gets configuration info from the PSSyncIt.json file.

    .DESCRIPTION
        Gets configuration info from the PSSyncIt.json file and
        returns as a PSCustomObject.

    .EXAMPLE
        PS />Get-PSSyncItSetting

    .INPUTS
        None

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param ()

    Write-Verbose -Message "Begin search for configurations in PSSyncIt.json"

    [string]$jsonFilePath = join-Path -Path $PSScriptRoot -ChildPath SyncIt.json
    Write-Verbose -Message "- JSON config file path is $jsonFilePath"

    [hashtable]$params = @{
        Raw         = $true
        Path        = $jsonFilePath
        ErrorAction = 'Stop'
    }#hashtable

    Write-Verbose -Message "- Retrieving JSON content from $jsonFilePath"

    Get-Content @params | ConvertFrom-Json

    Write-Verbose -Message "Finished search for configurations in PSSyncIt.json"
}


function Send-EmailNotification {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Subject,

        [Parameter(Mandatory)]
        [string]$MessageBody
    )

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 # modern HTTPS requests
    [pscustomobject]                 $notification     = Get-PSSyncItSetting | Select-Object -ExpandProperty Notification
    [string]                         $senderEmail      = $notification.SenderEmail

    New-Variable -Name secureString -Visibility Private -Value ($notification.SenderAccountPasswordSecureString | ConvertTo-SecureString)

    [pscredential]$credential = New-Object System.Management.Automation.PSCredential -ArgumentList $senderEmail, $secureString

    Remove-Variable -Name secureString

    [hashtable]$params = @{
        To         = [string]$notification.RecipientAddress
        SmtpServer = [string]$notification.SmtpServer
        Credential = $credential
        UseSsl     = [bool]$notification.UseSSL
        Subject    = $subject
        Port       = [uint16]$notification.SenderPort
        Body       = $MessageBody
        From       = $senderEmail
        BodyAsHtml = $true
    } # hashtable

    Send-MailMessage @params

    Remove-Variable credential, notification, params, senderEmail
} # function



function Sync-It {
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

        Paths and other settings can be modified in the PSSyncIt.json file in the
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


    [pscustomobject]$config               = Get-PSSyncItSetting
    [string]         $syncSourcePath      = $config.Path.Source
    [string]         $syncDestinationPath = $config.Path.Destination
    [System.Array]   $directories         = @($syncSourcePath, $syncDestinationPath)
    [pscustomobject] $notifier            = $config.Notification


    # test if path and destination directories exist
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




    Write-Verbose "Path is $syncSourcePath"
    Write-Verbose "Destination is $syncDestinationPath"


    # Get filesystem objects within Path and Destination
    [pscustomobject]$fileSystemObjects               = Compare-PSSync -Path $syncSourcePath -Destination $syncDestinationPath
    [pscustomobject]$fsoOnlyInPath                   = $fileSystemObjects | Where-Object -FilterScript { $_.SideIndicator -match '^<=$' }
    [pscustomobject]$fsoOnlyInDestination            = $fileSystemObjects | Where-Object -FilterScript { $_.SideIndicator -match '^=>$' }
    [string]         $syncDestinationPathDriveLetter = $syncDestinationPath.Substring(0, 2)
    [string]         $diffDirectoryVolumeLabel       = Get-VolumeName -DriveLetter $syncDestinationPathDriveLetter
    [pscustomobject] $syncStartedNotifier            = $notifier.SyncStartedNotifier
    [pscustomobject] $syncCompletedNotifier          = $notifier.SyncCompletedNotifier



    # If Resync specified, include all filesystem objects in Path
    # even if already existing in Destination (forces overwriting)
    if ($ResyncAll.IsPresent) {
        Write-Verbose -Message "Resync is specified"

        [pscustomobject]$fileSystemObjectsToSync = $fileSystemObjects | Where-Object -FilterScript { $_.SideIndicator -match '^[<=]=$' }
    }#if
    else {
        # Sync filesystem objects existing only in Path
        Write-Verbose -Message "Resync not specified"

        [pscustomobject]$fileSystemObjectsToSync = $fsoOnlyInPath
    }#else


    Remove-Variable -Name fileSystemObjects, fsoOnlyInPath, ResyncAll -ErrorAction SilentlyContinue



    # if enabled, send email notification that sync process has started
    if ($Notify.IsPresent -and $syncStartedNotifier.Active) {

        [string]$subject     = $syncStartedNotifier.Title
        [string]$messageBody = $syncStartedNotifier.Data -f $diffDirectoryVolumeLabel

        Send-EmailNotification -Subject $subject -MessageBody $messageBody
    }



    # Log file specifics
    [string]$moduleVersion   = Get-Module -Name PSSyncIt | Select-Object -ExpandProperty Version
    [string]$hostName        = [System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName
    [string]$dateFormat      = Get-Date -UFormat %Y%m%d%H%M%S
    [string]$logPath         = $config.Path.LogPath
    [string]$logFileFullName = $logPath -f $hostName, $dateFormat
    [string]$logHeader       = @"
OFFSITE BACKUP SYNC $moduleVersion

Date`t`t: $(Get-Date)
Host`t`t: $hostName
Items to Sync`t: $($fileSystemObjectsToSync.Count)
Source Path Parent`t`t: $syncSourcePath
Destination Parent`t: $syncDestinationPath
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
    If filesystem objects exist only in the Destination, remove them
    from Destination and log it. This ensures the Destination
    is in sync with the Path and prevents orphaned filesystem
    objects from consuming Destination disk space.
    #>
    [int]$orphanedFileSystemObjectCount = 0

    if ($fsoOnlyInDestination.Count -gt 0) {

        [hashtable]$contentProps = @{ Path = $logFileFullName }


        # Sort collection so orphaned files are at top and directories at bottom.
        # Once all 'orphaned' files in collection are removed from Destination,
        # any empty folders they were in can be deleted.
        ($fsoOnlyInDestination | Sort-Object -Property isContainer) | & {
            process {
                try {
                    Remove-OrphanedFSObject -InputObject $_ -Confirm: $false
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
            [int]$orphanedFileSystemObjectCount = $fsoOnlyInDestination.Count
        }#if
        else {
            [string]$orphanedFileSystemObjectCount = "$($fsoOnlyInDestination.Count) with errors"
        }#else
    }#if
    Remove-Variable -Name fsoOnlyInDestination



    # Counters
    [int]    $completedSyncCount = 0
    [int]    $failedSyncCount    = 0
    [string]$msgDetail           = $null


    # Copy filesystem objects to Destination
    foreach ($item in $fileSystemObjectsToSync) {

        [string]$sourceFullName       = Get-Item -Path $item.InputObject
        [string] $destinationFullName = ($sourceFullName).Replace($syncSourcePath, $syncDestinationPath)

        if (($sourceFullName.PSIsContainer) -and
            (-not (Test-Path -Path $destinationFullName -PathType Container))) {

            try { New-Item -Path $destinationFullName -ItemType Directory }#try
            catch {
                [int]    $failedSyncCount += 1
                [string]$failedFileSize    = "{0:N2} GB" -f ((Get-ChildItem -Path $sourceFullName).Length / 1GB)
                [string]$offsiteFreeSpace  = "{0:N2} GB" -f ((Get-Volume -DriveLetter ($syncDestinationPathDriveLetter -replace ':')).SizeRemaining / 1GB)
                [string]$msgDetail         = $_

                Write-Error $_
                break
            }#catch
        }#if
        else {
            Write-Output "Copying $sourceFullName to $destinationFullName"

            try { Copy-Item -Path $sourceFullName -Destination $destinationFullName -Force }#try
            catch [System.IO.IOException] {

                [int]    $failedSyncCount += 1
                [string]$failedFileSize    = "{0:N2} GB" -f ((Get-ChildItem -Path $sourceFullName).Length / 1GB)
                [string]$offsiteFreeSpace  = "{0:N2} GB" -f ((Get-Volume -DriveLetter ($syncDestinationPathDriveLetter -replace ':')).SizeRemaining / 1GB)
                [string]$msgDetail         = $notifier.IOException.Data -f $sourceFullName, $failedFileSize, $diffDirectoryVolumeLabel, $offsiteFreeSpace

                Remove-Variable -Name DestinationDriveLetter, failedFileSize, offsiteFreeSpace

                Write-Error "Failed to copy $sourceFullName to $destinationFullName. Copy process stopped."
                break
            }#catch IOException
            catch [System.Exception] {

                [int]    $failedSyncCount += 1
                [string]$msgDetail         = $_

                Write-Error "Could not copy $sourceFullName to $destinationFullName"
                break
            }#catch
        }#else


        if ($?) {
            [int]    $completedSyncCount += 1
            [string]$copyEndTime          = Get-Date -UFormat %c

            Add-Content -Path $logFileFullName -Value "[$copyEndTime]:`tCopied`t$($destinationFullName.Trim())"

            Remove-Variable -Name copyEndTime
        }#if
        Remove-Variable -Name sourceFullName, destinationFullName

    }#foreach

    Remove-Variable -Name hostName,
    fileSystemObjectsToSync, logFileFullName,
    logHeader, logPath, Destination,
    Path, moduleVersion
    
    # force safe removal of destination disk
    if ($EjectDisk.IsPresent) {
        $removeDriveExePath = Join-Path -Path $PSScriptRoot -ChildPath tools -AdditionalChildPath RemoveDrive.exe

        [string] $syncDestinationPathVolume = ("{0}:" -f $syncDestinationPathDriveLetter)

        & $removeDriveExePath $syncDestinationPathVolume '-f'

        if (-not (Test-Path -Path $syncDestinationPathVolume)) {
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

    Remove-Variable -Name config, completedSyncCount, DestinationDriveLetter,
    failedSyncCount, message, messageBody, msgDetail,
    orphanedFileSystemObjectCount, subject, diffDirectoryVolumeLabel
}#function