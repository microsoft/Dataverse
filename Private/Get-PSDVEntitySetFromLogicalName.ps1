function Get-PSDVEntitySetFromLogicalName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [String]
        $Table
    )

    try {
        $tableLiteral = ConvertTo-PSDVODataStringLiteral -Value $Table
        return (Invoke-PSDVWebRequest -WebUri "EntityDefinitions(LogicalName=$tableLiteral)" -Select 'EntitySetName').EntitySetName
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'PSDV*') {
            throw
        }
        throw "Cannot find table $Table in Dataverse Environment. $($_.InvocationInfo.MyCommand.Name),  $($_.InvocationInfo.InvocationName) , $($_ | Out-String)"
    }
}
