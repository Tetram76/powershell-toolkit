# Étendre la suite autour du SUD EncoderArgs.ps1 (pivot dot-sourcé par Tetram.Media.Reencode, pas isolable comme module seul).
#
# RepoRoot : depuis ce dossier, trois niveaux → racine repo
#   $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Charger le manifeste utilisé par l’outil : Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode.psd1') -Force
# Exposer la portée où EncoderArgs existe : BeforeAll/InModuleScope 'Tetram.Media.Reencode' { … puis appelle sur les fonctions/paramètres EncoderArgs.ps1 ou Mock des deps internes }
# Si une assertion touche ffmpeg : mocker Invoke-Executable / lignes CLI attendues au lieu du binaire système absent sur tout agent CI.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootEncoderArgs = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootEncoderArgs 'Tetram.Media.Reencode.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Reencode' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FFmpegArgs — color space remap' {

    It 'injecte setparams quand SourceColorSpace=gbr et encode AV1 en 420' {
        $video = [pscustomobject]@{
            _index        = 0
            __process     = $true
            __copy        = $false
            __deinterlace = $false
            __upscale     = $false
        }
        $audio = [pscustomobject]@{
            _index               = 0
            __process            = $false
            __copy               = $true
            __targetAudioCodec   = $null
            __targetAudioBitrate = $null
            __targetAudioFilter  = $null
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ Video = $video; Audio = $audio } {
            param($Video, $Audio)

            $args = Get-FFmpegArgs `
                -VideoCodec 'AV1' `
                -Quality 'Low' `
                -Upscale '' `
                -UpscaleWidth 0 `
                -UpscaleHeight 0 `
                -UpscaleFit '' `
                -ConfigUpscaleWidth 0 `
                -ClearStreamsTitle $false `
                -VideoTracks @($Video) `
                -IsSource10Bit $false `
                -SourceChroma '420' `
                -SourceColorSpace 'gbr' `
                -AudioTracks @($Audio) `
                -SubtitleTracks @() `
                -AttachmentTracks @()

            $vfIdx = [array]::IndexOf($args, '-vf:v:0')
            $vfIdx | Should -BeGreaterThan -1
            $args[$vfIdx + 1] | Should -BeExactly 'setparams=colorspace=bt709:color_primaries=bt709:color_trc=bt709'
        }
    }

    It 'n''injecte pas setparams quand SourceColorSpace=bt709' {
        $video = [pscustomobject]@{
            _index        = 0
            __process     = $true
            __copy        = $false
            __deinterlace = $false
            __upscale     = $false
        }
        $audio = [pscustomobject]@{
            _index               = 0
            __process            = $false
            __copy               = $true
            __targetAudioCodec   = $null
            __targetAudioBitrate = $null
            __targetAudioFilter  = $null
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ Video = $video; Audio = $audio } {
            param($Video, $Audio)

            $args = Get-FFmpegArgs `
                -VideoCodec 'AV1' `
                -Quality 'Low' `
                -Upscale '' `
                -UpscaleWidth 0 `
                -UpscaleHeight 0 `
                -UpscaleFit '' `
                -ConfigUpscaleWidth 0 `
                -ClearStreamsTitle $false `
                -VideoTracks @($Video) `
                -IsSource10Bit $false `
                -SourceChroma '420' `
                -SourceColorSpace 'bt709' `
                -AudioTracks @($Audio) `
                -SubtitleTracks @() `
                -AttachmentTracks @()

            $args | Should -Not -Contain '-vf:v:0'
        }
    }
}
