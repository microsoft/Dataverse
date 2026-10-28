function Get-PSDVAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            $uri = $_.ResourceUrl -as [uri]
            $_.ResourceUrl -is [string] -and $null -ne $uri -and $uri.IsAbsoluteUri -and
                $uri.Scheme -in @('http', 'https') -and $uri.Host -match '\S'
        }, ErrorMessage = 'AuthContext requires an absolute HTTP(S) ResourceUrl.')]
        [ValidateScript({
            $null -ne $_.Credential -or $_.ParameterSetName -in @(
                'ClientSecret', 'ClientCertificate', 'ClientCertificateThumbprint', 'ClientCertificatePath',
                'ManagedIdentity', 'SystemManagedIdentity', 'InteractiveLogin'
            )
        }, ErrorMessage = 'AuthContext requires a supported authentication parameter set or a cached credential.')]
        [ValidateScript({
            $null -eq $_.Credential -or $_.Credential.PSObject.Methods.Name -contains 'GetToken'
        }, ErrorMessage = 'A cached Credential must provide a GetToken method.')]
        [ValidateScript({
            $_.ParameterSetName -notin @('ManagedIdentity', 'SystemManagedIdentity') -or
                $_.ManagedIdentityTokenSource -notmatch '\S' -or
                $_.ManagedIdentityTokenSource -in @('AzureIdentity', 'FunctionRuntime')
        }, ErrorMessage = 'ManagedIdentityTokenSource must be AzureIdentity or FunctionRuntime.')]
        [Hashtable]
        $AuthContext
    )

    $isManagedIdentity = $AuthContext.ParameterSetName -in @('ManagedIdentity', 'SystemManagedIdentity')
    if ($isManagedIdentity -and $AuthContext.ManagedIdentityTokenSource -eq 'FunctionRuntime') {
        return Get-PSDVFunctionRuntimeManagedIdentityAccessToken -AuthContext $AuthContext
    }

    if ($null -eq $AuthContext.Credential) {
        $AuthContext.Credential = switch ($AuthContext.ParameterSetName) {
            'ClientSecret' { New-PSDVClientSecretCredential -AuthContext $AuthContext }
            'ClientCertificate' { New-PSDVClientCertificateCredential -AuthContext $AuthContext }
            'ClientCertificateThumbprint' { New-PSDVClientCertificateCredential -AuthContext $AuthContext }
            'ClientCertificatePath' { New-PSDVClientCertificateCredential -AuthContext $AuthContext }
            'ManagedIdentity' { New-PSDVManagedIdentityCredential -AuthContext $AuthContext }
            'SystemManagedIdentity' { New-PSDVManagedIdentityCredential -AuthContext $AuthContext }
            'InteractiveLogin' { New-PSDVInteractiveCredential -AuthContext $AuthContext }
            default { throw "Unsupported authentication parameter set '$($AuthContext.ParameterSetName)'" }
        }
    }

    Import-PSDVAzureIdentityAssemblies
    $scope = "$($AuthContext.ResourceUrl.TrimEnd('/'))/.default"
    $tokenRequestContext = [Azure.Core.TokenRequestContext]::new([String[]]@($scope))
    $sdkToken = $AuthContext.Credential.GetToken($tokenRequestContext, [System.Threading.CancellationToken]::None)

    return [PSCustomObject]@{
        Token     = ConvertTo-SecureString -String $sdkToken.Token -AsPlainText -Force
        ExpiresOn = $sdkToken.ExpiresOn.UtcDateTime
    }
}
