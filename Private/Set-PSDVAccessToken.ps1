function Set-PSDVAccessToken {
    [CmdletBinding()]
    param(
        [Parameter()]
        [Object]
        $AccessToken,

        [Parameter()]
        [Hashtable]
        $AuthContext = $Global:DATAVERSEAUTHCONTEXT,

        [Parameter()]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $Operation = 'Token acquisition'
    )

    if ($null -eq $AuthContext) {
        throw 'No existing connection to Dataverse Environment, run Connect-PSDVOrg before executing other PSDV cmdlets'
    }

    if ($null -eq $AccessToken) {
        if ($null -ne $Global:DATAVERSEACCESSTOKEN) {
            $cachedToken = $Global:DATAVERSEACCESSTOKEN
            $cachedExpiry = $cachedToken.ExpiresOn -as [DateTimeOffset]
            if ($cachedToken.Token -isnot [securestring] -or $cachedToken.Token.Length -eq 0 -or $null -eq $cachedExpiry) {
                throw 'The cached access token must contain a nonempty SecureString Token and valid ExpiresOn.'
            }
            if ($cachedExpiry.AddMinutes(-5) -gt [DateTimeOffset](Get-Date)) {
                return
            }
        }

        if ($AuthContext.ParameterSetName -eq 'AccessToken') {
            throw 'The access token supplied to Connect-PSDVOrg has expired or is about to expire and cannot be refreshed automatically. Acquire a new token and run Connect-PSDVOrg again with the -AccessToken parameter.'
        }

        Write-Verbose 'Refreshing Dataverse access token'
        $AccessToken = Get-PSDVAccessToken -AuthContext $AuthContext
        $Operation = 'Access token refresh'
    }

    if ($null -eq $AccessToken) {
        throw "$Operation did not return an access token."
    }

    $propertyNames = $AccessToken.PSObject.Properties.Name
    if ($propertyNames -notcontains 'Token' -or $null -eq $AccessToken.Token) {
        throw "$Operation returned an access token object without a Token value."
    }

    if ($AccessToken.Token -isnot [securestring] -or $AccessToken.Token.Length -eq 0) {
        throw "$Operation requires a nonempty SecureString Token value."
    }

    if ($propertyNames -notcontains 'ExpiresOn' -or $null -eq $AccessToken.ExpiresOn) {
        throw "$Operation returned an access token object without an ExpiresOn value."
    }

    $expiration = $AccessToken.ExpiresOn -as [DateTimeOffset]
    if ($null -eq $expiration) {
        throw "$Operation requires a valid ExpiresOn value."
    }
    $expiresOn = $expiration.UtcDateTime
    if ($expiresOn -le (Get-Date).ToUniversalTime()) {
        throw "$Operation returned an access token that is already expired."
    }

    if ($propertyNames -contains 'RefreshToken') {
        $AuthContext.RefreshToken = $AccessToken.RefreshToken
    }

    $Global:DATAVERSEACCESSTOKEN = $AccessToken
}
