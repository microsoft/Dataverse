# Dataverse PowerShell Module

A comprehensive PowerShell module for interacting with Microsoft Dataverse environments. This module provides full CRUD operations, authentication management, and advanced querying capabilities for Dataverse tables and records.

## Features

- **Multiple Authentication Methods**: Support for Service Principal, Managed Identity, and Interactive authentication
- **Comprehensive CRUD Operations**: Create, Read, Update, and Delete operations for Dataverse records
- **Advanced Querying**: OData filters, field selection, record expansion, automatic pagination, and page-by-page streaming for large queries
- **Metadata Operations**: Retrieve table and column metadata information
- **Audit and Change Tracking**: Access audit history and detailed change tracking
- **Webhook Management**: Register, inspect, update, and remove Dataverse table webhooks
- **PowerShell 7.6+ Compatible**: Modern PowerShell support
- **PSScriptAnalyzer Compliant**: Follows PowerShell best practices and coding standards

## Prerequisites

- PowerShell 7.6 or later (version 1.1.1 is the latest release that supports PowerShell 7.3-7.5; install it with `Install-Module Dataverse -RequiredVersion 1.1.1`)
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

$batchCreates = @(
    @{ ItemData = @{ name = "First Company"; accountnumber = "ACC001" } },
    @{ ItemData = @{ name = "Second Company"; accountnumber = "ACC002" } }
)
$batchCreateResult = New-PSDVTableItemBatch -Table "account" -Items $batchCreates
```

#### Update Records

```powershell
$updateData = @{
    name = "Updated Company Name"
    telephone1 = "555-987-6543"
}
Update-PSDVTableItem -Table "account" -ItemID "record-guid" -ItemData $updateData

$upsertData = @{
    accountnumber = "ACC001"
    name = "Upserted Company Name"
}
Invoke-PSDVTableItemUpsert -Table "account" -AlternateKeyColumnName "accountnumber" -ItemData $upsertData

Invoke-PSDVTableItemUpsert -Table "account" `
                          -AlternateKeyColumnName "accountnumber" `
                          -AlternateKeyValue "ACC003" `
                          -ItemData @{ name = "Create Only Company" } `
                          -CreateOnly

$batchUpdates = @(
    @{ ItemID = "first-record-guid"; ItemData = @{ name = "First Updated Company" } },
    @{ ItemID = "second-record-guid"; ItemData = @{ name = "Second Updated Company" } }
)
$batchUpdateResult = Update-PSDVTableItemBatch -Table "account" -Updates $batchUpdates

$batchUpserts = @(
    @{ AlternateKeyValue = "ACC001"; ItemData = @{ name = "First Upserted Company" } },
    @{ ItemData = @{ accountnumber = "ACC002"; name = "Second Upserted Company" } }
)
$batchUpsertResult = Invoke-PSDVTableItemUpsertBatch -Table "account" -AlternateKeyColumnName "accountnumber" -Items $batchUpserts

$batchCreateOnlyResult = Invoke-PSDVTableItemUpsertBatch -Table "account" `
                                                        -AlternateKeyColumnName "accountnumber" `
                                                        -Items $batchUpserts `
                                                        -CreateOnly
```

Batch commands return categorized per-request status results. Status codes `200`, `201`, and `204` count as `Created`; `409` and `412` count as `AlreadyExists`; all other or missing per-request statuses count as `Failed`.

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

- `Invoke-PSDVWebRequest` - Execute authenticated web requests, with optional `-MaxPageSize` and `-AsPages` support for large paged result sets, and `-SkipHttpErrorCheck` to inspect HTTP error responses
- `Get-PSDVTableItem` - Retrieve records from tables
- `New-PSDVTableItem` - Create new records
- `Update-PSDVTableItem` - Update records, optionally conditioned on an opaque ETag with `-IfMatch`
- `Invoke-PSDVTableItemUpsert` - Upsert one record by alternate key, with optional create-only behavior
- `New-PSDVTableItemBatch` - Create multiple records in one Dataverse batch request
- `Update-PSDVTableItemBatch` - Update multiple records by ID in one Dataverse batch request
- `Invoke-PSDVTableItemUpsertBatch` - Upsert multiple records by alternate key in one Dataverse batch request
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

### Large Query Page Streaming

Use `-MaxPageSize` to request a Dataverse OData page size and `-AsPages` to process each page before the next page is requested. Each page object includes `PageNumber`, `Count`, `Results`, and `NextLink`.

```powershell
Invoke-PSDVWebRequest -WebUri "accounts" -MaxPageSize 1000 -AsPages | ForEach-Object {
    $page = $_

    foreach ($account in $page.Results) {
        # Process this page before the next Dataverse page is requested
        $account.name
    }
}
```

### Handling Expected HTTP Errors

HTTP errors throw by default. Use `-SkipHttpErrorCheck -ReturnRawResponse` to inspect a non-success response's `StatusCode`, `Headers`, and unchanged body in `Content`. For example, a conditional PATCH can return HTTP 412 when another process has changed the record:

```powershell
$response = Invoke-PSDVWebRequest `
    -WebUri "accounts($accountId)" `
    -Method Patch `
    -Headers @{ 'If-Match' = $etag } `
    -Body @{ description = 'Updated description' } `
    -ReturnRawResponse `
    -SkipHttpErrorCheck

if ($response.StatusCode -eq 412) {
    Write-Warning 'Another process changed the row; skip or reconcile.'
}
elseif ($response.StatusCode -ge 400) {
    throw "Dataverse returned HTTP $($response.StatusCode): $($response.Content)"
}
```

The switch only skips HTTP-status error checks; transport failures (such as connection failures or timeouts) still throw. Omitting the switch or passing `-SkipHttpErrorCheck:$false` preserves the default behavior.

`-SkipHttpErrorCheck` can also be used without `-ReturnRawResponse`. Normal JSON parsing, collection, and page-output rules still apply, including parsing errors for non-JSON bodies. It is forwarded on both the initial request and subsequent pagination requests.

### ETag-Based Optimistic Concurrency

Use the row's `@odata.etag` unchanged to avoid overwriting a concurrent edit. Both `-Table` and `-EntitySet` support `-IfMatch`.

```powershell
$row = Get-PSDVTableItem -EntitySet accounts -ItemID $accountId

try {
    $updatedRow = Update-PSDVTableItem `
        -EntitySet accounts `
        -ItemID $accountId `
        -ItemData @{ name = 'Updated name' } `
        -IfMatch $row.'@odata.etag' `
        -ReturnItem `
        -ErrorAction Stop

    $newETag = $updatedRow.'@odata.etag'
}
catch {
    if ($_.FullyQualifiedErrorId -like 'PSDVPreconditionFailed*') {
        $details = $_.Exception.Data['PSDVHttpError']
        Write-Warning "Concurrency conflict (HTTP $($details.HttpStatusCode)); skip or reconcile."
    }
    else {
        throw
    }
}
```

| `-IfMatch` value | Meaning |
| --- | --- |
| Specific ETag, such as `W/"123456"` | Update only the retrieved row version. Dataverse optimistic concurrency must be enabled for the table. |
| `*` | Update only if the row exists. This does **not** prevent overwriting intervening edits. A missing row returns HTTP 404 rather than being created. |
| Omitted | Preserve the existing unconditional request behavior. |

Explicit null, empty, and whitespace-only conditions are rejected before any request. ETags are opaque: the module does not trim, quote, or convert the supplied value. Existing field validation, lookup parsing, and `-WhatIf` behavior remain supported; `-WhatIf` prevents the PATCH but can still read metadata.

`-ReturnItem` requests `Prefer: odata.include-annotations="*",return=representation`. With `-IfMatch`, the returned PATCH body must contain the persisted row and a nonblank string `@odata.etag`. The module does not mutate the original row, fabricate an ETag, or issue a follow-up GET that could observe another writer. Missing representations or ETags terminate with `PSDVUpdateRepresentationMissing` or `PSDVUpdateETagMissing`. **The write may already have succeeded when response validation fails.** Unconditional `-ReturnItem` behavior is unchanged.

Conditional writes are never automatically retried, refreshed with a newer ETag, or downgraded to unconditional writes. A connection failure or timeout can occur after a write commits; it does not confirm success or a concurrency conflict. The application owns re-reading and deciding whether its business operation can safely resume. Blind replay can return HTTP 412 even if the original attempt succeeded.

### Structured Request Errors

By default, `Invoke-PSDVWebRequest` raises terminating PowerShell error records for HTTP failures. Update commands preserve this contract. Match `FullyQualifiedErrorId` prefixes, since PowerShell may append command context:

| Error ID prefix | Meaning |
| --- | --- |
| `PSDVPreconditionFailed` | HTTP 412; category `ResourceBusy`. |
| `PSDVHttpError` | Other HTTP failures; category `InvalidOperation`. Inspect the numeric status to distinguish 401, 403, 404, 429, and server failures. |
| `PSDVWebRequestFailed` | Request/transport failure without a received HTTP response; no fabricated HTTP status. |

For HTTP failures, `$_.Exception.Data['PSDVHttpError']` contains:

| Property | Contract |
| --- | --- |
| `HttpStatusCode` | Integer HTTP status code. |
| `DataverseErrorCode` | Server `error.code` string, or null when absent. |
| `DataverseErrorMessage` | Server `error.message` string, or null when absent. |
| `ResponseHeaders` | Case-insensitive dictionary of header names to string arrays, including diagnostic response/content headers and `Retry-After` when supplied. |
| `ResponseBody` | Response text, including non-JSON content; native error details are used when content is unavailable. |
| `Method` | Effective method of the failed request. |
| `RequestUri` | Failed request URI, including the actual continuation URI for pagination failures. |

For example, inside a catch block:

```powershell
$details = $_.Exception.Data['PSDVHttpError']
if ($null -ne $details) {
    $details.HttpStatusCode
    $details.DataverseErrorCode
    $details.DataverseErrorMessage
    $details.ResponseHeaders['x-ms-service-request-id']
}
$originalException = $_.Exception.InnerException
```

The original native request exception is retained as `InnerException`; outgoing authorization headers and bearer tokens are not copied into the structured data. Empty or malformed HTTP error bodies do not replace the HTTP failure with a JSON parsing error. Ordinary successful-response JSON parsing errors remain distinct.

This improves the previous string-only error API: error IDs and structured exception data are now documented, while exception-message text is not a stable contract. Requests still throw by default. `-SkipHttpErrorCheck` and `-ReturnRawResponse` retain their existing behavior; bypassing the HTTP check returns the response through normal handling rather than creating a structured HTTP error.

### Running Concurrency Tests

The focused unit tests use deterministic HTTP fixtures and a stateful competing-writer mock:

```powershell
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path .\tests\Private\New-PSDVWebRequestErrorRecord.Tests.ps1,
    .\tests\Public\Invoke-PSDVWebRequest.Tests.ps1,
    .\tests\Public\Update-PSDVTableItem.Tests.ps1
```

The Integration-tagged test is skipped by default. It creates and deletes uniquely identified test-owned rows and launches two workers using the same original ETag. Use **only a disposable Dataverse test environment**, with a dedicated table that has optimistic concurrency enabled and permits creation with its primary ID and one writable text column. It must not require additional fields or plug-in side effects.

Before opting in, configure these process environment variables through your local secret-management or CI mechanism:

| Variable | Required value |
| --- | --- |
| `PSDV_INTEGRATION_ORG_URL` | Test organization's HTTPS URL. |
| `PSDV_INTEGRATION_ACCESS_TOKEN` | Short-lived bearer JWT for that organization, with enough remaining validity and test-table permissions. Do not commit or log it. |
| `PSDV_INTEGRATION_ENTITY_SET` | Dedicated test table's entity set name. |
| `PSDV_INTEGRATION_TEXT_COLUMN` | Writable text column used for test payloads. |

```powershell
$env:PSDV_RUN_INTEGRATION_TESTS = '1'
try {
    Invoke-Pester -Path .\tests\Integration\Update-PSDVTableItem.Concurrency.Tests.ps1 -Tag Integration
}
finally {
    Remove-Item Env:\PSDV_RUN_INTEGRATION_TESTS
}
```

Explicit opt-in with missing prerequisites fails clearly. A skipped live test is not evidence that server-side concurrency was verified.

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

## Input Validation

Public and private functions validate arguments using native PowerShell parameter types and validation attributes wherever possible. Required names and request paths must not be blank; record, webhook-step, and service-endpoint GUIDs must not be the zero GUID. Existing enum choices and numeric limits still apply.

- Organization and webhook destination URLs must be absolute HTTP(S) URLs with a host. Request `-WebUri` still accepts full URLs, relative API paths, resource names, and OData queries. Shape validation does not override PowerShell's authentication transport security requirements; use HTTPS for Dataverse.
- Client IDs must be non-empty GUIDs. Tenant IDs continue to support tenant domains and aliases, not just GUIDs. Managed identity inputs support non-empty GUIDs and user-assigned managed identity resource IDs.
- Certificate paths must resolve to one existing file; relative and spaced paths are supported. Certificate objects must have a private key, and thumbprints must be hexadecimal (embedded spaces are supported). Certificate lookup, file decoding/password errors, and actual key access remain runtime checks.
- Required access tokens and client secrets cannot be empty. Optional empty certificate passwords remain supported. Omitting `-AuthSecret` or supplying an empty/null value to `Update-PSDVTableWebHookAuthSecret` still clears the secret.
- Explicit `-AccessTokenExpiresOn` values must be in the future. Acquired/cached tokens are also checked at runtime before use.
- Optional selection/attribute lists can still be omitted, null, or empty. Supplied entries must not be null, empty, or whitespace-only. Optional empty query/filter values retain their prior handling; a mandatory legacy `-FilterQuery` must not be blank.
- Empty payload/header/metadata dictionaries remain supported where they were previously valid, and payload fields can still be null to clear values. ETags and alternate-key values are not trimmed or reformatted.
- Empty batch arrays still return an empty result without HTTP. Native mandatory-array binding continues to reject null arrays and null entries. Non-null malformed entries and nested update GUIDs are checked before metadata or request submission.
- Private helpers retain intentional allowances: empty strings in literal/XML escaping, blank cloud names defaulting to AzureCloud, null batch responses used for empty/WhatIf results, optional selector fallback, and null token inputs that trigger acquisition/refresh.

Invalid scalar arguments now generally raise PowerShell parameter-binding/validation errors before the function body, including with `-WhatIf`. This intentionally replaces some previous custom runtime exceptions or SDK/.NET argument exceptions. Do not rely on exact localized validation message text.

Compound, nullable-list, cross-parameter, metadata, service-response, and environment-dependent rules remain explicit runtime checks where attributes cannot preserve the existing contract. These checks use native PowerShell comparisons/path commands rather than relying on a downstream .NET failure. Authentication, transport, and structured HTTP/concurrency failures remain separate from input validation.

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

Pull requests targeting `dev` or `main` run the Pester suite on Windows and Ubuntu (`.github/workflows/ci.yml`). `.github/workflows/publish.yml` builds module-only downloads for stable and prerelease GitHub Releases. Only stable releases publish to the [PowerShell Gallery](https://www.powershellgallery.com/packages/Dataverse/).

1. Update `ModuleVersion` in `Dataverse.psd1` and the release notes. For a prerelease, set `PrivateData.PSData.Prerelease` to a label such as `preview1`. For a stable release, remove or clear that value and merge to `main`.
2. Create a GitHub Release with a matching tag: `v1.2.0` for a stable version, or `v1.2.0-preview1` for a prerelease. Check GitHub's **Set as a pre-release** option for prereleases. The flag must agree with the manifest. Prereleases may come from development branches; stable release commits must be reachable from `main`.
3. After tests pass, the workflow attaches `Dataverse-<version>.zip` and its `.sha256` checksum to the release. They include only `Dataverse.psd1`, `Dataverse.psm1`, `LICENSE`, `Public`, `Private`, and `lib`, under `Dataverse/<ModuleVersion>/`. GitHub's automatic **Source code** downloads still contain the repository; choose the named module ZIP instead.
4. Only stable releases check the Gallery for an existing version and publish using the `PSGALLERYAPI` repository secret. Prereleases never use this key or publish to the Gallery. Gallery versions cannot be overwritten.

To install a downloaded ZIP, verify its checksum with `Get-FileHash -Algorithm SHA256`, then extract it into a directory listed in `$env:PSModulePath`. The result should be `<module-path>/Dataverse/<ModuleVersion>/Dataverse.psd1`. Run `Import-Module Dataverse -RequiredVersion <ModuleVersion>` to load it. Stable and prerelease builds with the same numeric version use the same installation folder; do not extract one over the other.

The **Package and publish release** workflow can also be run manually. Manual runs only build downloadable workflow artifacts; they never attach release assets or publish to the Gallery. Release asset upload requires the workflow's `contents: write` permission; no protected GitHub Environment is required.

## Contributing

This module follows PowerShell best practices and PSScriptAnalyzer rules. When contributing:

1. Ensure PowerShell 7.6+ compatibility
2. Follow the existing code style and patterns
3. Include comprehensive help documentation
4. Test in both normal and Constrained Language Mode environments

## License

This project is licensed under the terms in [LICENSE](LICENSE).

## Support

This software is provided as-is, without warranty or guaranteed support. If you find a bug, have a question, or want to request an enhancement, open an issue in the GitHub repository with the module version, PowerShell version, and enough detail to reproduce the behavior.

## Changelog

### Version 1.2.0

- **Requires PowerShell 7.6 or later.** Version 1.1.1 is the latest release that supports PowerShell 7.3-7.5.
- Added alternate-key upsert support with `Invoke-PSDVTableItemUpsert` and optional create-only behavior.
- Added batch create, update, and upsert commands for Dataverse table records.
- Added categorized batch results for created, already-existing, and failed outcomes.
- Added configurable page sizes and page-by-page result streaming for large Dataverse queries.
- Improved JSON payload serialization depth for Dataverse web requests.
- Added `Invoke-PSDVWebRequest -AsCollection` and `-SkipHttpErrorCheck`.
- Added `Update-PSDVTableItem -IfMatch` for ETag-conditional updates.
- Added structured HTTP error IDs: `PSDVPreconditionFailed`, `PSDVHttpError`, and `PSDVWebRequestFailed`.
- Applied native PowerShell parameter validation across all public and private functions.

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
