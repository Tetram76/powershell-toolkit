# Étendre la suite autour du SUD EncoderArgs.ps1 (pivot dot-sourcé par Tetram.Media.Reencode, pas isolable comme module seul).
#
# RepoRoot : depuis ce dossier, trois niveaux → racine repo
#   $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Charger le manifeste utilisé par l’outil : Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode.psd1') -Force
# Exposer la portée où EncoderArgs existe : BeforeAll/InModuleScope 'Tetram.Media.Reencode' { … puis appelle sur les fonctions/paramètres EncoderArgs.ps1 ou Mock des deps internes }
# Si une assertion touche ffmpeg : mocker Invoke-Executable / lignes CLI attendues au lieu du binaire système absent sur tout agent CI.

Describe 'EncoderArgs (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}
