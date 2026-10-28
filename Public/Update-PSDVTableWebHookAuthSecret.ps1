function Update-PSDVTableWebHookAuthSecret {
    <#
    .SYNOPSIS
    Updates the authentication secret for an existing Dataverse table webhook.

    .DESCRIPTION
    Update-PSDVTableWebHookAuthSecret modifies the authentication secret for an existing webhook registration.
    The function can find the webhook by table and name, or by the specific webhook step ID for more precise
    identification. It then updates the service endpoint's auth configuration with the new secret value.
    The secret will be passed in the x-dv-webhook-secret header when the webhook is triggered.
    If no secret is provided, the auth configuration is cleared.

    .PARAMETER Table
    The logical name of the Dataverse table that the webhook is registered for.

    .PARAMETER WebHookName
    The name of the webhook registration to update. Use when webhook names are unique for the table.

    .PARAMETER WebHookStepId
    The unique identifier (GUID) of the webhook step to update. Use when webhook names might not be unique or for precise identification.

    .PARAMETER AuthSecret
    The new authentication secret value. If not provided or empty, the auth configuration will be cleared.

    .EXAMPLE
    Update-PSDVTableWebHookAuthSecret -Table "account" -WebHookName "Account Changes Monitor" -AuthSecret "NewSecretValue123"

    Updates the authentication secret for the "Account Changes Monitor" webhook using name-based lookup.

    .EXAMPLE
    Update-PSDVTableWebHookAuthSecret -Table "contact" -WebHookStepId "12345678-1234-1234-1234-123456789012" -AuthSecret "NewSecretValue123"

    Updates the authentication secret for a specific webhook using its step ID.

    .EXAMPLE
    Update-PSDVTableWebHookAuthSecret -Table "contact" -WebHookName "Contact Sync Webhook" -AuthSecret ""

    Clears the authentication secret for the specified webhook.

    .EXAMPLE
    Get-PSDVTableWebHook -Table "account" | Where-Object Name -eq "My Webhook" | ForEach-Object {
        Update-PSDVTableWebHookAuthSecret -Table "account" -WebHookStepId $_.WebHookStepId -AuthSecret "UpdatedSecret"
    }

    Updates the auth secret for a webhook found via Get-PSDVTableWebHook using step ID for precise identification.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [Parameter(Mandatory, ParameterSetName = 'ByStepId')]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $Table,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $WebHookName,

        [Parameter(Mandatory, ParameterSetName = 'ByStepId')]
        [ValidateScript({ $_ -ne [guid]::Empty }, ErrorMessage = 'WebHookStepId cannot be an empty GUID.')]
        [Guid]
        $WebHookStepId,

        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'ByStepId')]
        [String]
        $AuthSecret
    )

    if ($null -eq $Global:DATAVERSEACCESSTOKEN) {
        throw 'No existing connection to Dataverse Environment, run Connect-PSDVOrg before executing other PSDV cmdlets'
    }

    if ($PSBoundParameters.ContainsKey('WebHookStepId') -and $WebHookStepId -eq [Guid]::Empty) {
        throw 'WebHookStepId cannot be an empty GUID'
    }

    try {
        $serviceEndpointId = $null
        $webhookInfo = $null

        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Finding webhook '$WebHookName' for table '$Table' using name-based lookup"
            
            # Find the webhook by table and name
            $existingWebhook = Get-PSDVTableWebHook -Table $Table -Name $WebHookName
            
            if (-not $existingWebhook) {
                throw "Webhook '$WebHookName' not found for table '$Table'"
            }

            # Handle case where multiple webhooks match the name filter
            if ($existingWebhook.Count -gt 1) {
                # Try exact name match
                $exactMatch = $existingWebhook | Where-Object { $_.Name -eq $WebHookName }
                if ($exactMatch.Count -eq 1) {
                    $existingWebhook = $exactMatch
                } elseif ($exactMatch.Count -gt 1) {
                    throw "Multiple webhooks found with exact name '$WebHookName' for table '$Table'. Please use -WebHookStepId parameter for precise identification. Found step IDs: $($exactMatch.WebHookStepId -join ', ')"
                } else {
                    throw "Multiple webhooks found containing name '$WebHookName' for table '$Table'. Found: $($existingWebhook.Name -join ', '). Please use -WebHookStepId parameter for precise identification."
                }
            }

            $serviceEndpointId = $existingWebhook.ServiceEndpointId
            $webhookInfo = $existingWebhook
            Write-Verbose "Found webhook '$WebHookName' with service endpoint ID: $serviceEndpointId"
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByStepId') {
            Write-Verbose "Finding webhook with step ID '$WebHookStepId' for table '$Table' using step ID lookup"
            
            # Get webhook step details directly by ID and validate table
            $webhookStep = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/sdkmessageprocessingsteps($WebHookStepId)" -Select "sdkmessageprocessingstepid,name,description" -Expand "eventhandler_serviceendpoint(`$select=serviceendpointid,name,url),sdkmessagefilterid(`$select=sdkmessagefilterid,primaryobjecttypecode)"
            
            if (-not $webhookStep) {
                throw "Webhook step '$WebHookStepId' not found"
            }

            # Validate that the webhook is for the specified table
            if ($webhookStep.sdkmessagefilterid.primaryobjecttypecode -ne $Table) {
                throw "Webhook step '$WebHookStepId' is not configured for table '$Table'. It is configured for table '$($webhookStep.sdkmessagefilterid.primaryobjecttypecode)'"
            }

            # Validate that it has a service endpoint (is actually a webhook)
            if (-not $webhookStep.eventhandler_serviceendpoint -or -not $webhookStep.eventhandler_serviceendpoint.serviceendpointid) {
                throw "Step '$WebHookStepId' is not a webhook step (no service endpoint found)"
            }

            $serviceEndpointId = $webhookStep.eventhandler_serviceendpoint.serviceendpointid
            $webhookInfo = [PSCustomObject]@{
                WebHookStepId = $webhookStep.sdkmessageprocessingstepid
                Name = $webhookStep.name
                ServiceEndpointId = $webhookStep.eventhandler_serviceendpoint.serviceendpointid
                Url = $webhookStep.eventhandler_serviceendpoint.url
                ServiceEndpointName = $webhookStep.eventhandler_serviceendpoint.name
            }
            Write-Verbose "Found webhook step '$($webhookStep.name)' with service endpoint ID: $serviceEndpointId"
        }

        # Prepare the auth value based on whether a secret is provided
        if ($PSBoundParameters.ContainsKey('AuthSecret') -and -not [string]::IsNullOrEmpty($AuthSecret)) {
            $escapedAuthSecret = ConvertTo-PSDVXmlAttributeValue -Value $AuthSecret
            $authValue = "<settings><setting name=""x-dv-webhook-secret"" value=""$escapedAuthSecret""/></settings>"
            $actionDescription = "Update authentication secret"
        } else {
            $authValue = "<settings></settings>"
            $actionDescription = "Clear authentication secret"
        }

        # Update the service endpoint
        $updateData = @{
            "authvalue" = $authValue
        }

        $targetDescription = if ($PSCmdlet.ParameterSetName -eq 'ByName') { 
            "$WebHookName (Service Endpoint: $serviceEndpointId)" 
        } else { 
            "$($webhookInfo.Name) (Step ID: $WebHookStepId, Service Endpoint: $serviceEndpointId)" 
        }

        if ($PSCmdlet.ShouldProcess($targetDescription, $actionDescription)) {
            $requestHeaders = @{
                'Prefer' = 'odata.include-annotations="*",return=representation'
            }
            
            Write-Verbose "$actionDescription for webhook '$($webhookInfo.Name)'"
            $null = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/serviceendpoints($serviceEndpointId)" -Method Patch -Body $updateData -Headers $requestHeaders
            
            Write-Verbose "Successfully updated webhook authentication secret"
            
            # Return updated webhook information
            return [PSCustomObject]@{
                WebHookName = $webhookInfo.Name
                WebHookStepId = $webhookInfo.WebHookStepId
                Table = $Table
                ServiceEndpointId = $serviceEndpointId
                Url = $webhookInfo.Url
                ParameterSetUsed = $PSCmdlet.ParameterSetName
                AuthSecretUpdated = if ($PSBoundParameters.ContainsKey('AuthSecret') -and -not [string]::IsNullOrEmpty($AuthSecret)) { $true } else { $false }
                AuthSecretCleared = if (-not $PSBoundParameters.ContainsKey('AuthSecret') -or [string]::IsNullOrEmpty($AuthSecret)) { $true } else { $false }
                UpdatedOn = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        } else {
            $whatIfTarget = if ($PSCmdlet.ParameterSetName -eq 'ByName') { $WebHookName } else { "$($webhookInfo.Name) (Step ID: $WebHookStepId)" }
            Write-Verbose "Would $($actionDescription.ToLower()) for webhook: $whatIfTarget"
            return
        }
    }
    catch {
        $errorTarget = if ($PSCmdlet.ParameterSetName -eq 'ByName') { 
            "'$WebHookName' in table '$Table'" 
        } else { 
            "step ID '$WebHookStepId' in table '$Table'" 
        }
        throw "Error updating webhook auth secret for $errorTarget`: $($_.Exception.Message)"
    }
}
