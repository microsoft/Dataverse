# Dataverse PowerShell Module Release Notes

## Version 1.2.0

Release date: TBD

Version 1.2.0 adds alternate-key upsert, batch operations, large-query paging, optimistic concurrency with structured HTTP errors, and native parameter validation. It raises the minimum PowerShell version to 7.6.

### Compatibility

- **Breaking:** the minimum PowerShell version is now `7.6` (previously `7.3`). Version 1.1.1 is the latest release that supports PowerShell 7.3-7.5; use `Install-Module Dataverse -RequiredVersion 1.1.1` on those hosts.
- Blank-string parameter checks now use `[ValidateNotNullOrWhiteSpace()]` instead of the `[ValidatePattern('\S')]` workaround.

### Added

- Added optional `Invoke-PSDVWebRequest -SkipHttpErrorCheck`, forwarded on initial and pagination requests. Combine it with `-ReturnRawResponse` to inspect non-success HTTP status codes, headers, and bodies, including HTTP 412 for conditional PATCH requests. Existing HTTP-error behavior is unchanged when omitted or false, and transport failures still throw. Without raw output, existing JSON parsing and response-mode rules still apply.
- Added `Update-PSDVTableItem -IfMatch` for ETag-conditional PATCH requests with either `-Table` or `-EntitySet`. Specific ETags protect the retrieved version; `*` requires existence without protecting against intervening edits. Explicit blank conditions are rejected before requests.
- Conditional `-ReturnItem` updates now require the PATCH row representation and server ETag, without a follow-up GET. Missing output raises `PSDVUpdateRepresentationMissing` or `PSDVUpdateETagMissing`; the write may already have succeeded.
- Added opt-in live concurrency coverage and deterministic tests for competing updates, wildcard behavior, and preservation of validation, lookup parsing, and `-WhatIf`.
- Added alternate-key upsert support with `Invoke-PSDVTableItemUpsert` and optional `-CreateOnly` behavior for create-only requests.
- Added batch create, update, and upsert commands: `New-PSDVTableItemBatch`, `Update-PSDVTableItemBatch`, and `Invoke-PSDVTableItemUpsertBatch`.
- Batch commands now return categorized per-request results for created, already-existing, and failed outcomes.
- Added `Invoke-PSDVWebRequest -MaxPageSize` and `-AsPages` support for processing large Dataverse query results one page at a time.
- Added `Invoke-PSDVWebRequest -AsCollection` to always return an array (including an empty array for zero results), so callers do not need to remember the `@(...)` idiom. `-AsCollection` cannot be combined with `-AsPages` or `-ReturnRawResponse`.
- Declared `[OutputType([object[]])]` on `Invoke-PSDVWebRequest` and documented the output behavior, including that a single-record GET returning HTTP 204 (No Content) still yields `$null`.

### Changed

- Audited parameter validation across all public and private functions. Added native PowerShell string, GUID, URL, certificate/path, credential-context, and token checks where appropriate, and validate actual batch entries before metadata/HTTP work. Invalid scalar inputs now produce native parameter-binding errors instead of downstream runtime/SDK exceptions.
- Preserved intentional empty/default contracts, including empty batches/dictionaries, nullable optional selections, literal escaping, webhook-secret clearing, tenant/managed-identity forms, relative request paths, and opaque ETags. Existing mandatory batch-array null-entry rejection remains unchanged. Cross-parameter and service-response checks remain at runtime.
- `Invoke-PSDVWebRequest` now exposes terminating error IDs `PSDVPreconditionFailed` (HTTP 412), `PSDVHttpError` (other HTTP failures), and `PSDVWebRequestFailed` (request/transport failures without a response). HTTP details are available at `Exception.Data['PSDVHttpError']`, including integer status, Dataverse code/message, response headers/body, method, and URI; the original request exception is retained as `InnerException`. Logical-table resolution preserves these errors.
- Default HTTP throwing behavior and skip/raw-response modes remain unchanged. No automatic retries or condition refreshes are performed; uncertain write outcomes require caller reconciliation.
- Dataverse request bodies now support deeper JSON payloads when serialized for web requests.
- `Invoke-PSDVWebRequest` now returns an empty collection instead of `$null` when a collection query matches zero records, so wrapping calls in `@(...)` reliably reports a `.Count` of `0`. The empty and non-empty collection paths now share a single code path.

## Version 1.1.1

Release date: 2026-06-11

Version 1.1.1 is a patch release for the 1.1 series and is the latest release that supports PowerShell 7.3-7.5.

### Bug Fixes

- Fixed item data validation for lookup navigation properties supplied in OData bind format, such as `parentcustomerid_account@odata.bind`.
- Preserved existing OData bind entries when `-ParseItemData` is used, preventing already-bound lookup relationships from being reprocessed.

### Release Validation

Before release, the suite was validated with:

```powershell
Invoke-Pester -Path .\tests
```

## Version 1.1.0

Release date: 2026-06-10

Version 1.1.0 is a substantial update from the 1.0.0 release on `main`. It expands Dataverse operations, removes the direct Az.Accounts dependency, improves authentication flexibility, and adds automated test coverage for the module.

### Highlights

- Removed the direct Az.Accounts module dependency and bundled the Azure.Identity authentication dependencies with the module.
- Added browser-based interactive authentication support for MFA and Conditional Access scenarios.
- Added direct bearer token authentication through `Connect-PSDVOrg -AccessToken`, so users can acquire tokens with existing Azure tooling such as `Get-AzAccessToken` or Azure CLI and pass them to the module.
- Added managed identity support improvements, including system-assigned managed identity and an optional FunctionRuntime token source for Azure Functions/App Service environments.
- Added Dataverse webhook management commands.
- Added Pester test coverage for public and private module behavior.
- Refactored the module from a large monolithic script into focused `Public` and `Private` function files.

### Authentication Changes

- `Connect-PSDVOrg` now supports service principal authentication with client secrets and certificates, user-assigned managed identity, system-assigned managed identity, interactive browser login, device code login, and externally supplied bearer tokens.
- `-AccessToken` accepts a `SecureString` bearer token for the Dataverse resource.
- `-AccessTokenExpiresOn` can be provided with externally supplied tokens. If omitted, the module attempts to read the JWT `exp` claim.
- Supplied bearer tokens are not refreshed automatically. When a supplied token expires, acquire a new token and run `Connect-PSDVOrg` again.
- `Disconnect-PSDVOrg` clears the current session's Dataverse connection state.

### Dataverse API Improvements

- Added webhook cmdlets:
  - `New-PSDVTableWebHook`
  - `Get-PSDVTableWebHook`
  - `Remove-PSDVTableWebHook`
  - `Update-PSDVTableWebHookAuthSecret`
- Added `Get-PSDVTableItemAuditHistory` and `Get-PSDVTableItemChangeHistory` support.
- Added `-Top` OData query support to table item retrieval.
- Improved table column output to include available choice values.
- Hardened OData query construction and encoding for select, filter, expand, and paging scenarios.
- Improved pagination error handling and null/empty response behavior.
- Hardened webhook filter handling, GUID validation, and webhook secret escaping.

### Packaging And Compatibility

- Module version is now `1.1.0` in `Dataverse.psd1`.
- Minimum PowerShell version is `7.3`.
- Compatible PowerShell edition is `Core`.
- Azure.Identity and related dependencies are bundled under `lib/netstandard2.0`.
- The legacy `Install-DataverseModule.ps1` installation helper was removed in favor of native PowerShell module packaging.

### Deprecations

The following compatibility parameters remain available in 1.1.0 but are deprecated and planned for removal in the next major version:

- `Connect-PSDVOrg -SubscriptionId`
- `Get-PSDVTableItem -FilterQuery`
- `Get-PSDVTableItem -ExpandQuery`
- `Get-PSDVTableItem -SelectFields`

Use `-Filter`, `-Expand`, and `-Select` for new table item query code.

### Testing

Version 1.1.0 adds Pester coverage for authentication helpers, token handling, request construction, table operations, webhook operations, and connection cleanup. Before release, the suite was validated with:

```powershell
Invoke-Pester -Path .\tests -Output Normal
```

### Known Limitations

- Externally supplied bearer tokens cannot be refreshed by the module.
- JWT expiration parsing is best-effort. If a supplied token does not expose a parseable `exp` claim, pass `-AccessTokenExpiresOn` explicitly.
- Azure.Identity assembly versions can still conflict in long-lived PowerShell sessions that preload incompatible Azure SDK assemblies. Use `-AccessToken` when you need to rely on the host's already-installed Azure authentication tools.
