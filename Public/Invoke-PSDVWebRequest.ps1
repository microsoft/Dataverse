function Invoke-PSDVWebRequest {
    <#
    .SYNOPSIS
    Executes authenticated web requests to the Dataverse Web API.

    .DESCRIPTION
    Invoke-PSDVWebRequest is the core function for making authenticated HTTP requests to the Microsoft Dataverse Web API.
    It handles OAuth authentication, URL construction, query parameter formatting, and automatic pagination.
    The function supports all HTTP methods (GET, POST, PATCH, DELETE, PUT) and automatically follows OData nextLink
    properties to retrieve complete result sets for large datasets.

    .PARAMETER WebUri
    The nonblank Web API endpoint URI. Can be a full URL, relative path with 'api/data/v9.2/', or just the resource name.

    .PARAMETER Method
    The HTTP method to use. Valid values are Get, Post, Patch, Delete, or Put. Default is Get.

    .PARAMETER Select
    OData $select parameter to specify which fields to return.

    .PARAMETER Filter
    OData $filter parameter to specify query conditions.

    .PARAMETER Expand
    OData $expand parameter to include related records.

    .PARAMETER Top
    OData $top parameter to limit the number of returned records.

    .PARAMETER MaxPageSize
    Dataverse OData max page size preference to request for collection responses.

    .PARAMETER Body
    Hashtable containing the request body data for POST/PATCH operations.

    .PARAMETER Headers
    Additional HTTP headers to include in the request.

    .PARAMETER ReturnRawResponse
    Returns the raw web response object instead of parsing the JSON content.

    .PARAMETER SkipHttpErrorCheck
    Forwards HTTP error responses to the normal response handling instead of throwing for non-success
    status codes. Combine with -ReturnRawResponse to inspect StatusCode, Headers, and Content without
    JSON parsing. Transport failures still throw. When omitted or false, HTTP errors still throw.

    .PARAMETER AsPages
    Returns one page object at a time instead of combining all paged results into a single collection.

    .PARAMETER AsCollection
    Always returns an array, even when the query yields zero records. This wraps the output so callers
    receive a reliable collection (with a .Count of 0 for empty results) without needing the @(...) idiom.
    Cannot be combined with -AsPages or -ReturnRawResponse.

    .OUTPUTS
    System.Object[]

    For collection queries, the matched records are written to the pipeline. A collection query that
    matches zero records produces no pipeline output (an unrolled empty array), so wrap calls in @(...)
    for a reliable .Count, or use -AsCollection to always receive an array.
    A single-record GET that returns HTTP 204 (No Content) yields $null.

    .NOTES
    Required identifiers and numeric/enumerated inputs are validated by PowerShell before requests.
    Optional empty query values and empty Body/Headers dictionaries retain their existing handling.
    HTTP failures terminate with error ID prefix PSDVPreconditionFailed for status 412, or PSDVHttpError
    for other statuses. $_.Exception.Data['PSDVHttpError'] contains HttpStatusCode (integer),
    DataverseErrorCode and DataverseErrorMessage (strings or null), ResponseHeaders (case-insensitive
    dictionary of string arrays), ResponseBody, Method, and RequestUri. The original native exception
    is retained as $_.Exception.InnerException. Request/transport failures without a received HTTP
    response use PSDVWebRequestFailed and do not have PSDVHttpError data. JSON parsing errors remain
    distinct. Match error ID prefixes because PowerShell may append command context.
    -SkipHttpErrorCheck retains normal response handling instead of creating HTTP error records.
    The module does not automatically retry requests; an uncertain write outcome requires caller reconciliation.

    .EXAMPLE
    Invoke-PSDVWebRequest -WebUri "accounts" -Select "name,accountnumber"

    Retrieves all accounts with only name and account number fields.

    .EXAMPLE
    Invoke-PSDVWebRequest -WebUri "contacts" -Filter "firstname eq 'John'" -Expand "parentcustomerid_account"

    Retrieves contacts named John and expands the parent account information.

    .EXAMPLE
    Invoke-PSDVWebRequest -WebUri "accounts" -MaxPageSize 1000 -AsPages | ForEach-Object {
        $_.Results | ForEach-Object {
            $_.name
        }
    }

    Retrieves accounts in Dataverse pages of up to 1000 records and processes each page before requesting the next page.

    .EXAMPLE
    $data = @{ name = "New Account"; accountnumber = "ACC001" }
    Invoke-PSDVWebRequest -WebUri "accounts" -Method Post -Body $data

    Creates a new account record.

    .EXAMPLE
    $response = Invoke-PSDVWebRequest -WebUri "accounts($accountId)" -Method Patch `
        -Headers @{ 'If-Match' = $etag } -Body @{ description = 'Updated description' } `
        -ReturnRawResponse -SkipHttpErrorCheck
    if ($response.StatusCode -eq 412) {
        Write-Warning 'Another process changed the row; skip or reconcile.'
    }

    Returns the raw response so an expected concurrency conflict can be detected by status code.
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $WebUri,

        [parameter()]
        [ValidateSet('Get', 'Post', 'Patch', 'Delete', 'Put')]
        [string]
        $Method = 'Get',

        [parameter()]
        [string]
        $Select,

        [parameter()]
        [string]
        $Filter,

        [parameter()]
        [string]
        $Expand,

        [parameter()]
        [ValidateRange(1, 5000)]
        [Int32]
        $Top,

        [parameter()]
        [ValidateRange(1, 5000)]
        [Int32]
        $MaxPageSize,

        [parameter()]
        [hashtable]
        $Body,

        [parameter()]
        [hashtable]
        $Headers,

        [parameter()]
        [switch]
        $ReturnRawResponse = $false,

        [parameter()]
        [switch]
        $AsPages = $false,

        [parameter()]
        [switch]
        $AsCollection = $false,

        [parameter()]
        [switch]
        $SkipHttpErrorCheck = $false
    )

    if ($ReturnRawResponse -and $AsPages) {
        throw '-AsPages cannot be used with -ReturnRawResponse because raw responses are not parsed for OData pagination.'
    }

    if ($AsCollection -and $AsPages) {
        throw '-AsCollection cannot be used with -AsPages because -AsPages emits page objects rather than a single collection.'
    }

    if ($AsCollection -and $ReturnRawResponse) {
        throw '-AsCollection cannot be used with -ReturnRawResponse because raw responses are not parsed for OData pagination.'
    }

    Set-PSDVAccessToken

    # Remove leading slash if present
    if ($WebUri.StartsWith('/')) {
        $WebUri = $WebUri.Substring(1)
    }

    if ($WebUri.StartsWith(($Global:DATAVERSEORGURL))) {
        $dvRequestUri = $WebUri
    }
    elseif ( $WebUri.Contains('api/data/v9.2/') ) {
        $dvRequestUri = $Global:DATAVERSEORGURL + $WebUri
    }
    else {
        $dvRequestUri = $Global:DATAVERSEORGURL + 'api/data/v9.2/' + $WebUri
    }
    $dvRequestUri = [System.UriBuilder]$dvRequestUri

    # Append query parameters if provided
    $queryParams = [ordered]@{}
    if ($Select) { $queryParams['$select'] = $Select }
    if ($Filter) { $queryParams['$filter'] = $Filter }
    if ($Expand) { $queryParams['$expand'] = $Expand }
    if ($PSBoundParameters.ContainsKey('Top')) { $queryParams['$top'] = $Top }

    if ($queryParams.Count -gt 0) {
        $existingQuery = $dvRequestUri.Query
        if ($existingQuery.StartsWith('?')) {
            $existingQuery = $existingQuery.Substring(1)
        }
        $newQuery = Join-PSDVQueryString -QueryParameters $queryParams
        if ($existingQuery) {
            $dvRequestUri.Query = "$existingQuery&$newQuery"
        }
        else {
            $dvRequestUri.Query = $newQuery
        }
    }

    if ($Body) {
        if ($Method -eq 'Get') {
            $Method = 'Post'
        }

        $bodyContent = $Body | ConvertTo-Json -Depth 10
        $httpHeaders = @{
            'Content-Type' = 'application/json'
            'Accept'       = 'application/json'
        }
    }
    else {
        $bodyContent = $null
        $httpHeaders = @{}
    }

    if ($PSBoundParameters.ContainsKey('Headers')) {
        foreach ($key in $Headers.Keys) {
            $httpHeaders[$key] = $Headers[$key]
        }
    }

    if ($PSBoundParameters.ContainsKey('MaxPageSize')) {
        $pageSizePreference = "odata.maxpagesize=$MaxPageSize"
        $preferHeaderName = $httpHeaders.Keys | Where-Object { $_ -eq 'Prefer' } | Select-Object -First 1

        if ($preferHeaderName) {
            if ($httpHeaders[$preferHeaderName] -notmatch '(^|,)\s*odata\.maxpagesize=') {
                $httpHeaders[$preferHeaderName] = "$($httpHeaders[$preferHeaderName]),$pageSizePreference"
            }
        }
        else {
            $httpHeaders['Prefer'] = $pageSizePreference
        }
    }

    try {
        Write-Verbose "Executing Web API: $($dvRequestUri.Uri.AbsoluteUri)"
        $webResponse = Invoke-WebRequest -Authentication OAuth -Token $Global:DATAVERSEACCESSTOKEN.Token -Method $method -Uri $dvRequestUri.Uri.AbsoluteUri -Body $bodyContent -Headers $httpHeaders -SkipHttpErrorCheck:$SkipHttpErrorCheck
    }
    catch {
        $requestError = New-PSDVWebRequestErrorRecord -OriginalError $_ -Method $Method `
            -RequestUri $dvRequestUri.Uri.AbsoluteUri -MessagePrefix 'Error executing web query:'
        $PSCmdlet.ThrowTerminatingError($requestError)
    }

    if ($ReturnRawResponse) {
        return $webResponse
    }
    else {
        if ($null -eq $webResponse -or [string]::IsNullOrWhiteSpace($webResponse.Content)) {
            # Empty/204 response. Because the URI and headers alone don't reveal whether the caller
            # intended a single-record GET (legitimately $null on HTTP 204) or a collection query
            # (which should yield an empty collection), we default to $null and let -AsCollection
            # callers opt into an always-array result.
            if ($AsCollection) {
                return , @()
            }
            return $null
        }

        try {
            $jsonResponse = $webResponse.Content | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Failed to parse Dataverse JSON response. Error: $($_.Exception.Message)"
        }

        $allResults = [System.Collections.Generic.List[object]]::new()
        $retrievedCount = 0
        $pageNumber = 0

        # Handle paging by following @odata.nextLink
        do {
            if ($jsonResponse.PSObject.Properties.Name -contains 'Value') {
                $pageResults = @($jsonResponse.value)

                if ($pageResults.Count -gt 0) {
                    $pageNumber++
                    $retrievedCount += $pageResults.Count

                    if ($AsPages) {
                        [PSCustomObject]@{
                            PageNumber = $pageNumber
                            Count      = $pageResults.Count
                            Results    = $pageResults
                            NextLink   = $jsonResponse.'@odata.nextLink'
                        }
                    }
                    else {
                        foreach ($item in $pageResults) {
                            $allResults.Add($item)
                        }
                    }
                }
                elseif (-not $AsPages) {
                    # Empty collection: fall through so control reaches the final
                    # 'return $allResults.ToArray()', which is already an empty array.
                    # This unifies the empty and non-empty collection paths.
                }
            }
            else {
                if ($AsPages) {
                    throw '-AsPages can only be used with collection responses that contain a value property.'
                }

                #single item
                return $jsonResponse
            }

            # Check if there's a next page
            if ($jsonResponse.'@odata.nextLink') {
                $nextPageUri = $jsonResponse.'@odata.nextLink'
                try {
                    Write-Verbose "Following pagination link: $nextPageUri"
                    $webResponse = Invoke-WebRequest -Authentication OAuth -Token $Global:DATAVERSEACCESSTOKEN.Token -Method Get -Uri $nextPageUri -Headers $httpHeaders -SkipHttpErrorCheck:$SkipHttpErrorCheck
                }
                catch {
                    $requestError = New-PSDVWebRequestErrorRecord -OriginalError $_ -Method Get `
                        -RequestUri $nextPageUri -MessagePrefix "Pagination failed after retrieving $retrievedCount record(s). Error retrieving next page:"
                    $PSCmdlet.ThrowTerminatingError($requestError)
                }
                try {
                    $jsonResponse = $webResponse.Content | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    throw "Pagination failed after retrieving $retrievedCount record(s). Error retrieving next page: $($_.Exception.Message)"
                }
            }
            else {
                $jsonResponse = $null
            }
        } while ($jsonResponse)

        if ($AsCollection) {
            return , $allResults.ToArray()
        }

        return $allResults.ToArray()
    }
}
