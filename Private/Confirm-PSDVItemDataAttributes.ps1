function Confirm-PSDVItemDataAttributes {
    [CmdletBinding()]
    param(
        [Parameter()]
        [String]
        $Table,

        [Parameter()]
        [String]
        $EntitySet,

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]
        $ItemData
    )

    if ($Table -notmatch '\S' -and $EntitySet -notmatch '\S') {
        throw 'A nonblank Table or EntitySet is required.'
    }

    if ($Table -notmatch '\S') {
        $entitySetLiteral = ConvertTo-PSDVODataStringLiteral -Value $EntitySet
        $Table = (Invoke-PSDVWebRequest -WebUri 'EntityDefinitions' -Filter "EntitySetName eq $entitySetLiteral" -Select 'LogicalName').LogicalName
    }

    $tableLiteral = ConvertTo-PSDVODataStringLiteral -Value $Table
    $tableColumns = Invoke-PSDVWebRequest -WebUri "EntityDefinitions(LogicalName=$tableLiteral)/Attributes"
    $attributeDetails = @{}
    $invalidAttributes = @()
    $tableRelationships = $null
    $tableRelationshipsLoaded = $false

    foreach ($attribute in $ItemData.Keys) {
        $attributeName = [string] $attribute
        $attributeDetail = $tableColumns | Where-Object { $_.LogicalName -eq $attributeName } | Select-Object -Property AttributeType, SchemaName, Targets

        if ($null -eq $attributeDetail -and $attributeName -like '*@odata.bind') {
            $navigationProperty = $attributeName -replace '@odata\.bind$', ''
            $attributeDetail = $tableColumns | Where-Object {
                $_.AttributeType -eq 'Lookup' -and ($_.SchemaName -eq $navigationProperty -or $_.LogicalName -eq $navigationProperty)
            } | Select-Object -Property AttributeType, SchemaName, Targets

            if ($null -eq $attributeDetail) {
                if (-not $tableRelationshipsLoaded) {
                    $tableRelationships = Invoke-PSDVWebRequest -WebUri "EntityDefinitions(LogicalName=$tableLiteral)/ManyToOneRelationships" -Select 'ReferencingAttribute,ReferencingEntityNavigationPropertyName'
                    $tableRelationshipsLoaded = $true
                }

                $relationship = $tableRelationships | Where-Object {
                    $_.ReferencingEntityNavigationPropertyName -eq $navigationProperty
                } | Select-Object -First 1

                if ($null -ne $relationship) {
                    $attributeDetail = $tableColumns | Where-Object {
                        $_.LogicalName -eq $relationship.ReferencingAttribute
                    } | Select-Object -Property AttributeType, SchemaName, Targets
                }
            }
        }

        if ($null -eq $attributeDetail) {
            $invalidAttributes += $attributeName
        }
        else {
            $attributeDetails.Add($attributeName, $attributeDetail)
        }
    }

    if ($invalidAttributes.Count -gt 0) {
        throw "Invalid attributes not present in $Table : $($invalidAttributes -join ', ')"
    }

    return [PSCustomObject]@{
        Table            = $Table
        AttributeDetails = $attributeDetails
    }
}
