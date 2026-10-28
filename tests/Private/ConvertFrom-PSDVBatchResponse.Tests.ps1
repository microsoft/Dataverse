. (Join-Path $PSScriptRoot 'PrivateTestCommon.ps1')

Describe 'ConvertFrom-PSDVBatchResponse' {
    It 'categorizes 200, 201, and 204 statuses as created' {
        InModuleScope Dataverse {
            $response = [pscustomobject]@{ Content = "HTTP/1.1 200 OK`r`nHTTP/1.1 201 Created`r`nHTTP/1.1 204 No Content" }

            $result = ConvertFrom-PSDVBatchResponse -BatchResponse $response -ExpectedCount 3

            $result.RequestedCount | Should -Be 3
            $result.CreatedCount | Should -Be 3
            $result.AlreadyExistingCount | Should -Be 0
            $result.FailedCount | Should -Be 0
            $result.StatusCodes | Should -Be @(200, 201, 204)
            $result.Results.Category | Should -Be @('Created', 'Created', 'Created')
        }
    }

    It 'categorizes 409 and 412 statuses as already exists' {
        InModuleScope Dataverse {
            $response = [pscustomobject]@{ Content = "HTTP/1.1 409 Conflict`r`nHTTP/1.1 412 Precondition Failed" }

            $result = ConvertFrom-PSDVBatchResponse -BatchResponse $response -ExpectedCount 2

            $result.CreatedCount | Should -Be 0
            $result.AlreadyExistingCount | Should -Be 2
            $result.FailedCount | Should -Be 0
            $result.StatusCodes | Should -Be @(409, 412)
            $result.Results.Category | Should -Be @('AlreadyExists', 'AlreadyExists')
        }
    }

    It 'categorizes unexpected statuses and missing statuses as failed' {
        InModuleScope Dataverse {
            $response = [pscustomobject]@{ Content = 'HTTP/1.1 500 Internal Server Error' }

            $result = ConvertFrom-PSDVBatchResponse -BatchResponse $response -ExpectedCount 3

            $result.CreatedCount | Should -Be 0
            $result.AlreadyExistingCount | Should -Be 0
            $result.FailedCount | Should -Be 3
            $result.StatusCodes | Should -Be @(500)
            $result.Results[0].StatusCode | Should -Be 500
            $result.Results[0].Category | Should -BeExactly 'Failed'
            $result.Results[1].StatusCode | Should -BeNullOrEmpty
            $result.Results[1].Category | Should -BeExactly 'Failed'
            $result.Results[2].StatusCode | Should -BeNullOrEmpty
            $result.Results[2].Category | Should -BeExactly 'Failed'
        }
    }

    It 'returns requested failures when the response contains no per-request statuses' {
        InModuleScope Dataverse {
            $response = [pscustomobject]@{ Content = 'not a multipart batch response' }

            $result = ConvertFrom-PSDVBatchResponse -BatchResponse $response -ExpectedCount 2

            $result.RequestedCount | Should -Be 2
            $result.CreatedCount | Should -Be 0
            $result.AlreadyExistingCount | Should -Be 0
            $result.FailedCount | Should -Be 2
            $result.StatusCodes.Count | Should -Be 0
            $result.Results.Category | Should -Be @('Failed', 'Failed')
        }
    }
}