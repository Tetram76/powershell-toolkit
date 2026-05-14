# Étendre la suite autour du module SUD Utils/Tetram.Media.FFmpeg.psd1 (chemin ffmpeg, vérifs environnement).
#
# RepoRoot (deux niveaux depuis tests/Utils) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Utils/Tetram.Media.FFmpeg.psd1') -Force
# Couverture résiliente CI : tester ffmpeg absent/présents via Mock ou Get-Command plutôt qu’un `ffmpeg` garanti sur chaque runner ; couvrir sorties erreur attendues (code non-zéro, messages).

Describe 'Tetram.Media.FFmpeg (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}
