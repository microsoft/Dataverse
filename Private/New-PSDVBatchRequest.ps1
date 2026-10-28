function New-PSDVBatchRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [string]
        $EntitySet,

        [Parameter(Mandatory)]
        [ValidateSet('Create', 'Update', 'Upsert')]
        [string]
        $Operation,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [ValidateScript({ $_.ItemData -is [hashtable] }, ErrorMessage = 'Each batch entry must include an ItemData hashtable.')]
        [object[]]
        $Items,

        [Parameter()]
        [hashtable]
        $AttributeDetails,

        [Parameter()]
        [string]
        $AlternateKeyColumnName,

        [Parameter()]
        [switch]
        $ParseItemData,

        [Parameter()]
        [switch]
        $CreateOnly
    )

    if ($Items.Count -gt 0 -and $Operation -eq 'Upsert' -and $AlternateKeyColumnName -notmatch '\S') {
        throw 'AlternateKeyColumnName is required for upsert batches.'
    }
    if ($Items.Count -gt 0 -and $ParseItemData -and $null -eq $AttributeDetails) {
        throw 'AttributeDetails is required when ParseItemData is specified.'
    }

    $batchBoundary = "batch_$([guid]::NewGuid().ToString('N'))"
    $bodyLines = [System.Collections.Generic.List[string]]::new()
    $contentId = 1

    foreach ($item in $Items) {
        $itemData = $item.ItemData
        if ($Operation -eq 'Update') {
            $itemId = $item.ItemID -as [guid]
            if ($null -eq $itemId -or $itemId -eq [guid]::Empty) {
                throw 'Each batch update entry requires a non-empty ItemID GUID.'
            }
        }
        if ($Operation -eq 'Upsert') {
            $alternateKeyValue = $item.AlternateKeyValue
            if ($null -eq $alternateKeyValue -and $itemData.ContainsKey($AlternateKeyColumnName)) {
                $alternateKeyValue = $itemData[$AlternateKeyColumnName]
            }
            if ($null -eq $alternateKeyValue -or [string]$alternateKeyValue -notmatch '\S') {
                throw 'Each batch upsert entry requires an alternate key value.'
            }
        }
        $itemDataForRequest = @{}
        foreach ($key in $itemData.Keys) {
            $itemDataForRequest[$key] = $itemData[$key]
        }

        if ($Operation -eq 'Upsert' -and $CreateOnly.IsPresent -and -not $itemDataForRequest.ContainsKey($AlternateKeyColumnName)) {
            $itemDataForRequest[$AlternateKeyColumnName] = $alternateKeyValue
        }

        $itemDataToProcess = if ($ParseItemData.IsPresent) {
            $itemAttributeDetails = @{}
            foreach ($key in $itemDataForRequest.Keys) {
                $itemAttributeDetails[$key] = $AttributeDetails[$key]
            }

            ConvertTo-PSDVLookupItemData -ItemData $itemDataForRequest -AttributeDetails $itemAttributeDetails
        }
        else {
            $itemDataForRequest
        }

        switch ($Operation) {
            'Create' {
                $method = 'POST'
                $requestUri = $EntitySet
            }
            'Update' {
                $method = 'PATCH'
                $requestUri = "$EntitySet($itemId)"
            }
            'Upsert' {
                if ($CreateOnly.IsPresent) {
                    $method = 'POST'
                    $requestUri = $EntitySet
                }
                else {
                    $method = 'PATCH'
                    $alternateKeyLiteral = ConvertTo-PSDVODataStringLiteral -Value ([string]$alternateKeyValue)
                    $requestUri = "$EntitySet($AlternateKeyColumnName=$alternateKeyLiteral)"
                }
            }
        }

        $changesetBoundary = "changeset_$([guid]::NewGuid().ToString('N'))"

        $bodyLines.Add("--$batchBoundary")
        $bodyLines.Add("Content-Type: multipart/mixed;boundary=$changesetBoundary")
        $bodyLines.Add('')
        $bodyLines.Add("--$changesetBoundary")
        $bodyLines.Add('Content-Type: application/http')
        $bodyLines.Add('Content-Transfer-Encoding: binary')
        $bodyLines.Add("Content-ID: $contentId")
        $bodyLines.Add('')
        $bodyLines.Add("$method $requestUri HTTP/1.1")
        $bodyLines.Add('Content-Type: application/json;type=entry')

        $bodyLines.Add('')
        $bodyLines.Add(($itemDataToProcess | ConvertTo-Json -Compress -Depth 10))
        $bodyLines.Add("--$changesetBoundary--")
        $contentId++
    }

    $bodyLines.Add("--$batchBoundary--")

    return [pscustomobject]@{
        BatchBoundary = $batchBoundary
        BatchBody     = ($bodyLines -join "`r`n") + "`r`n"
        RequestedCount = @($Items).Count
    }
}