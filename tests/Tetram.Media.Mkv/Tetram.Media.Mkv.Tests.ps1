# Étendre la suite autour du manifeste Tetram.Media.Mkv.psd1 (NestedModules, FunctionsToExport).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Sanity : Test-ModuleManifest puis Import-Module -Force ; comparer FunctionsToExport aux commandes exportées.
# Comportement des commandes : Tetram.Media.Mkv.Tests.ps1 et Tetram.Media.Repair.Tests.ps1

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootReencodeManifest = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRootReencodeManifest = Join-Path $script:RepoRootReencodeManifest 'Tetram.Media.Mkv'
    $script:ManifestReencode = Join-Path $script:ModuleRootReencodeManifest 'Tetram.Media.Mkv.psd1'
    $script:ManifestDataReencode = Import-PowerShellDataFile -LiteralPath $script:ManifestReencode
}

Describe 'Tetram.Media.Mkv manifest' {
    It 'passe Test-ModuleManifest' {
        { Test-ModuleManifest -Path $script:ManifestReencode -ErrorAction Stop } | Should -Not -Throw
    }

    It 'charge Tetram.Media.Remux.psm1 et embarque Tetram.Media.Repair.psm1 en NestedModules' {
        $script:ManifestDataReencode.RootModule | Should -BeExactly 'Tetram.Media.Mkv.psm1'
        @($script:ManifestDataReencode.NestedModules) | Should -Contain 'Tetram.Media.Remux.psm1'
        @($script:ManifestDataReencode.NestedModules) | Should -Contain 'Tetram.Media.Repair.psm1'
    }

    It 'exporte exactement FunctionsToExport après chargement' {
        Import-Module -Name $script:ModuleRootReencodeManifest -Force -ErrorAction Stop
        try {
            $expected = @($script:ManifestDataReencode.FunctionsToExport | Sort-Object)
            $actual = @(Get-Command -Module 'Tetram.Media.Mkv' | Select-Object -ExpandProperty Name | Sort-Object)
            $actual | Should -Be $expected
        }
        finally {
            Remove-Module -Name 'Tetram.Media.Mkv' -Force -ErrorAction SilentlyContinue
        }
    }
}
