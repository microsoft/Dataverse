function Update-PSDVTableItem {
    <#
    .SYNOPSIS
    Updates an existing record in a Dataverse table.

    .DESCRIPTION
    Update-PSDVTableItem modifies an existing record in the specified Dataverse table using the provided data.
    It supports automatic field validation to ensure all provided fields exist in the target table.
    The function can optionally parse lookup relationships and convert them to the proper OData format.
    When ReturnItem is specified, it returns the updated record with current field values.
    Only the specified fields are updated; other fields remain unchanged.

    .PARAMETER Table
    The logical name of the Dataverse table containing the record to update.

    .PARAMETER EntitySet
    The entity set name of the Dataverse table (alternative to Table parameter).

    .PARAMETER ItemID
    The non-empty GUID of the record to update. The zero GUID is rejected at parameter binding.

    .PARAMETER ItemData
    Hashtable containing the field names and values to update in the record.

    .PARAMETER ParseItemData
    When specified, automatically parses lookup field values and converts them to OData format.

    .PARAMETER ReturnItem
    When specified, requests and returns the persisted row from the PATCH response, without a follow-up GET.
    With -IfMatch, a missing row representation or nonblank @odata.etag raises a terminating error.
    The update may already have succeeded even if this response validation fails.

    .PARAMETER IfMatch
    An opaque ETag sent unchanged as the If-Match header. A specific ETag, such as W/"123456",
    updates only that row version. The wildcard * updates only if the row exists, without protecting
    against intervening edits. Omission preserves existing behavior. Explicit null, empty, or
    whitespace-only values are rejected before any request.

    .NOTES
    No conditional write is automatically retried, and the supplied condition is never refreshed or removed.
    A transport failure can leave the write outcome unknown; the caller must decide whether to re-read
    and reconcile. HTTP 412 errors have a FullyQualifiedErrorId starting with PSDVPreconditionFailed and
    expose HttpStatusCode, DataverseErrorCode, DataverseErrorMessage, ResponseHeaders, ResponseBody,
    Method, and RequestUri at $_.Exception.Data['PSDVHttpError']. Other HTTP errors use PSDVHttpError;
    request/transport failures without an HTTP response use PSDVWebRequestFailed.
    Conditional return-item validation uses PSDVUpdateRepresentationMissing or PSDVUpdateETagMissing,
    not a concurrency error. The original request exception is retained as Exception.InnerException.

    .EXAMPLE
    $updateData = @{
        name = "Updated Company Name"
        telephone1 = "555-987-6543"
    }
    Update-PSDVTableItem -Table "account" -ItemID "12345678-1234-1234-1234-123456789012" -ItemData $updateData

    Updates an account record with new name and phone number.

    .EXAMPLE
    $contactUpdate = @{
        emailaddress1 = "newemail@contoso.com"
        parentcustomerid = "11111111-1111-1111-1111-111111111111"
    }
    Update-PSDVTableItem -Table "contact" -ItemID "87654321-4321-4321-4321-210987654321" -ItemData $contactUpdate -ParseItemData -ReturnItem

    Updates a contact's email and parent account, parses the lookup, and returns the updated record.

    .EXAMPLE
    $row = Get-PSDVTableItem -EntitySet accounts -ItemID $accountId
    try {
        $updated = Update-PSDVTableItem -EntitySet accounts -ItemID $accountId `
            -ItemData @{ name = 'Updated name' } -IfMatch $row.'@odata.etag' -ReturnItem -ErrorAction Stop
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'PSDVPreconditionFailed*') {
            Write-Warning 'The row changed; skip or reconcile before trying again.'
        }
        else {
            throw
        }
    }

    Updates only the retrieved row version and returns its persisted representation and server ETag.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [parameter(Mandatory, ParameterSetName = 'TableLogicalName')]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $Table,

        [parameter(Mandatory, ParameterSetName = 'TableEntitySetName')]
        [ValidateNotNullOrWhiteSpace()]
        [string]
        $EntitySet,

        [parameter(Mandatory)]
        [ValidateScript({ $_ -ne [guid]::Empty }, ErrorMessage = 'ItemID cannot be an empty GUID.')]
        [System.Guid]
        $ItemID,

        [parameter(Mandatory)]
        [System.Collections.Hashtable]
        $ItemData,

        [parameter()]
        [switch]
        $ParseItemData,

        [parameter()]
        [switch]
        $ReturnItem,

        [parameter()]
        [ValidateNotNullOrWhiteSpace()]
        [string]
        $IfMatch
    )

    if ($null -eq $Global:DATAVERSEACCESSTOKEN) {
        throw 'No existing connection to Dataverse Environment, run Connect-PSDVOrg before executing other PSDV cmdlets'
    }

    #lookup table relationships require setting the Microsoft.Dynamics.CRM.associatednavigationproperty odata.bind = /entitysetname(item ID)
    # ex, "cr33a_MACOM@odata.bind" = "/cr33a_macoms(b7322079-55d2-ee11-9078-000d3a33b5cf)"

    if (($PSCmdlet.ParameterSetName).StartsWith('TableLogicalName')) {
        $EntitySet = Get-PSDVEntitySetFromLogicalName -Table $Table
    }


    $requestHeaders = @{
        'Prefer'       = 'odata.include-annotations="*"'
    }

    if ($PSBoundParameters.ContainsKey('IfMatch')) {
        $requestHeaders['If-Match'] = $IfMatch
    }

    if ($ReturnItem.IsPresent) {
        $requestHeaders['Prefer'] = 'odata.include-annotations="*",return=representation'
    }

    $itemDataValidation = Confirm-PSDVItemDataAttributes -Table $Table -EntitySet $EntitySet -ItemData $ItemData
    $Table = $itemDataValidation.Table
    $attributeDetails = $itemDataValidation.AttributeDetails

    if ($ParseItemData.IsPresent) {
        $ItemData2Process = ConvertTo-PSDVLookupItemData -ItemData $ItemData -AttributeDetails $attributeDetails
    }
    else {
        $ItemData2Process = $ItemData
    }


    $dvRequestUri = "$EntitySet($ItemID)"

    if ($PSCmdlet.ShouldProcess("$EntitySet($ItemID)", "Update item")) {
        $requireRepresentation = $PSBoundParameters.ContainsKey('IfMatch') -and $ReturnItem.IsPresent
        $response = Invoke-PSDVWebRequest -WebUri $dvRequestUri -Headers $requestHeaders `
            -Body $ItemData2Process -Method 'Patch' -ReturnRawResponse:$requireRepresentation
        if (-not $requireRepresentation) {
            return $response
        }

        # Inspect the PATCH body before collection parsing can unwrap an unexpected envelope.
        $updatedItem = $null
        $parseException = $null
        if ($null -ne $response -and -not [string]::IsNullOrWhiteSpace($response.Content)) {
            try {
                $updatedItem = ConvertFrom-Json -InputObject $response.Content -NoEnumerate -ErrorAction Stop
            }
            catch [System.ArgumentException] {
                $parseException = $_.Exception
            }
        }

        $responseErrorId = $null
        if ($null -eq $updatedItem -or $updatedItem.GetType() -ne [System.Management.Automation.PSCustomObject] -or
            $updatedItem.PSObject.Properties.Name -contains '@odata.nextLink' -or
            $updatedItem.value -is [array]) {
            $responseErrorId = 'PSDVUpdateRepresentationMissing'
            $responseErrorMessage = 'The conditional PATCH did not return the requested row representation.'
        }
        elseif ($updatedItem.'@odata.etag' -isnot [string] -or
            [string]::IsNullOrWhiteSpace($updatedItem.'@odata.etag')) {
            $responseErrorId = 'PSDVUpdateETagMissing'
            $responseErrorMessage = 'The conditional PATCH representation did not include a nonblank @odata.etag.'
        }

        if ($responseErrorId) {
            $exception = [System.Exception]::new(
                "$responseErrorMessage The update may already have succeeded. No retry or follow-up GET was performed.",
                $parseException
            )
            $responseError = [System.Management.Automation.ErrorRecord]::new(
                $exception, $responseErrorId, [System.Management.Automation.ErrorCategory]::InvalidResult, $dvRequestUri
            )
            $PSCmdlet.ThrowTerminatingError($responseError)
        }

        return $updatedItem
    }

}
