BeforeAll {
    . (Join-Path $PSScriptRoot 'PublicTestCommon.ps1')
}

Describe 'Update-PSDVTableItem' {
    BeforeEach {
        Initialize-PSDVPublicTestConnection
    }

    AfterEach {
        Clear-PSDVPublicTestConnection
    }

    It 'updates an item with PATCH after validating attributes' {
        $itemId = [Guid]::NewGuid()

        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            if ($Uri -match '/EntityDefinitions\?') {
                return New-PSDVPublicTestWebResponse -Payload @{ LogicalName = 'account' }
            }
            if ($Uri -match "EntityDefinitions\(LogicalName='account'\)/Attributes") {
                return New-PSDVPublicTestWebResponse -Payload @{ value = @(@{ LogicalName = 'name'; AttributeType = 'String'; SchemaName = 'name'; Targets = @() }) }
            }

            return New-PSDVPublicTestWebResponse -Payload @{ accountid = $itemId; name = 'Updated' }
        }

        $result = Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Updated' } -ReturnItem

        $result.name | Should -BeExactly 'Updated'
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Method -eq 'Patch' -and $Uri -match "/accounts\($itemId\)$" -and $Headers['Prefer'] -match 'return=representation' -and $Body -match 'Updated' }
    }

    It 'rejects an empty item ID before making a web request' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith { throw 'should not be called' }

        { Update-PSDVTableItem -EntitySet 'accounts' -ItemID ([Guid]::Empty) -ItemData @{ name = 'Updated' } } |
            Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }

    Context 'conditional updates' {
        BeforeEach {
            $itemId = [Guid]::NewGuid()
            Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
                if ($Uri -match '/EntityDefinitions\?') {
                    return New-PSDVPublicTestWebResponse -Payload @{ LogicalName = 'account' }
                }
                if ($Uri -match '/Attributes') {
                    return New-PSDVPublicTestWebResponse -Payload @{
                        value = @(
                            @{ LogicalName = 'name'; AttributeType = 'String'; SchemaName = 'name' }
                            @{ LogicalName = 'description'; AttributeType = 'String'; SchemaName = 'description' }
                            @{ LogicalName = 'parentaccountid'; AttributeType = 'Lookup'; SchemaName = 'parentaccountid'; Targets = @('account') }
                        )
                    }
                }
                if ($Uri -match '/EntityDefinitions\(') {
                    return New-PSDVPublicTestWebResponse -Payload @{ EntitySetName = 'accounts' }
                }
                return New-PSDVPublicTestWebResponse -Payload @{
                    accountid = $itemId; name = 'Updated'; '@odata.etag' = 'W/"124"'
                }
            }
        }

        It 'forwards the unchanged ETag with <ParameterSet> and returns only the PATCH representation' -ForEach @(
            @{ ParameterSet = 'logical name'; Options = @{ Table = 'account' } }
            @{ ParameterSet = 'entity set'; Options = @{ EntitySet = 'accounts' } }
        ) {
            $row = [PSCustomObject]@{ accountid = $itemId; name = 'Original'; '@odata.etag' = 'W/"123"' }
            $data = @{ name = 'Updated' }

            $result = Update-PSDVTableItem @Options -ItemID $itemId -ItemData $data `
                -IfMatch $row.'@odata.etag' -ReturnItem -ErrorAction Stop

            $result.name | Should -BeExactly 'Updated'
            $result.'@odata.etag' | Should -BeExactly 'W/"124"'
            $row.name | Should -BeExactly 'Original'
            $row.'@odata.etag' | Should -BeExactly 'W/"123"'
            $data.Count | Should -Be 1
            $data.name | Should -BeExactly 'Updated'
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Patch' -and $Uri -match "/accounts\($itemId\)$" -and
                $Headers['If-Match'] -ceq 'W/"123"' -and
                $Headers['Prefer'] -ceq 'odata.include-annotations="*",return=representation' -and
                ($Body | ConvertFrom-Json).name -ceq 'Updated'
            }
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'Get' -and $Uri -match "/accounts\($itemId\)"
            }
        }

        It 'rejects explicitly supplied <Label> before any request' -ForEach @(
            @{ Label = 'null'; Value = $null }, @{ Label = 'empty'; Value = '' },
            @{ Label = 'spaces'; Value = '   ' }, @{ Label = 'tabs'; Value = "`t" }
        ) {
            { Update-PSDVTableItem -Table 'account' -ItemID $itemId -ItemData @{ name = 'Updated' } -IfMatch $Value } |
                Should -Throw
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
        }

        It 'forwards <Label> without normalizing the supplied string' -ForEach @(
            @{ Label = 'wildcard'; Value = '*' }
            @{ Label = 'opaque ETag'; Value = ' W/"opaque-version" ' }
        ) {
            Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Updated' } -IfMatch $Value
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Patch' -and $Headers['If-Match'] -ceq $Value
            }
        }

        It 'does not add an If-Match header when the parameter is omitted' {
            Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Updated' }
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Patch' -and -not $Headers.ContainsKey('If-Match')
            }
        }

        It 'uses the wildcard without a version check and preserves a missing-row HTTP 404' {
            $server = @{ Exists = $true; Name = 'Intervening edit'; ETag = 'W/"999"' }
            $original = New-PSDVTestHttpErrorRecord -StatusCode 404
            Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -ParameterFilter { $Method -eq 'Patch' } -MockWith {
                if (-not $server.Exists -and $Headers['If-Match'] -eq '*') { throw $original }
                $server.Exists = $true
                $server.Name = ($Body | ConvertFrom-Json).name
                return New-PSDVPublicTestWebResponse -Payload @{
                    accountid = $itemId; name = $server.Name; '@odata.etag' = $server.ETag
                }
            }
            $caught = $null
            try {
                $updated = Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId `
                    -ItemData @{ name = 'Wildcard update' } -IfMatch '*' -ReturnItem -ErrorAction Stop
                $server.Exists = $false
                try {
                    Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId `
                        -ItemData @{ name = 'Must not create' } -IfMatch '*' -ErrorAction Stop
                }
                catch { $caught = $_ }
            }
            finally { $original.Exception.Response.Dispose() }

            $updated.name | Should -BeExactly 'Wildcard update'
            $server.Name | Should -BeExactly 'Wildcard update'
            $server.Exists | Should -BeFalse
            $caught.FullyQualifiedErrorId | Should -BeLike 'PSDVHttpError*'
            $caught.Exception.Data['PSDVHttpError'].HttpStatusCode | Should -Be 404
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 2 -Exactly -ParameterFilter {
                $Method -eq 'Patch' -and $Headers['If-Match'] -ceq '*'
            }
        }

        It 'returns no content without ReturnItem and retains unconditional ReturnItem behavior' {
            Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -ParameterFilter { $Method -eq 'Patch' } -MockWith {
                return New-PSDVPublicTestWebResponse -Payload $null
            }
            $result = Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Updated' } -IfMatch 'W/"123"'
            $result | Should -BeNullOrEmpty
            $result = Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Updated' } -ReturnItem
            $result | Should -BeNullOrEmpty
        }

        It 'reports <Label> without replaying the PATCH or fetching the record' -ForEach @(
            @{ Label = 'empty representation'; Content = ''; ErrorId = 'PSDVUpdateRepresentationMissing' }
            @{ Label = 'invalid JSON'; Content = '<html>failure</html>'; ErrorId = 'PSDVUpdateRepresentationMissing' }
            @{ Label = 'null representation'; Content = 'null'; ErrorId = 'PSDVUpdateRepresentationMissing' }
            @{ Label = 'scalar representation'; Content = '123'; ErrorId = 'PSDVUpdateRepresentationMissing' }
            @{ Label = 'array representation'; Content = '[{"name":"Updated","@odata.etag":"W/\"124\""}]'; ErrorId = 'PSDVUpdateRepresentationMissing' }
            @{ Label = 'collection representation'; Content = '{"value":[{"name":"Updated"}]}'; ErrorId = 'PSDVUpdateRepresentationMissing' }
            @{ Label = 'missing ETag'; Content = '{"name":"Updated"}'; ErrorId = 'PSDVUpdateETagMissing' }
            @{ Label = 'blank ETag'; Content = '{"name":"Updated","@odata.etag":" "}'; ErrorId = 'PSDVUpdateETagMissing' }
            @{ Label = 'non-string ETag'; Content = '{"name":"Updated","@odata.etag":124}'; ErrorId = 'PSDVUpdateETagMissing' }
        ) {
            Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -ParameterFilter { $Method -eq 'Patch' } -MockWith {
                return New-PSDVPublicTestWebResponse -Payload $Content
            }
            $caught = $null
            try {
                Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Updated' } `
                    -IfMatch 'W/"123"' -ReturnItem -ErrorAction Stop
            }
            catch { $caught = $_ }

            $caught.FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
            $caught.Exception.Message | Should -BeLike '*may already have succeeded*'
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Method -eq 'Patch' }
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'Get' -and $Uri -match "/accounts\($itemId\)"
            }
        }

        It 'preserves existing lookup parsing and OData binds with a condition' -ForEach @(
            @{ Data = @{ parentaccountid = '11111111-1111-1111-1111-111111111111' }; Parse = $true }
            @{ Data = @{ 'parentaccountid@odata.bind' = '/accounts(11111111-1111-1111-1111-111111111111)' }; Parse = $true }
            @{ Data = @{ 'parentaccountid@odata.bind' = '/accounts(11111111-1111-1111-1111-111111111111)' }; Parse = $false }
        ) {
            Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData $Data `
                -IfMatch 'W/"123"' -ParseItemData:$Parse
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Patch' -and $Headers['If-Match'] -eq 'W/"123"' -and
                ($Body | ConvertFrom-Json).'parentaccountid@odata.bind' -eq '/accounts(11111111-1111-1111-1111-111111111111)'
            }
        }

        It 'does not PATCH with WhatIf or invalid fields' {
            Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Updated' } -IfMatch 'W/"123"' -WhatIf
            { Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ invalidfield = 'Updated' } -IfMatch 'W/"123"' } |
                Should -Throw '*Invalid attributes*'
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly -ParameterFilter { $Method -eq 'Patch' }
        }

        It 'allows only one write with the original ETag and does not apply the stale payload' {
            $server = @{ ETag = 'W/"123"'; Name = 'Original' }
            $original = New-PSDVTestHttpErrorRecord
            Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -ParameterFilter { $Method -eq 'Patch' } -MockWith {
                if ($Headers['If-Match'] -cne $server.ETag) { throw $original }
                $server.Name = ($Body | ConvertFrom-Json).name
                $server.ETag = 'W/"124"'
                return New-PSDVPublicTestWebResponse -Payload @{
                    accountid = $itemId; name = $server.Name; '@odata.etag' = $server.ETag
                }
            }
            $caught = $null
            try {
                $winner = Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Winner' } `
                    -IfMatch 'W/"123"' -ReturnItem -ErrorAction Stop
                try {
                    Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Loser' } `
                        -IfMatch 'W/"123"' -ReturnItem -ErrorAction Stop
                }
                catch { $caught = $_ }
            }
            finally { $original.Exception.Response.Dispose() }

            $winner.name | Should -BeExactly 'Winner'
            $winner.'@odata.etag' | Should -BeExactly 'W/"124"'
            $caught.FullyQualifiedErrorId | Should -BeLike 'PSDVPreconditionFailed*'
            $caught.Exception.Data['PSDVHttpError'].HttpStatusCode | Should -Be 412
            $server.Name | Should -BeExactly 'Winner'
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 2 -Exactly -ParameterFilter {
                $Method -eq 'Patch' -and $Headers['If-Match'] -ceq 'W/"123"'
            }
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'Get' -and $Uri -match "/accounts\($itemId\)"
            }
        }

        It 'does not replay or weaken a condition after HTTP <StatusCode>' -ForEach @(
            @{ StatusCode = 412; ErrorId = 'PSDVPreconditionFailed' }
            @{ StatusCode = 429; ErrorId = 'PSDVHttpError' }
            @{ StatusCode = 500; ErrorId = 'PSDVHttpError' }
        ) {
            $original = New-PSDVTestHttpErrorRecord -StatusCode $StatusCode
            Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -ParameterFilter { $Method -eq 'Patch' } -MockWith { throw $original }
            $caught = $null
            try {
                Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Updated' } -IfMatch 'W/"123"' -ErrorAction Stop
            }
            catch { $caught = $_ }
            finally { $original.Exception.Response.Dispose() }

            $caught.FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
            $caught.Exception.Data['PSDVHttpError'].HttpStatusCode | Should -Be $StatusCode
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Patch' -and $Headers['If-Match'] -ceq 'W/"123"'
            }
        }

        It 'preserves uncertain transport failure without replaying the update' {
            $exception = [System.Net.Http.HttpRequestException]::new('Response lost')
            Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -ParameterFilter { $Method -eq 'Patch' } -MockWith { throw $exception }
            $caught = $null
            try {
                Update-PSDVTableItem -EntitySet 'accounts' -ItemID $itemId -ItemData @{ name = 'Updated' } -IfMatch 'W/"123"' -ErrorAction Stop
            }
            catch { $caught = $_ }
            $caught.FullyQualifiedErrorId | Should -BeLike 'PSDVWebRequestFailed*'
            $caught.Exception.Data.Contains('PSDVHttpError') | Should -BeFalse
            [object]::ReferenceEquals($caught.Exception.InnerException, $exception) | Should -BeTrue
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Patch' -and $Headers['If-Match'] -ceq 'W/"123"'
            }
        }

        It 'preserves structured metadata errors when resolving a logical table name' {
            $original = New-PSDVTestHttpErrorRecord -StatusCode 403
            Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith { throw $original }
            $caught = $null
            try {
                Update-PSDVTableItem -Table 'account' -ItemID $itemId -ItemData @{ name = 'Updated' } -IfMatch 'W/"123"' -ErrorAction Stop
            }
            catch { $caught = $_ }
            finally { $original.Exception.Response.Dispose() }
            $caught.FullyQualifiedErrorId | Should -BeLike 'PSDVHttpError*'
            $caught.Exception.Data['PSDVHttpError'].HttpStatusCode | Should -Be 403
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly -ParameterFilter { $Method -eq 'Patch' }
        }
    }
}
