function Connect-PSDVOrg {
    <#
    .SYNOPSIS
    Establishes a connection to a Microsoft Dataverse organization.

    .DESCRIPTION
    Connect-PSDVOrg creates an authenticated connection to a Microsoft Dataverse environment using various authentication methods.
    It supports service principal authentication with client secrets or certificates, managed identity authentication, and interactive browser login.
    Upon successful connection, it retrieves and stores an access token for subsequent Dataverse API calls.

    .PARAMETER ClientID
    Must be a non-empty GUID; invalid values are rejected before credential construction.
    The Application (client) ID of the Azure AD application registration used for service principal authentication.

    .PARAMETER ClientSecret
    The client secret (secure string) for the Azure AD application used for service principal authentication.

    .PARAMETER Certificate
    The X.509 certificate with private key used for service principal authentication.

    .PARAMETER CertificateThumbprint
    The hexadecimal thumbprint of a certificate with private key in the CurrentUser or LocalMachine personal certificate store.
    Embedded spaces are supported.

    .PARAMETER CertificatePath
    A path resolving to one existing certificate file used for service principal authentication.
    Relative paths and paths containing spaces are supported. Directories and missing files are rejected at binding.

    .PARAMETER CertificatePassword
    The optional PFX certificate password.

    .PARAMETER ManagedIdentityID
    The client ID, object ID, or Azure resource ID of the managed identity to use for authentication in Azure environments (user-assigned managed identity). FunctionRuntime token acquisition supports client ID or Azure resource ID.

    .PARAMETER UseSystemManagedIdentity
    When specified, uses the system-assigned managed identity for authentication. No additional identity configuration is required.

    .PARAMETER AzureTenantId
    The Microsoft Entra tenant ID, domain, or supported tenant alias. Letters, digits, hyphens, and dots are accepted.
    Required for client secret and interactive authentication.

    .PARAMETER SubscriptionId
    Optional legacy parameter retained for compatibility with older examples. It is no longer used because this module no longer connects an Azure subscription context.

    .PARAMETER DataverseOrgURL
    The absolute HTTP(S) URL of the Dataverse organization (e.g., https://orgname.crm.dynamics.com/).
    URL validation does not override the underlying authentication transport security requirements.

    .PARAMETER Environment
    The Azure cloud authority host to use for OAuth token acquisition. Defaults to AzureCloud.

    .PARAMETER UseDeviceCode
    Uses device code authentication instead of the default browser-based interactive authentication.

    .PARAMETER ManagedIdentityTokenSource
    Controls how managed identity tokens are acquired. AzureIdentity uses the bundled Azure.Identity SDK. FunctionRuntime calls the Azure Functions/App Service managed identity endpoint directly without loading Azure.Identity.

    .PARAMETER AccessToken
    A bearer access token (secure string) already acquired for the Dataverse resource using external tooling such as Get-AzAccessToken or 'az account get-access-token'. When supplied, the module uses this token directly and does not load Azure.Identity or acquire a token itself. The token cannot be refreshed automatically; reconnect with a new token when it expires.

    .PARAMETER AccessTokenExpiresOn
    The expiration time of the supplied access token. If omitted, the expiration is read from the token's 'exp' claim when possible. Provide this value (for example, the ExpiresOn returned by Get-AzAccessToken) when the expiration cannot be determined automatically.
    An explicitly supplied expiration must be in the future.

    .EXAMPLE
    Connect-PSDVOrg -AzureTenantId "12345678-1234-1234-1234-123456789012" -DataverseOrgURL "https://contoso.crm.dynamics.com/"

    Connects to Dataverse using interactive authentication.

    .EXAMPLE
    $secret = ConvertTo-SecureString "MyClientSecret" -AsPlainText -Force
    Connect-PSDVOrg -ClientID "12345678-1234-1234-1234-123456789012" -ClientSecret $secret -AzureTenantId "87654321-4321-4321-4321-210987654321" -DataverseOrgURL "https://contoso.crm.dynamics.com/" -Environment "AzureCloud"

    Connects to Dataverse using service principal authentication.

    .EXAMPLE
    Connect-PSDVOrg -ClientID "12345678-1234-1234-1234-123456789012" -CertificateThumbprint "ABCDEF1234567890ABCDEF1234567890ABCDEF12" -AzureTenantId "87654321-4321-4321-4321-210987654321" -DataverseOrgURL "https://contoso.crm.dynamics.com/"

    Connects to Dataverse using service principal certificate authentication.

    .EXAMPLE
    Connect-PSDVOrg -ManagedIdentityID "12345678-1234-1234-1234-123456789012" -DataverseOrgURL "https://contoso.crm.dynamics.com/"

    Connects to Dataverse using user-assigned managed identity authentication.

    .EXAMPLE
    Connect-PSDVOrg -UseSystemManagedIdentity -DataverseOrgURL "https://contoso.crm.dynamics.com/"

    Connects to Dataverse using system-assigned managed identity authentication.

    .EXAMPLE
    Connect-PSDVOrg -UseSystemManagedIdentity -ManagedIdentityTokenSource FunctionRuntime -DataverseOrgURL "https://contoso.crm.dynamics.com/"

    Connects to Dataverse using the Azure Functions/App Service managed identity endpoint directly without loading Azure.Identity.

    .EXAMPLE
    $token = Get-AzAccessToken -ResourceUrl "https://contoso.crm.dynamics.com/" -AsSecureString
    Connect-PSDVOrg -AccessToken $token.Token -AccessTokenExpiresOn $token.ExpiresOn -DataverseOrgURL "https://contoso.crm.dynamics.com/"

    Connects to Dataverse using a bearer token acquired with Get-AzAccessToken, without loading Azure.Identity.
    #>

    [CmdletBinding(DefaultParameterSetName = 'InteractiveLogin')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ClientSecret')]
        [Parameter(Mandatory, ParameterSetName = 'ClientCertificate')]
        [Parameter(Mandatory, ParameterSetName = 'ClientCertificateThumbprint')]
        [Parameter(Mandatory, ParameterSetName = 'ClientCertificatePath')]
        [ValidateScript({
            $id = $_ -as [guid]
            $null -ne $id -and $id -ne [guid]::Empty
        }, ErrorMessage = 'ClientID must be a non-empty GUID.')]
        [String]
        $ClientID,

        [Parameter(Mandatory, ParameterSetName = 'ClientSecret')]
        [ValidateScript({ $_.Length -gt 0 }, ErrorMessage = 'ClientSecret cannot be empty.')]
        [SecureString]
        $ClientSecret,

        [Parameter(Mandatory, ParameterSetName = 'ClientCertificate')]
        [ValidateScript({ $_.HasPrivateKey }, ErrorMessage = 'Certificate must have a private key.')]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $Certificate,

        [Parameter(Mandatory, ParameterSetName = 'ClientCertificateThumbprint')]
        [ValidatePattern('^\s*(?:[0-9a-fA-F]\s*)+$')]
        [String]
        $CertificateThumbprint,

        [Parameter(Mandatory, ParameterSetName = 'ClientCertificatePath')]
        [ValidateScript({
            $files = @(Get-Item -Path $_ -ErrorAction Stop)
            $files.Count -eq 1 -and $files[0] -is [System.IO.FileInfo]
        }, ErrorMessage = 'CertificatePath must resolve to one existing file.')]
        [String]
        $CertificatePath,

        [Parameter(ParameterSetName = 'ClientCertificatePath')]
        [SecureString]
        $CertificatePassword,

        [Parameter(Mandatory, ParameterSetName = 'ManagedIdentity')]
        [ValidateScript({
            $id = $_ -as [guid]
            ($null -ne $id -and $id -ne [guid]::Empty) -or
                $_ -match '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.ManagedIdentity/userAssignedIdentities/[^/]+/?$'
        }, ErrorMessage = 'ManagedIdentityID must be a non-empty GUID or a managed identity resource ID.')]
        [String]
        $ManagedIdentityID,

        [Parameter(Mandatory, ParameterSetName = 'SystemManagedIdentity')]
        [Switch]
        $UseSystemManagedIdentity,

        [Parameter(Mandatory, ParameterSetName = 'ClientSecret')]
        [Parameter(Mandatory, ParameterSetName = 'ClientCertificate')]
        [Parameter(Mandatory, ParameterSetName = 'ClientCertificateThumbprint')]
        [Parameter(Mandatory, ParameterSetName = 'ClientCertificatePath')]
        [Parameter(Mandatory, ParameterSetName = 'InteractiveLogin')]
        [ValidatePattern('^[A-Za-z0-9.-]+$')]
        [String]
        $AzureTenantId,

        [Parameter(ParameterSetName = 'InteractiveLogin')]
        [String]
        $SubscriptionId,

        [Parameter(Mandatory)]
        [ValidateScript({
            $uri = $_ -as [uri]
            $null -ne $uri -and $uri.IsAbsoluteUri -and $uri.Scheme -in @('http', 'https') -and $uri.Host -match '\S'
        }, ErrorMessage = 'DataverseOrgURL must be an absolute HTTP(S) URL with a host.')]
        [String]
        $DataverseOrgURL,

        [Parameter()]
        [ValidateSet('AzureCloud', 'AzureChinaCloud', 'AzureUSGovernment', 'AzureGermanCloud')]
        [String]
        $Environment = 'AzureCloud',

        [Parameter(ParameterSetName = 'InteractiveLogin')]
        [Switch]
        $UseDeviceCode,

        [Parameter(ParameterSetName = 'ManagedIdentity')]
        [Parameter(ParameterSetName = 'SystemManagedIdentity')]
        [ValidateSet('AzureIdentity', 'FunctionRuntime')]
        [String]
        $ManagedIdentityTokenSource = 'AzureIdentity',

        [Parameter(Mandatory, ParameterSetName = 'AccessToken')]
        [ValidateScript({ $_.Length -gt 0 }, ErrorMessage = 'AccessToken cannot be empty.')]
        [SecureString]
        $AccessToken,

        [Parameter(ParameterSetName = 'AccessToken')]
        [ValidateScript({ $_ -gt [DateTimeOffset](Get-Date) }, ErrorMessage = 'AccessTokenExpiresOn must be in the future.')]
        [DateTimeOffset]
        $AccessTokenExpiresOn
    )

    #Ensure DataverseOrgURL has a trailing slash
    if (-not $DataverseOrgURL.EndsWith('/')) {
        $DataverseOrgURL = $DataverseOrgURL + '/'
    }

    if ($PSBoundParameters.ContainsKey('SubscriptionId')) {
        Write-Warning 'The -SubscriptionId parameter is deprecated and no longer used. It is planned for removal in the next major version.'
    }

    $authContext = @{
        ParameterSetName  = $PSCmdlet.ParameterSetName
        ResourceUrl       = $DataverseOrgURL
        ClientID          = $ClientID
        ClientSecret      = $ClientSecret
        Certificate       = $Certificate
        CertificateThumbprint = $CertificateThumbprint
        CertificatePath   = $CertificatePath
        CertificatePassword = $CertificatePassword
        AzureTenantId     = $AzureTenantId
        ManagedIdentityID = $ManagedIdentityID
        Environment       = $Environment
        SubscriptionId    = $SubscriptionId
        UseDeviceCode     = $UseDeviceCode.IsPresent
        ManagedIdentityTokenSource = $ManagedIdentityTokenSource
    }

    $suppliedAccessToken = $null
    if ($PSCmdlet.ParameterSetName -eq 'AccessToken') {
        if ($PSBoundParameters.ContainsKey('AccessTokenExpiresOn')) {
            $tokenExpiresOn = $AccessTokenExpiresOn.UtcDateTime
        }
        else {
            $tokenExpiresOn = $null
            try {
                $rawToken = ConvertFrom-PSDVSecureString -SecureString $AccessToken
                $tokenParts = $rawToken.Split('.')
                if ($tokenParts.Count -ge 2) {
                    $payloadSegment = $tokenParts[1].Replace('-', '+').Replace('_', '/')
                    switch ($payloadSegment.Length % 4) {
                        2 { $payloadSegment += '==' }
                        3 { $payloadSegment += '=' }
                    }
                    $payloadJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payloadSegment))
                    $payloadClaims = $payloadJson | ConvertFrom-Json
                    if (($payloadClaims.PSObject.Properties.Name -contains 'exp') -and $payloadClaims.exp) {
                        $tokenExpiresOn = [DateTimeOffset]::FromUnixTimeSeconds([long]$payloadClaims.exp).UtcDateTime
                    }
                }
            }
            catch {
                $tokenExpiresOn = $null
            }

            if ($null -eq $tokenExpiresOn) {
                throw 'Unable to determine the supplied access token expiration. Provide -AccessTokenExpiresOn (for example, the ExpiresOn value returned by Get-AzAccessToken).'
            }
        }

        $suppliedAccessToken = [PSCustomObject]@{
            Token     = $AccessToken
            ExpiresOn = $tokenExpiresOn
        }
    }

    try {
        Write-Verbose "Getting Dataverse Access Token for $DataverseOrgUrl"
        if ($PSCmdlet.ParameterSetName -eq 'AccessToken') {
            $dvAccessToken = $suppliedAccessToken
        }
        else {
            $dvAccessToken = Get-PSDVAccessToken -AuthContext $authContext
        }
        Set-PSDVAccessToken -AccessToken $dvAccessToken -AuthContext $authContext -Operation 'Initial token acquisition'
        $Global:DATAVERSEAUTHCONTEXT = $authContext
        $Global:DATAVERSEORGURL = $DataverseOrgURL
    }
    catch {
        throw "Error executing $($_.InvocationInfo.MyCommand.Name), $($_ | Out-String)"
    }

}
