# Étendre la suite autour du module SUD Tetram.Remove-Empty-Dirs (suppression dossiers vides depuis une racine).
#
# RepoRoot depuis tests/ racine : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Remove-Empty-Dirs.psd1') -Force après éventuelle étape Test-ModuleManifest sur le même .psd1
# Arborescences : sous $TestDrive, créez parents/enfants vides imbriqués (New-Item) puis invoquez l’outil sur Join-Path $TestDrive … ; vérifiez ce qui doit disparaître vs rester selon comportement attendu (écrit assertions sur Test-Path après coup).

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootEmptyDirs = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestEmptyDirs = Join-Path $script:RepoRootEmptyDirs 'Tetram.Remove-Empty-Dirs.psd1'
    Import-Module -Name $script:ManifestEmptyDirs -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Remove-Empty-Dirs' -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-EmptyDirs -DeepScan -WhatIf' {

    It 'termine quand un dossier vide existe (WhatIf ne compte pas comme suppression)' {
        $leaf = Join-Path $TestDrive 'parent' 'child'
        New-Item -ItemType Directory -Path $leaf -Force | Out-Null

        # Job + timeout : sans le correctif, while ($changed) ne sort jamais sous -WhatIf.
        $job = Start-Job -ScriptBlock {
            param($ModulePath, $Root)
            Import-Module -Name $ModulePath -Force
            Remove-EmptyDirs -Path $Root -DeepScan -WhatIf
        } -ArgumentList $script:ManifestEmptyDirs, $TestDrive.ToString()

        try {
            $finished = Wait-Job -Job $job -Timeout 8
            $finished | Should -Not -BeNullOrEmpty
            $job.State | Should -Be 'Completed'
            Receive-Job -Job $job -ErrorAction Stop | Out-Null
        }
        finally {
            $job | Stop-Job -ErrorAction SilentlyContinue
            $job | Remove-Job -Force -ErrorAction SilentlyContinue
        }

        Test-Path -LiteralPath $leaf | Should -BeTrue
    }
}
