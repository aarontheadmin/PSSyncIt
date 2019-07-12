function Get-VolumeName {
    <#
    .SYNOPSIS
        Gets the volume name.

    .DESCRIPTION
        Gets the volume name based on the specified drive letter, including the
        colon (:), using CIM.

    .PARAMETER DriveLetter
        The drive letter to get the volume name for.

    .EXAMPLE
        PS />Get-VolumeName -DriveLetter C:

    .INPUTS
        None

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ (Get-PSDrive -Name ($_ -replace ':')) })]
        [string]$DriveLetter
    )

    [hashtable]$props = @{
        ClassName = 'Win32_LogicalDisk'
        Filter    = "DeviceId='$DriveLetter'"
    } # hashtable

    Get-CimInstance @props | Select-Object -ExpandProperty VolumeName

    Remove-Variable props
} # function