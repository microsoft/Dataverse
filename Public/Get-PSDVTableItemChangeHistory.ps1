function Get-PSDVTableItemChangeHistory {
    <#
    .SYNOPSIS
    Retrieves detailed change history for a specific Dataverse record.

    .DESCRIPTION
    Get-PSDVTableItemChangeHistory uses the RetrieveRecordChangeHistory API to fetch comprehensive
    change details for a specific record. Unlike audit history, this function provides detailed
    information about what specific field values were changed, including before and after values.
    This function requires auditing to be enabled and provides more granular change tracking.

    .PARAMETER Table
    The logical name of the Dataverse table containing the record.

    .PARAMETER EntitySet
    The entity set name of the Dataverse table (alternative to Table parameter).

    .PARAMETER ItemID
    The unique identifier (GUID) of the record to retrieve change history for.

    .EXAMPLE
    Get-PSDVTableItemChangeHistory -Table "account" -ItemID "12345678-1234-1234-1234-123456789012"

    Retrieves detailed change history for a specific account record.

    .EXAMPLE
    Get-PSDVTableItemChangeHistory -EntitySet "contacts" -ItemID "87654321-4321-4321-4321-210987654321"

    Retrieves change history using entity set name instead of logical name.
    #>

    [CmdletBinding()]
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

    $targetJson = @{ '@odata.id' = "$EntitySet($ItemID)" } | ConvertTo-Json -Compress
    $targetQuery = Join-PSDVQueryString -QueryParameters ([ordered]@{ '@target' = $targetJson })
    $dvRequestUri = "RetrieveRecordChangeHistory(Target=@target)?$targetQuery"

    $webResponse = Invoke-PSDVWebRequest -WebUri  $dvRequestUri -Headers $requestHeaders -Method 'Get'

    if ($webResponse.AuditDetailCollection.count -gt 0) {
        return $webResponse.AuditDetailCollection
    }
    else {
        return $webResponse
    }
}
