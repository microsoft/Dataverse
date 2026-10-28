function New-PSDVClientSecretCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            $id = $_.ClientID -as [guid]
            $null -ne $id -and $id -ne [guid]::Empty -and $_.AzureTenantId -match '^[A-Za-z0-9.-]+$' -and
                $_.ClientSecret -is [securestring] -and $_.ClientSecret.Length -gt 0
        }, ErrorMessage = 'AuthContext requires a valid ClientID, nonblank AzureTenantId, and nonempty secure ClientSecret.')]
        [Hashtable]
        $AuthContext
    )

    $authorityHost = Get-PSDVAzureAuthorityHost -Environment $AuthContext.Environment
    Import-PSDVAzureIdentityAssemblies
    $options = [Azure.Identity.ClientSecretCredentialOptions]::new()
    $options.AuthorityHost = $authorityHost

    return [Azure.Identity.ClientSecretCredential]::new(
        $AuthContext.AzureTenantId,
        $AuthContext.ClientID,
        (ConvertFrom-PSDVSecureString -SecureString $AuthContext.ClientSecret),
        $options
    )
}
