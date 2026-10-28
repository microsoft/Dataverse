function New-PSDVTableWebHook {
    <#
    .SYNOPSIS
    Creates a new webhook registration for a Dataverse table.

    .DESCRIPTION
    New-PSDVTableWebHook registers a webhook endpoint to be triggered when specified operations occur on a Dataverse table.
    The function creates a service endpoint, retrieves the necessary SDK message and filter IDs, and then creates the 
    webhook step registration. This enables real-time notifications to external systems when data changes occur.

    .PARAMETER Table
    The logical name of the Dataverse table to monitor for webhook triggers.

    .PARAMETER WebHookName
    The display name for the webhook registration.

    .PARAMETER TriggerUri
    Must be an absolute HTTP(S) URL with a host; relative or unsupported-scheme destinations are rejected at binding.
    The HTTP endpoint URL that will receive webhook notifications when the trigger events occur.

    .PARAMETER Operation
    The SDK message operation to monitor. Valid values are Create, Update, Delete, or Retrieve. Default is Create.

    .PARAMETER AuthSecret
    The optional authentication secret for webhook security. This will be passed in the x-dv-webhook-secret header.

    .PARAMETER Stage
    The execution stage for the webhook. Valid values are PreValidation (10), PreOperation (20), MainOperation (30), or PostOperation (40). Default is PostOperation.

    .PARAMETER Rank
    The execution order rank within the stage. Lower numbers execute first. Default is 1.

    .PARAMETER Mode
    The execution mode. Valid values are Synchronous (0) or Asynchronous (1). Default is Asynchronous.

    .PARAMETER SupportedDeployment
    The deployment scope. Valid values are ServerOnly (0), ClientOnly (1), or Both (2). Default is ServerOnly.

    .PARAMETER FilteringAttributes
    An optional array of column logical names to filter on. When specified, the webhook will only trigger when one or more of these columns are modified. This is only applicable for Update operations. If not specified, the webhook triggers for all column changes.

    .PARAMETER PreImage
    When specified, registers a pre-image on the webhook step. A pre-image captures a snapshot of the entity record's values before the operation is executed. This is useful for comparing old and new values during Update or Delete operations.

    .PARAMETER PreImageAttributes
    An optional array of column logical names to include in the pre-image. When specified, only these columns will be captured in the pre-image snapshot. If not specified, all columns are included. Only used when -PreImage is specified.

    .PARAMETER PostImage
    When specified, registers a post-image on the webhook step. A post-image captures a snapshot of the entity record's values after the operation is executed. This is useful for accessing the final state of the record after Create or Update operations.

    .PARAMETER PostImageAttributes
    An optional array of column logical names to include in the post-image. When specified, only these columns will be captured in the post-image snapshot. If not specified, all columns are included. Only used when -PostImage is specified.

    .EXAMPLE
    New-PSDVTableWebHook -Table "account" -WebHookName "Account Changes Monitor" -TriggerUri "https://myapp.azurewebsites.net/api/DataverseTrigger" -Operation "Create"

    Creates a webhook to monitor account creation events.

    .EXAMPLE
    New-PSDVTableWebHook -Table "spork_sporkuserrequest" -WebHookName "SPORK Users New Record WebHook" -TriggerUri "https://sporkapps.azurewebsites.net/api/DataverseTrigger" -Operation "Create" -AuthSecret "DontTell"

    Creates a webhook with authentication secret for a custom table.

    .EXAMPLE
    New-PSDVTableWebHook -Table "contact" -WebHookName "Contact Update Monitor" -TriggerUri "https://myapp.com/webhook" -Operation "Update" -Stage "PreOperation" -Mode "Synchronous"

    Creates a synchronous webhook that fires before contact updates are processed.

    .EXAMPLE
    New-PSDVTableWebHook -Table "account" -WebHookName "Account Name Monitor" -TriggerUri "https://myapp.com/webhook" -Operation "Update" -FilteringAttributes @("name", "accountcategorycode")

    Creates a webhook that only triggers when the account name or category code fields are updated.

    .EXAMPLE
    New-PSDVTableWebHook -Table "contact" -WebHookName "Contact Update With PreImage" -TriggerUri "https://myapp.com/webhook" -Operation "Update" -PreImage -PreImageAttributes @("firstname", "lastname", "emailaddress1")

    Creates a webhook that captures a pre-image of the firstname, lastname, and emailaddress1 fields before contact updates.

    .EXAMPLE
    New-PSDVTableWebHook -Table "account" -WebHookName "Account Create With PostImage" -TriggerUri "https://myapp.com/webhook" -Operation "Create" -PostImage -PostImageAttributes @("name", "accountnumber")

    Creates a webhook that captures a post-image of the name and accountnumber fields after account creation.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $Table,

        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $WebHookName,

        [Parameter(Mandatory)]
        [ValidateScript({
            $uri = $_ -as [uri]
            $null -ne $uri -and $uri.IsAbsoluteUri -and $uri.Scheme -in @('http', 'https') -and $uri.Host -match '\S'
        }, ErrorMessage = 'TriggerUri must be an absolute HTTP(S) URL with a host.')]
        [String]
        $TriggerUri,

        [Parameter()]
        [ValidateSet('Create', 'Update', 'Delete', 'Retrieve')]
        [String]
        $Operation = 'Create',

        [Parameter()]
        [String]
        $AuthSecret,

        [Parameter()]
        [ValidateSet('PreValidation', 'PreOperation', 'MainOperation', 'PostOperation')]
        [String]
        $Stage = 'PostOperation',

        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [Int32]
        $Rank = 1,

        [Parameter()]
        [ValidateSet('Synchronous', 'Asynchronous')]
        [String]
        $Mode = 'Asynchronous',

        [Parameter()]
        [ValidateSet('ServerOnly', 'ClientOnly', 'Both')]
        [String]
        $SupportedDeployment = 'ServerOnly',

        [Parameter()]
        [String[]]
        $FilteringAttributes,

        [Parameter()]
        [Switch]
        $PreImage,

        [Parameter()]
        [String[]]
        $PreImageAttributes,

        [Parameter()]
        [Switch]
        $PostImage,

        [Parameter()]
        [String[]]
        $PostImageAttributes
    )

    foreach ($selection in @('FilteringAttributes', 'PreImageAttributes', 'PostImageAttributes')) {
        foreach ($column in $PSBoundParameters[$selection]) {
            if ($column -notmatch '\S') {
                throw "$selection entries cannot be null, empty, or whitespace."
            }
        }
    }

    if ($null -eq $Global:DATAVERSEACCESSTOKEN) {
        throw 'No existing connection to Dataverse Environment, run Connect-PSDVOrg before executing other PSDV cmdlets'
    }

    # Validate filtering attributes are only used with Update operations
    if ($FilteringAttributes -and $Operation -ne 'Update') {
        throw "FilteringAttributes parameter can only be used with Update operations. Current operation: $Operation"
    }

    # Validate PreImageAttributes are only used with PreImage
    if ($PreImageAttributes -and -not $PreImage) {
        throw "PreImageAttributes parameter can only be used when -PreImage is specified"
    }

    # Validate PreImage is only used with Update or Delete operations
    if ($PreImage -and $Operation -notin @('Update', 'Delete')) {
        throw "PreImage parameter can only be used with Update or Delete operations. Current operation: $Operation"
    }

    # Validate PostImageAttributes are only used with PostImage
    if ($PostImageAttributes -and -not $PostImage) {
        throw "PostImageAttributes parameter can only be used when -PostImage is specified"
    }

    # Validate PostImage is only used with Create or Update operations
    if ($PostImage -and $Operation -notin @('Create', 'Update')) {
        throw "PostImage parameter can only be used with Create or Update operations. Current operation: $Operation"
    }

    # Convert stage names to numeric values
    $stageMap = @{
        'PreValidation' = 10
        'PreOperation' = 20
        'MainOperation' = 30
        'PostOperation' = 40
    }

    # Convert mode names to numeric values  
    $modeMap = @{
        'Synchronous' = 0
        'Asynchronous' = 1
    }

    # Convert deployment names to numeric values
    $deploymentMap = @{
        'ServerOnly' = 0
        'ClientOnly' = 1
        'Both' = 2
    }

    # Check for existing webhook with same table, operation, and URL
    Write-Verbose "Checking for existing webhook with same table ($Table), operation ($Operation), and URL ($TriggerUri)"
    try {
        $tableLiteral = ConvertTo-PSDVODataStringLiteral -Value $Table
        $operationLiteral = ConvertTo-PSDVODataStringLiteral -Value $Operation
        $triggerUriLiteral = ConvertTo-PSDVODataStringLiteral -Value $TriggerUri
        $existingWebhookQuery = "eventhandler_serviceendpoint ne null and eventhandler_serviceendpoint/serviceendpointid ne null and sdkmessagefilterid/primaryobjecttypecode eq $tableLiteral and sdkmessageid/name eq $operationLiteral and eventhandler_serviceendpoint/url eq $triggerUriLiteral"
        $existingWebhook = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/sdkmessageprocessingsteps" -Select "sdkmessageprocessingstepid,name" -Expand "eventhandler_serviceendpoint(`$select=serviceendpointid,name,url)" -Filter $existingWebhookQuery
        
        if ($existingWebhook -and $existingWebhook.Count -gt 0) {
            $existingWebhookName = if ($existingWebhook[0].eventhandler_serviceendpoint.name) { $existingWebhook[0].eventhandler_serviceendpoint.name } else { "Unknown" }
            throw "A webhook already exists for table '$Table', operation '$Operation', and URL '$TriggerUri'. Existing webhook: $existingWebhookName"
        }
        
        Write-Verbose "No duplicate webhook found. Proceeding with webhook creation."
    }
    catch {
        if ($_.Exception.Message -like "*webhook already exists*") {
            throw
        }
        Write-Verbose "Error checking for duplicates (proceeding anyway): $($_.Exception.Message)"
    }

    try {
        # Step 1: Create service endpoint
        Write-Verbose "Creating service endpoint for webhook: $WebHookName"
        
        $serviceEndPointSetup = @{
            "name" = $WebHookName
            "url" = $TriggerUri
            "contract" = 8  # WebHook contract type
            "authtype" = 5  # HttpHeader authentication
        }

        if ($PSBoundParameters.ContainsKey('AuthSecret')) {
            $escapedAuthSecret = ConvertTo-PSDVXmlAttributeValue -Value $AuthSecret
            $serviceEndPointSetup["authvalue"] = "<settings><setting name=""x-dv-webhook-secret"" value=""$escapedAuthSecret""/></settings>"
        } else {
            $serviceEndPointSetup["authvalue"] = "<settings></settings>"
        }

        if ($PSCmdlet.ShouldProcess($WebHookName, "Create service endpoint")) {
            $serviceEndpointHeaders = @{
                'Prefer' = 'odata.include-annotations="*",return=representation'
            }
            $serviceEndpoint = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/serviceendpoints" -Method Post -Body $serviceEndPointSetup -Headers $serviceEndpointHeaders
            Write-Verbose "Service endpoint created with ID: $($serviceEndpoint.serviceendpointid)"
        } else {
            Write-Verbose "Would create service endpoint for: $WebHookName"
            return
        }

        # Step 2: Get SDK message ID
        Write-Verbose "Retrieving SDK message ID for operation: $Operation"
        $operationLiteral = ConvertTo-PSDVODataStringLiteral -Value $Operation
        $sdkMessage = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/sdkmessages" -Select "sdkmessageid,name" -Filter "name eq $operationLiteral"
        
        if (-not $sdkMessage -or $sdkMessage.Count -eq 0) {
            throw "SDK message '$Operation' not found"
        }
        
        $sdkMessageId = $sdkMessage.sdkmessageid
        Write-Verbose "SDK message ID: $sdkMessageId"

        # Step 3: Get SDK message filter ID
        Write-Verbose "Retrieving SDK message filter for table '$Table' and operation '$Operation'"
        $tableLiteral = ConvertTo-PSDVODataStringLiteral -Value $Table
        $operationLiteral = ConvertTo-PSDVODataStringLiteral -Value $Operation
        $sdkMessageFilter = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/sdkmessagefilters" -Select "sdkmessagefilterid,primaryobjecttypecode" -Filter "primaryobjecttypecode eq $tableLiteral and sdkmessageid/name eq $operationLiteral"
        
        if (-not $sdkMessageFilter -or $sdkMessageFilter.Count -eq 0) {
            throw "SDK message filter for table '$Table' and operation '$Operation' not found"
        }
        
        $sdkMessageFilterId = $sdkMessageFilter.sdkmessagefilterid
        Write-Verbose "SDK message filter ID: $sdkMessageFilterId"

        # Step 4: Create webhook step
        Write-Verbose "Creating webhook step registration"
        $webhookStepName = "$($WebHookName.ToLower().Replace(' ', '.')).$Table.$($Operation.ToLower())"
        
        $webhookStep = @{
            "name" = $webhookStepName
            "description" = "$WebHookName - $Table - $Operation"
            "stage" = $stageMap[$Stage]
            "rank" = $Rank
            "mode" = $modeMap[$Mode]
            "supporteddeployment" = $deploymentMap[$SupportedDeployment]
            "eventhandler_serviceendpoint@odata.bind" = "/serviceendpoints($($serviceEndpoint.serviceendpointid))"
            "sdkmessageid@odata.bind" = "/sdkmessages($sdkMessageId)"
            "sdkmessagefilterid@odata.bind" = "/sdkmessagefilters($sdkMessageFilterId)"
        }

        # Add filtering attributes if specified
        if ($FilteringAttributes -and $FilteringAttributes.Count -gt 0) {
            $webhookStep["filteringattributes"] = ($FilteringAttributes -join ",")
            Write-Verbose "Adding filtering attributes: $($FilteringAttributes -join ', ')"
        }

        if ($PSCmdlet.ShouldProcess($webhookStepName, "Create webhook step")) {
            $webhookStepHeaders = @{
                'Prefer' = 'odata.include-annotations="*",return=representation'
            }
            $webhookStepResult = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/sdkmessageprocessingsteps" -Method Post -Body $webhookStep -Headers $webhookStepHeaders
            Write-Verbose "Webhook step created with ID: $($webhookStepResult.sdkmessageprocessingstepid)"

            # Step 5: Register pre-image if requested
            $preImageId = $null
            if ($PreImage) {
                Write-Verbose "Registering pre-image on webhook step"
                $preImageBody = @{
                    "sdkmessageprocessingstepid@odata.bind" = "/sdkmessageprocessingsteps($($webhookStepResult.sdkmessageprocessingstepid))"
                    "imagetype" = 0  # PreImage
                    "name" = "PreImage"
                    "entityalias" = "PreImage"
                    "messagepropertyname" = "Target"
                }

                if ($PreImageAttributes -and $PreImageAttributes.Count -gt 0) {
                    $preImageBody["attributes"] = ($PreImageAttributes -join ",")
                    Write-Verbose "Pre-image attributes: $($PreImageAttributes -join ', ')"
                }

                $preImageHeaders = @{
                    'Prefer' = 'odata.include-annotations="*",return=representation'
                }
                $preImageResult = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/sdkmessageprocessingstepimages" -Method Post -Body $preImageBody -Headers $preImageHeaders
                $preImageId = $preImageResult.sdkmessageprocessingstepimageid
                Write-Verbose "Pre-image registered with ID: $preImageId"
            }

            # Step 6: Register post-image if requested
            $postImageId = $null
            if ($PostImage) {
                Write-Verbose "Registering post-image on webhook step"
                $postImageBody = @{
                    "sdkmessageprocessingstepid@odata.bind" = "/sdkmessageprocessingsteps($($webhookStepResult.sdkmessageprocessingstepid))"
                    "imagetype" = 1  # PostImage
                    "name" = "PostImage"
                    "entityalias" = "PostImage"
                    "messagepropertyname" = "Target"
                }

                if ($PostImageAttributes -and $PostImageAttributes.Count -gt 0) {
                    $postImageBody["attributes"] = ($PostImageAttributes -join ",")
                    Write-Verbose "Post-image attributes: $($PostImageAttributes -join ', ')"
                }

                $postImageHeaders = @{
                    'Prefer' = 'odata.include-annotations="*",return=representation'
                }
                $postImageResult = Invoke-PSDVWebRequest -WebUri "api/data/v9.2/sdkmessageprocessingstepimages" -Method Post -Body $postImageBody -Headers $postImageHeaders
                $postImageId = $postImageResult.sdkmessageprocessingstepimageid
                Write-Verbose "Post-image registered with ID: $postImageId"
            }
            
            # Return webhook registration details
            return [PSCustomObject]@{
                WebHookName = $WebHookName
                ServiceEndpointId = $serviceEndpoint.serviceendpointid
                WebHookStepId = $webhookStepResult.sdkmessageprocessingstepid
                Table = $Table
                Operation = $Operation
                TriggerUri = $TriggerUri
                Stage = $Stage
                Mode = $Mode
                Rank = $Rank
                SupportedDeployment = $SupportedDeployment
                FilteringAttributes = if ($FilteringAttributes) { $FilteringAttributes } else { $null }
                PreImageId = $preImageId
                PreImageAttributes = if ($PreImageAttributes) { $PreImageAttributes } else { $null }
                PostImageId = $postImageId
                PostImageAttributes = if ($PostImageAttributes) { $PostImageAttributes } else { $null }
            }
        }
    }
    catch {
        throw "Error creating webhook '$WebHookName': $($_.Exception.Message)"
    }
}
