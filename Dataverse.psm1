$script:PSDVPublicClientID = '1950a258-227b-4e31-a9cf-717495945fc2'
$script:PSDVAzureIdentityLoaded = $false
$script:PSDVAzureIdentityAssemblyPath = Join-Path $PSScriptRoot 'lib' 'netstandard2.0'
$script:PSDVAzureAuthorityHosts = @{
    AzureCloud        = 'https://login.microsoftonline.com/'
    AzureChinaCloud   = 'https://login.chinacloudapi.cn/'
    AzureUSGovernment = 'https://login.microsoftonline.us/'
    AzureGermanCloud  = 'https://login.microsoftonline.de/'
}

$privateFunctions = @(
    'Import-PSDVAzureIdentityAssemblies',
    'ConvertFrom-PSDVSecureString',
    'ConvertTo-PSDVODataStringLiteral',
    'ConvertTo-PSDVXmlAttributeValue',
    'Join-PSDVQueryString',
    'Get-PSDVEntitySetFromLogicalName',
    'Confirm-PSDVItemDataAttributes',
    'ConvertTo-PSDVLookupItemData',
    'Set-PSDVAccessToken',
    'Get-PSDVAzureAuthorityHost',
    'New-PSDVClientSecretCredential',
    'New-PSDVClientCertificateCredential',
    'New-PSDVManagedIdentityCredential',
    'New-PSDVInteractiveCredential',
    'Get-PSDVFunctionRuntimeManagedIdentityAccessToken',
    'Get-PSDVAccessToken'
)

$publicFunctions = @(
    'Connect-PSDVOrg',
    'Disconnect-PSDVOrg',
    'Invoke-PSDVWebRequest',
    'Read-PSDVTableData',
    'Get-PSDVTableDetail',
    'Get-PSDVTableColumn',
    'Get-PSDVTableItem',
    'Get-PSDVTableItemAuditHistory',
    'Get-PSDVTableItemChangeHistory',
    'New-PSDVTableItem',
    'Update-PSDVTableItem',
    'Remove-PSDVTableItem',
    'New-PSDVTableWebHook',
    'Get-PSDVTableWebHook',
    'Remove-PSDVTableWebHook',
    'Update-PSDVTableWebHookAuthSecret'
)

foreach ($functionName in $privateFunctions) {
    . (Join-Path $PSScriptRoot 'Private' "$functionName.ps1")
}

foreach ($functionName in $publicFunctions) {
    . (Join-Path $PSScriptRoot 'Public' "$functionName.ps1")
}

Export-ModuleMember -Function $publicFunctions
