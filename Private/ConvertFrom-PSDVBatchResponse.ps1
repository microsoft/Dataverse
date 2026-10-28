function ConvertFrom-PSDVBatchResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]
        $BatchResponse,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $ExpectedCount
    )

    $content = if ($null -eq $BatchResponse -or $null -eq $BatchResponse.Content) {
        ''
    }
    elseif ($BatchResponse.Content -is [byte[]]) {
        [System.Text.Encoding]::UTF8.GetString($BatchResponse.Content)
    }
    else {
        [string]$BatchResponse.Content
    }

    $statusMatches = [regex]::Matches($content, 'HTTP/\d(?:\.\d)?\s+(\d{3})')
    $statusCodes = @()
    $results = [System.Collections.Generic.List[object]]::new()
    $createdCount = 0
    $alreadyExistingCount = 0
    $failedCount = 0

    foreach ($statusMatch in $statusMatches) {
        $statusCodes += [int]$statusMatch.Groups[1].Value
    }

    for ($index = 0; $index -lt $ExpectedCount; $index++) {
        $statusCode = if ($index -lt $statusCodes.Count) { $statusCodes[$index] } else { $null }

        if ($statusCode -in @(200, 201, 204)) {
            $category = 'Created'
            $createdCount++
        }
        elseif ($statusCode -in @(409, 412)) {
            $category = 'AlreadyExists'
            $alreadyExistingCount++
        }
        else {
            $category = 'Failed'
            $failedCount++
        }

        $results.Add([pscustomobject]@{
            Index      = $index
            StatusCode = $statusCode
            Category   = $category
        })
    }

    return [pscustomobject]@{
        RequestedCount       = $ExpectedCount
        CreatedCount         = $createdCount
        AlreadyExistingCount = $alreadyExistingCount
        FailedCount          = $failedCount
        StatusCodes          = $statusCodes
        Results              = @($results)
    }
}