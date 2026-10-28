function New-PSDVClientCertificateCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            $id = $_.ClientID -as [guid]
            $null -ne $id -and $id -ne [guid]::Empty -and $_.AzureTenantId -match '^[A-Za-z0-9.-]+$'
        }, ErrorMessage = 'AuthContext requires a valid ClientID and nonblank AzureTenantId.')]
        [ValidateScript({
            if ($null -ne $_.Certificate) {
                return $_.Certificate -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and $_.Certificate.HasPrivateKey
            }
            if ($_.CertificateThumbprint -match '\S') {
                return $_.CertificateThumbprint -is [string] -and $_.CertificateThumbprint -match '^\s*(?:[0-9a-fA-F]\s*)+$'
            }
            $files = @(Get-Item -Path $_.CertificatePath -ErrorAction Stop)
            $files.Count -eq 1 -and $files[0] -is [System.IO.FileInfo]
        }, ErrorMessage = 'Certificate authentication requires a certificate with a private key, a hexadecimal thumbprint, or one existing certificate file.')]
        [ValidateScript({
            if ($null -ne $_.Certificate -or $_.CertificateThumbprint -match '\S') {
                return $true
            }
            $null -eq $_.CertificatePassword -or $_.CertificatePassword -is [securestring]
        }, ErrorMessage = 'CertificatePassword must be a SecureString when supplied.')]
        [Hashtable]
        $AuthContext
    )

    $authorityHost = Get-PSDVAzureAuthorityHost -Environment $AuthContext.Environment
    $certificate = $AuthContext.Certificate
    if ($null -eq $certificate) {
        if ($AuthContext.CertificateThumbprint -match '\S') {
            $normalizedThumbprint = $AuthContext.CertificateThumbprint.Replace(' ', '').ToUpperInvariant()
            $certificate = Get-ChildItem -Path Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                Where-Object { $_.Thumbprint -eq $normalizedThumbprint } |
                Select-Object -First 1

            if ($null -eq $certificate) {
                throw "Certificate with thumbprint '$($AuthContext.CertificateThumbprint)' was not found in CurrentUser or LocalMachine personal certificate stores"
            }
        }
        elseif ($AuthContext.CertificatePath -match '\S') {
            $resolvedCertificatePath = (Resolve-Path -Path $AuthContext.CertificatePath -ErrorAction Stop).Path
            $keyStorageFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
            $plainTextPassword = if ($null -ne $AuthContext.CertificatePassword) { ConvertFrom-PSDVSecureString -SecureString $AuthContext.CertificatePassword } else { '' }
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($resolvedCertificatePath, $plainTextPassword, $keyStorageFlags)
        }
    }

    if ($null -eq $certificate -or -not $certificate.HasPrivateKey) {
        throw 'Certificate authentication requires a certificate with an accessible private key'
    }

    Import-PSDVAzureIdentityAssemblies
    $options = [Azure.Identity.ClientCertificateCredentialOptions]::new()
    $options.AuthorityHost = $authorityHost

    return [Azure.Identity.ClientCertificateCredential]::new(
        $AuthContext.AzureTenantId,
        $AuthContext.ClientID,
        $certificate,
        $options
    )
}
