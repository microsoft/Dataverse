function Get-PSDVAzureAuthorityHost {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [ValidateScript({
            $_ -notmatch '\S' -or $_ -in $script:PSDVAzureAuthorityHosts.Keys
        }, ErrorMessage = 'Unsupported Azure environment.')]
        [String]
        $Environment = 'AzureCloud'
    )

    if ($Environment -notmatch '\S') {
        $Environment = 'AzureCloud'
    }

    return [System.Uri]::new($script:PSDVAzureAuthorityHosts[$Environment])
}
