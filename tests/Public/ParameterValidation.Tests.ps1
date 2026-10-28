BeforeDiscovery {
    $id = '11111111-1111-1111-1111-111111111111'
    $row = @{ ItemData = @{ name = 'Test' }; ItemID = $id; AlternateKeyValue = 'KEY' }
    $records = @(
        @{ Command = 'Get-PSDVTableItem'; Extra = @{ ItemID = $id } }
        @{ Command = 'Get-PSDVTableItemChangeHistory'; Extra = @{ ItemID = $id } }
        @{ Command = 'New-PSDVTableItem'; Extra = @{ ItemData = @{ name = 'Test' } } }
        @{ Command = 'Update-PSDVTableItem'; Extra = @{ ItemID = $id; ItemData = @{ name = 'Test' }; IfMatch = 'W/"opaque"' } }
        @{ Command = 'Remove-PSDVTableItem'; Extra = @{ ItemID = $id } }
        @{ Command = 'Invoke-PSDVTableItemUpsert'; Extra = @{ AlternateKeyColumnName = 'accountnumber'; ItemData = @{ accountnumber = 'KEY' } } }
        @{ Command = 'New-PSDVTableItemBatch'; Extra = @{ Items = @($row) } }
        @{ Command = 'Update-PSDVTableItemBatch'; Extra = @{ Updates = @($row) } }
        @{ Command = 'Invoke-PSDVTableItemUpsertBatch'; Extra = @{ AlternateKeyColumnName = 'accountnumber'; Items = @($row) } }
    )
    $fixtures = @(
        foreach ($record in $records) {
            foreach ($selector in @('Table', 'EntitySet')) {
                $arguments = $record.Extra.Clone()
                $arguments[$selector] = if ($selector -eq 'Table') { 'account' } else { 'accounts' }
                @{ Command = $record.Command; Arguments = $arguments; Names = @($selector) + @($record.Extra.Keys | Where-Object { $_ -in @('AlternateKeyColumnName', 'IfMatch') }) }
            }
        }
        @{ Command = 'Get-PSDVTableColumn'; Arguments = @{ Table = 'account' }; Names = @('Table') }
        @{ Command = 'Get-PSDVTableDetail'; Arguments = @{ Table = 'account' }; Names = @('Table') }
        @{ Command = 'Get-PSDVTableItemAuditHistory'; Arguments = @{ Table = 'account'; ItemID = $id }; Names = @('Table') }
        @{ Command = 'Get-PSDVTableWebHook'; Arguments = @{ Table = 'account' }; Names = @('Table') }
        @{ Command = 'Invoke-PSDVWebRequest'; Arguments = @{ WebUri = 'accounts' }; Names = @('WebUri') }
        @{ Command = 'New-PSDVTableWebHook'; Arguments = @{ Table = 'account'; WebHookName = 'Test'; TriggerUri = 'https://example.test/hook' }; Names = @('Table', 'WebHookName', 'TriggerUri') }
        @{ Command = 'Remove-PSDVTableWebHook'; Arguments = @{ ServiceEndpointId = $id }; Names = @() }
        @{ Command = 'Update-PSDVTableWebHookAuthSecret'; Arguments = @{ Table = 'account'; WebHookName = 'Test' }; Names = @('Table', 'WebHookName') }
        @{ Command = 'Update-PSDVTableWebHookAuthSecret'; Arguments = @{ Table = 'account'; WebHookStepId = $id }; Names = @('Table') }
    )
    $blankCases = @(
        foreach ($fixture in $fixtures) {
            foreach ($name in $fixture.Names) {
                foreach ($invalid in @(
                    @{ Label = 'null'; Value = $null }, @{ Label = 'empty'; Value = '' },
                    @{ Label = 'spaces'; Value = '   ' }, @{ Label = 'tabs'; Value = "`t" }
                )) {
                    @{ Command = $fixture.Command; Arguments = $fixture.Arguments; Parameter = $name; Value = $invalid.Value; Label = $invalid.Label }
                }
            }
        }
    )
    $guidCases = @(
        foreach ($fixture in $fixtures) {
            foreach ($name in @('ItemID', 'ServiceEndpointId', 'WebHookStepId')) {
                if ($fixture.Arguments.ContainsKey($name)) {
                    foreach ($value in @([guid]::Empty, 'not-a-guid')) {
                        @{ Command = $fixture.Command; Arguments = $fixture.Arguments; Parameter = $name; Value = $value }
                    }
                }
            }
        }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'PublicTestCommon.ps1')
}

Describe 'Public parameter validation' {
    BeforeEach {
        Initialize-PSDVPublicTestConnection
        Mock Invoke-WebRequest -ModuleName Dataverse { throw 'Unexpected HTTP request' }
        Mock Invoke-RestMethod -ModuleName Dataverse { throw 'Unexpected token request' }
        Mock Import-PSDVAzureIdentityAssemblies -ModuleName Dataverse { throw 'Unexpected SDK load' }
    }

    AfterEach {
        Clear-PSDVPublicTestConnection
    }

    It '<Command> rejects <Label> <Parameter> at binding' -ForEach $blankCases {
        $inputArguments = $Arguments.Clone()
        $inputArguments[$Parameter] = $Value
        $caught = $null
        try { & $Command @inputArguments -ErrorAction Stop }
        catch { $caught = $_ }
        $caught.Exception | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
        Should -Invoke Import-PSDVAzureIdentityAssemblies -ModuleName Dataverse -Times 0 -Exactly
    }

    It '<Command> rejects invalid <Parameter> <Value> at binding' -ForEach $guidCases {
        $inputArguments = $Arguments.Clone()
        $inputArguments[$Parameter] = $Value
        $caught = $null
        try { & $Command @inputArguments -ErrorAction Stop }
        catch { $caught = $_ }
        $caught.Exception | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }

    It 'rejects malformed destinations before HTTP or authentication' -ForEach @(
        @{ Command = 'Connect-PSDVOrg'; Parameter = 'DataverseOrgURL'; Arguments = @{ AzureTenantId = 'organizations' } }
        @{ Command = 'New-PSDVTableWebHook'; Parameter = 'TriggerUri'; Arguments = @{ Table = 'account'; WebHookName = 'Test' } }
    ) {
        foreach ($value in @('relative/path', 'https://', 'file:///C:/test', 'not a URL')) {
            $inputArguments = $Arguments.Clone()
            $inputArguments[$Parameter] = $value
            { & $Command @inputArguments -ErrorAction Stop } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
        Should -Invoke Import-PSDVAzureIdentityAssemblies -ModuleName Dataverse -Times 0 -Exactly
    }

    It 'accepts absolute <Scheme> organization URLs and tenant aliases without authenticating for real' -ForEach @(
        @{ Scheme = 'http' }, @{ Scheme = 'https' }
    ) {
        Mock Get-PSDVAccessToken -ModuleName Dataverse { New-PSDVTestAccessToken }
        Connect-PSDVOrg -AzureTenantId 'organizations' -DataverseOrgURL "${Scheme}://example.test"
        $Global:DATAVERSEORGURL | Should -BeExactly "${Scheme}://example.test/"
        Should -Invoke Get-PSDVAccessToken -ModuleName Dataverse -Times 1 -Exactly
    }

    It 'rejects invalid client and managed identity IDs before SDK work' {
        $secret = (New-PSDVTestSecureString).SecureString
        foreach ($value in @('invalid', [guid]::Empty.ToString())) {
            { Connect-PSDVOrg -ClientID $value -ClientSecret $secret -AzureTenantId 'contoso.onmicrosoft.com' -DataverseOrgURL 'https://example.test' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            { Connect-PSDVOrg -ManagedIdentityID $value -DataverseOrgURL 'https://example.test' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }
        Should -Invoke Import-PSDVAzureIdentityAssemblies -ModuleName Dataverse -Times 0 -Exactly
    }

    It 'preserves managed identity resource IDs, tenant domains, and spaced thumbprints' {
        Mock Get-PSDVAccessToken -ModuleName Dataverse { New-PSDVTestAccessToken }
        Connect-PSDVOrg -ManagedIdentityID '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test' `
            -DataverseOrgURL 'https://example.test'
        Connect-PSDVOrg -ClientID ([guid]::NewGuid()) -AzureTenantId 'contoso.onmicrosoft.com' `
            -CertificateThumbprint ' AA BB CC DD EE FF 00 11 22 33 44 55 66 77 88 99 AA BB CC DD ' -DataverseOrgURL 'https://example.test'
        Should -Invoke Get-PSDVAccessToken -ModuleName Dataverse -Times 2 -Exactly
    }

    It 'rejects empty required secrets and past explicit token expiry without exposing secrets' {
        $emptySecret = [securestring]::new()
        { Connect-PSDVOrg -ClientID ([guid]::NewGuid()) -ClientSecret $emptySecret -AzureTenantId 'organizations' -DataverseOrgURL 'https://example.test' } |
            Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        { Connect-PSDVOrg -AccessToken $emptySecret -DataverseOrgURL 'https://example.test' } |
            Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        $token = (New-PSDVTestSecureString).SecureString
        { Connect-PSDVOrg -AccessToken $token -AccessTokenExpiresOn ([DateTimeOffset]::UtcNow.AddMinutes(-1)) -DataverseOrgURL 'https://example.test' } |
            Should -Throw -ErrorId 'ParameterArgumentValidationError*'
    }

    It 'rejects missing and directory certificate paths but accepts a relative spaced file path' {
        $folder = Join-Path $TestDrive 'certificate folder'
        $null = New-Item -ItemType Directory -Path $folder
        $file = Join-Path $folder 'test certificate.pfx'
        Set-Content -LiteralPath $file -Value 'validation-only fixture'
        $options = @{ ClientID = [guid]::NewGuid().ToString(); AzureTenantId = 'organizations'; DataverseOrgURL = 'https://example.test' }
        foreach ($path in @($folder, (Join-Path $folder 'missing.pfx'))) {
            { Connect-PSDVOrg @options -CertificatePath $path } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }
        Mock Get-PSDVAccessToken -ModuleName Dataverse { New-PSDVTestAccessToken }
        Push-Location $TestDrive
        try {
            Connect-PSDVOrg @options -CertificatePath '.\certificate folder\test certificate.pfx' -CertificatePassword ([securestring]::new())
        }
        finally { Pop-Location }
        Should -Invoke Get-PSDVAccessToken -ModuleName Dataverse -Times 1 -Exactly
    }

    It 'validates actual batch entries before logical-table metadata lookup' -ForEach @(
        @{ Command = 'New-PSDVTableItemBatch'; Parameter = 'Items'; Entry = @{ ItemData = 'invalid' }; Extra = @{} }
        @{ Command = 'Update-PSDVTableItemBatch'; Parameter = 'Updates'; Entry = @{ ItemID = 'not-a-guid'; ItemData = @{} }; Extra = @{} }
        @{ Command = 'Update-PSDVTableItemBatch'; Parameter = 'Updates'; Entry = @{ ItemID = [guid]::Empty; ItemData = @{} }; Extra = @{} }
        @{ Command = 'Invoke-PSDVTableItemUpsertBatch'; Parameter = 'Items'; Entry = @{ ItemData = @{} }; Extra = @{ AlternateKeyColumnName = 'accountnumber' } }
    ) {
        $options = $Extra.Clone()
        $options.Table = 'account'
        $options[$Parameter] = @($Entry)
        { & $Command @options -ErrorAction Stop } | Should -Throw
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }

    It 'preserves empty batches and native null-entry rejection' -ForEach @(
        @{ Command = 'New-PSDVTableItemBatch'; Parameter = 'Items'; Extra = @{} }
        @{ Command = 'Update-PSDVTableItemBatch'; Parameter = 'Updates'; Extra = @{} }
        @{ Command = 'Invoke-PSDVTableItemUpsertBatch'; Parameter = 'Items'; Extra = @{ AlternateKeyColumnName = 'accountnumber' } }
    ) {
        $options = $Extra.Clone()
        $options.Table = 'account'
        $options[$Parameter] = @()
        $result = & $Command @options
        $result.RequestedCount | Should -Be 0
        $options[$Parameter] = @($null, $null)
        { & $Command @options } | Should -Throw -ErrorId 'ParameterArgumentValidationErrorNullNotAllowed*'
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }

    It 'rejects blank list entries but preserves omitted, null, and empty selections' {
        Mock Invoke-WebRequest -ModuleName Dataverse { New-PSDVPublicTestWebResponse -Payload @{ value = @() } }
        { Get-PSDVTableItem -EntitySet accounts -Select @('name', ' ') } | Should -Throw '*Select entries*'
        { Get-PSDVTableColumn -Table account -ColumnName @('name', $null) } | Should -Throw '*ColumnName entries*'
        { New-PSDVTableWebHook -Table account -WebHookName Test -TriggerUri 'https://example.test' -Operation Update -FilteringAttributes @('name', '') } |
            Should -Throw '*FilteringAttributes entries*'
        Get-PSDVTableItem -EntitySet accounts -Select $null | Should -BeNullOrEmpty
        Get-PSDVTableItem -EntitySet accounts -Select @() | Should -BeNullOrEmpty
        Get-PSDVTableItem -EntitySet accounts -Filter ' ' | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 3 -Exactly
    }

    It 'preserves empty request dictionaries and query syntax in a relative WebUri' {
        Mock Invoke-WebRequest -ModuleName Dataverse { New-PSDVPublicTestWebResponse -Payload @{ value = @() } }
        Invoke-PSDVWebRequest -WebUri 'accounts?$select=name' -Headers @{} -Body @{} | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*accounts*select=name*' -and $Method -eq 'Post'
        }
    }

    It 'retains native numeric and enum boundaries for <Command>' -ForEach @(
        @{ Command = 'Get-PSDVTableItem'; Arguments = @{ EntitySet = 'accounts'; Top = 0 } }
        @{ Command = 'Get-PSDVTableItem'; Arguments = @{ EntitySet = 'accounts'; Top = 5001 } }
        @{ Command = 'Invoke-PSDVWebRequest'; Arguments = @{ WebUri = 'accounts'; MaxPageSize = 0 } }
        @{ Command = 'Invoke-PSDVWebRequest'; Arguments = @{ WebUri = 'accounts'; MaxPageSize = 5001 } }
        @{ Command = 'Invoke-PSDVWebRequest'; Arguments = @{ WebUri = 'accounts'; Method = 'Unsupported' } }
        @{ Command = 'Get-PSDVTableWebHook'; Arguments = @{ Table = 'account'; Stage = 'Unsupported' } }
        @{ Command = 'New-PSDVTableWebHook'; Arguments = @{ Table = 'account'; WebHookName = 'Test'; TriggerUri = 'https://example.test'; Rank = 0 } }
        @{ Command = 'New-PSDVTableWebHook'; Arguments = @{ Table = 'account'; WebHookName = 'Test'; TriggerUri = 'https://example.test'; Mode = 'Unsupported' } }
    ) {
        { & $Command @Arguments -ErrorAction Stop } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -Exactly
    }

    It 'preserves the valid page-size boundaries' {
        Mock Invoke-WebRequest -ModuleName Dataverse { New-PSDVPublicTestWebResponse -Payload @{ value = @() } }
        foreach ($size in @(1, 5000)) {
            Invoke-PSDVWebRequest -WebUri accounts -Top $size -MaxPageSize $size | Should -BeNullOrEmpty
        }
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 2 -Exactly
    }

    It 'preserves legacy query parameters while rejecting a blank mandatory legacy filter' {
        Mock Invoke-WebRequest -ModuleName Dataverse { New-PSDVPublicTestWebResponse -Payload @{ value = @() } }
        { Get-PSDVTableItem -Table account -FilterQuery ' ' } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        Get-PSDVTableItem -EntitySet accounts -FilterQuery 'statecode eq 0' -SelectFields @() -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly
    }
}
