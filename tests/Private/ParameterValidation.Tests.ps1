BeforeDiscovery {
    $contextCases = @(
        @{ Command = 'Get-PSDVAccessToken'; Changes = @{ ResourceUrl = 'relative/path' } }
        @{ Command = 'Get-PSDVAccessToken'; Changes = @{ ResourceUrl = [uri]'https://example.test' } }
        @{ Command = 'Get-PSDVAccessToken'; Changes = @{ ParameterSetName = 'Unsupported' } }
        @{ Command = 'Get-PSDVAccessToken'; Changes = @{ Credential = 'not-a-credential' } }
        @{ Command = 'Get-PSDVAccessToken'; Changes = @{ ParameterSetName = 'SystemManagedIdentity'; ManagedIdentityTokenSource = 'Unsupported' } }
        @{ Command = 'Get-PSDVFunctionRuntimeManagedIdentityAccessToken'; Changes = @{ ResourceUrl = 'file:///C:/test' } }
        @{ Command = 'Get-PSDVFunctionRuntimeManagedIdentityAccessToken'; Changes = @{ ManagedIdentityID = 'not-an-identity' } }
        @{ Command = 'New-PSDVClientSecretCredential'; Changes = @{ ClientID = 'invalid' } }
        @{ Command = 'New-PSDVClientSecretCredential'; Changes = @{ AzureTenantId = ' ' } }
        @{ Command = 'New-PSDVClientSecretCredential'; Changes = @{ AzureTenantId = 'tenant/invalid' } }
        @{ Command = 'New-PSDVClientSecretCredential'; Changes = @{ ClientSecret = 'plaintext' } }
        @{ Command = 'New-PSDVClientSecretCredential'; Changes = @{ ClientSecret = [securestring]::new() } }
        @{ Command = 'New-PSDVClientCertificateCredential'; Changes = @{ ClientID = [guid]::Empty.ToString() } }
        @{ Command = 'New-PSDVClientCertificateCredential'; Changes = @{ Certificate = 'not-a-certificate' } }
        @{ Command = 'New-PSDVClientCertificateCredential'; Changes = @{ CertificateThumbprint = 'not hex' } }
        @{ Command = 'New-PSDVClientCertificateCredential'; Changes = @{ CertificateThumbprint = 123 } }
        @{ Command = 'New-PSDVClientCertificateCredential'; Changes = @{ CertificatePassword = 'plaintext' } }
        @{ Command = 'New-PSDVInteractiveCredential'; Changes = @{ AzureTenantId = '' } }
        @{ Command = 'New-PSDVInteractiveCredential'; Changes = @{ UseDeviceCode = 'false' } }
        @{ Command = 'New-PSDVManagedIdentityCredential'; Changes = @{ ManagedIdentityID = 'invalid' } }
        @{ Command = 'New-PSDVManagedIdentityCredential'; Changes = @{ ManagedIdentityID = [guid]::Empty.ToString() } }
    )
    $scalarCases = @(
        @{ Command = 'Get-PSDVEntitySetFromLogicalName'; Parameter = 'Table'; Value = ' '; Arguments = @{} }
        @{ Command = 'Get-PSDVAzureAuthorityHost'; Parameter = 'Environment'; Value = 'Unsupported'; Arguments = @{} }
        @{ Command = 'New-PSDVBatchRequest'; Parameter = 'EntitySet'; Value = ' '; Arguments = @{ Operation = 'Create'; Items = @() } }
        @{ Command = 'New-PSDVBatchRequest'; Parameter = 'Operation'; Value = 'Unsupported'; Arguments = @{ EntitySet = 'accounts'; Items = @() } }
        @{ Command = 'New-PSDVBatchRequest'; Parameter = 'Items'; Value = @(@{ ItemData = 'invalid' }); Arguments = @{ EntitySet = 'accounts'; Operation = 'Create' } }
        @{ Command = 'ConvertFrom-PSDVBatchResponse'; Parameter = 'ExpectedCount'; Value = -1; Arguments = @{ BatchResponse = $null } }
        @{ Command = 'Set-PSDVAccessToken'; Parameter = 'Operation'; Value = ' '; Arguments = @{} }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'PrivateTestCommon.ps1')
    & $script:PSDVModule { Import-PSDVAzureIdentityAssemblies }
}

Describe 'Private parameter validation' {
    BeforeEach {
        Mock Invoke-WebRequest -ModuleName Dataverse { throw 'Unexpected HTTP request' }
        Mock Invoke-RestMethod -ModuleName Dataverse { throw 'Unexpected token request' }
        Mock Import-PSDVAzureIdentityAssemblies -ModuleName Dataverse { throw 'Unexpected SDK load' }
    }

    AfterEach {
        $Global:DATAVERSEAUTHCONTEXT = $null
        $Global:DATAVERSEACCESSTOKEN = $null
    }

    It '<Command> rejects malformed context fields before SDK work' -ForEach $contextCases {
        InModuleScope Dataverse -Parameters @{ Command = $Command; Changes = $Changes } {
            param($Command, $Changes)
            $context = New-PSDVTestAuthContext
            $context.ClientSecret = (New-PSDVTestSecureString).SecureString
            foreach ($key in $Changes.Keys) { $context[$key] = $Changes[$key] }
            $caught = $null
            try { & $Command -AuthContext $context -ErrorAction Stop }
            catch { $caught = $_ }
            $caught.Exception | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
        }
        Should -Invoke Import-PSDVAzureIdentityAssemblies -ModuleName Dataverse -Times 0 -Exactly
        Should -Invoke Invoke-RestMethod -ModuleName Dataverse -Times 0 -Exactly
    }

    It '<Command> rejects invalid <Parameter> before I/O' -ForEach $scalarCases {
        InModuleScope Dataverse -Parameters @{ Command = $Command; Parameter = $Parameter; Value = $Value; Arguments = $Arguments } {
            param($Command, $Parameter, $Value, $Arguments)
            $inputArguments = $Arguments.Clone()
            $inputArguments[$Parameter] = $Value
            $caught = $null
            try { & $Command @inputArguments -ErrorAction Stop }
            catch { $caught = $_ }
            $caught.Exception | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
        }
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
        Should -Invoke Import-PSDVAzureIdentityAssemblies -ModuleName Dataverse -Times 0 -Exactly
    }

    It 'rejects malformed batch request objects before token acquisition or HTTP' -ForEach @(
        @{ Value = @{ BatchBoundary = ' '; BatchBody = 'body'; RequestedCount = 1 } }
        @{ Value = @{ BatchBoundary = "batch`r`ninvalid"; BatchBody = 'body'; RequestedCount = 1 } }
        @{ Value = @{ BatchBoundary = 'batch'; BatchBody = ''; RequestedCount = 1 } }
        @{ Value = @{ BatchBoundary = 'batch'; BatchBody = 'body'; RequestedCount = -1 } }
        @{ Value = @{ BatchBoundary = 'batch'; BatchBody = 'body'; RequestedCount = 'not-a-count' } }
        @{ Value = @{ BatchBoundary = 'batch'; BatchBody = 'body'; RequestedCount = 1.5 } }
    ) {
        InModuleScope Dataverse -Parameters @{ Value = $Value } {
            param($Value)
            { Invoke-PSDVBatchRequest -BatchRequest ([pscustomobject]$Value) } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }

    It 'rejects malformed nested update IDs and missing upsert requirements before serialization' {
        InModuleScope Dataverse {
            foreach ($id in @('invalid', [guid]::Empty)) {
                { New-PSDVBatchRequest -EntitySet accounts -Operation Update -Items @(@{ ItemID = $id; ItemData = @{} }) } |
                    Should -Throw '*non-empty ItemID GUID*'
            }
            { New-PSDVBatchRequest -EntitySet accounts -Operation Upsert -Items @(@{ ItemData = @{} }) } |
                Should -Throw '*AlternateKeyColumnName*'
            { New-PSDVBatchRequest -EntitySet accounts -Operation Upsert -AlternateKeyColumnName accountnumber -Items @(@{ ItemData = @{} }) } |
                Should -Throw '*alternate key value*'
            { New-PSDVBatchRequest -EntitySet accounts -Operation Create -ParseItemData -Items @(@{ ItemData = @{} }) } |
                Should -Throw '*AttributeDetails*'
        }
    }

    It 'rejects absent selectors and incomplete lookup metadata before web or lookup operations' {
        InModuleScope Dataverse {
            { Confirm-PSDVItemDataAttributes -ItemData @{} -Table '' -EntitySet '' } | Should -Throw '*Table or EntitySet*'
            { ConvertTo-PSDVLookupItemData -ItemData @{ name = 'Test' } -AttributeDetails @{} } |
                Should -Throw '*missing metadata*'
            { ConvertTo-PSDVLookupItemData -ItemData @{ parentaccountid = [guid]::NewGuid() } `
                -AttributeDetails @{ parentaccountid = @{ AttributeType = 'Lookup'; SchemaName = 'parentaccountid'; Targets = 'account' } } } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }

    It 'retains all blank authority fallbacks and sovereign cloud names' {
        InModuleScope Dataverse {
            foreach ($value in @($null, '', ' ', "`t")) {
                (Get-PSDVAzureAuthorityHost -Environment $value).AbsoluteUri | Should -BeExactly 'https://login.microsoftonline.com/'
            }
            (Get-PSDVAzureAuthorityHost -Environment AzureChinaCloud).AbsoluteUri | Should -BeExactly 'https://login.chinacloudapi.cn/'
        }
    }

    It 'preserves empty dictionaries, literals, null responses, and empty batches' {
        InModuleScope Dataverse {
            ConvertTo-PSDVODataStringLiteral -Value '' | Should -BeExactly "''"
            ConvertTo-PSDVXmlAttributeValue -Value '' | Should -BeNullOrEmpty
            Join-PSDVQueryString -QueryParameters @{} | Should -BeExactly ''
            Join-PSDVQueryString -QueryParameters @{ '$filter' = $null; '$select' = ' ' } | Should -BeExactly ''
            (ConvertTo-PSDVLookupItemData -ItemData @{} -AttributeDetails @{}).Count | Should -Be 0
            (ConvertFrom-PSDVBatchResponse -BatchResponse $null -ExpectedCount 0).RequestedCount | Should -Be 0
            (New-PSDVBatchRequest -EntitySet accounts -Operation Create -Items @()).RequestedCount | Should -Be 0
            $emptyPassword = [securestring]::new()
            ConvertFrom-PSDVSecureString -SecureString $emptyPassword | Should -BeExactly ''
        }
    }

    It 'preserves prebound lookups and null payload values without requiring unused lookup metadata' {
        InModuleScope Dataverse {
            $result = ConvertTo-PSDVLookupItemData -ItemData @{ 'parentaccountid@odata.bind' = $null } `
                -AttributeDetails @{ 'parentaccountid@odata.bind' = @{} }
            $result.ContainsKey('parentaccountid@odata.bind') | Should -BeTrue
            $result['parentaccountid@odata.bind'] | Should -BeNullOrEmpty
        }
    }

    It 'preserves managed identity omission, GUID IDs, and resource IDs' {
        Mock Import-PSDVAzureIdentityAssemblies -ModuleName Dataverse {}
        InModuleScope Dataverse {
            foreach ($value in @($null, '', ' ', [guid]::NewGuid().ToString(),
                '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test')) {
                $credential = New-PSDVManagedIdentityCredential -AuthContext @{ ManagedIdentityID = $value }
                $credential.GetType().FullName | Should -BeExactly 'Azure.Identity.ManagedIdentityCredential'
            }
        }
    }

    It 'preserves cached credentials without imposing unused identity fields' {
        Mock Import-PSDVAzureIdentityAssemblies -ModuleName Dataverse {}
        InModuleScope Dataverse {
            $credential = [pscustomobject]@{}
            $credential | Add-Member -MemberType ScriptMethod -Name GetToken -Value {
                param($Context, $CancellationToken)
                [pscustomobject]@{ Token = 'test-token'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) }
            }
            $token = Get-PSDVAccessToken -AuthContext @{ ResourceUrl = 'https://example.test/'; Credential = $credential }
            $token.Token | Should -BeOfType ([securestring])
        }
    }

    It 'rejects malformed supplied or cached token values explicitly' {
        InModuleScope Dataverse {
            $context = New-PSDVTestAuthContext
            { Set-PSDVAccessToken -AuthContext $context -AccessToken ([pscustomobject]@{
                Token = 'plaintext'; ExpiresOn = [DateTime]::UtcNow.AddHours(1)
            }) } | Should -Throw '*nonempty SecureString Token*'
            { Set-PSDVAccessToken -AuthContext $context -AccessToken ([pscustomobject]@{
                Token = (New-PSDVTestSecureString).SecureString; ExpiresOn = 'not-a-date'
            }) } | Should -Throw '*valid ExpiresOn*'
            $Global:DATAVERSEACCESSTOKEN = [pscustomobject]@{ Token = 'invalid'; ExpiresOn = 'invalid' }
            { Set-PSDVAccessToken -AuthContext $context } | Should -Throw '*cached access token*'
        }
    }

    It 'preserves error diagnostics even when the failed URI itself is malformed' {
        InModuleScope Dataverse {
            $original = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Invalid URI'), 'InvalidUri', [System.Management.Automation.ErrorCategory]::InvalidArgument, $null
            )
            $result = New-PSDVWebRequestErrorRecord -OriginalError $original -Method Patch -RequestUri 'not a URI' -MessagePrefix 'Request failed:'
            [object]::ReferenceEquals($result.Exception.InnerException, $original.Exception) | Should -BeTrue
            { New-PSDVWebRequestErrorRecord -OriginalError $original -Method ' ' -RequestUri 'invalid' -MessagePrefix 'Request failed:' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }
    }
}
