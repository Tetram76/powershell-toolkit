# Étendre la suite autour du module SUD Utils/Tetram.Media.AudioUtils.psd1.
#
# RepoRoot depuis tests/Utils : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path (deux niveaux jusqu’à la racine repo)
# Import du manifeste sous Utils : Import-Module (Join-Path $RepoRoot 'Utils/Tetram.Media.AudioUtils.psd1') -Force ; optionnel Import-Module préalable FFmpeg si tests croisés
# It : cibler fonction exportée précise ; mocks des appels FFmpeg/IO suivant signatures réelles plutôt qu’un binaire installé uniquement localement.

Describe 'Tetram.Media.AudioUtils (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}
