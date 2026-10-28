BeforeAll {
    . (Join-Path $PSScriptRoot 'PublicTestCommon.ps1')
}

Describe 'Invoke-PSDVTableItemUpsertBatch' {
    BeforeEach {
        Initialize-PSDVPublicTestConnection
    }

    AfterEach {
        Clear-PSDVPublicTestConnection
    }

    It 'submits alternate-key PATCH operations and returns categorized status results' {
        $items = @(
            @{ AlternateKeyValue = 'ACC-001'; ItemData = @{ name = 'First' } },
            @{ ItemData = @{ accountnumber = "O'Hare"; name = 'Second' } }
        )

        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -match '/EntityDefinitions\?') {
                return New-PSDVPublicTestWebResponse -Payload @{ LogicalName = 'account' }
            }
            if ($Uri -match "EntityDefinitions\(LogicalName='account'\)/Attributes") {
                return New-PSDVPublicTestWebResponse -Payload @{ value = @(
                    @{ LogicalName = 'accountnumber'; AttributeType = 'String'; SchemaName = 'accountnumber'; Targets = @() },
                    @{ LogicalName = 'name'; AttributeType = 'String'; SchemaName = 'name'; Targets = @() }
                ) }
            }

            return [PSCustomObject]@{
                StatusCode = 200
                Content    = "HTTP/1.1 201 Created`r`nHTTP/1.1 204 No Content"
            }
        }

        $result = Invoke-PSDVTableItemUpsertBatch -EntitySet 'accounts' -AlternateKeyColumnName 'accountnumber' -Items $items

        $result.RequestedCount | Should -Be 2
        $result.CreatedCount | Should -Be 2
        $result.AlreadyExistingCount | Should -Be 0
        $result.FailedCount | Should -Be 0
        $result.StatusCodes | Should -Be @(201, 204)
        $result.Results.Category | Should -Be @('Created', 'Created')
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Uri -match '/\$batch$' -and $Method -eq 'Post' -and $Body -match "PATCH accounts\(accountnumber='ACC-001'\) HTTP/1.1" -and $Body -match "PATCH accounts\(accountnumber='O''Hare'\) HTTP/1.1" -and $Body -notmatch 'If-None-Match' }
    }

    It 'uses POST for create-only upsert batches and categorizes existing records' {
        $items = @(@{ AlternateKeyValue = 'ACC-001'; ItemData = @{ name = 'First' } })

        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -match '/EntityDefinitions\?') {
                return New-PSDVPublicTestWebResponse -Payload @{ LogicalName = 'account' }
            }
            if ($Uri -match "EntityDefinitions\(LogicalName='account'\)/Attributes") {
                return New-PSDVPublicTestWebResponse -Payload @{ value = @(
                    @{ LogicalName = 'accountnumber'; AttributeType = 'String'; SchemaName = 'accountnumber'; Targets = @() },
                    @{ LogicalName = 'name'; AttributeType = 'String'; SchemaName = 'name'; Targets = @() }
                ) }
            }

            return [PSCustomObject]@{
                StatusCode = 200
                Content    = 'HTTP/1.1 412 Precondition Failed'
            }
        }

        $result = Invoke-PSDVTableItemUpsertBatch -EntitySet 'accounts' -AlternateKeyColumnName 'accountnumber' -Items $items -CreateOnly

        $result.CreatedCount | Should -Be 0
        $result.AlreadyExistingCount | Should -Be 1
        $result.FailedCount | Should -Be 0
        $result.Results[0].Category | Should -BeExactly 'AlreadyExists'
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Uri -match '/\$batch$' -and $Method -eq 'Post' -and $Body -match 'POST accounts HTTP/1.1' -and $Body -match '"accountnumber":"ACC-001"' -and $Body -notmatch 'If-None-Match' }
    }

    It 'rejects upsert entries without an alternate key value before submitting the batch' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith { throw 'should not be called' }

        { Invoke-PSDVTableItemUpsertBatch -EntitySet 'accounts' -AlternateKeyColumnName 'accountnumber' -Items @(@{ ItemData = @{ name = 'Missing key' } }) } | Should -Throw 'Each batch upsert entry must include an AlternateKeyValue or an ItemData value for AlternateKeyColumnName.'
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }
}