function Compare-PSSync {
    <#
    .SYNOPSIS
        Compares content between two relative paths.

    .DESCRIPTION
        Compare-PSSync recursively compares all child items between
        two relative directory structures that are meant to be identical.
        The intent is to ensure the Destination (target) is always in
        sync with the Path (source), such as cloning a repo or
        backup sets to an offsite medium.

        If there are no destinations between the Path and Destination
        structures, recursively, the output will be blank.

    .PARAMETER Path
        The path to the path directory. This should point to the parent directory.
        The structure within the parent directory should be identical to
        -Destination.

    .PARAMETER Destination
        The path to destination directory. This should point to the parent directory.
        The structure within the parent directory should be identical to
        -Path.

    .EXAMPLE
        PS />Compare-PSSync -Path C:\MyScripts\ -Destination E:\Backups\MyScripts

        The example above will compare all items within C:\MyScripts to all items in
        E:\Backups\MyScripts, recursively, and will output any destinations it finds.

        The parent directory for Path and Destination is MyScripts.
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
        [System.IO.DirectoryInfo]$Path,

        [Alias('DifferenceObject')]
        [Parameter(Mandatory)]
        [ValidateScript( { Test-Path -Path $_ -PathType Container } )]
        [System.IO.DirectoryInfo]$Destination,

        [Parameter()]
        [switch]$IncludeEqual
    )

    # Store all (recursive) full paths existing in the Path and Destination into two separate hashtables (as the
    # key names), respectively. The default Value for Path keys is '<='. The default Value for Destination keys is $null.

    # Loop through all keys (full paths) in the Destination hashtable. For each key (full path), append its relative path
    # portion to the specified Path, constructing a potential path of the same object but within the Path.
    # Check if the newly constructed path exists as a key (full path) in the Path hashtable. If it exists, remove it from the
    # hashtable but output to host. If the path does not exist in the Path hashtable, output only the path in the
    # Destination with a SideIndicator of '=>'. If the relative path exists in both hashtables, and the -IncludeEqual is specified,
    # both objects will output with the SideIndicator of '=='.

    # Store each child object existing in Path into hashtable as Key and set the Value to '<='
    # as the default.
    [hashtable]$syncSourcePathChildren = @{ }
    Get-ChildItem -Path $Path -Recurse | & { process { $syncSourcePathChildren[$_.FullName] = '<=' } }

    # Store each child object existing in Destination into hashtable as key and set the Value to
    # $null - Value to be modified later.
    [hashtable]$syncDestinationPathChildren = @{ }
    Get-ChildItem -Path $Destination -Recurse | & { process { $syncDestinationPathChildren[$_.FullName] = $null } }

    # Loop through all Keys (full paths) in hashtable containing Destination child objects.
    foreach ($destinationChildObject in $syncDestinationPathChildren.Keys) {

        # Get the relative path from the current child object by removing the Destination portion, and append the
        # relative path to the specified Path path. This constructs the full path of the same child object but
        # in the Path.
        [string]$relativePath = $destinationChildObject.Replace($Destination, '')
        [string]$PathFullName = Join-Path -Path $path -ChildPath $relativePath
        [bool]   $isContainer = $false # default object type to file

        # Check if current Destination is a directory (otherwise it's a file)
        if ((Get-Item -Path $destinationChildObject) -is [System.IO.DirectoryInfo]) {
            $isContainer = $true
        } # if


        # Create hashtable to store 'final output' objects. Set object type (directory or file).
        [hashtable]$comparedObjectProps = @{
            InputObject   = $null
            PSIsContainer = $isContainer
        } # hashtable


        # Check the newly constructed Path path against the hashtable containing the actual
        # Path objects (by Key name).
        switch ($PathFullName) {
            { $syncSourcePathChildren.ContainsKey($_) } {

                # Object exists in hashtable (as Key) containing Path objects. Object is
                # added to 'final output' hashtable.

                # Remove object from Path hashtable as it has been processed.
                $syncSourcePathChildren.Remove($_)

                if ($IncludeEqual.IsPresent) {
                    # The object's full path exists in the Path and Destination; set
                    # SideIndicator to '=='.
                    $comparedObjectProps.SideIndicator = '=='

                    # Output both object's full paths.
                    $comparedObjectProps.InputObject = $destinationChildObject
                    New-Object -TypeName psobject -Property $comparedObjectProps

                    $comparedObjectProps.InputObject = $PathFullName
                    New-Object -TypeName psobject -Property $comparedObjectProps
                }
                break
            }
            { (-not ($syncSourcePathChildren.ContainsKey($_))) } {

                # Object full path does not exist in hashtable containing Path objects.
                # Assign '=>' as SideIndicator and output only the Destination object.
                $comparedObjectProps.SideIndicator = '=>'
                $comparedObjectProps.InputObject   = $destinationChildObject

                New-Object -TypeName psobject -Property $comparedObjectProps
                break
            }
        } # switch
    } # foreach


    # Loop through all Keys in hashtable containing Path child objects
    # and output to host. This is to process the remaining objects in the
    # Path hashtable that were not compared against the Destination
    # hashtable objects above.
    foreach ($pathChildObject in $syncSourcePathChildren.GetEnumerator()) {
        [bool]$isContainer = $false

        # Check if object is a directory (otherwise it's a file)
        if ((Get-Item -Path $pathChildObject.Key) -is [System.IO.DirectoryInfo]) {
            $isContainer = $true
        } # if


        # Create hashtable of properties
        [hashtable]$comparedObjectProps = @{
            InputObject   = $pathChildObject.Key
            PSIsContainer = $isContainer
            SideIndicator = $pathChildObject.Value
        } # hashtable

        New-Object -TypeName psobject -Property $comparedObjectProps
    } # foreach
} # function