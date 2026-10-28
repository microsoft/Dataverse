function New-PSDVWebRequestErrorRecord {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]
        $OriginalError,

        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [string]
        $RequestUri,

        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [string]
        $MessagePrefix
    )

    $originalException = $OriginalError.Exception
    $exception = [System.Exception]::new("$MessagePrefix $($originalException.Message)", $originalException)
    $errorId = 'PSDVWebRequestFailed'
    $category = [System.Management.Automation.ErrorCategory]::ConnectionError

    if ($originalException -is [Microsoft.PowerShell.Commands.HttpResponseException] -and
        $null -ne $originalException.Response) {
        $response = $originalException.Response
        $statusCode = [int]$response.StatusCode
        $errorId = 'PSDVHttpError'
        $category = [System.Management.Automation.ErrorCategory]::InvalidOperation
        if ($statusCode -eq 412) {
            $errorId = 'PSDVPreconditionFailed'
            $category = [System.Management.Automation.ErrorCategory]::ResourceBusy
        }

        $responseHeaders = @{}
        foreach ($header in $response.Headers) {
            $responseHeaders[$header.Key] = [string[]]@($header.Value)
        }

        $responseBody = $null
        if ($null -ne $response.Content) {
            foreach ($header in $response.Content.Headers) {
                $responseHeaders[$header.Key] = [string[]]@($header.Value)
            }
            try {
                $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            }
            catch [System.ObjectDisposedException], [System.Net.Http.HttpRequestException], [System.IO.IOException] {
                # PowerShell can dispose HTTP content before delivering the error record.
                Write-Verbose "Could not read HTTP error content; using ErrorDetails if available. $($_.Exception.Message)"
            }
        }
        if ($null -eq $responseBody -and $null -ne $OriginalError.ErrorDetails) {
            $responseBody = $OriginalError.ErrorDetails.Message
        }

        $dataverseErrorCode = $null
        $dataverseErrorMessage = $null
        if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
            try {
                $payload = ConvertFrom-Json -InputObject $responseBody -AsHashtable -NoEnumerate -ErrorAction Stop
                if ($payload -is [System.Collections.IDictionary] -and
                    $payload['error'] -is [System.Collections.IDictionary]) {
                    if ($payload['error']['code'] -is [string]) {
                        $dataverseErrorCode = $payload['error']['code']
                    }
                    if ($payload['error']['message'] -is [string]) {
                        $dataverseErrorMessage = $payload['error']['message']
                    }
                }
            }
            catch [System.ArgumentException] {
                Write-Verbose "HTTP error content is not valid JSON; retaining the original body. $($_.Exception.Message)"
            }
        }

        $exception.Data['PSDVHttpError'] = [PSCustomObject]@{
            HttpStatusCode        = $statusCode
            DataverseErrorCode    = $dataverseErrorCode
            DataverseErrorMessage = $dataverseErrorMessage
            ResponseHeaders       = $responseHeaders
            ResponseBody          = $responseBody
            Method                = $Method
            RequestUri            = $RequestUri
        }
    }

    return [System.Management.Automation.ErrorRecord]::new($exception, $errorId, $category, $RequestUri)
}
