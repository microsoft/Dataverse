. (Join-Path $PSScriptRoot 'PrivateTestCommon.ps1')

Describe 'Get-PSDVAccessToken' {
    BeforeEach {
        $script:OriginalIdentityEndpoint = $env:IDENTITY_ENDPOINT
        $script:OriginalIdentityHeader = $env:IDENTITY_HEADER
        $script:OriginalMsiEndpoint = $env:MSI_ENDPOINT
        $script:OriginalMsiSecret = $env:MSI_SECRET
    }

    AfterEach {
        $env:IDENTITY_ENDPOINT = $script:OriginalIdentityEndpoint
        $env:IDENTITY_HEADER = $script:OriginalIdentityHeader
        $env:MSI_ENDPOINT = $script:OriginalMsiEndpoint
        $env:MSI_SECRET = $script:OriginalMsiSecret
    }

    It 'uses the FunctionRuntime managed identity path without creating an Azure.Identity credential' {
        $env:IDENTITY_ENDPOINT = 'http://localhost/runtime/token'
        $env:IDENTITY_HEADER = [Guid]::NewGuid().ToString('N')
        $env:MSI_ENDPOINT = $null
        $env:MSI_SECRET = $null

        Mock -CommandName Invoke-RestMethod -ModuleName Dataverse -MockWith {
            return [PSCustomObject]@{
                access_token = [Guid]::NewGuid().ToString('N')
                expires_in   = 3600
            }
        }

        InModuleScope Dataverse {
            $authContext = New-PSDVTestAuthContext -ParameterSetName 'SystemManagedIdentity'
            $authContext.ManagedIdentityTokenSource = 'FunctionRuntime'

            $token = Get-PSDVAccessToken -AuthContext $authContext

            $token.Token | Should -Not -BeNullOrEmpty
            $authContext.ContainsKey('Credential') | Should -BeFalse
        }

        Should -Invoke -CommandName Invoke-RestMethod -ModuleName Dataverse -Times 1 -Exactly
    }

    It 'throws for unsupported parameter sets before requesting a token' {
        InModuleScope Dataverse {
            $originalLoaded = $script:PSDVAzureIdentityLoaded
            try {
                $script:PSDVAzureIdentityLoaded = $true
                $authContext = New-PSDVTestAuthContext -ParameterSetName 'Unsupported'

                { Get-PSDVAccessToken -AuthContext $authContext } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            }
            finally {
                $script:PSDVAzureIdentityLoaded = $originalLoaded
            }
        }
    }
}
