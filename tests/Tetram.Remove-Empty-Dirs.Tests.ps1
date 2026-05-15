# Étendre la suite autour du module SUD Tetram.Remove-Empty-Dirs (suppression dossiers vides depuis une racine).
#
# RepoRoot depuis tests/ racine : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Remove-Empty-Dirs.psd1') -Force après éventuelle étape Test-ModuleManifest sur le même .psd1
# Arborescences : sous $TestDrive, créez parents/enfants vides imbriqués (New-Item) puis invoquez l’outil sur Join-Path $TestDrive … ; vérifiez ce qui doit disparaître vs rester selon comportement attendu (écrit assertions sur Test-Path après coup).

Describe 'Tetram.Remove-Empty-Dirs (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}
