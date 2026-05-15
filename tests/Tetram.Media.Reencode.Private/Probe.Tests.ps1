# Étendre la suite autour du SUD Probe.ps1 (ffprobe/JSON métadonnées).
#
# RepoRoot (trois `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode.psd1') ; InModuleScope 'Tetram.Media.Reencode' { … }
# ffprobe/ffmpeg : éviter dépendance à l’installation hôte — mocker la fonction qui lance la commande et faire retourner du JSON représentatif (succès / erreurs / fichier absent).

Describe 'Probe (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}
