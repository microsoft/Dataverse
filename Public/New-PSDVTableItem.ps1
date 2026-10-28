function New-PSDVTableItem {
    <#
    .SYNOPSIS
    Creates a new record in a Dataverse table.

    .DESCRIPTION
    New-PSDVTableItem creates a new record in the specified Dataverse table using the provided data.
    It supports automatic field validation to ensure all provided fields exist in the target table.
    The function can optionally parse lookup relationships and convert them to the proper OData format.
    When ReturnItem is specified, it returns the created record with all server-generated values.

    .PARAMETER Table
    The logical name of the Dataverse table to create the record in.

    .PARAMETER EntitySet
    The entity set name of the Dataverse table (alternative to Table parameter).

    .PARAMETER ItemData
    Hashtable containing the field names and values for the new record.

    .PARAMETER ParseItemData
    When specified, automatically parses lookup field values and converts them to OData format.

    .PARAMETER ReturnItem
    When specified, returns the created record with server-generated values like ID and timestamps.

    .EXAMPLE
    $data = @{
        name = "Contoso Corporation"
        accountnumber = "ACC001"
        telephone1 = "555-123-4567"
    }
    New-PSDVTableItem -Table "account" -ItemData $data

    Creates a new account record with the specified data.

    .EXAMPLE
    $contactData = @{
        firstname = "John"
        lastname = "Doe"
        emailaddress1 = "john.doe@contoso.com"
        parentcustomerid = "12345678-1234-1234-1234-123456789012"
    }
    New-PSDVTableItem -Table "contact" -ItemData $contactData -ParseItemData -ReturnItem

    Creates a new contact with a lookup relationship, parses the lookup, and returns the created record.
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
        [System.Collections.Hashtable]
        $ItemData,

        [parameter()]
        [switch]
        $ParseItemData,

        [parameter()]
        [switch]
        $ReturnItem
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


    $dvRequestUri = $EntitySet

    if ($PSCmdlet.ShouldProcess($EntitySet, "Create new item")) {
        return (Invoke-PSDVWebRequest -WebUri  $dvRequestUri -Headers $requestHeaders -Body $ItemData2Process)
    }

}
