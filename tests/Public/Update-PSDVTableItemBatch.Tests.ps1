BeforeAll {
    . (Join-Path $PSScriptRoot 'PublicTestCommon.ps1')
}

Describe 'Update-PSDVTableItemBatch' {
    BeforeEach {
        Initialize-PSDVPublicTestConnection
    }

    AfterEach {
        Clear-PSDVPublicTestConnection
    }

    It 'submits multiple PATCH operations by item ID and returns categorized status results' {
        $firstItemId = [Guid]::NewGuid()
        $secondItemId = [Guid]::NewGuid()
        $updates = @(
            @{ ItemID = $firstItemId; ItemData = @{ name = 'First' } },
            @{ ItemID = $secondItemId; ItemData = @{ name = 'Second' } }
        )

        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -match '/EntityDefinitions\?') {
                return New-PSDVPublicTestWebResponse -Payload @{ LogicalName = 'account' }
            }
            if ($Uri -match "EntityDefinitions\(LogicalName='account'\)/Attributes") {
                return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ LogicalName = 'name'; AttributeType = 'String'; SchemaName = 'name'; Targets = @() }) }
            }

            return [PSCustomObject]@{
                StatusCode = 200
                Content    = "HTTP/1.1 204 No Content`r`nHTTP/1.1 412 Precondition Failed"
            }
        }

        $result = Update-PSDVTableItemBatch -EntitySet 'accounts' -Updates $updates

        $result.RequestedCount | Should -Be 2
        $result.CreatedCount | Should -Be 1
        $result.AlreadyExistingCount | Should -Be 1
        $result.FailedCount | Should -Be 0
        $result.StatusCodes | Should -Be @(204, 412)
        $result.Results.Category | Should -Be @('Created', 'AlreadyExists')
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Uri -match '/\$batch$' -and $Method -eq 'Post' -and $ContentType -match 'multipart/mixed;boundary=batch_' -and $Body -match "PATCH accounts\($firstItemId\) HTTP/1.1" -and $Body -match "PATCH accounts\($secondItemId\) HTTP/1.1" -and $Body -notmatch 'If-None-Match' }
    }

    It 'returns an empty categorized result without submitting a request when no updates are supplied' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith { throw 'should not be called' }

        $result = Update-PSDVTableItemBatch -EntitySet 'accounts' -Updates @()

        $result.RequestedCount | Should -Be 0
        $result.CreatedCount | Should -Be 0
        $result.AlreadyExistingCount | Should -Be 0
        $result.FailedCount | Should -Be 0
        $result.StatusCodes.Count | Should -Be 0
        $result.Results.Count | Should -Be 0
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }

    It 'rejects update entries without an item ID before submitting the batch' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith { throw 'should not be called' }

        { Update-PSDVTableItemBatch -EntitySet 'accounts' -Updates @(@{ AlternateKeyValue = 'ACC001'; ItemData = @{ name = 'Invalid' } }) } | Should -Throw 'Each batch update entry must include an ItemID.'
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }
}