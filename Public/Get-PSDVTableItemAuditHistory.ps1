function Get-PSDVTableItemAuditHistory {
    <#
    .SYNOPSIS
    Retrieves audit history for a specific Dataverse record.

    .DESCRIPTION
    Get-PSDVTableItemAuditHistory fetches the audit trail for a specific record in a Dataverse table.
    It returns audit information including who made changes, when changes were made, and what operations
    were performed. This function is useful for compliance, troubleshooting, and tracking data modifications.
    Auditing must be enabled on the table and fields for this function to return meaningful data.

    .PARAMETER Table
    The logical name of the Dataverse table containing the record.

    .PARAMETER ItemID
    The unique identifier (GUID) of the record to retrieve audit history for.

    .PARAMETER Select
    Array of audit field names to include in the response.

    .EXAMPLE
    Get-PSDVTableItemAuditHistory -Table "account" -ItemID "12345678-1234-1234-1234-123456789012"

    Retrieves all audit history for a specific account record.

    .EXAMPLE
    Get-PSDVTableItemAuditHistory -Table "contact" -ItemID "87654321-4321-4321-4321-210987654321" -Select @("createdon", "createdby", "operation")

    Retrieves specific audit fields for a contact record.
    #>

    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $Table,

        [parameter(Mandatory)]
        [ValidateScript({ $_ -ne [guid]::Empty }, ErrorMessage = 'ItemID cannot be an empty GUID.')]
        [Guid]
        $ItemID,

        [parameter()]
        [String[]]
        $Select
    )

    if ($null -eq $Global:DATAVERSEACCESSTOKEN) {
        throw 'No existing connection to Dataverse Environment, run Connect-PSDVOrg before executing other PSDV cmdlets'
    }

    foreach ($column in $Select) {
        if ($column -notmatch '\S') {
            throw 'Select entries cannot be null, empty, or whitespace.'
        }
    }

    $requestHeaders = @{'Prefer' = 'odata.include-annotations="*"' }

    $tableLiteral = ConvertTo-PSDVODataStringLiteral -Value $Table
    $queryFilter = "objecttypecode eq $tableLiteral and _objectid_value eq $ItemID"

    if ($PSBoundParameters.ContainsKey('Select')) {
      $selectQuery = $Select -join ','
    }

    $invokeParameters = @{
        WebUri  = 'audits'
        Headers = $requestHeaders
        Method  = 'Get'
        Filter  = $queryFilter
    }

    if (-not [string]::IsNullOrWhiteSpace($selectQuery)) {
        $invokeParameters.Select = $selectQuery
    }

    return (Invoke-PSDVWebRequest @invokeParameters)

}
