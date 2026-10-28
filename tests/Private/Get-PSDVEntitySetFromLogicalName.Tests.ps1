. (Join-Path $PSScriptRoot 'PrivateTestCommon.ps1')

Describe 'Get-PSDVEntitySetFromLogicalName' {
    BeforeEach {
        InModuleScope Dataverse {
            $Global:DATAVERSEAUTHCONTEXT = New-PSDVTestAuthContext
            $Global:DATAVERSEACCESSTOKEN = New-PSDVTestAccessToken
            $Global:DATAVERSEORGURL = 'https://example.crm.dynamics.com/'
        }
    }

    AfterEach {
        InModuleScope Dataverse {
            $Global:DATAVERSEAUTHCONTEXT = $null
            $Global:DATAVERSEACCESSTOKEN = $null
            $Global:DATAVERSEORGURL = $null
        }
    }

    It 'returns the entity set name for a logical table name' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            return [PSCustomObject]@{ Content = '{"EntitySetName":"accounts"}' }
        } -ParameterFilter { $Uri -match "EntityDefinitions\(LogicalName='account'\)" -and $Uri -match '%24select=EntitySetName' }

        InModuleScope Dataverse {
            Get-PSDVEntitySetFromLogicalName -Table 'account' | Should -BeExactly 'accounts'
        }

        Should -Invoke -CommandName Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Uri -match "EntityDefinitions\(LogicalName='account'\)" -and $Uri -match '%24select=EntitySetName' }
    }

    It 'wraps lookup failures with table context' {
        Mock -CommandName Invoke-PSDVWebRequest -ModuleName Dataverse -MockWith { throw 'metadata unavailable' }

        InModuleScope Dataverse {
            { Get-PSDVEntitySetFromLogicalName -Table 'missingtable' } | Should -Throw '*Cannot find table missingtable in Dataverse Environment*'
        }
    }

    It 'preserves structured transport failures without flattening the original exception' {
        Mock -CommandName Invoke-WebRequest -ModuleName Dataverse -MockWith {
            throw [System.Net.Http.HttpRequestException]::new('metadata unavailable')
        }
        InModuleScope Dataverse {
            $caught = $null
            try { Get-PSDVEntitySetFromLogicalName -Table 'missingtable' }
            catch { $caught = $_ }
            $caught.FullyQualifiedErrorId | Should -BeLike 'PSDVWebRequestFailed*'
            $caught.Exception.InnerException | Should -BeOfType ([System.Net.Http.HttpRequestException])
        }
    }
}
