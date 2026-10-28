function Invoke-PSDVTableItemUpsertBatch {
    <#
    .SYNOPSIS
    Upserts multiple Dataverse records by alternate key in a single OData batch request.
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

        [parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Items,

        [parameter()]
        [switch]
        $ParseItemData,

        [parameter()]
        [switch]
        $CreateOnly
    )

    if ($null -eq $Global:DATAVERSEACCESSTOKEN) {
        throw 'No existing connection to Dataverse Environment, run Connect-PSDVOrg before executing other PSDV cmdlets'
    }

    $itemsToProcess = @($Items | Where-Object { $null -ne $_ })
    if ($itemsToProcess.Count -eq 0) {
        return (ConvertFrom-PSDVBatchResponse -BatchResponse $null -ExpectedCount 0)
    }

    $resolvedItems = [System.Collections.Generic.List[object]]::new()
    $combinedItemData = @{}

    foreach ($item in $itemsToProcess) {
        if ($item -is [System.Collections.IDictionary]) {
            $alternateKeyValue = $item['AlternateKeyValue']
            $itemData = $item['ItemData']
        }
        else {
            $alternateKeyProperty = $item.PSObject.Properties['AlternateKeyValue']
            $itemDataProperty = $item.PSObject.Properties['ItemData']

            $alternateKeyValue = if ($null -ne $alternateKeyProperty) { $alternateKeyProperty.Value } else { $null }
            $itemData = if ($null -ne $itemDataProperty) { $itemDataProperty.Value } else { $null }
        }

        if ($null -eq $itemData -or -not ($itemData -is [System.Collections.Hashtable])) {
            throw 'Each batch upsert entry must include an ItemData hashtable.'
        }

        if ($null -eq $alternateKeyValue -and $itemData.ContainsKey($AlternateKeyColumnName)) {
            $alternateKeyValue = $itemData[$AlternateKeyColumnName]
        }

        if ($null -eq $alternateKeyValue -or [string]$alternateKeyValue -notmatch '\S') {
            throw 'Each batch upsert entry must include an AlternateKeyValue or an ItemData value for AlternateKeyColumnName.'
        }

        foreach ($key in $itemData.Keys) {
            if (-not $combinedItemData.ContainsKey($key)) {
                $combinedItemData[$key] = $itemData[$key]
            }
        }

        if (-not $combinedItemData.ContainsKey($AlternateKeyColumnName)) {
            $combinedItemData[$AlternateKeyColumnName] = $alternateKeyValue
        }

        $resolvedItems.Add([pscustomobject]@{
            AlternateKeyValue = $alternateKeyValue
            ItemData          = $itemData
        })
    }

    if (($PSCmdlet.ParameterSetName).StartsWith('TableLogicalName')) {
        $EntitySet = Get-PSDVEntitySetFromLogicalName -Table $Table
    }

    $itemDataValidation = Confirm-PSDVItemDataAttributes -Table $Table -EntitySet $EntitySet -ItemData $combinedItemData
    $attributeDetails = $itemDataValidation.AttributeDetails
    $batchRequest = New-PSDVBatchRequest -EntitySet $EntitySet -Operation Upsert -Items $resolvedItems -AttributeDetails $attributeDetails -AlternateKeyColumnName $AlternateKeyColumnName -ParseItemData:$ParseItemData.IsPresent -CreateOnly:$CreateOnly.IsPresent
    $shouldProcessAction = if ($CreateOnly.IsPresent) { "Submit batch create-only upsert containing $($resolvedItems.Count) item(s)" } else { "Submit batch upsert containing $($resolvedItems.Count) item(s)" }

    if ($PSCmdlet.ShouldProcess($EntitySet, $shouldProcessAction)) {
        return Invoke-PSDVBatchRequest -BatchRequest $batchRequest -ErrorMessagePrefix 'Dataverse batch upsert'
    }

    return (ConvertFrom-PSDVBatchResponse -BatchResponse $null -ExpectedCount $resolvedItems.Count)
}