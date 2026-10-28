function Get-PSDVTableWebHook {
    <#
    .SYNOPSIS
    Retrieves registered webhooks for a Dataverse table.

    .DESCRIPTION
    Get-PSDVTableWebHook queries the Dataverse environment to find webhook registrations for a specified table.
    It returns detailed information about each webhook including the service endpoint details, execution settings,
    and associated SDK message information. By default, system and hidden webhooks are filtered out to show only
    user-created webhooks. This function is useful for auditing webhook configurations and troubleshooting issues.

    .PARAMETER Table
    The logical name of the Dataverse table to retrieve webhook registrations for.

    .PARAMETER Operation
    Optional filter to return webhooks for a specific operation only. Valid values are Create, Update, Delete, or Retrieve.

    .PARAMETER Url
    Optional filter to return webhooks for a specific endpoint URL only.

    .PARAMETER Stage
    Optional filter to return webhooks for a specific execution stage only. Valid values are PreValidation, PreOperation, MainOperation, or PostOperation.

    .PARAMETER Name
    Optional filter to return webhooks with names containing the specified text (case-insensitive partial match).

    .PARAMETER IncludeSystemWebHooks
    When specified, includes system-level and hidden webhooks in the results. By default, these are filtered out.

    .EXAMPLE
    Get-PSDVTableWebHook -Table "account"

    Retrieves user-created webhook registrations for the Account table (excludes system webhooks).

    .EXAMPLE
    Get-PSDVTableWebHook -Table "contact" -Operation "Create"

    Retrieves only user-created webhooks that trigger on Contact creation.

    .EXAMPLE
    Get-PSDVTableWebHook -Table "account" -Url "https://myapp.azurewebsites.net/api/webhook"

    Retrieves webhooks for the Account table that target a specific URL.

    .EXAMPLE
    Get-PSDVTableWebHook -Table "contact" -Stage "PreOperation" -Name "validation"

    Retrieves webhooks for the Contact table that run in PreOperation stage and have 'validation' in their name.

    .EXAMPLE
    Get-PSDVTableWebHook -Table "account" -IncludeSystemWebHooks

    Retrieves all webhook registrations for the Account table, including system-level webhooks.

    .EXAMPLE
    Get-PSDVTableWebHook -Table "spork_sporkuserrequest" | Select-Object Name, Url, Stage, Mode

    Retrieves webhooks for a custom table and displays specific properties.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $Table,

        [Parameter()]
        [ValidateSet('Create', 'Update', 'Delete', 'Retrieve')]
        [String]
        $Operation,

        [Parameter()]
        [String]
        $Url,

        [Parameter()]
        [ValidateSet('PreValidation', 'PreOperation', 'MainOperation', 'PostOperation')]
        [String]
        $Stage,

        [Parameter()]
        [String]
        $Name,

        [Parameter()]
        [Switch]
        $IncludeSystemWebHooks
    )

    try {
        Write-Verbose "Retrieving webhook registrations for table: $Table"
        
        # Build the query to get SDK message processing steps with webhook service endpoints
        $select = "sdkmessageprocessingstepid,name,description,stage,rank,mode,statuscode,supporteddeployment,filteringattributes"
        $expand = "eventhandler_serviceendpoint(`$select=serviceendpointid,name,url,authtype,iscustomizable),sdkmessagefilterid(`$select=sdkmessagefilterid,primaryobjecttypecode),sdkmessageid(`$select=sdkmessageid,name)"
        
        # Filter for webhook steps (eventhandler_serviceendpoint exists) and specific table
        $tableLiteral = ConvertTo-PSDVODataStringLiteral -Value $Table
        $filter = "eventhandler_serviceendpoint ne null and eventhandler_serviceendpoint/serviceendpointid ne null and sdkmessagefilterid/primaryobjecttypecode eq $tableLiteral"
        
        # Add operation filter if specified
        if ($PSBoundParameters.ContainsKey('Operation')) {
            $operationLiteral = ConvertTo-PSDVODataStringLiteral -Value $Operation
            $filter += " and sdkmessageid/name eq $operationLiteral"
        }

        # Add URL filter if specified
        if ($PSBoundParameters.ContainsKey('Url')) {
            $urlLiteral = ConvertTo-PSDVODataStringLiteral -Value $Url
            $filter += " and eventhandler_serviceendpoint/url eq $urlLiteral"
        }

        # Add stage filter if specified
        if ($PSBoundParameters.ContainsKey('Stage')) {
            $stageValue = switch ($Stage) {
                'PreValidation' { 10 }
                'PreOperation' { 20 }
                'MainOperation' { 30 }
                'PostOperation' { 40 }
            }
            $filter += " and stage eq $stageValue"
        }

        # Add name filter if specified (use 'contains' for partial matching)
        if ($PSBoundParameters.ContainsKey('Name')) {
            $nameLiteral = ConvertTo-PSDVODataStringLiteral -Value $Name
            $filter += " and contains(name,$nameLiteral)"
        }

        # Filter out system webhooks by default (more efficient than filtering locally)
        if (-not $IncludeSystemWebHooks.IsPresent) {
            $filter += " and eventhandler_serviceendpoint/iscustomizable/Value eq true"
        }

        $webhookSteps = Invoke-PSDVWebRequest -WebUri 'sdkmessageprocessingsteps' -Select $select -Expand $expand -Filter $filter
        
        if (-not $webhookSteps -or $webhookSteps.Count -eq 0) {
            Write-Verbose "No webhook registrations found for table '$Table'"
            return $null
        }

        Write-Verbose "Found $($webhookSteps.Count) webhook registration(s) for table '$Table'"

        # Convert to more user-friendly objects
        $results = foreach ($step in $webhookSteps) {
            [PSCustomObject]@{
                WebHookStepId = $step.sdkmessageprocessingstepid
                Name = $step.name
                Description = $step.description
                Table = $step.sdkmessagefilterid.primaryobjecttypecode
                Operation = $step.sdkmessageid.name
                ColumnFilter = if ($step.filteringattributes) { $step.filteringattributes.Split(',') } else { $null }
                Url = $step.eventhandler_serviceendpoint.url
                ServiceEndpointName = $step.eventhandler_serviceendpoint.name
                ServiceEndpointId = $step.eventhandler_serviceendpoint.serviceendpointid
                Stage = switch ($step.stage) {
                    10 { 'PreValidation' }
                    20 { 'PreOperation' }  
                    30 { 'MainOperation' }
                    40 { 'PostOperation' }
                    default { $step.stage }
                }
                Rank = $step.rank
                Mode = switch ($step.mode) {
                    0 { 'Synchronous' }
                    1 { 'Asynchronous' }
                    default { $step.mode }
                }
                Status = switch ($step.statuscode) {
                    1 { 'Enabled' }
                    2 { 'Disabled' }
                    default { $step.statuscode }
                }
                SupportedDeployment = switch ($step.supporteddeployment) {
                    0 { 'ServerOnly' }
                    1 { 'ClientOnly' }
                    2 { 'Both' }
                    default { $step.supporteddeployment }
                }
                AuthType = $step.eventhandler_serviceendpoint.authtype
                IsSystemWebHook = $step.eventhandler_serviceendpoint.iscustomizable.Value -eq $false
                IsCustomizable = $step.eventhandler_serviceendpoint.iscustomizable.Value -eq $true
                #HasAuthSecret = if ($step.eventhandler_serviceendpoint.authvalue -and $step.eventhandler_serviceendpoint.authvalue.Contains('x-dv-webhook-secret')) { $true } else { $false }
            }
        }

        # Update verbose message to reflect filtering
        if (-not $IncludeSystemWebHooks.IsPresent) {
            Write-Verbose "Returning $(@($results).Count) user webhook(s) (system webhooks filtered at API level)"
        } else {
            Write-Verbose "Returning $(@($results).Count) webhook(s) (including system webhooks)"
        }

        return $results
    }
    catch {
        throw "Error retrieving webhooks for table '$Table': $($_.Exception.Message)"
    }
}
