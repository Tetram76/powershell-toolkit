# Étendre la suite autour du module SUD Utils/Tetram.Media.VideoUtils.psd1.
#
# RepoRoot depuis tests/Utils (deux `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Utils/Tetram.Media.VideoUtils.psd1') ; pour comportements combinés FFmpeg, importer Tetram.Media.FFmpeg en amont avec Mock sur exécution.
# It : mocks ffprobe/ffmpeg ou petits artefacts sous $TestDrive ; évite dépendances à médias volumineux du repo sur agents CI légers.

Describe 'Tetram.Media.VideoUtils (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}
