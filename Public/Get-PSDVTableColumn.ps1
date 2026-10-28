function Get-PSDVTableColumn {
    <#
    .SYNOPSIS
    Retrieves column metadata for a specific Dataverse table.

    .DESCRIPTION
    Get-PSDVTableColumn returns detailed information about columns (attributes) in a specified Dataverse table.
    For each column, it provides metadata including logical name, display name, data type, validation rules,
    maximum length, precision, and relationship targets. This function is useful for understanding the
    structure and constraints of table fields before performing data operations. Optionally, you can specify
    specific column names to retrieve only those columns' metadata.

    .PARAMETER Table
    The logical name of the Dataverse table to retrieve column information for.

    .PARAMETER ColumnName
    Optional array of column logical names to retrieve. If not specified, all columns are returned.

    .EXAMPLE
    Get-PSDVTableColumn -Table "account"

    Returns detailed column information for all columns in the Account table.

    .EXAMPLE
    Get-PSDVTableColumn -Table "account" -ColumnName @("name", "telephone1", "websiteurl")

    Returns detailed column information for only the specified columns in the Account table.

    .EXAMPLE
    Get-PSDVTableColumn -Table "contact" | Where-Object { $_.RequiredLevel -eq "ApplicationRequired" }

    Returns only the required columns for the Contact table.

    .EXAMPLE
    Get-PSDVTableColumn -Table "account" -ColumnName @("accountid", "name") | Format-Table LogicalName, DisplayName, AttributeType

    Displays a formatted table of key column properties for specific columns.

    .EXAMPLE
    Get-PSDVTableColumn -Table "account" | Where-Object { $_.ChoiceValues } | Select-Object LogicalName, ChoiceValues

    Returns only choice (picklist) columns with their text-to-numeric value mappings.
    #>

    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $Table,

        [parameter()]
        [String[]]
        $ColumnName
    )

    foreach ($column in $ColumnName) {
        if ($column -notmatch '\S') {
            throw 'ColumnName entries cannot be null, empty, or whitespace.'
        }
    }

    # Build the base URI for the attributes endpoint
    $tableLiteral = ConvertTo-PSDVODataStringLiteral -Value $Table
    $baseUri = "EntityDefinitions(LogicalName=$tableLiteral)/Attributes"
    
    # If specific column names are provided, build a filter expression
    if ($ColumnName -and $ColumnName.Count -gt 0) {
        $filterConditions = @()
        foreach ($column in $ColumnName) {
            $columnLiteral = ConvertTo-PSDVODataStringLiteral -Value $column
            $filterConditions += "LogicalName eq $columnLiteral"
        }
        $filterExpression = $filterConditions -join ' or '
        $webResponse = Invoke-PSDVWebRequest -Method Get -WebUri $baseUri -Filter $filterExpression
    }
    else {
        $webResponse = Invoke-PSDVWebRequest -Method Get -WebUri $baseUri
    }

    # Get picklist metadata for choice columns (both local and global choices)
    $picklistData = @{}
    try {
        $picklistUri = "EntityDefinitions(LogicalName=$tableLiteral)/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        $picklistResponse = Invoke-PSDVWebRequest -Method Get -WebUri $picklistUri -Expand "OptionSet,GlobalOptionSet"

        if ($picklistResponse) {
            foreach ($picklist in $picklistResponse) {
                $options = [ordered]@{}
                $optionSet = if ($picklist.GlobalOptionSet -and $picklist.GlobalOptionSet.Options) {
                    $picklist.GlobalOptionSet
                } elseif ($picklist.OptionSet -and $picklist.OptionSet.Options) {
                    $picklist.OptionSet
                } else {
                    $null
                }

                if ($optionSet -and $optionSet.Options) {
                    foreach ($option in $optionSet.Options) {
                        if ($option.Label -and $option.Label.LocalizedLabels -and $option.Label.LocalizedLabels.Count -gt 0) {
                            $label = $option.Label.LocalizedLabels[0].Label
                            $options[$label] = $option.Value
                        }
                    }
                }

                if ($options.Count -gt 0) {
                    $picklistData[$picklist.LogicalName] = $options
                }
            }
        }
    }
    catch {
        Write-Verbose "Unable to retrieve picklist metadata: $($_.Exception.Message)"
    }

    foreach ($tableColumn in $webResponse) {
        [PSCustomObject]@{
            LogicalName = $tableColumn.LogicalName
            DisplayName = $tableColumn.DisplayName.LocalizedLabels[0].Label
            AttributeType = $tableColumn.AttributeType
            IsValidForCreate = $tableColumn.IsValidForCreate
            IsValidForUpdate = $tableColumn.IsValidForUpdate
            IsValidForRead = $tableColumn.IsValidForRead
            RequiredLevel = $tableColumn.RequiredLevel.Value
            MaxLength = $tableColumn.MaxLength
            Precision = $tableColumn.Precision
            Targets = $tableColumn.Targets -join ', '
            ChoiceValues = if ($picklistData.ContainsKey($tableColumn.LogicalName)) { $picklistData[$tableColumn.LogicalName] } else { $null }
        }
    }
}
