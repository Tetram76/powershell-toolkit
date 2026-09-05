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

    function script:Invoke-SelectSubtitleStreamsUnderTest {
        param(
            [Parameter(Mandatory)] [hashtable] $FfprobeOutput,
            [string[]] $SubTitlesToKeep = @('fr', 'en'),
            [Parameter(Mandatory)] [string] $DirectoryName
        )

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{
            FfprobeOutput   = $FfprobeOutput
            SubTitlesToKeep = $SubTitlesToKeep
            DirectoryName   = $DirectoryName
        } {
            param($FfprobeOutput, $SubTitlesToKeep, $DirectoryName)

            Select-SubtitleStreams `
                -FfprobeOutput $FfprobeOutput `
                -FinalExtension '.mkv' `
                -AllowSubTitlesConversion $false `
                -NoTranscodeMode $false `
                -SubTitlesToKeep $SubTitlesToKeep `
                -Filename 'episode.mkv' `
                -DirectoryName $DirectoryName
        }
    }

    function script:Invoke-SelectVideoStreamsUnderTest {
        param(
            [Parameter(Mandatory)] [hashtable] $FfprobeOutput,
            [bool] $ForceRecodeVideo = $false
        )

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{
            FfprobeOutput    = $FfprobeOutput
            ForceRecodeVideo = $ForceRecodeVideo
        } {
            param($FfprobeOutput, $ForceRecodeVideo)

            Select-VideoStreams `
                -FfprobeOutput $FfprobeOutput `
                -ForceRecodeVideo $ForceRecodeVideo `
                -VideoCodec 'HEVC' `
                -AllowVideoCodecUpgrade $false `
                -Deinterlace $false `
                -Upscale '' `
                -UpscaleWidth 0 `
                -UpscaleHeight 0 `
                -UpscaleFit '' `
                -ConfigUpscaleWidth 0 `
                -NoTranscodeMode $false
        }
    }

    function script:Invoke-SelectAudioStreamsUnderTest {
        param(
            [Parameter(Mandatory)] [hashtable] $FfprobeOutput,
            [string] $FinalExtension = '.mkv',
            [string] $Quality = 'High',
            [bool] $NoTranscodeMode = $false,
            [bool] $FinalVideoIsAV1 = $false
        )

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{
            FfprobeOutput   = $FfprobeOutput
            FinalExtension  = $FinalExtension
            Quality         = $Quality
            NoTranscodeMode     = $NoTranscodeMode
            FinalVideoIsAV1 = $FinalVideoIsAV1
        } {
            param($FfprobeOutput, $FinalExtension, $Quality, $NoTranscodeMode, $FinalVideoIsAV1)

            Select-AudioStreams `
                -FfprobeOutput $FfprobeOutput `
                -FinalExtension $FinalExtension `
                -Quality $Quality `
                -NoTranscodeMode $NoTranscodeMode `
                -FinalVideoIsAV1 $FinalVideoIsAV1
        }
    }
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

            $tracks = Select-AudioStreams -FfprobeOutput $FfprobeOutput -FinalExtension '.mkv' -Quality 'Low' -NoTranscodeMode $false
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

            $tracks = Select-AudioStreams -FfprobeOutput $FfprobeOutput -FinalExtension '.mkv' -Quality 'Low' -NoTranscodeMode $false
            $tracks[0].__recode | Should -BeTrue
            $tracks[0].__targetAudioCodec | Should -BeExactly 'opus'
        }
    }

    It 'force AAC vers EAC3 en High quand la vidéo finale est AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'aac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '192000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $true
        $tracks[0].codec_name | Should -BeExactly 'aac'
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__copy | Should -BeFalse
        $tracks[0].__process | Should -BeTrue
        $tracks[0].__targetAudioBitrate | Should -BeNullOrEmpty
    }

    It 'force AAC vers EAC3 en Medium quand la vidéo finale est AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'aac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '192000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'Medium' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__copy | Should -BeFalse
        $tracks[0].__process | Should -BeTrue
    }

    It 'cible Opus (pas EAC3) quand un AAC Low est réencodé malgré une vidéo finale AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'aac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '192000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'Low' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'opus'
        $tracks[0].__targetAudioCodec | Should -Not -BeExactly 'eac3'
        $tracks[0].__targetAudioBitrate | Should -BeExactly '96k'
        $tracks[0].__copy | Should -BeFalse
        $tracks[0].__process | Should -BeTrue
    }

    It 'ne convertit pas AAC Low uniquement parce que la vidéo finale est AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'aac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '96000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'Low' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeFalse
        $tracks[0].__copy | Should -BeTrue
        $tracks[0].PSObject.Properties['__targetAudioCodec'] | Should -BeNullOrEmpty
    }

    It 'cible Opus (pas EAC3) quand un lossless Low est réencodé malgré une vidéo finale AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'flac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '900000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'Low' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'opus'
        $tracks[0].__targetAudioCodec | Should -Not -BeExactly 'eac3'
        $tracks[0].__targetAudioBitrate | Should -BeExactly '96k'
    }

    It 'applique la contrainte AV1+AAC à toutes les pistes AAC conservées' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{ codec_type = 'audio'; codec_name = 'aac'; channels = 2; channel_layout = 'stereo'; bit_rate = '192000' }
                [pscustomobject]@{ codec_type = 'audio'; codec_name = 'aac'; channels = 2; channel_layout = 'stereo'; bit_rate = '128000' }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -FinalVideoIsAV1 $true
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[1].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__recode | Should -BeTrue
        $tracks[1].__recode | Should -BeTrue
    }

    It 'ne force vers EAC3 par la règle AV1 que les pistes AAC dans un mélange' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{ codec_type = 'audio'; codec_name = 'aac'; channels = 2; channel_layout = 'stereo'; bit_rate = '192000' }
                [pscustomobject]@{ codec_type = 'audio'; codec_name = 'opus'; channels = 2; channel_layout = 'stereo'; bit_rate = '96000' }
                [pscustomobject]@{ codec_type = 'audio'; codec_name = 'aac'; channels = 2; channel_layout = 'stereo'; bit_rate = '160000' }
                [pscustomobject]@{ codec_type = 'audio'; codec_name = 'eac3'; channels = 6; channel_layout = '5.1'; bit_rate = '448000' }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $true
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__recode | Should -BeTrue
        $tracks[1].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[1].__recode | Should -BeTrue
        $tracks[2].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[2].__recode | Should -BeTrue
        $tracks[3].__recode | Should -BeFalse
        $tracks[3].__copy | Should -BeTrue
    }

    It 'ne force pas AAC vers EAC3 en HEVC final High (politique normale)' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'aac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '192000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $false
        $tracks[0].__recode | Should -BeFalse
        $tracks[0].__copy | Should -BeTrue
    }

    It 'cible eac3 quand un lossless est réencodé en HEVC final High' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'flac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '900000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $false
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__targetAudioBitrate | Should -BeNullOrEmpty
    }

    It 'cible eac3 quand un lossless est réencodé en HEVC final Medium' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'flac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '900000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'Medium' -FinalVideoIsAV1 $false
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
    }

    It 'cible opus quand un lossless est réencodé en HEVC final Low' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'flac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '900000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'Low' -FinalVideoIsAV1 $false
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'opus'
    }

    It 'réencode Opus vers EAC3 en High non-MP4 même sans gain de bitrate' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'opus'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '64000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $false
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__copy | Should -BeFalse
        $tracks[0].__process | Should -BeTrue
        $tracks[0].__targetAudioBitrate | Should -BeNullOrEmpty
    }

    It 'réencode Opus vers EAC3 en Medium non-MP4' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'opus'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '64000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'Medium' -FinalVideoIsAV1 $false
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__copy | Should -BeFalse
        $tracks[0].__process | Should -BeTrue
    }

    It 'ne migre pas Opus vers EAC3 en NoTranscode même en High non-MP4' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'opus'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '64000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -NoTranscodeMode $true
        $tracks[0].__recode | Should -BeFalse
        $tracks[0].__copy | Should -BeTrue
    }

    It 'force AAC vers EAC3 sur une sortie MP4 si la vidéo finale est AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'aac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '192000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -FinalExtension '.mp4' -Quality 'High' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__copy | Should -BeFalse
        $tracks[0].__process | Should -BeTrue
    }

    It 'ne force pas AAC vers EAC3 en NoTranscode même si la vidéo finale est AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'aac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '192000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -NoTranscodeMode $true -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeFalse
        $tracks[0].__copy | Should -BeTrue
    }

    It 'ne force pas AC3 vers EAC3 uniquement parce que la vidéo finale est AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'ac3'
                    channels       = 6
                    channel_layout = '5.1'
                    bit_rate       = '448000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeFalse
        $tracks[0].__copy | Should -BeTrue
    }

    It 'ne réencode pas une piste EAC3 uniquement parce que la vidéo finale est AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'eac3'
                    channels       = 6
                    channel_layout = '5.1'
                    bit_rate       = '448000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeFalse
        $tracks[0].__copy | Should -BeTrue
    }

    It 'migre Opus vers EAC3 en High même si la vidéo finale est AV1 (politique normale, pas AAC)' {
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

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
    }

    It 'cible eac3 (pas aac) quand un lossless MP4 est recodé et que la vidéo finale est AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'flac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '900000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -FinalExtension '.mp4' -Quality 'High' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__copy | Should -BeFalse
        $tracks[0].__process | Should -BeTrue
    }

    It 'conserve aac pour un lossless MP4 recodé sans AV1 final' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'flac'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '900000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -FinalExtension '.mp4' -Quality 'High' -FinalVideoIsAV1 $false
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'aac'
    }

    It 'downmixe en 5.1 une piste EAC3 à plus de 6 canaux' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'truehd'
                    channels       = 8
                    channel_layout = '7.1'
                    bit_rate       = '4000000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $false
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__targetAudioFilter | Should -BeExactly 'aformat=channel_layouts=5.1'
    }

    It 'ne downmixe pas une piste EAC3 5.1 (6 canaux)' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'flac'
                    channels       = 6
                    channel_layout = '5.1'
                    bit_rate       = '900000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $false
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].PSObject.Properties['__targetAudioFilter'] | Should -BeNullOrEmpty
    }

    It 'downmixe en 5.1 un AAC 7.1 forcé EAC3 par AV1 final High' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'aac'
                    channels       = 8
                    channel_layout = '7.1'
                    bit_rate       = '512000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__targetAudioFilter | Should -BeExactly 'aformat=channel_layouts=5.1'
    }

    It 'downmixe en 5.1 un AAC 7.1 forcé EAC3 par AV1 final Medium' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'aac'
                    channels       = 8
                    channel_layout = '7.1'
                    bit_rate       = '512000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'Medium' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'eac3'
        $tracks[0].__targetAudioFilter | Should -BeExactly 'aformat=channel_layouts=5.1'
    }

    It 'ne downmixe pas un AAC 7.1 Low vers Opus malgré une vidéo finale AV1' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'aac'
                    channels       = 8
                    channel_layout = '7.1'
                    bit_rate       = '512000'
                }
            )
        }

        $tracks = Invoke-SelectAudioStreamsUnderTest -FfprobeOutput $ffprobe -Quality 'Low' -FinalVideoIsAV1 $true
        $tracks[0].__recode | Should -BeTrue
        $tracks[0].__targetAudioCodec | Should -BeExactly 'opus'
        $tracks[0].__targetAudioBitrate | Should -BeExactly '320k'
        $tracks[0].PSObject.Properties['__targetAudioFilter'] | Should -BeNullOrEmpty
    }
}

Describe 'Test-FinalVideoIsAV1' {

    function script:New-FinalVideoTrack {
        param(
            [string] $CodecName,
            [bool] $Copy = $false,
            [bool] $Process = $false,
            [bool] $Recode = $false,
            [bool] $Deinterlace = $false,
            [bool] $Upscale = $false
        )

        [pscustomobject]@{
            codec_name    = $CodecName
            __copy        = $Copy
            __process     = $Process
            __recode      = $Recode
            __deinterlace = $Deinterlace
            __upscale     = $Upscale
        }
    }

    It 'reconnaît une piste AV1 source copiée (VideoCodec HEVC, aucun recodage)' {
        $tracks = @(
            (New-FinalVideoTrack -CodecName 'av1' -Copy $true)
        )

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ VideoTracks = $tracks } {
            param($VideoTracks)
            Test-FinalVideoIsAV1 -VideoTracks $VideoTracks -VideoCodec 'HEVC' | Should -BeTrue
        }
    }

    It 'ignore une cible AV1 configurée si la piste HEVC est copiée' {
        $tracks = @(
            (New-FinalVideoTrack -CodecName 'hevc' -Copy $true)
        )

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ VideoTracks = $tracks } {
            param($VideoTracks)
            Test-FinalVideoIsAV1 -VideoTracks $VideoTracks -VideoCodec 'AV1' | Should -BeFalse
        }
    }

    It 'reconnaît un H264 réellement réencodé en AV1' {
        $tracks = @(
            (New-FinalVideoTrack -CodecName 'h264' -Process $true -Recode $true)
        )

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ VideoTracks = $tracks } {
            param($VideoTracks)
            Test-FinalVideoIsAV1 -VideoTracks $VideoTracks -VideoCodec 'AV1' | Should -BeTrue
        }
    }

    It 'reconnaît un HEVC réencodé AV1 uniquement par __deinterlace' {
        $tracks = @(
            (New-FinalVideoTrack -CodecName 'hevc' -Process $true -Deinterlace $true)
        )

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ VideoTracks = $tracks } {
            param($VideoTracks)
            Test-FinalVideoIsAV1 -VideoTracks $VideoTracks -VideoCodec 'AV1' | Should -BeTrue
        }
    }

    It 'reconnaît un HEVC réencodé AV1 uniquement par __upscale' {
        $tracks = @(
            (New-FinalVideoTrack -CodecName 'hevc' -Process $true -Upscale $true)
        )

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ VideoTracks = $tracks } {
            param($VideoTracks)
            Test-FinalVideoIsAV1 -VideoTracks $VideoTracks -VideoCodec 'AV1' | Should -BeTrue
        }
    }

    It 'ignore une piste AV1 supprimée si aucune autre piste finale n''est AV1' {
        $tracks = @(
            (New-FinalVideoTrack -CodecName 'av1')
            (New-FinalVideoTrack -CodecName 'hevc' -Copy $true)
        )

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ VideoTracks = $tracks } {
            param($VideoTracks)
            Test-FinalVideoIsAV1 -VideoTracks $VideoTracks -VideoCodec 'HEVC' | Should -BeFalse
        }
    }
}

Describe 'Get-FontAttachmentTargetMimetype' {

    It 'fait primer l''extension .otf sur un mimetype ttf déjà mappé (codec ttf)' {
        InModuleScope 'Tetram.Media.Reencode' {
            Get-FontAttachmentTargetMimetype `
                -Mimetype 'application/x-truetype-font' `
                -Filename 'CustomFont.otf' `
                -Codec 'ttf' |
                Should -BeExactly 'application/vnd.ms-opentype'
        }
    }

    It 'fait primer l''extension .ttf sur un mimetype opentype déjà mappé (codec otf)' {
        InModuleScope 'Tetram.Media.Reencode' {
            Get-FontAttachmentTargetMimetype `
                -Mimetype 'application/vnd.ms-opentype' `
                -Filename 'CustomFont.ttf' `
                -Codec 'otf' |
                Should -BeExactly 'application/x-truetype-font'
        }
    }

    It 'se sert du mimetype font/otf seulement quand ffprobe n''a pas posé de codec' {
        InModuleScope 'Tetram.Media.Reencode' {
            Get-FontAttachmentTargetMimetype `
                -Mimetype 'font/otf' `
                -Filename 'SomeFont' `
                -Codec '' |
                Should -BeExactly 'application/vnd.ms-opentype'

            Get-FontAttachmentTargetMimetype `
                -Mimetype 'font/otf' `
                -Filename 'SomeFont' `
                -Codec 'ttf' |
                Should -BeExactly 'application/x-truetype-font'
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

    It 'mappe font/otf (sans le mot opentype) vers application/vnd.ms-opentype, pas vers ttf' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = $null; tags = @{ mimetype = 'font/otf'; filename = 'SomeFont' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams -FfprobeOutput $FfprobeOutput -HasAssSubtitles $true
            $tracks[0].__targetMimetype | Should -BeExactly 'application/vnd.ms-opentype'
        }
    }

    It 'mappe une police .woff vers application/x-truetype-font (seul type ttf que ffprobe reconnaît)' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = $null; tags = @{ mimetype = $null; filename = 'Subtitle.woff' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams -FfprobeOutput $FfprobeOutput -HasAssSubtitles $true
            $tracks[0].__targetMimetype | Should -BeExactly 'application/x-truetype-font'
        }
    }

    It 'mappe une police .woff2 vers application/x-truetype-font (mkv_mime_tags)' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = $null; tags = @{ mimetype = $null; filename = 'Subtitle.woff2' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams -FfprobeOutput $FfprobeOutput -HasAssSubtitles $true
            $tracks[0].__targetMimetype | Should -BeExactly 'application/x-truetype-font'
        }
    }

    It 'mappe une police .ttc vers application/x-truetype-font (mkv_mime_tags)' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = $null; tags = @{ mimetype = $null; filename = 'Family.ttc' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams -FfprobeOutput $FfprobeOutput -HasAssSubtitles $true
            $tracks[0].__targetMimetype | Should -BeExactly 'application/x-truetype-font'
        }
    }

    It 'corrige le mimetype quand le codec est ttf mais le fichier est un otf' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = 'ttf'; tags = @{ mimetype = 'application/x-truetype-font'; filename = 'CustomFont.otf' } }
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

    It 'corrige le mimetype quand le codec est otf mais le fichier est un ttf' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = 'otf'; tags = @{ mimetype = 'application/vnd.ms-opentype'; filename = 'CustomFont.ttf' } }
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

Describe 'Select-AttachmentStreams — RemoveAttachments' {

    It 'conserve une police TTF/OTF lorsque ASS est présent et RemoveAttachments est faux' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = 'otf'; tags = @{ mimetype = $null; filename = 'Deja.otf' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams `
                -FfprobeOutput $FfprobeOutput `
                -HasAssSubtitles $true `
                -RemoveAttachments $false
            @($tracks).Count | Should -Be 1
            $tracks[0].__copy | Should -BeTrue
            $tracks[0].__process | Should -BeFalse
        }
    }

    It 'supprime une police même si un sous-titre ASS conservé est présent' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = 'otf'; tags = @{ mimetype = $null; filename = 'Deja.otf' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams `
                -FfprobeOutput $FfprobeOutput `
                -HasAssSubtitles $true `
                -RemoveAttachments $true
            @($tracks).Count | Should -Be 1
            $tracks[0].__copy | Should -BeFalse
            $tracks[0].__process | Should -BeFalse
        }
    }

    It 'supprime un attachment non-police' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = 'mjpeg'; tags = @{ filename = 'cover.jpg' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams `
                -FfprobeOutput $FfprobeOutput `
                -HasAssSubtitles $false `
                -RemoveAttachments $true
            @($tracks).Count | Should -Be 1
            $tracks[0].__copy | Should -BeFalse
            $tracks[0].__process | Should -BeFalse
        }
    }

    It 'supprime tous les attachments hétérogènes' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = 'ttf'; tags = @{ filename = 'Arial.ttf' } }
                @{ codec_type = 'attachment'; codec_name = $null; tags = @{ mimetype = 'application/x-truetype-font'; filename = 'Subtitle.woff' } }
                @{ codec_type = 'attachment'; codec_name = 'mjpeg'; tags = @{ filename = 'cover.jpg' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = @(Select-AttachmentStreams `
                    -FfprobeOutput $FfprobeOutput `
                    -HasAssSubtitles $true `
                    -RemoveAttachments $true)
            $tracks.Count | Should -Be 3
            foreach ($track in $tracks)
            {
                $track.__copy | Should -BeFalse
                $track.__process | Should -BeFalse
            }
        }
    }

    It 'ne corrige pas le mimetype d''un attachment destiné à être supprimé' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = $null; tags = @{ mimetype = 'application/x-truetype-font'; filename = 'Arial' } }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams `
                -FfprobeOutput $FfprobeOutput `
                -HasAssSubtitles $true `
                -RemoveAttachments $true
            $tracks[0].__copy | Should -BeFalse
            $tracks[0].__process | Should -BeFalse
            $tracks[0].PSObject.Properties.Name | Should -Not -Contain '__targetMimetype'
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
                -NoTranscodeMode $false

            $result.VideoTracks[0].color_space | Should -BeExactly 'gbr'
            $result.SourceChroma | Should -BeExactly '420'
        }
    }
}

Describe 'Select-SubtitleStreams' {

    It 'conserve une piste subrip sans tags (ffprobe omet la map) sans lever StrictMode' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'subrip' }
            )
        }

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeTrue
        $result.SubtitleTracks[0].__process | Should -BeFalse
        $result.SubtitleTracks[0].__recode | Should -BeFalse
    }

    It 'conserve une piste dont tags n''a pas de clé language' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ title = 'Signs' } }
            )
        }

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeTrue
        $result.SubtitleTracks[0].__process | Should -BeFalse
    }

    It 'écarte une langue hors SubTitlesToKeep' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'jpn' } }
            )
        }

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en') -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeFalse
        $result.SubtitleTracks[0].__process | Should -BeFalse
    }

    It 'conserve language=fre listé dans SubTitlesToKeep' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fre' } }
            )
        }

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en', 'fre') -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeTrue
    }

    It 'filtre LANGUAGE (casse JSON OrderedHashtable) comme language — écarte jpn' {
        # ConvertFrom-Json -AsHashtable : Contains('language') est faux pour LANGUAGE ; Keys -contains ne l'est pas.
        $ffprobe = ConvertFrom-Json -AsHashtable -InputObject '{"streams":[{"codec_type":"subtitle","codec_name":"subrip","tags":{"LANGUAGE":"jpn"}}]}'

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en') -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeFalse
        $result.SubtitleTracks[0].__process | Should -BeFalse
    }

    It 'filtre LANGUAGE (casse JSON OrderedHashtable) comme language — conserve fre' {
        $ffprobe = ConvertFrom-Json -AsHashtable -InputObject '{"streams":[{"codec_type":"subtitle","codec_name":"subrip","tags":{"LANGUAGE":"fre"}}]}'

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en', 'fre') -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeTrue
    }

    It 'conserve language=eng quand tags est un PSCustomObject (pas de Keys)' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type = 'subtitle'
                    codec_name = 'subrip'
                    tags       = [pscustomobject]@{ language = 'eng' }
                }
            )
        }

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en', 'eng') -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeTrue
    }

    It 'conserve language présent à $null comme indéterminée' {
        $ffprobe = ConvertFrom-Json -AsHashtable -InputObject '{"streams":[{"codec_type":"subtitle","codec_name":"subrip","tags":{"language":null}}]}'

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en') -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeTrue
        $result.SubtitleTracks[0].__process | Should -BeFalse
    }

    It 'conserve language un et und même hors SubTitlesToKeep' {
        foreach ($lang in @('un', 'und', 'UND'))
        {
            $ffprobe = @{
                streams = @(
                    @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = $lang } }
                )
            }

            $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en') -DirectoryName $TestDrive
            $result.SubtitleTracks[0].__copy | Should -BeTrue -Because "language=$lang"
        }
    }

    It 'conserve language unk comme indéterminée (und), même hors SubTitlesToKeep' {
        foreach ($lang in @('unk', 'UNK'))
        {
            $ffprobe = @{
                streams = @(
                    @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = $lang } }
                )
            }

            $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en') -DirectoryName $TestDrive
            $result.SubtitleTracks[0].__copy | Should -BeTrue -Because "language=$lang"
            $result.SubtitleTracks[0].__process | Should -BeFalse -Because "language=$lang"
        }
    }
}

Describe 'Select-AttachmentStreams — tags optionnels' {

    It 'ne lève pas si tags est omis (pas une police)' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = 'mjpeg' }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AttachmentStreams -FfprobeOutput $FfprobeOutput -HasAssSubtitles $false
            $tracks[0].__copy | Should -BeTrue
        }
    }
}

Describe 'Select-VideoStreams — disposition optionnelle' {

    It 'ne lève pas si disposition est omise' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type  = 'video'
                    codec_name  = 'hevc'
                    profile     = 'Main'
                    height      = 1080
                    width       = 1920
                    pix_fmt     = 'yuv420p'
                    color_space = 'bt709'
                }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $result = Select-VideoStreams `
                -FfprobeOutput $FfprobeOutput `
                -ForceRecodeVideo $false `
                -VideoCodec 'HEVC' `
                -AllowVideoCodecUpgrade $false `
                -Deinterlace $false `
                -Upscale '' `
                -UpscaleWidth 0 `
                -UpscaleHeight 0 `
                -UpscaleFit '' `
                -ConfigUpscaleWidth 0 `
                -NoTranscodeMode $false

            $result.VideoTracks[0].__copy | Should -BeTrue
            $result.VideoTracks[0].__process | Should -BeFalse
            $result.VideoTracks[0].__recode | Should -BeFalse
        }
    }

    It 'écarte une piste attached_pic=1 (cover) sans lever StrictMode' {
        $ffprobe = ConvertFrom-Json -AsHashtable -InputObject @'
{
  "streams": [
    {
      "codec_type": "video",
      "codec_name": "h264",
      "profile": "High",
      "height": 720,
      "width": 1280,
      "pix_fmt": "yuv420p",
      "color_space": "bt709",
      "disposition": { "attached_pic": 1 }
    }
  ]
}
'@

        $result = Invoke-SelectVideoStreamsUnderTest -FfprobeOutput $ffprobe
        $result.VideoTracks[0].__copy | Should -BeFalse
        $result.VideoTracks[0].__process | Should -BeFalse
    }
}

Describe 'Select-* — sonde ConvertFrom-Json -AsHashtable (type Get-FFprobeJson)' {

    It 'enchaîne vidéo sans disposition, sous-titre sans tags, sous-titre language=fre' {
        $ffprobe = ConvertFrom-Json -AsHashtable -InputObject @'
{
  "streams": [
    {
      "codec_type": "video",
      "codec_name": "hevc",
      "profile": "Main",
      "height": 1080,
      "width": 1920,
      "pix_fmt": "yuv420p",
      "color_space": "bt709"
    },
    { "codec_type": "subtitle", "codec_name": "subrip" },
    { "codec_type": "subtitle", "codec_name": "subrip", "tags": { "language": "fre" } }
  ]
}
'@

        $video = Invoke-SelectVideoStreamsUnderTest -FfprobeOutput $ffprobe
        $video.VideoTracks[0].__copy | Should -BeTrue
        $video.VideoTracks[0].__process | Should -BeFalse

        $subs = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en', 'fre') -DirectoryName $TestDrive
        @($subs.SubtitleTracks).Count | Should -Be 2
        $subs.SubtitleTracks[0].__copy | Should -BeTrue
        $subs.SubtitleTracks[0].__process | Should -BeFalse
        $subs.SubtitleTracks[1].__copy | Should -BeTrue
    }
}

Describe 'Get-ProbeProperty / Test-ProbeHasProperty / Resolve-ProbeMapKey' {

    It 'Get-ProbeProperty retourne null sur objet null ou clé absente' {
        InModuleScope 'Tetram.Media.Reencode' {
            Get-ProbeProperty $null 'language' | Should -BeNullOrEmpty
            Get-ProbeProperty @{ title = 'x' } 'language' | Should -BeNullOrEmpty
            Test-ProbeHasProperty $null 'language' | Should -BeFalse
            Test-ProbeHasProperty @{ title = 'x' } 'language' | Should -BeFalse
        }
    }

    It 'résout LANGUAGE en language sur OrderedHashtable et lit la valeur' {
        $map = ConvertFrom-Json -AsHashtable -InputObject '{"LANGUAGE":"fre"}'
        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ Map = $map } {
            param($Map)
            Test-ProbeHasProperty $Map 'language' | Should -BeTrue
            Get-ProbeProperty $Map 'language' | Should -BeExactly 'fre'
            (Resolve-ProbeMapKey $Map 'language') | Should -BeExactly 'LANGUAGE'
        }
    }

    It 'Test-ProbeHasAssignedLanguage est faux pour unk (même sémantique que l''absence)' {
        InModuleScope 'Tetram.Media.Reencode' {
            Test-ProbeHasAssignedLanguage @{ language = 'unk' } | Should -BeFalse
            Test-ProbeHasAssignedLanguage @{ language = 'UNK' } | Should -BeFalse
            Test-ProbeHasAssignedLanguage @{ language = 'und' } | Should -BeTrue
            Test-ProbeHasAssignedLanguage @{ language = 'eng' } | Should -BeTrue
        }
    }

    It 'lit une NoteProperty PSCustomObject (hors IDictionary)' {
        $obj = [pscustomobject]@{ mimetype = 'font/ttf' }
        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ Obj = $obj } {
            param($Obj)
            Test-ProbeHasProperty $Obj 'mimetype' | Should -BeTrue
            Get-ProbeProperty $Obj 'mimetype' | Should -BeExactly 'font/ttf'
            Test-ProbeHasProperty $Obj 'filename' | Should -BeFalse
        }
    }
}

function script:Invoke-SelectVideoStreamsNoTranscode {
    param(
        [Parameter(Mandatory)] [hashtable] $FfprobeOutput,
        [bool] $NoTranscodeMode = $true,
        [bool] $ForceRecodeVideo = $false,
        [string] $VideoCodec = 'HEVC',
        [bool] $AllowVideoCodecUpgrade = $false,
        [bool] $Deinterlace = $false,
        [string] $Upscale = ''
    )

    InModuleScope 'Tetram.Media.Reencode' -Parameters @{
        FfprobeOutput           = $FfprobeOutput
        NoTranscodeMode         = $NoTranscodeMode
        ForceRecodeVideo        = $ForceRecodeVideo
        VideoCodec              = $VideoCodec
        AllowVideoCodecUpgrade  = $AllowVideoCodecUpgrade
        Deinterlace             = $Deinterlace
        Upscale                 = $Upscale
    } {
        param($FfprobeOutput, $NoTranscodeMode, $ForceRecodeVideo, $VideoCodec, $AllowVideoCodecUpgrade, $Deinterlace, $Upscale)

        Select-VideoStreams `
            -FfprobeOutput $FfprobeOutput `
            -ForceRecodeVideo $ForceRecodeVideo `
            -VideoCodec $VideoCodec `
            -AllowVideoCodecUpgrade $AllowVideoCodecUpgrade `
            -Deinterlace $Deinterlace `
            -Upscale $Upscale `
            -UpscaleWidth 0 `
            -UpscaleHeight 0 `
            -UpscaleFit '' `
            -ConfigUpscaleWidth 0 `
            -NoTranscodeMode $NoTranscodeMode
    }
}

function script:Invoke-SelectAudioStreamsNoTranscode {
    param(
        [Parameter(Mandatory)] [hashtable] $FfprobeOutput,
        [bool] $NoTranscodeMode = $true,
        [string] $FinalExtension = '.mkv',
        [string] $Quality = 'High',
        [bool] $FinalVideoIsAV1 = $false
    )

    InModuleScope 'Tetram.Media.Reencode' -Parameters @{
        FfprobeOutput   = $FfprobeOutput
        NoTranscodeMode = $NoTranscodeMode
        FinalExtension  = $FinalExtension
        Quality         = $Quality
        FinalVideoIsAV1 = $FinalVideoIsAV1
    } {
        param($FfprobeOutput, $NoTranscodeMode, $FinalExtension, $Quality, $FinalVideoIsAV1)

        Select-AudioStreams `
            -FfprobeOutput $FfprobeOutput `
            -FinalExtension $FinalExtension `
            -Quality $Quality `
            -NoTranscodeMode $NoTranscodeMode `
            -FinalVideoIsAV1 $FinalVideoIsAV1
    }
}

function script:Invoke-SelectSubtitleStreamsNoTranscode {
    param(
        [Parameter(Mandatory)] [hashtable] $FfprobeOutput,
        [bool] $NoTranscodeMode = $true,
        [string] $FinalExtension = '.mkv',
        [bool] $AllowSubTitlesConversion = $false,
        [string[]] $SubTitlesToKeep = @('fr', 'en'),
        [Parameter(Mandatory)] [string] $DirectoryName
    )

    InModuleScope 'Tetram.Media.Reencode' -Parameters @{
        FfprobeOutput              = $FfprobeOutput
        NoTranscodeMode            = $NoTranscodeMode
        FinalExtension             = $FinalExtension
        AllowSubTitlesConversion   = $AllowSubTitlesConversion
        SubTitlesToKeep            = $SubTitlesToKeep
        DirectoryName              = $DirectoryName
    } {
        param($FfprobeOutput, $NoTranscodeMode, $FinalExtension, $AllowSubTitlesConversion, $SubTitlesToKeep, $DirectoryName)

        Select-SubtitleStreams `
            -FfprobeOutput $FfprobeOutput `
            -FinalExtension $FinalExtension `
            -AllowSubTitlesConversion $AllowSubTitlesConversion `
            -NoTranscodeMode $NoTranscodeMode `
            -SubTitlesToKeep $SubTitlesToKeep `
            -Filename 'episode.mkv' `
            -DirectoryName $DirectoryName
    }
}

function script:New-VideoProbeStream {
    param(
        [string] $CodecName,
        [string] $Profile = 'High',
        [int] $Width = 1920,
        [int] $Height = 1080,
        [hashtable] $Disposition = @{ attached_pic = 0 }
    )

    @{
        codec_type  = 'video'
        codec_name  = $CodecName
        profile     = $Profile
        width       = $Width
        height      = $Height
        pix_fmt     = 'yuv420p'
        color_space = 'bt709'
        disposition = $Disposition
    }
}

function script:New-AudioProbeStream {
    param(
        [string] $CodecName,
        [int] $Channels = 2,
        [string] $Layout = 'stereo',
        [string] $BitRate = '192000'
    )

    [pscustomobject]@{
        codec_type     = 'audio'
        codec_name     = $CodecName
        channels       = $Channels
        channel_layout = $Layout
        bit_rate       = $BitRate
    }
}

Describe 'Select-VideoStreams — NoTranscodeMode' {

    It 'copie H.264 sans transformation' {
        $ffprobe = @{ streams = @(New-VideoProbeStream -CodecName 'h264') }
        $track = (Invoke-SelectVideoStreamsNoTranscode -FfprobeOutput $ffprobe).VideoTracks[0]
        $track.__copy | Should -BeTrue
        $track.__process | Should -BeFalse
        $track.__recode | Should -BeFalse
        $track.__deinterlace | Should -BeFalse
        $track.__upscale | Should -BeFalse
    }

    It 'copie HEVC sans transformation' {
        $ffprobe = @{ streams = @(New-VideoProbeStream -CodecName 'hevc' -Profile 'Main') }
        $track = (Invoke-SelectVideoStreamsNoTranscode -FfprobeOutput $ffprobe).VideoTracks[0]
        $track.__copy | Should -BeTrue
        $track.__process | Should -BeFalse
        $track.__recode | Should -BeFalse
        $track.__deinterlace | Should -BeFalse
        $track.__upscale | Should -BeFalse
    }

    It 'copie AV1 sans transformation' {
        $ffprobe = @{ streams = @(New-VideoProbeStream -CodecName 'av1') }
        $track = (Invoke-SelectVideoStreamsNoTranscode -FfprobeOutput $ffprobe).VideoTracks[0]
        $track.__copy | Should -BeTrue
        $track.__process | Should -BeFalse
        $track.__recode | Should -BeFalse
        $track.__deinterlace | Should -BeFalse
        $track.__upscale | Should -BeFalse
    }

    It 'écarte une attached-picture' {
        $ffprobe = @{ streams = @(New-VideoProbeStream -CodecName 'h264' -Disposition @{ attached_pic = 1 }) }
        $track = (Invoke-SelectVideoStreamsNoTranscode -FfprobeOutput $ffprobe).VideoTracks[0]
        $track.__copy | Should -BeFalse
        $track.__process | Should -BeFalse
    }

    It 'écarte une vignette MJPEG' {
        $ffprobe = @{ streams = @(New-VideoProbeStream -CodecName 'mjpeg' -Width 640 -Height 360) }
        $track = (Invoke-SelectVideoStreamsNoTranscode -FfprobeOutput $ffprobe).VideoTracks[0]
        $track.__copy | Should -BeFalse
        $track.__process | Should -BeFalse
    }

    It 'ignore ForceRecodeVideo / Deinterlace / Upscale sur une piste conservée' {
        $ffprobe = @{ streams = @(New-VideoProbeStream -CodecName 'h264' -Width 640 -Height 360) }
        $track = (Invoke-SelectVideoStreamsNoTranscode `
                -FfprobeOutput $ffprobe `
                -ForceRecodeVideo $true `
                -Deinterlace $true `
                -Upscale '1080p').VideoTracks[0]
        $track.__copy | Should -BeTrue
        $track.__recode | Should -BeFalse
        $track.__deinterlace | Should -BeFalse
        $track.__upscale | Should -BeFalse
    }
}

Describe 'Select-AudioStreams — NoTranscodeMode' {

    It 'conserve AAC même si la vidéo finale est AV1' {
        $ffprobe = @{ streams = @(New-AudioProbeStream -CodecName 'aac') }
        $track = (Invoke-SelectAudioStreamsNoTranscode -FfprobeOutput $ffprobe -FinalVideoIsAV1 $true -Quality 'High')[0]
        $track.__copy | Should -BeTrue
        $track.__process | Should -BeFalse
        $track.__recode | Should -BeFalse
        $track.codec_name | Should -BeExactly 'aac'
    }

    It 'conserve Opus en High hors MP4' {
        $ffprobe = @{ streams = @(New-AudioProbeStream -CodecName 'opus' -BitRate '64000') }
        $track = (Invoke-SelectAudioStreamsNoTranscode -FfprobeOutput $ffprobe -Quality 'High')[0]
        $track.__copy | Should -BeTrue
        $track.__process | Should -BeFalse
        $track.__recode | Should -BeFalse
        $track.codec_name | Should -BeExactly 'opus'
    }

    It 'conserve Opus en Medium hors MP4' {
        $ffprobe = @{ streams = @(New-AudioProbeStream -CodecName 'opus' -BitRate '64000') }
        $track = (Invoke-SelectAudioStreamsNoTranscode -FfprobeOutput $ffprobe -Quality 'Medium')[0]
        $track.__copy | Should -BeTrue
        $track.__process | Should -BeFalse
        $track.__recode | Should -BeFalse
        $track.codec_name | Should -BeExactly 'opus'
    }

    It 'conserve FLAC' {
        $ffprobe = @{ streams = @(New-AudioProbeStream -CodecName 'flac') }
        $track = (Invoke-SelectAudioStreamsNoTranscode -FfprobeOutput $ffprobe -Quality 'High')[0]
        $track.__copy | Should -BeTrue
        $track.__process | Should -BeFalse
        $track.__recode | Should -BeFalse
        $track.codec_name | Should -BeExactly 'flac'
    }

    It 'conserve TrueHD' {
        $ffprobe = @{ streams = @(New-AudioProbeStream -CodecName 'truehd' -Channels 8 -Layout '7.1') }
        $track = (Invoke-SelectAudioStreamsNoTranscode -FfprobeOutput $ffprobe -Quality 'High')[0]
        $track.__copy | Should -BeTrue
        $track.__process | Should -BeFalse
        $track.__recode | Should -BeFalse
        $track.codec_name | Should -BeExactly 'truehd'
    }

    It 'conserve AC3 et EAC3' {
        $ffprobe = @{
            streams = @(
                (New-AudioProbeStream -CodecName 'ac3' -Channels 6 -Layout '5.1' -BitRate '448000')
                (New-AudioProbeStream -CodecName 'eac3' -Channels 6 -Layout '5.1' -BitRate '448000')
            )
        }
        $tracks = Invoke-SelectAudioStreamsNoTranscode -FfprobeOutput $ffprobe -Quality 'Low'
        $tracks[0].__copy | Should -BeTrue
        $tracks[0].__recode | Should -BeFalse
        $tracks[0].codec_name | Should -BeExactly 'ac3'
        $tracks[1].__copy | Should -BeTrue
        $tracks[1].__recode | Should -BeFalse
        $tracks[1].codec_name | Should -BeExactly 'eac3'
    }

    It 'copie chaque piste d''un fichier multi-audio sans transcodage' {
        $ffprobe = @{
            streams = @(
                (New-AudioProbeStream -CodecName 'aac')
                (New-AudioProbeStream -CodecName 'ac3' -Channels 6 -Layout '5.1')
                (New-AudioProbeStream -CodecName 'flac')
            )
        }
        $tracks = Invoke-SelectAudioStreamsNoTranscode -FfprobeOutput $ffprobe -Quality 'High' -FinalVideoIsAV1 $true
        @($tracks).Count | Should -Be 3
        foreach ($track in $tracks)
        {
            $track.__copy | Should -BeTrue
            $track.__process | Should -BeFalse
            $track.__recode | Should -BeFalse
        }
        $tracks[0].codec_name | Should -BeExactly 'aac'
        $tracks[1].codec_name | Should -BeExactly 'ac3'
        $tracks[2].codec_name | Should -BeExactly 'flac'
    }
}

Describe 'Select-SubtitleStreams — NoTranscodeMode' {

    It 'conserve une langue listée et n''annonce aucune conversion' {
        $ffprobe = @{ streams = @(@{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fre' } }) }
        $result = Invoke-SelectSubtitleStreamsNoTranscode -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en', 'fre') -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeTrue
        $result.SubtitleTracks[0].__process | Should -BeFalse
        $result.SubtitleTracks[0].__recode | Should -BeFalse
    }

    It 'filtre une langue hors SubTitlesToKeep' {
        $ffprobe = @{ streams = @(@{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'jpn' } }) }
        $result = Invoke-SelectSubtitleStreamsNoTranscode -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en') -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeFalse
        $result.SubtitleTracks[0].__process | Should -BeFalse
        $result.SubtitleTracks[0].__recode | Should -BeFalse
    }

    It 'conserve und et unk comme indéterminées' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'und' } }
                @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'unk' } }
                @{ codec_type = 'subtitle'; codec_name = 'subrip' }
            )
        }
        $result = Invoke-SelectSubtitleStreamsNoTranscode -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr') -DirectoryName $TestDrive
        foreach ($track in $result.SubtitleTracks)
        {
            $track.__copy | Should -BeTrue
            $track.__recode | Should -BeFalse
        }
    }

    It 'copie mov_text dans un MP4 et écarte un subrip non copiable' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'mov_text'; tags = @{ language = 'eng' } }
                @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fre' } }
            )
        }
        $result = Invoke-SelectSubtitleStreamsNoTranscode `
            -FfprobeOutput $ffprobe `
            -FinalExtension '.mp4' `
            -SubTitlesToKeep @('eng', 'fre') `
            -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeTrue
        $result.SubtitleTracks[0].__recode | Should -BeFalse
        $result.SubtitleTracks[1].__copy | Should -BeFalse
        $result.SubtitleTracks[1].__recode | Should -BeFalse
    }

    It 'ne skippe pas tout le fichier MP4 quand un sous-titre non copiable peut être écarté' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fre' } }
            )
        }
        $result = Invoke-SelectSubtitleStreamsNoTranscode `
            -FfprobeOutput $ffprobe `
            -FinalExtension '.mp4' `
            -AllowSubTitlesConversion $false `
            -SubTitlesToKeep @('fre') `
            -DirectoryName $TestDrive
        $result | Should -Not -BeNullOrEmpty
        $result.SubtitleTracks[0].__copy | Should -BeFalse
    }

    It 'signale HasAssSubtitles pour les attachments utiles' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'ass'; tags = @{ language = 'fre' } }
            )
        }
        $result = Invoke-SelectSubtitleStreamsNoTranscode -FfprobeOutput $ffprobe -SubTitlesToKeep @('fre') -DirectoryName $TestDrive
        $result.HasAssSubtitles | Should -BeTrue
        $result.SubtitleTracks[0].__copy | Should -BeTrue
        $result.SubtitleTracks[0].__recode | Should -BeFalse
    }
}

Describe 'Filtrage commun au réencodage et à NoTranscode' {

    It 'écarte la même vignette MJPEG dans les deux modes' {
        $ffprobe = @{ streams = @(New-VideoProbeStream -CodecName 'mjpeg') }
        $normal = (Invoke-SelectVideoStreamsNoTranscode -FfprobeOutput $ffprobe -NoTranscodeMode $false).VideoTracks[0]
        $copy = (Invoke-SelectVideoStreamsNoTranscode -FfprobeOutput $ffprobe -NoTranscodeMode $true).VideoTracks[0]
        $normal.__copy | Should -BeFalse
        $copy.__copy | Should -BeFalse
    }

    It 'filtre la même langue de sous-titre dans les deux modes' {
        $ffprobe = @{ streams = @(@{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'jpn' } }) }
        $normal = Invoke-SelectSubtitleStreamsNoTranscode -FfprobeOutput $ffprobe -NoTranscodeMode $false -DirectoryName $TestDrive
        $copy = Invoke-SelectSubtitleStreamsNoTranscode -FfprobeOutput $ffprobe -NoTranscodeMode $true -DirectoryName $TestDrive
        $normal.SubtitleTracks[0].__copy | Should -BeFalse
        $copy.SubtitleTracks[0].__copy | Should -BeFalse
    }

    It 'conserve la même piste H.264 mais ne la transforme qu''en réencodage' {
        $ffprobe = @{ streams = @(New-VideoProbeStream -CodecName 'h264') }
        $normal = (Invoke-SelectVideoStreamsNoTranscode -FfprobeOutput $ffprobe -NoTranscodeMode $false).VideoTracks[0]
        $copy = (Invoke-SelectVideoStreamsNoTranscode -FfprobeOutput $ffprobe -NoTranscodeMode $true).VideoTracks[0]
        $normal.__copy | Should -BeFalse
        $normal.__recode | Should -BeTrue
        $copy.__copy | Should -BeTrue
        $copy.__recode | Should -BeFalse
    }

    It 'filtre une police inutile aux ASS dans les deux modes' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'attachment'; codec_name = 'ttf'; tags = @{ filename = 'Unused.ttf'; mimetype = 'application/x-truetype-font' } }
            )
        }
        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)
            $tracks = Select-AttachmentStreams -FfprobeOutput $FfprobeOutput -HasAssSubtitles $false
            $tracks[0].__copy | Should -BeFalse
            $tracks[0].__process | Should -BeFalse
        }
    }
}
