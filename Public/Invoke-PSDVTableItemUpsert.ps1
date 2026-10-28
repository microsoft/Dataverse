function Invoke-PSDVTableItemUpsert {
    <#
    .SYNOPSIS
    Upserts a Dataverse record by alternate key.

    .DESCRIPTION
    Invoke-PSDVTableItemUpsert updates an existing record or creates a missing record by sending a PATCH request to a Dataverse alternate-key URI.
    When CreateOnly is specified, the request uses POST with the alternate key in the request body so Dataverse creates missing records and reports existing records as precondition failures.

    .PARAMETER Table
    The logical name of the Dataverse table containing the record to upsert.

    .PARAMETER EntitySet
    The entity set name of the Dataverse table (alternative to Table parameter).

    .PARAMETER AlternateKeyColumnName
    The logical name of the alternate key column.

    .PARAMETER AlternateKeyValue
    The alternate key value for the record. If omitted, the value is read from ItemData using AlternateKeyColumnName.

    .PARAMETER ItemData
    Hashtable containing the field names and values to write to the record.

    .PARAMETER ParseItemData
    When specified, automatically parses lookup field values and converts them to OData format.

    .PARAMETER ReturnItem
    When specified, returns the upserted record with current field values.

    .PARAMETER CreateOnly
    When specified, sends a POST create request with the alternate key in the request body.
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
        [ValidateNotNullOrWhiteSpace()]
        [string]
        $AlternateKeyColumnName,

        [parameter()]
        [object]
        $AlternateKeyValue,

        [parameter(Mandatory)]
        [System.Collections.Hashtable]
        $ItemData,

        [parameter()]
        [switch]
        $ParseItemData,

        [parameter()]
        [switch]
        $ReturnItem,

        [parameter()]
        [switch]
        $CreateOnly
    )

    if ($null -eq $Global:DATAVERSEACCESSTOKEN) {
        throw 'No existing connection to Dataverse Environment, run Connect-PSDVOrg before executing other PSDV cmdlets'
    }

    if ($null -eq $AlternateKeyValue -and $ItemData.ContainsKey($AlternateKeyColumnName)) {
        $AlternateKeyValue = $ItemData[$AlternateKeyColumnName]
    }

    if ($null -eq $AlternateKeyValue -or [string]$AlternateKeyValue -notmatch '\S') {
        throw 'AlternateKeyValue is required when ItemData does not include AlternateKeyColumnName.'
    }

    if (($PSCmdlet.ParameterSetName).StartsWith('TableLogicalName')) {
        $EntitySet = Get-PSDVEntitySetFromLogicalName -Table $Table
    }

    $itemDataToValidate = @{}
    foreach ($key in $ItemData.Keys) {
        $itemDataToValidate[$key] = $ItemData[$key]
    }

    if (-not $itemDataToValidate.ContainsKey($AlternateKeyColumnName)) {
        $itemDataToValidate[$AlternateKeyColumnName] = $AlternateKeyValue
    }

    $itemDataValidation = Confirm-PSDVItemDataAttributes -Table $Table -EntitySet $EntitySet -ItemData $itemDataToValidate
    $Table = $itemDataValidation.Table
    $attributeDetails = @{}

    foreach ($key in $ItemData.Keys) {
        $attributeDetails[$key] = $itemDataValidation.AttributeDetails[$key]
    }

    $itemDataForRequest = @{}
    foreach ($key in $ItemData.Keys) {
        $itemDataForRequest[$key] = $ItemData[$key]
    }

    if ($CreateOnly.IsPresent -and -not $itemDataForRequest.ContainsKey($AlternateKeyColumnName)) {
        $itemDataForRequest[$AlternateKeyColumnName] = $AlternateKeyValue
        $attributeDetails[$AlternateKeyColumnName] = $itemDataValidation.AttributeDetails[$AlternateKeyColumnName]
    }

    $itemDataToProcess = if ($ParseItemData.IsPresent) {
        ConvertTo-PSDVLookupItemData -ItemData $itemDataForRequest -AttributeDetails $attributeDetails
    }
    else {
        $itemDataForRequest
    }

    $requestHeaders = @{
        'Prefer' = 'odata.include-annotations="*"'
    }

    if ($ReturnItem.IsPresent) {
        $requestHeaders['Prefer'] = 'odata.include-annotations="*",return=representation'
    }

    $alternateKeyLiteral = ConvertTo-PSDVODataStringLiteral -Value ([string]$AlternateKeyValue)
    $dvRequestUri = if ($CreateOnly.IsPresent) { $EntitySet } else { "$EntitySet($AlternateKeyColumnName=$alternateKeyLiteral)" }
    $method = if ($CreateOnly.IsPresent) { 'Post' } else { 'Patch' }
    $shouldProcessAction = if ($CreateOnly.IsPresent) { 'Create item by alternate key' } else { 'Upsert item by alternate key' }

    if ($PSCmdlet.ShouldProcess($dvRequestUri, $shouldProcessAction)) {
        return (Invoke-PSDVWebRequest -WebUri $dvRequestUri -Headers $requestHeaders -Body $itemDataToProcess -Method $method)
    }
}