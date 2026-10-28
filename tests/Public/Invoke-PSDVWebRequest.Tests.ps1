BeforeAll {
    . (Join-Path $PSScriptRoot 'PublicTestCommon.ps1')
}

Describe 'Invoke-PSDVWebRequest' {
    BeforeEach {
        Initialize-PSDVPublicTestConnection
    }

    AfterEach {
        Clear-PSDVPublicTestConnection
    }

    It 'builds a Dataverse API request, sends JSON body content, and parses a single response object' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            return New-PSDVPublicTestWebResponse -Payload @{ accountid = [Guid]::NewGuid(); name = 'Contoso' }
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts' -Select 'name' -Filter "name eq 'Contoso'" -Body @{ name = 'Contoso' }

        $result.name | Should -BeExactly 'Contoso'
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Method -eq 'Post' -and $Uri -match '/accounts' -and $Headers['Content-Type'] -eq 'application/json' -and $Body -match 'Contoso' }
    }

    It 'follows OData pagination links and returns the combined collection' {
        $nextLink = 'https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=next'

        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -eq $nextLink) {
                return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ name = 'Second' }) }
            }

            return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ name = 'First' }); '@odata.nextLink' = $nextLink }
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts'

        @($result).Count | Should -Be 2
        @($result).name | Should -Be @('First', 'Second')
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 2 -Exactly
    }

    It 'requests an OData max page size and still returns the combined collection' {
        $nextLink = 'https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=next'

        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -eq $nextLink) {
                return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ name = 'Second' }) }
            }

            return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ name = 'First' }); '@odata.nextLink' = $nextLink }
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts' -MaxPageSize 1000

        @($result).Count | Should -Be 2
        @($result).name | Should -Be @('First', 'Second')
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 2 -Exactly -ParameterFilter { $Headers['Prefer'] -eq 'odata.maxpagesize=1000' }
    }

    It 'appends OData max page size to an existing Prefer header' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ name = 'Contoso' }) }
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts' -MaxPageSize 500 -Headers @{ Prefer = 'odata.include-annotations="*"' }

        @($result).Count | Should -Be 1
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Headers['Prefer'] -eq 'odata.include-annotations="*",odata.maxpagesize=500' }
    }

    It 'returns one page object per OData page when requested' {
        $nextLink = 'https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=next'

        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -eq $nextLink) {
                return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ name = 'Second' }, @{ name = 'Third' }) }
            }

            return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ name = 'First' }); '@odata.nextLink' = $nextLink }
        }

        $pages = @(Invoke-PSDVWebRequest -WebUri 'accounts' -MaxPageSize 1000 -AsPages)

        $pages.Count | Should -Be 2
        $pages[0].PageNumber | Should -Be 1
        $pages[0].Count | Should -Be 1
        $pages[0].Results.name | Should -Be 'First'
        $pages[0].NextLink | Should -Be $nextLink
        $pages[1].PageNumber | Should -Be 2
        $pages[1].Count | Should -Be 2
        $pages[1].Results.name | Should -Be @('Second', 'Third')
        $pages[1].NextLink | Should -BeNullOrEmpty
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 2 -Exactly -ParameterFilter { $Headers['Prefer'] -eq 'odata.maxpagesize=1000' }
    }

    It 'returns an empty collection when a query matches no records' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            return New-PSDVPublicTestWebResponse -Payload @{ value = @() }
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts'

        @($result).Count | Should -Be 0
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly
    }

    It 'returns an empty array for an empty collection when -AsCollection is used' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            return New-PSDVPublicTestWebResponse -Payload @{ value = @() }
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts' -AsCollection

        $null -eq $result | Should -BeFalse
        $result -is [array] | Should -BeTrue
        $result.Count | Should -Be 0
    }

    It 'returns an array for a populated collection when -AsCollection is used' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ name = 'Contoso' }) }
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts' -AsCollection

        $result -is [array] | Should -BeTrue
        $result.Count | Should -Be 1
        $result[0].name | Should -BeExactly 'Contoso'
    }

    It 'returns an empty array for a 204/no-content response when -AsCollection is used' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            return New-PSDVPublicTestWebResponse -Payload $null
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts' -AsCollection

        $result -is [array] | Should -BeTrue
        $result.Count | Should -Be 0
    }

    It 'returns $null for a 204/no-content response without -AsCollection' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            return New-PSDVPublicTestWebResponse -Payload $null
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts'

        $result | Should -BeNullOrEmpty
    }

    It 'rejects -AsCollection when combined with -AsPages' {
        { Invoke-PSDVWebRequest -WebUri 'accounts' -AsCollection -AsPages } | Should -Throw '*-AsCollection cannot be used with -AsPages*'
    }

    It 'rejects -AsCollection when combined with -ReturnRawResponse' {
        { Invoke-PSDVWebRequest -WebUri 'accounts' -AsCollection -ReturnRawResponse } | Should -Throw '*-AsCollection cannot be used with -ReturnRawResponse*'
    }

    It 'rejects page output when returning raw responses' {
        { Invoke-PSDVWebRequest -WebUri 'accounts' -ReturnRawResponse -AsPages } | Should -Throw '*-AsPages cannot be used with -ReturnRawResponse*'
    }

    It 'returns the raw web response when requested' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            return [PSCustomObject]@{ Content = '{"ok":true}'; StatusCode = 204 }
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts' -ReturnRawResponse

        $result.StatusCode | Should -Be 204
    }

    It 'returns the unchanged raw HTTP <StatusCode> response when HTTP error checks are skipped' -ForEach @(
        @{ StatusCode = 412; Content = '{"error":{"message":"Precondition Failed"}}' }
        @{ StatusCode = 404; Content = '{"error":{"message":"Not Found"}}' }
        @{ StatusCode = 500; Content = '<html>Internal Server Error</html>' }
    ) {
        $expectedResponse = [PSCustomObject]@{
            StatusCode = $StatusCode
            Headers    = @{ 'x-ms-service-request-id' = 'request-123'; ETag = 'W/"123"' }
            Content    = $Content
        }
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if (-not $SkipHttpErrorCheck) {
                throw "HTTP $StatusCode"
            }
            return $expectedResponse
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts(account-id)' -Method Patch `
            -Headers @{ 'If-Match' = 'W/"122"' } -Body @{ description = 'Updated description' } `
            -ReturnRawResponse -SkipHttpErrorCheck

        [object]::ReferenceEquals($result, $expectedResponse) | Should -BeTrue
        $result.StatusCode | Should -Be $StatusCode
        $result.Headers['x-ms-service-request-id'] | Should -BeExactly 'request-123'
        $result.Headers.ETag | Should -BeExactly 'W/"123"'
        $result.Content | Should -BeExactly $Content
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
            $SkipHttpErrorCheck -and $Method -eq 'Patch' -and
            $Headers['If-Match'] -eq 'W/"122"' -and
            ($Body | ConvertFrom-Json).description -eq 'Updated description'
        }
    }

    It 'still throws HTTP errors with <Mode> and raw output <Raw>' -ForEach @(
        @{ Mode = 'omitted switch'; Options = @{}; Raw = $false }
        @{ Mode = 'omitted switch'; Options = @{}; Raw = $true }
        @{ Mode = 'explicit false'; Options = @{ SkipHttpErrorCheck = $false }; Raw = $false }
        @{ Mode = 'explicit false'; Options = @{ SkipHttpErrorCheck = $false }; Raw = $true }
    ) {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if (-not $SkipHttpErrorCheck) {
                throw 'HTTP 412 Precondition Failed'
            }
            return [PSCustomObject]@{ StatusCode = 412; Content = '{"error":{}}' }
        }

        { Invoke-PSDVWebRequest -WebUri 'accounts' -ReturnRawResponse:$Raw @Options } |
            Should -Throw '*Error executing web query:*HTTP 412 Precondition Failed*'

        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
            -not $SkipHttpErrorCheck
        }
    }

    It 'still throws transport errors when HTTP checks are skipped and raw output is <Raw>' -ForEach @(
        @{ Raw = $false }
        @{ Raw = $true }
    ) {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            throw [System.Net.Http.HttpRequestException]::new('Connection failed')
        }

        { Invoke-PSDVWebRequest -WebUri 'accounts' -SkipHttpErrorCheck -ReturnRawResponse:$Raw } |
            Should -Throw '*Error executing web query:*Connection failed*'

        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
            $SkipHttpErrorCheck
        }
    }

    It 'parses JSON error content when HTTP checks are skipped without raw output' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if (-not $SkipHttpErrorCheck) {
                throw 'HTTP 412 Precondition Failed'
            }
            return [PSCustomObject]@{
                StatusCode = 412
                Content    = '{"error":{"code":"ConcurrencyVersionMismatch","message":"Precondition Failed"}}'
            }
        }

        $result = Invoke-PSDVWebRequest -WebUri 'accounts' -SkipHttpErrorCheck

        $result.error.code | Should -BeExactly 'ConcurrencyVersionMismatch'
        $result.error.message | Should -BeExactly 'Precondition Failed'
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
            $SkipHttpErrorCheck
        }
    }

    It 'still throws for invalid JSON without raw output when HTTP checks are skipped' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            return [PSCustomObject]@{ StatusCode = 500; Content = '<html>Internal Server Error</html>' }
        }

        { Invoke-PSDVWebRequest -WebUri 'accounts' -SkipHttpErrorCheck } |
            Should -Throw '*Failed to parse Dataverse JSON response*'
    }

    It 'forwards <Mode> on every request with page output <Pages>' -ForEach @(
        @{ Mode = 'true'; Options = @{ SkipHttpErrorCheck = $true }; ExpectedSkip = $true; Pages = $false }
        @{ Mode = 'true'; Options = @{ SkipHttpErrorCheck = $true }; ExpectedSkip = $true; Pages = $true }
        @{ Mode = 'omitted'; Options = @{}; ExpectedSkip = $false; Pages = $false }
        @{ Mode = 'omitted'; Options = @{}; ExpectedSkip = $false; Pages = $true }
        @{ Mode = 'false'; Options = @{ SkipHttpErrorCheck = $false }; ExpectedSkip = $false; Pages = $false }
        @{ Mode = 'false'; Options = @{ SkipHttpErrorCheck = $false }; ExpectedSkip = $false; Pages = $true }
    ) {
        $nextLink = 'https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=next'
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -eq $nextLink) {
                return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ name = 'Second' }) }
            }
            return New-PSDVPublicTestWebResponse -Payload @{
                value = @(@{ name = 'First' }); '@odata.nextLink' = $nextLink
            }
        }

        $result = @(Invoke-PSDVWebRequest -WebUri 'accounts' -AsPages:$Pages @Options)

        $result.Count | Should -Be 2
        if ($Pages) {
            $result[0].Results.name | Should -BeExactly 'First'
            $result[1].Results.name | Should -BeExactly 'Second'
        }
        else {
            $result.name | Should -Be @('First', 'Second')
        }
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 2 -Exactly -ParameterFilter {
            [bool]$SkipHttpErrorCheck -eq $ExpectedSkip
        }
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
            $Uri -eq $nextLink -and $Method -eq 'Get' -and [bool]$SkipHttpErrorCheck -eq $ExpectedSkip
        }
    }

    It 'preserves pagination transport errors when HTTP checks are skipped' {
        $nextLink = 'https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=next'
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -eq $nextLink) {
                throw [System.Net.Http.HttpRequestException]::new('Connection failed')
            }
            return New-PSDVPublicTestWebResponse -Payload @{
                value = @(@{ name = 'First' }); '@odata.nextLink' = $nextLink
            }
        }

        { Invoke-PSDVWebRequest -WebUri 'accounts' -SkipHttpErrorCheck } |
            Should -Throw '*Pagination failed after retrieving 1 record(s).*Connection failed*'

        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 2 -Exactly -ParameterFilter {
            $SkipHttpErrorCheck
        }
    }

    It 'exposes structured HTTP <StatusCode> errors to callers with raw output <Raw>' -ForEach @(
        @{ StatusCode = 412; Raw = $false; ErrorId = 'PSDVPreconditionFailed' }
        @{ StatusCode = 412; Raw = $true; ErrorId = 'PSDVPreconditionFailed' }
        @{ StatusCode = 401; Raw = $false; ErrorId = 'PSDVHttpError' }
        @{ StatusCode = 403; Raw = $false; ErrorId = 'PSDVHttpError' }
        @{ StatusCode = 404; Raw = $false; ErrorId = 'PSDVHttpError' }
        @{ StatusCode = 429; Raw = $false; ErrorId = 'PSDVHttpError' }
        @{ StatusCode = 500; Raw = $false; ErrorId = 'PSDVHttpError' }
    ) {
        $original = New-PSDVTestHttpErrorRecord -StatusCode $StatusCode
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith { throw $original }
        $caught = $null
        try {
            Invoke-PSDVWebRequest -WebUri 'accounts' -Method Patch -ReturnRawResponse:$Raw -ErrorAction Stop
        }
        catch {
            $caught = $_
        }
        finally {
            $original.Exception.Response.Dispose()
        }

        $caught | Should -Not -BeNullOrEmpty
        $caught.FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
        $caught.Exception.Data['PSDVHttpError'].HttpStatusCode | Should -Be $StatusCode
        $caught.Exception.Data['PSDVHttpError'].DataverseErrorCode | Should -BeExactly '0x80060882'
        [object]::ReferenceEquals($caught.Exception.InnerException, $original.Exception) | Should -BeTrue
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly
    }

    It 'exposes HTTP details and pagination context when a later page fails' {
        $nextLink = 'https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=next'
        $original = New-PSDVTestHttpErrorRecord -StatusCode 429
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -eq $nextLink) { throw $original }
            return New-PSDVPublicTestWebResponse -Payload @{
                value = @(@{ name = 'First' }); '@odata.nextLink' = $nextLink
            }
        }
        $caught = $null
        try {
            Invoke-PSDVWebRequest -WebUri 'accounts' -ErrorAction Stop
        }
        catch {
            $caught = $_
        }
        finally {
            $original.Exception.Response.Dispose()
        }

        $caught.FullyQualifiedErrorId | Should -BeLike 'PSDVHttpError*'
        $caught.Exception.Message | Should -BeLike '*Pagination failed after retrieving 1 record(s).*'
        $details = $caught.Exception.Data['PSDVHttpError']
        $details.HttpStatusCode | Should -Be 429
        $details.Method | Should -BeExactly 'Get'
        $details.RequestUri | Should -BeExactly $nextLink
        $details.ResponseHeaders['Retry-After'] | Should -Be @('5')
    }

    It 'does not classify pagination JSON parsing errors as HTTP failures' {
        $nextLink = 'https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=next'
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -eq $nextLink) {
                return New-PSDVPublicTestWebResponse -Payload '<html>invalid JSON</html>'
            }
            return New-PSDVPublicTestWebResponse -Payload @{
                value = @(@{ name = 'First' }); '@odata.nextLink' = $nextLink
            }
        }
        $caught = $null
        try { Invoke-PSDVWebRequest -WebUri 'accounts' -ErrorAction Stop }
        catch { $caught = $_ }

        $caught.Exception.Message | Should -BeLike '*Pagination failed after retrieving 1 record(s).*'
        $caught.FullyQualifiedErrorId | Should -Not -BeLike 'PSDVHttpError*'
        $caught.Exception.Data.Contains('PSDVHttpError') | Should -BeFalse
    }

    It 'exposes a distinct failure ID and original exception for transport failures' -ForEach @(
        @{ Exception = [System.Net.Http.HttpRequestException]::new('Connection failed') }
        @{ Exception = [System.Threading.Tasks.TaskCanceledException]::new('Request timed out') }
    ) {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith { throw $Exception }
        $caught = $null
        try { Invoke-PSDVWebRequest -WebUri 'accounts' -Method Patch -ErrorAction Stop }
        catch { $caught = $_ }

        $caught.FullyQualifiedErrorId | Should -BeLike 'PSDVWebRequestFailed*'
        $caught.Exception.Data.Contains('PSDVHttpError') | Should -BeFalse
        [object]::ReferenceEquals($caught.Exception.InnerException, $Exception) | Should -BeTrue
    }
}
