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

    It 'injecte setparams quand color_space=gbr sur la piste vidéo (AV1 420)' {
        $video = [pscustomobject]@{
            _index        = 0
            __process     = $true
            __copy        = $false
            __deinterlace = $false
            __upscale     = $false
            color_space   = 'gbr'
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
                -AudioTracks @($Audio) `
                -SubtitleTracks @() `
                -AttachmentTracks @()

            $vfIdx = [array]::IndexOf($args, '-vf:v:0')
            $vfIdx | Should -BeGreaterThan -1
            $args[$vfIdx + 1] | Should -BeExactly 'setparams=colorspace=bt709'
        }
    }

    It 'n''injecte pas setparams quand color_space=bt709' {
        $video = [pscustomobject]@{
            _index        = 0
            __process     = $true
            __copy        = $false
            __deinterlace = $false
            __upscale     = $false
            color_space   = 'bt709'
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
                -AudioTracks @($Audio) `
                -SubtitleTracks @() `
                -AttachmentTracks @()

            $args | Should -Not -Contain '-vf:v:0'
        }
    }

    It 'applique le remap uniquement à la piste gbr (multi-vidéo)' {
        $videos = @(
            [pscustomobject]@{
                _index        = 0
                __process     = $true
                __copy        = $false
                __deinterlace = $false
                __upscale     = $false
                color_space   = 'bt709'
            }
            [pscustomobject]@{
                _index        = 1
                __process     = $true
                __copy        = $false
                __deinterlace = $false
                __upscale     = $false
                color_space   = 'gbr'
            }
        )
        $audio = [pscustomobject]@{
            _index               = 0
            __process            = $false
            __copy               = $true
            __targetAudioCodec   = $null
            __targetAudioBitrate = $null
            __targetAudioFilter  = $null
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ Videos = $videos; Audio = $audio } {
            param($Videos, $Audio)

            $args = Get-FFmpegArgs `
                -VideoCodec 'AV1' `
                -Quality 'Low' `
                -Upscale '' `
                -UpscaleWidth 0 `
                -UpscaleHeight 0 `
                -UpscaleFit '' `
                -ConfigUpscaleWidth 0 `
                -ClearStreamsTitle $false `
                -VideoTracks $Videos `
                -IsSource10Bit $false `
                -SourceChroma '420' `
                -AudioTracks @($Audio) `
                -SubtitleTracks @() `
                -AttachmentTracks @()

            $args | Should -Not -Contain '-vf:v:0'
            $vf1 = [array]::IndexOf($args, '-vf:v:1')
            $vf1 | Should -BeGreaterThan -1
            $args[$vf1 + 1] | Should -BeExactly 'setparams=colorspace=bt709'
        }
    }
}
