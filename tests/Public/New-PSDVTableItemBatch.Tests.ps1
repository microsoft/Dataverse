BeforeAll {
    . (Join-Path $PSScriptRoot 'PublicTestCommon.ps1')
}

Describe 'New-PSDVTableItemBatch' {
    BeforeEach {
        Initialize-PSDVPublicTestConnection
    }

    AfterEach {
        Clear-PSDVPublicTestConnection
    }

    It 'submits multiple POST operations and returns categorized status results' {
        $items = @(
            @{ ItemData = @{ name = 'First' } },
            @{ ItemData = @{ name = 'Second' } },
            @{ ItemData = @{ name = 'Third' } }
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
                Content    = "HTTP/1.1 201 Created`r`nHTTP/1.1 409 Conflict`r`nHTTP/1.1 500 Internal Server Error"
            }
        }

        $result = New-PSDVTableItemBatch -EntitySet 'accounts' -Items $items

        $result.RequestedCount | Should -Be 3
        $result.CreatedCount | Should -Be 1
        $result.AlreadyExistingCount | Should -Be 1
        $result.FailedCount | Should -Be 1
        $result.StatusCodes | Should -Be @(201, 409, 500)
        $result.Results.Category | Should -Be @('Created', 'AlreadyExists', 'Failed')
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Uri -match '/\$batch$' -and $Method -eq 'Post' -and $ContentType -match 'multipart/mixed;boundary=batch_' -and $Body -match 'POST accounts HTTP/1.1' -and $Body -match '"name":"First"' -and $Body -match '"name":"Second"' -and $Body -match '"name":"Third"' }
    }

    It 'rejects entries without item data before submitting the batch' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith { throw 'should not be called' }

        { New-PSDVTableItemBatch -EntitySet 'accounts' -Items @(@{ name = 'Invalid' }) } | Should -Throw 'Each batch create entry must include an ItemData hashtable.'
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }
}