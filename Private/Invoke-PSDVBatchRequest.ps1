function Invoke-PSDVBatchRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            $count = $_.RequestedCount -as [int]
            $_.BatchBoundary -is [string] -and $_.BatchBoundary -match '\S' -and $_.BatchBoundary -notmatch '[\r\n]' -and
                $_.BatchBody -is [string] -and $_.BatchBody -match '\S' -and
                $null -ne $count -and $count -ge 0 -and $_.RequestedCount -eq $count
        }, ErrorMessage = 'BatchRequest requires a nonblank boundary and body and a nonnegative integer RequestedCount.')]
        [pscustomobject]
        $BatchRequest,

        [Parameter()]
        [ValidateNotNullOrWhiteSpace()]
        [string]
        $ErrorMessagePrefix = 'Dataverse batch request'
    )

    Set-PSDVAccessToken

    $batchUri = "$($Global:DATAVERSEORGURL.TrimEnd('/'))/api/data/v9.2/`$batch"
    $batchResponse = Invoke-WebRequest `
        -Authentication OAuth `
        -Token $Global:DATAVERSEACCESSTOKEN.Token `
        -Method Post `
        -Uri $batchUri `
        -ContentType "multipart/mixed;boundary=$($BatchRequest.BatchBoundary)" `
        -Headers @{ Prefer = 'odata.continue-on-error' } `
        -Body $BatchRequest.BatchBody `
        -SkipHttpErrorCheck

    $parsedResponse = ConvertFrom-PSDVBatchResponse -BatchResponse $batchResponse -ExpectedCount $BatchRequest.RequestedCount

    if (($batchResponse.StatusCode -lt 200 -or $batchResponse.StatusCode -ge 300) -and $parsedResponse.StatusCodes.Count -eq 0) {
        $responseContent = if ($batchResponse.Content -is [byte[]]) {
            [System.Text.Encoding]::UTF8.GetString($batchResponse.Content)
        }
        else {
            [string]$batchResponse.Content
        }

        throw "$ErrorMessagePrefix returned HTTP status $($batchResponse.StatusCode). Response content: $responseContent"
    }

    return $parsedResponse
}