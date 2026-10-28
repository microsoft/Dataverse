. (Join-Path $PSScriptRoot 'PrivateTestCommon.ps1')

Describe 'Get-PSDVAzureAuthorityHost' {
    It 'defaults to AzureCloud when environment is not supplied' {
        InModuleScope Dataverse {
            (Get-PSDVAzureAuthorityHost).AbsoluteUri | Should -BeExactly 'https://login.microsoftonline.com/'
        }
    }

    It 'defaults blank environments to AzureCloud' {
        InModuleScope Dataverse {
            (Get-PSDVAzureAuthorityHost -Environment '').AbsoluteUri | Should -BeExactly 'https://login.microsoftonline.com/'
        }
    }

    It 'returns a sovereign cloud authority host' {
        InModuleScope Dataverse {
            (Get-PSDVAzureAuthorityHost -Environment 'AzureUSGovernment').AbsoluteUri | Should -BeExactly 'https://login.microsoftonline.us/'
        }
    }

    It 'throws for unsupported environments' {
        InModuleScope Dataverse {
            { Get-PSDVAzureAuthorityHost -Environment 'UnsupportedCloud' } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }
    }
}
