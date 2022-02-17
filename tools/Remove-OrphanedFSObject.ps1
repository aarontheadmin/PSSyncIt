function Remove-OrphanedFSObject {
    <#
    .SYNOPSIS
        Removes an orphaned filesystem object.

    .DESCRIPTION
        Removes an orphaned filesystem object when used with Compare-PSSync.

        Remove-OrphanedFSObject is intended for output objects from Compare-PSSync.
        When Compare-PSSync outputs an item (filesystem object) with the
        SideIndicator '=>', this indicates the item (filesystem object) exists only within
        the Destination, and is therefore considered out-of-sync with the
        Path. Thus, the orphaned object can be removed from the filesystem of
        the Destination.

        Note: Remove-OrphanedFSObject will only process items where the SideIndicator is '=>'.

        Deleting Directories: As long as a directory is empty (except for .DS_Store), it can
        be deleted.

    .PARAMETER InputObject
        The array object containing the full path of the filesystem object(s) to be removed,
        and the SideIndicator '=>'.

    .EXAMPLE
        PS />Remove-OrphanedFSObject -InputObject @{ InputObject = 'C:\backups\oldbackup.spf'; SideIndicator = '=>' }

        The example above shows that the file 'C:\backups\oldbackup.spf' will be removed as indicated
        by the SideIndicator = '=>'.

    .EXAMPLE
        PS />$pathDir = 'E:\Work\Backups'
        PS />$destinationDir = 'G:\Backups'
        PS />Compare-PSSync -Path $pathDir -destination $destinationDir | Remove-OrphanedFSObject

        The example above shows the (recursive) content of 'E:\Work\Backups' is compared to the contents in 'G:\Backups'. The
        output objects of Compare-PSSync are piped to Remove-OrphanedFSObject where any of the objects with the
        SideIndicator of '=>' are deleted from the filesystem.

    .INPUTS
        System.Array

    .OUTPUTS
        None
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript( {
            ($_.SideIndicator -match '^(=>)$') -and (Test-Path -Path $_.InputObject)
        })]
        [pscustomobject[]]$InputObject
    )

    PROCESS {
        foreach ($fsoObject in $InputObject) {

            [string]$fullName = $fsoObject.InputObject

            switch ($fullName) {
                # Item is a file
                { (-not (Get-Item -Path $_).PSIsContainer) } {

                    if ($PSCmdlet.ShouldProcess("Delete file")) {
                        Remove-Item -Path $fullName -Confirm:$false -Force
                        Write-Verbose -Message "Deleted file $_"
                    }
                    break
                } # switch condition
                # Item is an empty directory (can be deleted)
                { ((Get-ChildItem -Path $_ -Exclude '.DS_Store').Count -eq 0) } {

                    if ($PSCmdlet.ShouldProcess("Delete empty directory")) {
                        Remove-Item -Path $fullName -Force
                        Write-Verbose -Message "Deleted empty directory $_"
                    }
                    break
                } # switch condition
            } # switch
        } # foreach
    } # PROCESS
} # function