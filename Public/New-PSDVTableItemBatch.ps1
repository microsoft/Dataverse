function New-PSDVTableItemBatch {
    <#
    .SYNOPSIS
    Creates multiple Dataverse records in a single OData batch request.
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
        [AllowEmptyCollection()]
        [object[]]
        $Items,

        [parameter()]
        [switch]
        $ParseItemData
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
        $itemData = if ($item -is [System.Collections.IDictionary]) {
            $item['ItemData']
        }
        else {
            $itemDataProperty = $item.PSObject.Properties['ItemData']
            if ($null -ne $itemDataProperty) { $itemDataProperty.Value } else { $null }
        }

        if ($null -eq $itemData -or -not ($itemData -is [System.Collections.Hashtable])) {
            throw 'Each batch create entry must include an ItemData hashtable.'
        }

        foreach ($key in $itemData.Keys) {
            if (-not $combinedItemData.ContainsKey($key)) {
                $combinedItemData[$key] = $itemData[$key]
            }
        }

        $resolvedItems.Add([pscustomobject]@{ ItemData = $itemData })
    }

    if (($PSCmdlet.ParameterSetName).StartsWith('TableLogicalName')) {
        $EntitySet = Get-PSDVEntitySetFromLogicalName -Table $Table
    }

    $itemDataValidation = Confirm-PSDVItemDataAttributes -Table $Table -EntitySet $EntitySet -ItemData $combinedItemData
    $attributeDetails = $itemDataValidation.AttributeDetails
    $batchRequest = New-PSDVBatchRequest -EntitySet $EntitySet -Operation Create -Items $resolvedItems -AttributeDetails $attributeDetails -ParseItemData:$ParseItemData.IsPresent

    if ($PSCmdlet.ShouldProcess($EntitySet, "Submit batch create containing $($resolvedItems.Count) item(s)")) {
        return Invoke-PSDVBatchRequest -BatchRequest $batchRequest -ErrorMessagePrefix 'Dataverse batch create'
    }

    return (ConvertFrom-PSDVBatchResponse -BatchResponse $null -ExpectedCount $resolvedItems.Count)
}