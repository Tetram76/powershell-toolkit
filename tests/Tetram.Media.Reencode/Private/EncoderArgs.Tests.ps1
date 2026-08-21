# Étendre la suite autour du SUD EncoderArgs.ps1 (pivot dot-sourcé par Tetram.Media.Reencode, pas isolable comme module seul).
#
# RepoRoot : depuis ce dossier, trois niveaux → racine repo
#   $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Charger le manifeste utilisé par l’outil : Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode') -Force
# Exposer la portée où EncoderArgs existe : BeforeAll/InModuleScope 'Tetram.Media.Reencode' { … puis appelle sur les fonctions/paramètres EncoderArgs.ps1 ou Mock des deps internes }
# Si une assertion touche ffmpeg : mocker Invoke-Executable / lignes CLI attendues au lieu du binaire système absent sur tout agent CI.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootEncoderArgs = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootEncoderArgs 'Tetram.Media.Reencode') -Force -ErrorAction Stop
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

Describe 'Get-FFmpegArgs — pièces jointes police' {

    It 'conserve -c:t copy et pose le mimetype FFmpeg (application/x-truetype-font)' {
        $attachment = [pscustomobject]@{
            _index            = 0
            __process         = $true
            __copy            = $false
            __targetMimetype  = 'application/x-truetype-font'
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ Attachment = $attachment } {
            param($Attachment)

            $args = Get-FFmpegArgs `
                -VideoCodec 'AV1' `
                -Quality 'Low' `
                -Upscale '' `
                -UpscaleWidth 0 `
                -UpscaleHeight 0 `
                -UpscaleFit '' `
                -ConfigUpscaleWidth 0 `
                -ClearStreamsTitle $false `
                -VideoTracks @() `
                -IsSource10Bit $false `
                -SourceChroma '420' `
                -AudioTracks @() `
                -SubtitleTracks @() `
                -AttachmentTracks @($Attachment)

            $cIdx = [array]::IndexOf($args, '-c:t:0')
            $cIdx | Should -BeGreaterThan -1
            $args[$cIdx + 1] | Should -BeExactly 'copy'
            $metaIdx = [array]::IndexOf($args, '-metadata:s:t:0')
            $metaIdx | Should -BeGreaterThan -1
            $args[$metaIdx + 1] | Should -BeExactly 'mimetype=application/x-truetype-font'
            [array]::IndexOf($args, '-map_metadata') | Should -BeLessThan $metaIdx
            $args | Should -Contain '0:t:0'
        }
    }

    It 'conserve copy sans mimetype forcé quand la police a déjà un codec' {
        $attachment = [pscustomobject]@{
            _index     = 0
            __process  = $false
            __copy     = $true
            codec_name = 'otf'
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ Attachment = $attachment } {
            param($Attachment)

            $args = Get-FFmpegArgs `
                -VideoCodec 'AV1' `
                -Quality 'Low' `
                -Upscale '' `
                -UpscaleWidth 0 `
                -UpscaleHeight 0 `
                -UpscaleFit '' `
                -ConfigUpscaleWidth 0 `
                -ClearStreamsTitle $false `
                -VideoTracks @() `
                -IsSource10Bit $false `
                -SourceChroma '420' `
                -AudioTracks @() `
                -SubtitleTracks @() `
                -AttachmentTracks @($Attachment)

            $cIdx = [array]::IndexOf($args, '-c:t:0')
            $cIdx | Should -BeGreaterThan -1
            $args[$cIdx + 1] | Should -BeExactly 'copy'
            $args | Should -Not -Contain '-metadata:s:t:0'
        }
    }
}
