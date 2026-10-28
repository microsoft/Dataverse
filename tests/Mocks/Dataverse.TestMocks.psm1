function New-PSDVTestSecureString {
    [CmdletBinding()]
    param()

    $plainText = [Guid]::NewGuid().ToString('N')
    return [PSCustomObject]@{
        PlainText    = $plainText
        SecureString = ConvertTo-SecureString -String $plainText -AsPlainText -Force
    }
}

function New-PSDVTestAccessToken {
    [CmdletBinding()]
    param(
        [Parameter()]
        [DateTime]
        $ExpiresOn = (Get-Date).ToUniversalTime().AddHours(1),

        [Parameter()]
        [Switch]
        $IncludeRefreshToken
    )

    $tokenText = [Guid]::NewGuid().ToString('N')
    $token = [PSCustomObject]@{
        Token     = ConvertTo-SecureString -String $tokenText -AsPlainText -Force
        ExpiresOn = $ExpiresOn
    }

    if ($IncludeRefreshToken.IsPresent) {
        $token | Add-Member -NotePropertyName RefreshToken -NotePropertyValue ([Guid]::NewGuid().ToString('N'))
    }

    return $token
}

function New-PSDVTestAuthContext {
    [CmdletBinding()]
    param(
        [Parameter()]
        [String]
        $ParameterSetName = 'InteractiveLogin',

        [Parameter()]
        [String]
        $ResourceUrl = 'https://example.crm.dynamics.com/',

        [Parameter()]
        [String]
        $Environment = 'AzureCloud'
    )

    return @{
        ParameterSetName = $ParameterSetName
        ResourceUrl       = $ResourceUrl
        Environment       = $Environment
        AzureTenantId     = [Guid]::NewGuid().ToString()
        ClientID          = [Guid]::NewGuid().ToString()
    }
}

function New-PSDVTestCertificate {
    [CmdletBinding()]
    param()

    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $subject = "CN=PSDVTest-$([Guid]::NewGuid().ToString('N'))"
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        $subject,
        $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )

    $notBefore = [DateTimeOffset]::UtcNow.AddMinutes(-5)
    $notAfter = [DateTimeOffset]::UtcNow.AddHours(1)
    return $request.CreateSelfSigned($notBefore, $notAfter)
}

function New-PSDVTestCertificateFile {
    [CmdletBinding()]
    param()

    $certificate = New-PSDVTestCertificate
    $passwordData = New-PSDVTestSecureString
    $path = Join-Path ([System.IO.Path]::GetTempPath()) "psdv-test-$([Guid]::NewGuid().ToString('N')).pfx"
    $bytes = $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $passwordData.PlainText)
    [System.IO.File]::WriteAllBytes($path, $bytes)

    return [PSCustomObject]@{
        Path        = $path
        Password    = $passwordData.SecureString
        Certificate = $certificate
    }
}

function Clear-PSDVTestCertificateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [Object]
        $CertificateFile
    )

    if ($null -ne $CertificateFile -and -not [string]::IsNullOrWhiteSpace($CertificateFile.Path) -and (Test-Path -LiteralPath $CertificateFile.Path)) {
        Remove-Item -LiteralPath $CertificateFile.Path -Force
    }
}

function New-PSDVTestMetadataAttribute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]
        $LogicalName,

        [Parameter()]
        [String]
        $AttributeType = 'String',

        [Parameter()]
        [String]
        $SchemaName = $LogicalName,

        [Parameter()]
        [String[]]
        $Targets = @()
    )

    return [PSCustomObject]@{
        LogicalName   = $LogicalName
        AttributeType = $AttributeType
        SchemaName    = $SchemaName
        Targets       = $Targets
    }
}

function New-PSDVTestHttpErrorRecord {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]
        $StatusCode = 412,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Content = '{"error":{"code":"0x80060882","message":"Version mismatch"}}'
    )

    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$StatusCode)
    $response.Content = [System.Net.Http.StringContent]::new($Content)
    $null = $response.Headers.TryAddWithoutValidation('x-ms-service-request-id', 'request-123')
    $null = $response.Headers.TryAddWithoutValidation('x-test-values', [string[]]@('first', 'second'))
    $null = $response.Headers.TryAddWithoutValidation('Retry-After', '5')
    $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("HTTP $StatusCode", $response)
    $record = [System.Management.Automation.ErrorRecord]::new(
        $exception, 'NativeHttpError', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null
    )
    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Content)
    return $record
}

Export-ModuleMember -Function @(
    'New-PSDVTestHttpErrorRecord',
    'New-PSDVTestSecureString',
    'New-PSDVTestAccessToken',
    'New-PSDVTestAuthContext',
    'New-PSDVTestCertificate',
    'New-PSDVTestCertificateFile',
    'Clear-PSDVTestCertificateFile',
    'New-PSDVTestMetadataAttribute'
)
