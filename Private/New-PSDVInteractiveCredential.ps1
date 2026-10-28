function New-PSDVInteractiveCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $_.AzureTenantId -match '^[A-Za-z0-9.-]+$' }, ErrorMessage = 'AuthContext requires a tenant ID, domain, or supported tenant alias.')]
        [ValidateScript({
            $null -eq $_.UseDeviceCode -or $_.UseDeviceCode -is [bool] -or
                $_.UseDeviceCode -is [System.Management.Automation.SwitchParameter]
        }, ErrorMessage = 'UseDeviceCode must be Boolean when supplied.')]
        [Hashtable]
        $AuthContext
    )

    $authorityHost = Get-PSDVAzureAuthorityHost -Environment $AuthContext.Environment
    Import-PSDVAzureIdentityAssemblies
    if ($AuthContext.UseDeviceCode) {
        $options = [Azure.Identity.DeviceCodeCredentialOptions]::new()
        $options.TenantId = $AuthContext.AzureTenantId
        $options.ClientId = $script:PSDVPublicClientID
        $options.AuthorityHost = $authorityHost
        $options.DeviceCodeCallback = [System.Func[Azure.Identity.DeviceCodeInfo, System.Threading.CancellationToken, System.Threading.Tasks.Task]] {
            param($deviceCodeInfo, $cancellationToken)
            Write-Information $deviceCodeInfo.Message -InformationAction Continue
            return [System.Threading.Tasks.Task]::CompletedTask
        }

        return [Azure.Identity.DeviceCodeCredential]::new($options)
    }

    $options = [Azure.Identity.InteractiveBrowserCredentialOptions]::new()
    $options.TenantId = $AuthContext.AzureTenantId
    $options.ClientId = $script:PSDVPublicClientID
    $options.AuthorityHost = $authorityHost

    return [Azure.Identity.InteractiveBrowserCredential]::new($options)
}
