BeforeAll {
    . (Join-Path $PSScriptRoot 'PublicTestCommon.ps1')
}

Describe 'Invoke-PSDVTableItemUpsert' {
    BeforeEach {
        Initialize-PSDVPublicTestConnection
    }

    AfterEach {
        Clear-PSDVPublicTestConnection
    }

    It 'upserts an item with PATCH to an alternate-key URI' {
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

            return New-PSDVPublicTestWebResponse -Payload @{ accountnumber = "O'Hare"; name = 'Updated' }
        }

        $result = Invoke-PSDVTableItemUpsert -EntitySet 'accounts' -AlternateKeyColumnName 'accountnumber' -AlternateKeyValue "O'Hare" -ItemData @{ name = 'Updated' } -ReturnItem

        $result.name | Should -BeExactly 'Updated'
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Method -eq 'Patch' -and $Uri -match "/accounts\(accountnumber='O''Hare'\)$" -and $Headers['Prefer'] -match 'return=representation' -and -not $Headers.ContainsKey('If-None-Match') -and $Body -match 'Updated' }
    }

    It 'derives the alternate key value from item data' {
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

            return New-PSDVPublicTestWebResponse -Payload @{ accountnumber = 'ACC001'; name = 'Updated' }
        }

        Invoke-PSDVTableItemUpsert -EntitySet 'accounts' -AlternateKeyColumnName 'accountnumber' -ItemData @{ accountnumber = 'ACC001'; name = 'Updated' }

        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Method -eq 'Patch' -and $Uri -match "/accounts\(accountnumber='ACC001'\)$" -and $Body -match 'ACC001' }
    }

    It 'uses POST with the alternate key in the body when CreateOnly is specified' {
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

            return New-PSDVPublicTestWebResponse -Payload @{ accountnumber = 'ACC001'; name = 'Created' }
        }

        Invoke-PSDVTableItemUpsert -EntitySet 'accounts' -AlternateKeyColumnName 'accountnumber' -AlternateKeyValue 'ACC001' -ItemData @{ name = 'Created' } -CreateOnly

        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Method -eq 'Post' -and $Uri -match '/accounts$' -and -not $Headers.ContainsKey('If-None-Match') -and $Body -match '"accountnumber"\s*:\s*"ACC001"' -and $Body -match '"name"\s*:\s*"Created"' }
    }

    It 'rejects missing alternate key values before making a web request' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith { throw 'should not be called' }

        { Invoke-PSDVTableItemUpsert -EntitySet 'accounts' -AlternateKeyColumnName 'accountnumber' -ItemData @{ name = 'Missing key' } } | Should -Throw 'AlternateKeyValue is required when ItemData does not include AlternateKeyColumnName.'
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }
}