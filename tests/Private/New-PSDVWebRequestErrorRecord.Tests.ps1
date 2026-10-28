. (Join-Path $PSScriptRoot 'PrivateTestCommon.ps1')

Describe 'New-PSDVWebRequestErrorRecord' {
    It 'retains the original HTTP exception, response content, and multivalue diagnostic headers' {
        InModuleScope Dataverse {
            $original = New-PSDVTestHttpErrorRecord
            try {
                $result = New-PSDVWebRequestErrorRecord -OriginalError $original -Method Patch `
                    -RequestUri 'https://example.crm.dynamics.com/api/data/v9.2/accounts(id)' `
                    -MessagePrefix 'Error executing web query:'

                $result.FullyQualifiedErrorId | Should -BeExactly 'PSDVPreconditionFailed'
                $result.CategoryInfo.Category | Should -Be 'ResourceBusy'
                [object]::ReferenceEquals($result.Exception.InnerException, $original.Exception) | Should -BeTrue
                $details = $result.Exception.Data['PSDVHttpError']
                $details.HttpStatusCode | Should -BeOfType ([int])
                $details.HttpStatusCode | Should -Be 412
                $details.DataverseErrorCode | Should -BeExactly '0x80060882'
                $details.DataverseErrorMessage | Should -BeExactly 'Version mismatch'
                $details.ResponseBody | Should -BeExactly $original.ErrorDetails.Message
                $details.ResponseHeaders['X-MS-SERVICE-REQUEST-ID'] | Should -Be @('request-123')
                $details.ResponseHeaders['x-test-values'] | Should -Be @('first', 'second')
                $details.ResponseHeaders['Content-Type'][0] | Should -Match 'text/plain'
                $details.ResponseHeaders['Retry-After'] | Should -Be @('5')
                $details.ResponseHeaders.ContainsKey('Authorization') | Should -BeFalse
                $details.Method | Should -BeExactly 'Patch'
                $details.RequestUri | Should -BeExactly 'https://example.crm.dynamics.com/api/data/v9.2/accounts(id)'
            }
            finally {
                $original.Exception.Response.Dispose()
            }
        }
    }

    It 'does not classify HTTP <StatusCode> as a concurrency conflict' -ForEach @(
        @{ StatusCode = 401 }, @{ StatusCode = 403 }, @{ StatusCode = 404 },
        @{ StatusCode = 429 }, @{ StatusCode = 500 }, @{ StatusCode = 503 }
    ) {
        InModuleScope Dataverse -Parameters @{ StatusCode = $StatusCode } {
            param($StatusCode)
            $original = New-PSDVTestHttpErrorRecord -StatusCode $StatusCode
            try {
                $result = New-PSDVWebRequestErrorRecord -OriginalError $original -Method Patch `
                    -RequestUri 'https://example.test/record' -MessagePrefix 'Request failed:'
                $result.FullyQualifiedErrorId | Should -BeExactly 'PSDVHttpError'
                $result.CategoryInfo.Category | Should -Be 'InvalidOperation'
                $result.Exception.Data['PSDVHttpError'].HttpStatusCode | Should -Be $StatusCode
            }
            finally {
                $original.Exception.Response.Dispose()
            }
        }
    }

    It 'preserves HTTP status and original body for <Label> content' -ForEach @(
        @{ Label = 'empty'; Content = '' }
        @{ Label = 'HTML'; Content = '<html>failure</html>' }
        @{ Label = 'malformed JSON'; Content = '{"error":' }
        @{ Label = 'JSON null'; Content = 'null' }
        @{ Label = 'JSON array'; Content = '[1,2]' }
        @{ Label = 'single-error array'; Content = '[{"error":{"code":"unexpected","message":"not an error object"}}]' }
        @{ Label = 'missing error'; Content = '{"other":"value"}' }
        @{ Label = 'unexpected error'; Content = '{"error":"failure"}' }
        @{ Label = 'non-string error fields'; Content = '{"error":{"code":123,"message":{}}}' }
    ) {
        InModuleScope Dataverse -Parameters @{ Content = $Content } {
            param($Content)
            $original = New-PSDVTestHttpErrorRecord -Content $Content
            try {
                $result = New-PSDVWebRequestErrorRecord -OriginalError $original -Method Patch `
                    -RequestUri 'https://example.test/record' -MessagePrefix 'Request failed:'
                $details = $result.Exception.Data['PSDVHttpError']
                $result.FullyQualifiedErrorId | Should -BeExactly 'PSDVPreconditionFailed'
                $details.HttpStatusCode | Should -Be 412
                $details.ResponseBody | Should -BeExactly $Content
                $details.DataverseErrorCode | Should -BeNullOrEmpty
                $details.DataverseErrorMessage | Should -BeNullOrEmpty
            }
            finally {
                $original.Exception.Response.Dispose()
            }
        }
    }

    It 'uses the native ErrorDetails when response content was disposed' {
        InModuleScope Dataverse {
            $original = New-PSDVTestHttpErrorRecord
            $original.Exception.Response.Content.Dispose()
            try {
                $result = New-PSDVWebRequestErrorRecord -OriginalError $original -Method Patch `
                    -RequestUri 'https://example.test/record' -MessagePrefix 'Request failed:'
                $result.Exception.Data['PSDVHttpError'].ResponseBody | Should -BeExactly $original.ErrorDetails.Message
                $result.Exception.Data['PSDVHttpError'].DataverseErrorCode | Should -BeExactly '0x80060882'
            }
            finally {
                $original.Exception.Response.Dispose()
            }
        }
    }

    It 'preserves a transport exception without fabricating an HTTP response' {
        InModuleScope Dataverse {
            $exception = [System.Net.Http.HttpRequestException]::new('Connection failed')
            $original = [System.Management.Automation.ErrorRecord]::new(
                $exception, 'NativeTransportError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null
            )
            $result = New-PSDVWebRequestErrorRecord -OriginalError $original -Method Patch `
                -RequestUri 'https://example.test/record' -MessagePrefix 'Request failed:'
            $result.FullyQualifiedErrorId | Should -BeExactly 'PSDVWebRequestFailed'
            $result.Exception.Data.Contains('PSDVHttpError') | Should -BeFalse
            [object]::ReferenceEquals($result.Exception.InnerException, $exception) | Should -BeTrue
        }
    }
}
