function Get-PSPathSyncConfiguration {
    <#
    .SYNOPSIS
        Gets configuration info from the PSPathSync.json file.

    .DESCRIPTION
        Gets configuration info from the PSPathSync.json file and
        returns as a PSCustomObject.

    .EXAMPLE
        PS />Get-PSPathSyncConfiguration

    .INPUTS
        None

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param ()

    Write-Verbose -Message "Begin search for configurations in PSPathSync.json"

    [string]$jsonConfigPath = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath PSPathSync.config
    Write-Verbose -Message "- Path to config file pointing to JSON path is $jsonConfigPath"

    [System.IO.StreamReader]$streamReader = New-Object -TypeName System.IO.StreamReader($jsonConfigPath) -ErrorAction Stop
    Write-Verbose -Message "- Created System.IO.StreamReader object to read JSON path in $jsonConfigPath"

    [string]$jsonFilePath = $streamReader.ReadLine() -replace '.*='
    Write-Verbose -Message "- JSON config file path is $jsonFilePath"

    $streamReader.Dispose()
    Remove-Variable streamReader

    Write-Verbose -Message "- Removed System.IO.StreamReader object"

    [hashtable]$params = @{
        Raw         = $true
        Path        = $jsonFilePath
        ErrorAction = 'Stop'
    }#hashtable

    Write-Verbose -Message "- Retrieving JSON content from $jsonFilePath"

    Get-Content @params | ConvertFrom-Json

    Write-Verbose -Message "Finished search for configurations in PSPathSync.json"
}