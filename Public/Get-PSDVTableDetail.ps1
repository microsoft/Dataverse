function Get-PSDVTableDetail {
    <#
    .SYNOPSIS
    Retrieves detailed metadata for a specific Dataverse table.

    .DESCRIPTION
    Get-PSDVTableDetails fetches comprehensive metadata for a specified Dataverse table, including
    the table definition and all field/column information. It returns a detailed object containing
    table properties and a Fields collection with information about each attribute in the table.
    This function provides schema information useful for understanding table structure.

    .PARAMETER Table
    The logical name of the Dataverse table to retrieve details for.

    .EXAMPLE
    Get-PSDVTableDetails -Table "account"

    Returns detailed metadata for the Account table including all field definitions.

    .EXAMPLE
    $tableInfo = Get-PSDVTableDetails -Table "contact"
    $tableInfo.Fields.Keys

    Gets table details and lists all available field names.
    #>

    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $Table
    )

    #Get table details
    $tableLiteral = ConvertTo-PSDVODataStringLiteral -Value $Table
    try {
        $webResponse = Invoke-PSDVWebRequest  -Method Get -WebUri "EntityDefinitions(LogicalName=$tableLiteral)"
    }
    catch {
        throw "Error getting table details: $($_.InvocationInfo.MyCommand.Name), $($_ | Out-String)"
    }

    $tableDetails = $webResponse

    #get fields / column details
    try {
        $webResponse = Invoke-PSDVWebRequest  -Method Get -WebUri "EntityDefinitions(LogicalName=$tableLiteral)/Attributes"
    }
    catch {
        throw "Error getting attribute details: $($_.InvocationInfo.MyCommand.Name), $($_ | Out-String)"
    }

    $columnDetails = $webResponse
    $columnDetailsProperties = @{}

    foreach ($column in $columnDetails) {
        $columnDetailsProperties.Add($column.LogicalName, $column)
    }

    # Create a hashtable with all properties including Fields
    $allProperties = @{ Fields = $columnDetailsProperties }

    # Add all original properties from tableDetails
    foreach ($property in $tableDetails.PSObject.Properties) {
        $allProperties[$property.Name] = $property.Value
    }

    # Create new PSCustomObject with all properties
    $tableDetailsWithFields = [PSCustomObject]$allProperties

    return $tableDetailsWithFields
}
