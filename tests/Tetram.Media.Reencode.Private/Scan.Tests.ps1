# Étendre la suite autour du SUD Scan.ps1 (découverte fichiers sous un racine donnée).
#
# RepoRoot (trois `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode.psd1') ; InModuleScope 'Tetram.Media.Reencode' { … }
# Arborescences de test : New-Item -ItemType Directory / File sous $TestDrive puis passer la racine de scan résolue (Join-Path $TestDrive ...) pour ne pas toucher aux sources du repo.

Describe 'Scan (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}
