$script:PSDVRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:PSDVModulePath = Join-Path $script:PSDVRepoRoot 'Dataverse.psd1'
$script:PSDVMockModulePath = Join-Path $script:PSDVRepoRoot 'tests' 'Mocks' 'Dataverse.TestMocks.psm1'

Import-Module $script:PSDVMockModulePath -Force
Import-Module $script:PSDVModulePath -Force

$script:PSDVModule = Get-Module Dataverse | Where-Object { $_.Path -eq (Join-Path $script:PSDVRepoRoot 'Dataverse.psm1') } | Select-Object -First 1
& $script:PSDVModule {
	param($MockModulePath)
	Import-Module $MockModulePath -Force
} $script:PSDVMockModulePath
