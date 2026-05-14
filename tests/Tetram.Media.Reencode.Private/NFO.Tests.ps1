# Étendre la suite autour du SUD NFO.ps1 (même mécanisme de chargement intra-module que les autres fichiers sous Private/).
#
# RepoRoot depuis ce dossier (trois `..`) :
#   $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode.psd1') -Force
# InModuleScope 'Tetram.Media.Reencode' { … appels sur parsing/écriture NFO avec chemins relatifs depuis $PSScriptRoot ou $TestDrive }
# Arborescences : préparer dossiers/fixtures sous $TestDrive puis résoudre avec Join-Path pour ne pas réécrire le repo.

Describe 'NFO (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}
