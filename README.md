# Dataverse PowerShell Module

A comprehensive PowerShell module for interacting with Microsoft Dataverse environments. This module provides full CRUD operations, authentication management, and advanced querying capabilities for Dataverse tables and records.

## Features

- **Multiple Authentication Methods**: Support for Service Principal, Managed Identity, and Interactive authentication
- **Comprehensive CRUD Operations**: Create, Read, Update, and Delete operations for Dataverse records
- **Advanced Querying**: OData filters, field selection, record expansion, and automatic pagination
- **Metadata Operations**: Retrieve table and column metadata information
- **Audit and Change Tracking**: Access audit history and detailed change tracking
- **Webhook Management**: Register, inspect, update, and remove Dataverse table webhooks
- **PowerShell 7.3+ Compatible**: Modern PowerShell support
- **PSScriptAnalyzer Compliant**: Follows PowerShell best practices and coding standards

## Prerequisites

- PowerShell 7.3 or later
- Appropriate permissions to access your Dataverse environment

The module bundles a pinned Azure.Identity SDK dependency set under `lib/netstandard2.0`, so client machines do not need Az.Accounts or NuGet package installation for authentication. Managed identity authentication can optionally use the Azure Functions/App Service runtime endpoint directly to avoid loading Azure.Identity in hosts that already load conflicting MSAL or identity assemblies.

The `lib/netstandard2.0` DLLs are intentionally committed with the module so authentication works on machines that cannot install NuGet packages at runtime. Update those DLLs as a single dependency set to avoid mixed Azure.Identity/MSAL versions.

## Installation

### Install from a PowerShell repository

```powershell
Install-Module -Name Dataverse -Scope CurrentUser
```

To download the module without installing it into a module path, use `Save-Module`:

```powershell
Save-Module -Name Dataverse -Path .\Modules
$env:PSModulePath = ".\Modules$([IO.Path]::PathSeparator)$env:PSModulePath"
Import-Module Dataverse
```

If you publish the module to a private repository, pass the repository name to either cmdlet:

```powershell
Install-Module -Name Dataverse -Repository "YourRepository" -Scope CurrentUser
Save-Module -Name Dataverse -Repository "YourRepository" -Path .\Modules
```

### Import the module

```powershell
Import-Module Dataverse
```

### Verify Installation

```powershell
Get-Module Dataverse -ListAvailable
Get-Command -Module Dataverse
```

## Quick Start

### 1. Connect to Dataverse

#### Interactive Authentication

```powershell
Connect-PSDVOrg -AzureTenantId "your-tenant-id" `
                -DataverseOrgURL "https://yourorg.crm.dynamics.com/"
```

Interactive authentication uses browser-based Azure.Identity authentication by default, which supports MFA and Conditional Access. Use `-UseDeviceCode` only when browser authentication is not available.

#### Service Principal Authentication

```powershell
$secret = ConvertTo-SecureString "your-client-secret" -AsPlainText -Force
Connect-PSDVOrg -ClientID "your-client-id" `
                -ClientSecret $secret `
                -AzureTenantId "your-tenant-id" `
                -DataverseOrgURL "https://yourorg.crm.dynamics.com/"
```

#### Service Principal Certificate Authentication

```powershell
Connect-PSDVOrg -ClientID "your-client-id" `
                -CertificateThumbprint "certificate-thumbprint" `
                -AzureTenantId "your-tenant-id" `
                -DataverseOrgURL "https://yourorg.crm.dynamics.com/"

$certPassword = ConvertTo-SecureString "pfx-password" -AsPlainText -Force
Connect-PSDVOrg -ClientID "your-client-id" `
                -CertificatePath "C:\certs\app-auth.pfx" `
                -CertificatePassword $certPassword `
                -AzureTenantId "your-tenant-id" `
                -DataverseOrgURL "https://yourorg.crm.dynamics.com/"
```

For sovereign clouds, add `-Environment AzureUSGovernment`, `-Environment AzureChinaCloud`, or `-Environment AzureGermanCloud` to interactive, client secret, or certificate authentication.

#### Managed Identity Authentication

```powershell
# System-assigned managed identity
Connect-PSDVOrg -UseSystemManagedIdentity `
                -DataverseOrgURL "https://yourorg.crm.dynamics.com/"

# User-assigned managed identity
Connect-PSDVOrg -ManagedIdentityID "your-managed-identity-client-id" `
                -DataverseOrgURL "https://yourorg.crm.dynamics.com/"

# Azure Functions/App Service runtime endpoint without loading Azure.Identity
Connect-PSDVOrg -UseSystemManagedIdentity `
                -ManagedIdentityTokenSource FunctionRuntime `
                -DataverseOrgURL "https://yourorg.crm.dynamics.com/"
```

Managed identity uses Azure.Identity by default for broad Azure host compatibility. Use `-ManagedIdentityTokenSource FunctionRuntime` only in Azure Functions or App Service environments where the managed identity runtime endpoint is available through `IDENTITY_ENDPOINT` and `IDENTITY_HEADER`, or legacy App Service environments that expose `MSI_ENDPOINT` and `MSI_SECRET`. Azure VMs and other hosts should use the default AzureIdentity token source.

#### Bearer Token Authentication

When you already have a bearer token for the Dataverse resource (for example from `Get-AzAccessToken` or `az account get-access-token`), pass it directly. The module uses the token as-is and does not load Azure.Identity, which avoids assembly conflicts in hosts that preload other Azure modules (such as Azure Cloud Shell).

```powershell
# Acquire a token with Az PowerShell and pass it to the module
$token = Get-AzAccessToken -ResourceUrl "https://yourorg.crm.dynamics.com/" -AsSecureString
Connect-PSDVOrg -AccessToken $token.Token `
                -AccessTokenExpiresOn $token.ExpiresOn `
                -DataverseOrgURL "https://yourorg.crm.dynamics.com/"

# Acquire a token with the Azure CLI
$cliToken = az account get-access-token --resource "https://yourorg.crm.dynamics.com/" | ConvertFrom-Json
$secureToken = ConvertTo-SecureString $cliToken.accessToken -AsPlainText -Force
Connect-PSDVOrg -AccessToken $secureToken `
                -AccessTokenExpiresOn ([DateTimeOffset]$cliToken.expiresOn) `
                -DataverseOrgURL "https://yourorg.crm.dynamics.com/"
```

A supplied token cannot be refreshed automatically. When it expires, run `Connect-PSDVOrg` again with a fresh token. If `-AccessTokenExpiresOn` is omitted, the module reads the expiration from the token's `exp` claim when possible.

`-SubscriptionId` is a deprecated compatibility parameter for older examples. It is no longer used and is planned for removal in the next major version.

Disconnect when you are finished to clear the session-scoped connection state:

```powershell
Disconnect-PSDVOrg
```

### 2. Basic Operations

#### Retrieve Records

```powershell
# Get all accounts
Get-PSDVTableItem -Table "account"

# Get specific account by ID
Get-PSDVTableItem -Table "account" -ItemID "12345678-1234-1234-1234-123456789012"

# Filter records
Get-PSDVTableItem -Table "contact" -Filter "firstname eq 'John'"

# Select specific fields
Get-PSDVTableItem -Table "account" -Select @("name", "telephone1", "websiteurl")
```

#### Create Records

```powershell
$accountData = @{
    name = "Contoso Corporation"
    accountnumber = "ACC001"
    telephone1 = "555-123-4567"
}
New-PSDVTableItem -Table "account" -ItemData $accountData
```

#### Update Records

```powershell
$updateData = @{
    name = "Updated Company Name"
    telephone1 = "555-987-6543"
}
Update-PSDVTableItem -Table "account" -ItemID "record-guid" -ItemData $updateData
```

#### Delete Records

```powershell
Remove-PSDVTableItem -Table "account" -ItemID "record-guid"
```

### 3. Metadata Operations

#### Get Table Information

```powershell
# Get all tables
Read-PSDVTableData

# Get detailed table metadata
Get-PSDVTableDetail -Table "account"

# Get column information
Get-PSDVTableColumn -Table "account"

# Get specific columns
Get-PSDVTableColumn -Table "account" -ColumnName @("name", "telephone1")
```

## Function Reference

### Connection Functions

- `Connect-PSDVOrg` - Establish connection to Dataverse
- `Disconnect-PSDVOrg` - Clear the current Dataverse connection state

Access tokens are refreshed automatically by Dataverse operations when they are close to expiration.

### Core Operations

- `Invoke-PSDVWebRequest` - Execute authenticated web requests
- `Get-PSDVTableItem` - Retrieve records from tables
- `New-PSDVTableItem` - Create new records
- `Update-PSDVTableItem` - Update existing records
- `Remove-PSDVTableItem` - Delete records

### Metadata Functions

- `Read-PSDVTableData` - Get all table metadata
- `Get-PSDVTableDetail` - Get detailed table information
- `Get-PSDVTableColumn` - Get column metadata

### Audit Functions

- `Get-PSDVTableItemAuditHistory` - Get audit history
- `Get-PSDVTableItemChangeHistory` - Get detailed change history

### Webhook Functions

- `New-PSDVTableWebHook` - Register a webhook for table create, update, delete, or retrieve events
- `Get-PSDVTableWebHook` - Retrieve webhook registrations for a table, with filters for operation, URL, stage, or name
- `Remove-PSDVTableWebHook` - Remove a webhook by deleting its service endpoint and associated processing steps
- `Update-PSDVTableWebHookAuthSecret` - Set, rotate, or clear the `x-dv-webhook-secret` value for an existing webhook

## Advanced Examples

### Complex Filtering and Expansion

```powershell
# Get accounts with revenue over $1M and include primary contact
Get-PSDVTableItem -Table "account" `
                  -Filter "revenue gt 1000000" `
                  -Expand "primarycontactid" `
                  -Select @("name", "revenue", "primarycontactid")
```

### Working with Lookup Fields

```powershell
# Create contact with parent account lookup
$contactData = @{
    firstname = "John"
    lastname = "Doe"
    emailaddress1 = "john.doe@contoso.com"
    parentcustomerid = "account-guid"
}
New-PSDVTableItem -Table "contact" -ItemData $contactData -ParseItemData
```

### Audit Trail Analysis

```powershell
# Get complete audit history for a record
Get-PSDVTableItemAuditHistory -Table "account" -ItemID "record-guid"

# Get detailed change history
Get-PSDVTableItemChangeHistory -Table "account" -ItemID "record-guid"
```

### Webhook Management

```powershell
# Register a webhook for account create events
New-PSDVTableWebHook -Table "account" `
                    -WebHookName "Account Create Webhook" `
                    -TriggerUri "https://myapp.azurewebsites.net/api/dataverse" `
                    -Operation "Create" `
                    -AuthSecret "shared-secret"

# Register an update webhook that only fires when selected columns change
New-PSDVTableWebHook -Table "contact" `
                    -WebHookName "Contact Email Monitor" `
                    -TriggerUri "https://myapp.azurewebsites.net/api/dataverse" `
                    -Operation "Update" `
                    -FilteringAttributes @("emailaddress1", "telephone1") `
                    -PreImage `
                    -PreImageAttributes @("emailaddress1", "telephone1")

# Review and rotate webhook secrets
$webhook = Get-PSDVTableWebHook -Table "account" -Name "Account Create Webhook"
Update-PSDVTableWebHookAuthSecret -Table "account" `
                                  -WebHookStepId $webhook.WebHookStepId `
                                  -AuthSecret "new-shared-secret"

# Remove a webhook
Remove-PSDVTableWebHook -ServiceEndpointId $webhook.ServiceEndpointId
```

Webhook registration supports pre-operation and post-operation stages, synchronous or asynchronous mode, update filtering attributes, and pre/post images for supported operations.

## Error Handling

The module includes comprehensive error handling with meaningful error messages. Common patterns:

```powershell
try {
    $result = Get-PSDVTableItem -Table "account" -ItemID "invalid-guid"
}
catch {
    Write-Error "Failed to retrieve account: $($_.Exception.Message)"
}
```

## Security Considerations

- Use Service Principal authentication for automated scenarios
- Store secrets securely using PowerShell SecureString or Azure Key Vault
- Follow the principle of least privilege for Dataverse permissions
- The module is compatible with PowerShell Constrained Language Mode (CLM)

## Troubleshooting

### Common Issues

1. **Authentication Errors**: Ensure correct tenant ID, client ID, and permissions
2. **Table Not Found**: Verify table logical names and case sensitivity
3. **Permission Denied**: Check Dataverse security roles and permissions
4. **Token Expiration**: The module automatically handles token refresh

### Verbose Logging

```powershell
# Enable verbose output for troubleshooting
Get-PSDVTableItem -Table "account" -Verbose
```

## Releasing

Pull requests targeting `dev` or `main` run the Pester suite on Windows and Ubuntu (`.github/workflows/ci.yml`). Publishing to the [PowerShell Gallery](https://www.powershellgallery.com/packages/Dataverse/) is automated by `.github/workflows/publish.yml`:

1. In a pull request, update `ModuleVersion` in `Dataverse.psd1` (and the release notes), and merge it to `main`.
2. Create a GitHub Release from `main` with the tag `v<ModuleVersion>` (for example `v1.1.1`). Prereleases are ignored.
3. The workflow reruns the tests, verifies that the tag matches the manifest version, that the commit is on `main`, and that the version is not already on the Gallery, then publishes only the module files (`Dataverse.psd1`, `Dataverse.psm1`, `LICENSE`, `Public`, `Private`, `lib`).

## Contributing

This module follows PowerShell best practices and PSScriptAnalyzer rules. When contributing:

1. Ensure PowerShell 7.3+ compatibility
2. Follow the existing code style and patterns
3. Include comprehensive help documentation
4. Test in both normal and Constrained Language Mode environments

## License

This project is licensed under the terms in [LICENSE](LICENSE).

## Support

This software is provided as-is, without warranty or guaranteed support. If you find a bug, have a question, or want to request an enhancement, open an issue in the GitHub repository with the module version, PowerShell version, and enough detail to reproduce the behavior.

## Changelog

### Version 1.1.1

- Fixed item data validation for lookup navigation properties supplied in OData bind format, such as `parentcustomerid_account@odata.bind`.
- Preserved existing OData bind entries when `-ParseItemData` is used.

### Version 1.1.0

- Removed the direct Az.Accounts dependency and use bundled Azure.Identity authentication dependencies.
- Added browser-based interactive authentication support for MFA and Conditional Access scenarios.
- Added bearer token authentication with `Connect-PSDVOrg -AccessToken` for users who acquire tokens with existing Azure tooling such as `Get-AzAccessToken` or Azure CLI.
- Added optional FunctionRuntime managed identity token acquisition for Azure Functions/App Service hosts.
- Added `Disconnect-PSDVOrg` to clear session connection state.
- Added webhook management cmdlets: `New-PSDVTableWebHook`, `Get-PSDVTableWebHook`, `Remove-PSDVTableWebHook`, and `Update-PSDVTableWebHookAuthSecret`.
- Hardened OData query encoding, pagination failure handling, token validation, GUID validation, and webhook secret escaping.
- Added automated Pester coverage across public and private module functions.
- Deprecated legacy `-SubscriptionId`, `-FilterQuery`, `-ExpandQuery`, and `-SelectFields` parameters.

### Version 1.0.0

- Initial release
- Support for all major Dataverse operations
- Multiple authentication methods
- Comprehensive help documentation
- PSScriptAnalyzer compliance
- Constrained Language Mode compatibility
