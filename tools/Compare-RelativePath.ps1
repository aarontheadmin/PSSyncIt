function Compare-RelativePath {
    <#
    .SYNOPSIS
        Compares content between two relative paths.

    .DESCRIPTION
        Compare-RelativePath recursively compares all child items between
        two relative directory structures that are meant to be identical.
        The intent is to ensure the DifferenceObject (target) is always in
        sync with the ReferenceObject (source), such as cloning a repo or
        backup sets to an offsite medium.

        If there are no differences between the ReferenceDirectory and DifferenceDirectory
        structures, recursively, the output will be blank.

    .PARAMETER ReferenceDirectory
        The path to the reference directory. This should point to the parent directory.
        The structure within the parent directory should be identical to
        -DifferenceDirectory.

    .PARAMETER DifferenceDirectory
        The path to difference directory. This should point to the parent directory.
        The structure within the parent directory should be identical to
        -ReferenceDirectory.

    .EXAMPLE
        PS />Compare-RelativePath -ReferenceDirectory C:\MyScripts\ -DifferenceDirectory E:\Backups\MyScripts

        The example above will compare all items within C:\MyScripts to all items in
            E:\Backups\MyScripts, recursively, and will output any differences it finds.

        The parent directory for ReferenceDirectory and DifferenceDirectory is MyScripts.
        These parent directory names do not have to match but the relative structure within
        them do.

    .INPUTS
        None

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    param (
        [Alias('ReferenceObject')]
        [Parameter(Mandatory)]
        [ValidateScript( { Test-Path -Path $_ -PathType Container } )]
        [System.IO.DirectoryInfo]$ReferenceDirectory,

        [Alias('DifferenceObject')]
        [Parameter(Mandatory)]
        [ValidateScript( { Test-Path -Path $_ -PathType Container } )]
        [System.IO.DirectoryInfo]$DifferenceDirectory,

        [Parameter()]
        [switch]$IncludeEqual
    )

    # Store all (recursive) full paths existing in the ReferenceDirectory and DifferenceDirectory into two separate hashtables (as the
    # key names), respectively. The default Value for ReferenceDirectory keys is '<='. The default Value for DifferenceDirectory keys is $null.

    # Loop through all keys (full paths) in the DifferenceDirectory hashtable. For each key (full path), append its relative path
    # portion to the specified ReferenceDirectory, constructing a potential path of the same object but within the ReferenceDirectory.
    # Check if the newly constructed path exists as a key (full path) in the ReferenceDirectory hashtable. If it exists, remove it from the
    # hashtable but output to host. If the path does not exist in the ReferenceDirectory hashtable, output only the path in the
    # DifferenceObject with a SideIndicator of '=>'. If the relative path exists in both hashtables, and the -IncludeEqual is specified,
    # both objects will output with the SideIndicator of '=='.

    # Store each child object existing in ReferenceDirectory into hashtable as Key and set the Value to '<='
    # as the default.
    [hashtable]$referenceDirectoryChildren = @{ }
    Get-ChildItem -Path $ReferenceDirectory -Recurse | & { process { $referenceDirectoryChildren[$_.FullName] = '<=' } }

    # Store each child object existing in DifferenceDirectory into hashtable as key and set the Value to
    # $null - Value to be modified later.
    [hashtable]$differenceDirectoryChildren = @{ }
    Get-ChildItem -Path $DifferenceDirectory -Recurse | & { process { $differenceDirectoryChildren[$_.FullName] = $null } }


    # Loop through all Keys (full paths) in hashtable containing DifferenceDirectory child objects.
    foreach ($differenceChildObject in $differenceDirectoryChildren.Keys) {

        # Get the relative path from the current child object by removing the DifferenceDirectory portion, and append the
        # relative path to the specified ReferenceDirectory path. This constructs the full path of the same child object but
        # in the ReferenceDirectory.
        [string]$relativePath            = $differenceChildObject.Replace($DifferenceDirectory, '')
        [string]$referenceObjectFullName = Join-Path -Path $ReferenceDirectory -ChildPath $relativePath
        [bool]   $isContainer            = $false # default object type to file

        # Check if current DifferenceObject is a directory (otherwise it's a file)
        if ((Get-Item -Path $differenceChildObject) -is [System.IO.DirectoryInfo]) {
            $isContainer = $true
        } # if


        # Create hashtable to store 'final output' objects. Set object type (directory or file).
        [hashtable]$comparedObjectProps = @{
            InputObject   = $null
            PSIsContainer = $isContainer
        } # hashtable


        # Check the newly constructed ReferenceDirectory path against the hashtable containing the actual
        # ReferenceDirectory objects (by Key name).
        switch ($referenceObjectFullName) {
            { $referenceDirectoryChildren.ContainsKey($_) } {

                # Object exists in hashtable (as Key) containing ReferenceDirectory objects. Object is
                # added to 'final output' hashtable.

                # Remove object from ReferenceDirectory hashtable as it has been processed.
                $referenceDirectoryChildren.Remove($_)

                if ($IncludeEqual.IsPresent) {
                    # The object's full path exists in the ReferenceDirectory and DifferenceDirectory; set
                    # SideIndicator to '=='.
                    $comparedObjectProps.SideIndicator = '=='

                    # Output both object's full paths.
                    $comparedObjectProps.InputObject = $differenceChildObject
                    New-Object -TypeName psobject -Property $comparedObjectProps

                    $comparedObjectProps.InputObject = $referenceObjectFullName
                    New-Object -TypeName psobject -Property $comparedObjectProps
                }
                break
            }
            { (-not ($referenceDirectoryChildren.ContainsKey($_))) } {

                # Object full path does not exist in hashtable containing ReferenceDirectory objects.
                # Assign '=>' as SideIndicator and output only the DifferenceDirectory object.
                $comparedObjectProps.SideIndicator = '=>'
                $comparedObjectProps.InputObject   = $differenceChildObject

                New-Object -TypeName psobject -Property $comparedObjectProps
                break
            }
        } # switch
    } # foreach


    # Loop through all Keys in hashtable containing ReferenceDirectory child objects
    # and output to host. This is to process the remaining objects in the
    # ReferenceDirectory hashtable that were not compared against the DifferenceDirectory
    # hashtable objects above.
    foreach ($referenceChildObject in $referenceDirectoryChildren.GetEnumerator()) {
        [bool]$isContainer = $false

        # Check if object is a directory (otherwise it's a file)
        if ((Get-Item -Path $referenceChildObject.Key) -is [System.IO.DirectoryInfo]) {
            $isContainer = $true
        } # if


        # Create hashtable of properties
        [hashtable]$comparedObjectProps = @{
            InputObject   = $referenceChildObject.Key
            PSIsContainer = $isContainer
            SideIndicator = $referenceChildObject.Value
        } # hashtable

        New-Object -TypeName psobject -Property $comparedObjectProps
    } # foreach
} # function