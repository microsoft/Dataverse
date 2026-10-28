$script:PSDVRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:PSDVModulePath = Join-Path $script:PSDVRepoRoot 'Dataverse.psd1'
$script:PSDVMockModulePath = Join-Path $script:PSDVRepoRoot 'tests' 'Mocks' 'Dataverse.TestMocks.psm1'

Import-Module $script:PSDVMockModulePath -Force
Import-Module $script:PSDVModulePath -Force

function Initialize-PSDVPublicTestConnection {
    [CmdletBinding()]
    param(
        [Parameter()]
        [String]
        $OrgUrl = 'https://example.crm.dynamics.com/'
    )

    $Global:DATAVERSEAUTHCONTEXT = New-PSDVTestAuthContext -ResourceUrl $OrgUrl
    $Global:DATAVERSEACCESSTOKEN = New-PSDVTestAccessToken
    $Global:DATAVERSEORGURL = $OrgUrl
}

function Clear-PSDVPublicTestConnection {
    [CmdletBinding()]
    param()

    $Global:DATAVERSEAUTHCONTEXT = $null
    $Global:DATAVERSEACCESSTOKEN = $null
    $Global:DATAVERSEORGURL = $null
}

function New-PSDVPublicTestWebResponse {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [Object]
        $Payload
    )

    $content = if ($null -eq $Payload) {
        $null
    }
    elseif ($Payload -is [String]) {
        $Payload
    }
    else {
        $Payload | ConvertTo-Json -Depth 20 -Compress
    }

    return [PSCustomObject]@{ Content = $content }
}
