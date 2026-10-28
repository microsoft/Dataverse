function Get-PSDVFunctionRuntimeManagedIdentityAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            $uri = $_.ResourceUrl -as [uri]
            $_.ResourceUrl -is [string] -and $null -ne $uri -and $uri.IsAbsoluteUri -and
                $uri.Scheme -in @('http', 'https') -and $uri.Host -match '\S'
        }, ErrorMessage = 'AuthContext requires an absolute HTTP(S) ResourceUrl.')]
        [ValidateScript({
            $value = $_.ManagedIdentityID
            $id = $value -as [guid]
            $value -notmatch '\S' -or ($null -ne $id -and $id -ne [guid]::Empty) -or
                $value -match '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.ManagedIdentity/userAssignedIdentities/[^/]+/?$'
        }, ErrorMessage = 'ManagedIdentityID must be a non-empty GUID or a managed identity resource ID, or omitted for system identity.')]
        [Hashtable]
        $AuthContext
    )

    $resource = $AuthContext.ResourceUrl.TrimEnd('/')
    $managedIdentityID = [string]$AuthContext.ManagedIdentityID

    if (-not [string]::IsNullOrWhiteSpace($env:IDENTITY_ENDPOINT) -and -not [string]::IsNullOrWhiteSpace($env:IDENTITY_HEADER)) {
        $query = [ordered]@{
            'api-version' = '2019-08-01'
            resource      = $resource
        }

        if (-not [string]::IsNullOrWhiteSpace($managedIdentityID)) {
            if ($managedIdentityID.StartsWith('/subscriptions/', [System.StringComparison]::OrdinalIgnoreCase)) {
                $query['mi_res_id'] = $managedIdentityID
            }
            else {
                $query['client_id'] = $managedIdentityID
            }
        }

        $uriBuilder = [System.UriBuilder]::new($env:IDENTITY_ENDPOINT)
        $uriBuilder.Query = ($query.GetEnumerator() | ForEach-Object { '{0}={1}' -f [System.Net.WebUtility]::UrlEncode($_.Key), [System.Net.WebUtility]::UrlEncode($_.Value) }) -join '&'
        $headers = @{
            'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER
        }

        $response = Invoke-RestMethod -Method Get -Uri $uriBuilder.Uri.AbsoluteUri -Headers $headers -ErrorAction Stop
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:MSI_ENDPOINT) -and -not [string]::IsNullOrWhiteSpace($env:MSI_SECRET)) {
        $query = [ordered]@{
            'api-version' = '2017-09-01'
            resource      = $resource
        }

        if (-not [string]::IsNullOrWhiteSpace($managedIdentityID)) {
            $query['clientid'] = $managedIdentityID
        }

        $uriBuilder = [System.UriBuilder]::new($env:MSI_ENDPOINT)
        $uriBuilder.Query = ($query.GetEnumerator() | ForEach-Object { '{0}={1}' -f [System.Net.WebUtility]::UrlEncode($_.Key), [System.Net.WebUtility]::UrlEncode($_.Value) }) -join '&'
        $headers = @{
            Secret = $env:MSI_SECRET
        }

        $response = Invoke-RestMethod -Method Get -Uri $uriBuilder.Uri.AbsoluteUri -Headers $headers -ErrorAction Stop
    }
    else {
        throw 'Function runtime managed identity token acquisition requires IDENTITY_ENDPOINT and IDENTITY_HEADER environment variables, or legacy MSI_ENDPOINT and MSI_SECRET environment variables.'
    }

    if ([string]::IsNullOrWhiteSpace($response.access_token)) {
        throw 'Function runtime managed identity endpoint did not return an access token.'
    }

    $expiresOn = $null
    if ($response.expires_on) {
        $expiresOnText = [string]$response.expires_on
        $epochSeconds = 0L
        if ([Int64]::TryParse($expiresOnText, [ref]$epochSeconds)) {
            $expiresOn = [DateTimeOffset]::FromUnixTimeSeconds($epochSeconds).UtcDateTime
        }
        else {
            $expiresOn = ([DateTimeOffset]::Parse($expiresOnText, [Globalization.CultureInfo]::InvariantCulture)).UtcDateTime
        }
    }
    elseif ($response.expires_in) {
        $expiresOn = (Get-Date).ToUniversalTime().AddSeconds([Int32]$response.expires_in)
    }
    else {
        throw 'Function runtime managed identity endpoint did not return token expiration metadata.'
    }

    return [PSCustomObject]@{
        Token     = ConvertTo-SecureString -String $response.access_token -AsPlainText -Force
        ExpiresOn = $expiresOn
    }
}
