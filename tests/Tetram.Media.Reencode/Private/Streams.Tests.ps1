# Étendre la suite autour du SUD Streams.ps1 (pistes/dérivation à partir médias ffmpeg).
#
# RepoRoot (trois `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode') ; InModuleScope 'Tetram.Media.Reencode' { … }
# Simuler ffmpeg/ffprobe : mocker wrappers ou lignes `-print_format json`/`ffprobe …` comme pour Probe selon signatures réelles utilisées dans Streams.ps1.
# Fixtures : médias légers dans $TestDrive ou moquer les fichiers si la logique peut s’injecter avec des chemins factices contrôlés.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootStreams = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootStreams 'Tetram.Media.Reencode') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Reencode' -Force -ErrorAction SilentlyContinue
}

Describe 'Select-AudioStreams' {

    It 'ne force pas le réencodage Opus quand le flux est déjà Opus (qualité Low, bitrate <= cible)' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'opus'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '96000'
                }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AudioStreams -FfprobeOutput $FfprobeOutput -FinalExtension '.mkv' -Quality 'Low' -RewriteMode $false
            $tracks[0].__recode | Should -BeFalse
            $tracks[0].__copy | Should -BeTrue
            $tracks[0].__process | Should -BeFalse
        }
    }

    It 'réencode Opus en Low uniquement s''il y a un gain de bitrate' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'opus'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '256000'
                }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AudioStreams -FfprobeOutput $FfprobeOutput -FinalExtension '.mkv' -Quality 'Low' -RewriteMode $false
            $tracks[0].__recode | Should -BeTrue
            $tracks[0].__targetAudioCodec | Should -BeExactly 'opus'
        }
    }
}

Describe 'Select-AttachmentStreams' {

    It 'pose le mimetype FFmpeg ttf (application/x-truetype-font) quand le codec est absent' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = $null; tags = @{ mimetype = 'application/x-truetype-font'; filename = 'Arial' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams -FfprobeOutput $FfprobeOutput -HasAssSubtitles $true
            $tracks[0].__targetMimetype | Should -BeExactly 'application/x-truetype-font'
            $tracks[0].__recode | Should -BeTrue
            $tracks[0].__process | Should -BeTrue
            $tracks[0].__copy | Should -BeFalse
        }
    }

    It 'pose le mimetype FFmpeg otf (application/vnd.ms-opentype) quand le codec est absent' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = $null; tags = @{ mimetype = $null; filename = 'CustomFont.otf' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams -FfprobeOutput $FfprobeOutput -HasAssSubtitles $true
            $tracks[0].__targetMimetype | Should -BeExactly 'application/vnd.ms-opentype'
            $tracks[0].__recode | Should -BeTrue
            $tracks[0].__process | Should -BeTrue
            $tracks[0].__copy | Should -BeFalse
        }
    }

    It 'ne modifie pas le codec déjà renseigné (ttf/otf) d''une police conservée' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = 'otf'; tags = @{ mimetype = $null; filename = 'Deja.otf' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams -FfprobeOutput $FfprobeOutput -HasAssSubtitles $true
            $tracks[0].codec_name | Should -BeExactly 'otf'
            $tracks[0].__copy | Should -BeTrue
            $tracks[0].__process | Should -BeFalse
        }
    }

    It 'ne modifie pas le codec d''une police non conservée (pas de sous-titres ass)' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = $null; tags = @{ mimetype = 'application/x-truetype-font'; filename = 'Arial' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams -FfprobeOutput $FfprobeOutput -HasAssSubtitles $false
            $tracks[0].__copy | Should -BeFalse
            $tracks[0].codec_name | Should -BeNullOrEmpty
        }
    }
}

Describe 'Select-VideoStreams — color_space' {

    It 'conserve color_space=gbr sur chaque VideoTrack' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type  = 'video'
                    codec_name  = 'hevc'
                    profile     = 'Main'
                    height      = 1080
                    width       = 1920
                    pix_fmt     = 'yuv420p'
                    color_space = 'gbr'
                    disposition = @{ attached_pic = 0 }
                }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $result = Select-VideoStreams `
                -FfprobeOutput $FfprobeOutput `
                -ForceRecodeVideo $true `
                -VideoCodec 'AV1' `
                -AllowVideoCodecUpgrade $true `
                -Deinterlace $false `
                -Upscale '' `
                -UpscaleWidth 0 `
                -UpscaleHeight 0 `
                -UpscaleFit '' `
                -ConfigUpscaleWidth 0 `
                -RewriteMode $false

            $result.VideoTracks[0].color_space | Should -BeExactly 'gbr'
            $result.SourceChroma | Should -BeExactly '420'
        }
    }
}
