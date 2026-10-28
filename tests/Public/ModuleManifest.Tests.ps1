Describe 'Dataverse module manifest' {
    BeforeAll {
        $manifestPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Dataverse.psd1'
        $script:Manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    }

    It 'requires PowerShell 7.6 or later' {
        $script:Manifest.PowerShellVersion | Should -Be ([version]'7.6')
    }

    It 'is version 1.2.0' {
        $script:Manifest.Version | Should -Be ([version]'1.2.0')
    }

    It 'supports only the Core edition' {
        $script:Manifest.CompatiblePSEditions | Should -Be @('Core')
    }
}
