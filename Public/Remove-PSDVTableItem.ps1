function Remove-PSDVTableItem {
    <#
    .SYNOPSIS
    Deletes a record from a Dataverse table.

    .DESCRIPTION
    Remove-PSDVTableItem removes a specific record from the specified Dataverse table using the record's
    unique identifier. The function supports both logical name and entity set name parameter sets for
    table identification. Once deleted, the record cannot be recovered unless it's restored from a backup
    or the Dataverse recycle bin (if available and not expired).

    .PARAMETER Table
    The logical name of the Dataverse table containing the record to delete.

    .PARAMETER EntitySet
    The entity set name of the Dataverse table (alternative to Table parameter).

    .PARAMETER ItemID
    The unique identifier (GUID) of the record to delete.

    .EXAMPLE
    Remove-PSDVTableItem -Table "account" -ItemID "12345678-1234-1234-1234-123456789012"

    Deletes a specific account record by its ID.

    .EXAMPLE
    Remove-PSDVTableItem -EntitySet "contacts" -ItemID "87654321-4321-4321-4321-210987654321"

    Deletes a contact record using entity set name instead of logical name.

    .EXAMPLE
    Get-PSDVTableItem -Table "account" -Filter "name eq 'Test Account'" | ForEach-Object {
        Remove-PSDVTableItem -Table "account" -ItemID $_.accountid
    }

    Finds and deletes all accounts named "Test Account".
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
         [parameter(Mandatory, ParameterSetName = 'TableLogicalName')]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $Table,

        [parameter(Mandatory, ParameterSetName = 'TableEntitySetName')]
        [ValidateNotNullOrWhiteSpace()]
        [string]
        $EntitySet,

        [parameter(Mandatory)]
        [ValidateScript({ $_ -ne [guid]::Empty }, ErrorMessage = 'ItemID cannot be an empty GUID.')]
        [Guid]
        $ItemID
    )

    if ($null -eq $Global:DATAVERSEACCESSTOKEN) {
        throw 'No existing connection to Dataverse Environment, run Connect-PSDVOrg before executing other PSDV cmdlets'
    }


    if (($PSCmdlet.ParameterSetName).StartsWith('TableLogicalName')) {
        $EntitySet = Get-PSDVEntitySetFromLogicalName -Table $Table
    }


    $requestHeaders = @{'Prefer' = 'odata.include-annotations="*"' }


    #build the dv web query
    $dvRequestUri = "$EntitySet($ItemID)"

    if ($PSCmdlet.ShouldProcess("$EntitySet($ItemID)", "Delete item")) {
        return (Invoke-PSDVWebRequest -WebUri  $dvRequestUri -Headers $requestHeaders -Method 'Delete' )
    }
}
