# Étendre la suite autour du module SUD Tetram.Media.AudioUtils/Tetram.Media.AudioUtils.psd1.
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path (deux niveaux jusqu’à la racine repo)
# Import du manifeste : Import-Module (Join-Path $RepoRoot 'Tetram.Media.AudioUtils') -Force ; optionnel Import-Module préalable FFmpeg si tests croisés
# It : cibler fonction exportée précise ; mocks des appels FFmpeg/IO suivant signatures réelles plutôt qu’un binaire installé uniquement localement.

Describe 'Tetram.Media.AudioUtils (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}
