# TODO:
# - $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path (tests/Tetram.Media.Reencode.Private => trois parents)
# - EncoderArgs.ps1 n’est généralement pas un module isolé ; Import-Module Join-Path $RepoRoot 'Tetram.Media.Reencode.psd1' puis
#   InModuleScope 'Tetram.Media.Reencode' pour tester la logique exposée après dot-source par le module parent.


Describe 'EncoderArgs (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}
