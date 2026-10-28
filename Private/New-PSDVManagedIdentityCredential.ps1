function New-PSDVManagedIdentityCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            $value = $_.ManagedIdentityID
            $id = $value -as [guid]
            $value -notmatch '\S' -or ($null -ne $id -and $id -ne [guid]::Empty) -or
                $value -match '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.ManagedIdentity/userAssignedIdentities/[^/]+/?$'
        }, ErrorMessage = 'ManagedIdentityID must be a non-empty GUID or a managed identity resource ID, or omitted for system identity.')]
        [Hashtable]
        $AuthContext
    )

    Import-PSDVAzureIdentityAssemblies
    $managedIdentityID = [string]$AuthContext.ManagedIdentityID

    if ($managedIdentityID -notmatch '\S') {
        return [Azure.Identity.ManagedIdentityCredential]::new()
    }

    if ($managedIdentityID.StartsWith('/subscriptions/', [System.StringComparison]::OrdinalIgnoreCase)) {
        $resourceId = [Azure.Core.ResourceIdentifier]::new($managedIdentityID)
        return [Azure.Identity.ManagedIdentityCredential]::new($resourceId)
    }

    return [Azure.Identity.ManagedIdentityCredential]::new($managedIdentityID)
}
