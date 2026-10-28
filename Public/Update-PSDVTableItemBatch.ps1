function Update-PSDVTableItemBatch {
    <#
    .SYNOPSIS
    Updates multiple Dataverse records in a single OData batch request.
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
        $Updates,

        [parameter()]
        [switch]
        $ParseItemData
    )

    if ($null -eq $Global:DATAVERSEACCESSTOKEN) {
        throw 'No existing connection to Dataverse Environment, run Connect-PSDVOrg before executing other PSDV cmdlets'
    }

    $updatesToProcess = @($Updates | Where-Object { $null -ne $_ })
    if ($updatesToProcess.Count -eq 0) {
        return (ConvertFrom-PSDVBatchResponse -BatchResponse $null -ExpectedCount 0)
    }

    $resolvedUpdates = [System.Collections.Generic.List[object]]::new()
    $combinedItemData = @{}

    foreach ($update in $updatesToProcess) {
        if ($update -is [System.Collections.IDictionary]) {
            $itemIdValue = $update['ItemID']
            $itemData = $update['ItemData']
        }
        else {
            $itemIdProperty = $update.PSObject.Properties['ItemID']
            $itemDataProperty = $update.PSObject.Properties['ItemData']

            $itemIdValue = if ($null -ne $itemIdProperty) { $itemIdProperty.Value } else { $null }
            $itemData = if ($null -ne $itemDataProperty) { $itemDataProperty.Value } else { $null }
        }

        if ($null -eq $itemIdValue) {
            throw 'Each batch update entry must include an ItemID.'
        }

        $itemId = $itemIdValue -as [guid]
        if ($null -eq $itemId) {
            throw 'Each batch update entry must include a valid ItemID GUID.'
        }
        if ($itemId -eq [Guid]::Empty) {
            throw 'ItemID cannot be an empty GUID'
        }

        if ($null -eq $itemData -or -not ($itemData -is [System.Collections.Hashtable])) {
            throw 'Each batch update entry must include an ItemData hashtable.'
        }

        foreach ($key in $itemData.Keys) {
            if (-not $combinedItemData.ContainsKey($key)) {
                $combinedItemData[$key] = $itemData[$key]
            }
        }

        $resolvedUpdates.Add([pscustomobject]@{
            ItemID   = $itemId
            ItemData = $itemData
        })
    }

    if (($PSCmdlet.ParameterSetName).StartsWith('TableLogicalName')) {
        $EntitySet = Get-PSDVEntitySetFromLogicalName -Table $Table
    }

    $itemDataValidation = Confirm-PSDVItemDataAttributes -Table $Table -EntitySet $EntitySet -ItemData $combinedItemData
    $attributeDetails = $itemDataValidation.AttributeDetails
    $batchRequest = New-PSDVBatchRequest -EntitySet $EntitySet -Operation Update -Items $resolvedUpdates -AttributeDetails $attributeDetails -ParseItemData:$ParseItemData.IsPresent

    if ($PSCmdlet.ShouldProcess($EntitySet, "Submit batch update containing $($resolvedUpdates.Count) item(s)")) {
        return Invoke-PSDVBatchRequest -BatchRequest $batchRequest -ErrorMessagePrefix 'Dataverse batch update'
    }

    return (ConvertFrom-PSDVBatchResponse -BatchResponse $null -ExpectedCount $resolvedUpdates.Count)
}