function Remove-PSDVTableWebHook {
    <#
    .SYNOPSIS
    Removes a webhook registration from Dataverse by deleting its service endpoint.

    .DESCRIPTION
    Remove-PSDVTableWebHook removes a webhook registration by deleting the associated service endpoint from Dataverse.
    This will also automatically remove all associated SDK message processing steps (webhook steps) that reference
    this service endpoint. Use this function with caution as the deletion cannot be undone.

    .PARAMETER ServiceEndpointId
    The unique identifier (GUID) of the service endpoint to delete.

    .EXAMPLE
    Remove-PSDVTableWebHook -ServiceEndpointId "12345678-1234-1234-1234-123456789012"

    Removes the webhook by deleting the service endpoint with the specified ID.

    .EXAMPLE
    Get-PSDVTableWebHook -Table "account" | Where-Object Name -eq "My Account Webhook" | ForEach-Object {
        Remove-PSDVTableWebHook -ServiceEndpointId $_.ServiceEndpointId
    }

    Finds a specific webhook by name and removes it.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $_ -ne [guid]::Empty }, ErrorMessage = 'ServiceEndpointId cannot be an empty GUID.')]
        [Guid]
        $ServiceEndpointId
    )

    if ($null -eq $Global:DATAVERSEACCESSTOKEN) {
        throw 'No existing connection to Dataverse Environment, run Connect-PSDVOrg before executing other PSDV cmdlets'
    }

    if ($ServiceEndpointId -eq [Guid]::Empty) {
        throw 'ServiceEndpointId cannot be an empty GUID'
    }

    try {
        # Get service endpoint details for confirmation
        Write-Verbose "Retrieving service endpoint details: $ServiceEndpointId"
        $serviceEndpoint = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/serviceendpoints($ServiceEndpointId)" -Select "serviceendpointid,name,url"
        
        if (-not $serviceEndpoint) {
            throw "Service endpoint '$ServiceEndpointId' not found"
        }
        
        $endpointName = $serviceEndpoint.name
        Write-Verbose "Found service endpoint: $ServiceEndpointId ($endpointName)"

        # First, find and delete all associated SDK message processing steps
        Write-Verbose "Finding associated webhook steps for service endpoint: $ServiceEndpointId"
        $associatedSteps = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/sdkmessageprocessingsteps" -Select "sdkmessageprocessingstepid,name" -Filter "eventhandler_serviceendpoint/serviceendpointid eq $ServiceEndpointId"
        
        if ($associatedSteps -and $associatedSteps.Count -gt 0) {
            Write-Verbose "Found $($associatedSteps.Count) associated webhook step(s) to delete"
            
            foreach ($step in $associatedSteps) {
                if ($PSCmdlet.ShouldProcess("Webhook Step '$($step.name)' ($($step.sdkmessageprocessingstepid))", "Delete associated webhook step")) {
                    Write-Verbose "Deleting webhook step: $($step.sdkmessageprocessingstepid) - $($step.name)"
                    $stepUri = "sdkmessageprocessingsteps($($step.sdkmessageprocessingstepid))"
                    Invoke-PSDVWebRequest -WebUri $stepUri -Method 'Delete'
                    Write-Verbose "Successfully deleted webhook step: $($step.name)"
                } else {
                    Write-Verbose "Would delete webhook step: $($step.name)"
                }
            }
        } else {
            Write-Verbose "No associated webhook steps found for service endpoint: $ServiceEndpointId"
        }

        $requestHeaders = @{'Prefer' = 'odata.include-annotations="*"' }
        $dvRequestUri = "serviceendpoints($ServiceEndpointId)"

        if ($PSCmdlet.ShouldProcess("Service Endpoint '$endpointName' ($ServiceEndpointId)", "Delete webhook")) {
            Write-Verbose "Deleting service endpoint: $ServiceEndpointId"
            $null = Invoke-PSDVWebRequest -WebUri $dvRequestUri -Headers $requestHeaders -Method 'Delete'
            
            Write-Verbose "Successfully deleted webhook service endpoint: $endpointName"
            return [PSCustomObject]@{
                Message = "Webhook service endpoint deleted successfully"
                ServiceEndpointId = $ServiceEndpointId
                Name = $endpointName
                AssociatedStepsDeleted = if ($associatedSteps) { $associatedSteps.Count } else { 0 }
                Deleted = $true
            }
        }
    }
    catch {
        throw "Error removing webhook service endpoint '$ServiceEndpointId': $($_.Exception.Message)"
    }
}
