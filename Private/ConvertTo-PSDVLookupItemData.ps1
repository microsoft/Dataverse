function ConvertTo-PSDVLookupItemData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]
        $ItemData,

        [Parameter(Mandatory)]
        [ValidateScript({
            foreach ($attribute in $_.Keys) {
                if ($attribute -like '*@odata.bind') {
                    continue
                }
                $detail = $_[$attribute]
                if ($null -eq $detail -or $detail.AttributeType -notmatch '\S') {
                    return $false
                }
                if ($detail.AttributeType -eq 'Lookup' -and
                    ($detail.SchemaName -notmatch '\S' -or $detail.Targets -isnot [System.Collections.IList] -or
                        $detail.Targets.Count -eq 0 -or $detail.Targets[0] -notmatch '\S')) {
                    return $false
                }
            }
            return $true
        }, ErrorMessage = 'AttributeDetails must include attribute types and lookup navigation names and targets.')]
        [System.Collections.Hashtable]
        $AttributeDetails
    )

    foreach ($attribute in $ItemData.Keys) {
        if (-not $AttributeDetails.ContainsKey($attribute)) {
            throw "AttributeDetails is missing metadata for '$attribute'."
        }
    }

    $parsedItemData = @{}

    foreach ($attribute in $AttributeDetails.Keys) {
        if ($attribute -like '*@odata.bind') {
            $parsedItemData.Add($attribute, $ItemData[$attribute])
        }
        elseif ($AttributeDetails[$attribute].AttributeType -eq 'Lookup') {
            $navProperty = $AttributeDetails[$attribute].SchemaName
            $targetTable = $AttributeDetails[$attribute].Targets[0]
            $targetTableSet = Get-PSDVEntitySetFromLogicalName -Table $targetTable
            $targetItemID = $ItemData[$attribute]
            $parsedItemData.Add("$navProperty@odata.bind", "/$targetTableSet($targetItemID)")
        }
        else {
            $parsedItemData.Add($attribute, $ItemData[$attribute])
        }
    }

    return $parsedItemData
}
