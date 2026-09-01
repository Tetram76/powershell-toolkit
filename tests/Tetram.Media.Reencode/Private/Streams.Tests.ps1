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
                -RewriteMode $false `
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
                -RewriteMode $false
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

            $tracks = Select-AudioStreams -FfprobeOutput $FfprobeOutput -FinalExtension '.mkv' -Quality 'Low' -RewriteMode $false
            $tracks[0].__recode | Should -BeFalse
            $tracks[0].__copy | Should -BeFalse
            $tracks[0].__assignUndeterminedLanguage | Should -BeTrue
            $tracks[0].__process | Should -BeTrue
        }
    }

    It 'ne pose pas __assignUndeterminedLanguage si tags.language est déjà affecté' {
        $ffprobe = @{
            streams = @(
                [pscustomobject]@{
                    codec_type     = 'audio'
                    codec_name     = 'opus'
                    channels       = 2
                    channel_layout = 'stereo'
                    bit_rate       = '96000'
                    tags           = @{ language = 'eng' }
                }
            )
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{ FfprobeOutput = $ffprobe } {
            param($FfprobeOutput)

            $tracks = Select-AudioStreams -FfprobeOutput $FfprobeOutput -FinalExtension '.mkv' -Quality 'Low' -RewriteMode $false
            $tracks[0].__assignUndeterminedLanguage | Should -BeFalse
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

Describe 'Select-SubtitleStreams' {

    It 'conserve une piste subrip sans tags (ffprobe omet la map) sans lever StrictMode' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'subrip' }
            )
        }

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeFalse
        $result.SubtitleTracks[0].__process | Should -BeTrue
        $result.SubtitleTracks[0].__recode | Should -BeFalse
        $result.SubtitleTracks[0].__assignUndeterminedLanguage | Should -BeTrue
    }

    It 'conserve une piste dont tags n''a pas de clé language' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ title = 'Signs' } }
            )
        }

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeFalse
        $result.SubtitleTracks[0].__process | Should -BeTrue
        $result.SubtitleTracks[0].__assignUndeterminedLanguage | Should -BeTrue
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
        $result.SubtitleTracks[0].__assignUndeterminedLanguage | Should -BeFalse
    }

    It 'conserve language=fre listé dans SubTitlesToKeep' {
        $ffprobe = @{
            streams = @(
                @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fre' } }
            )
        }

        $result = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en', 'fre') -DirectoryName $TestDrive
        $result.SubtitleTracks[0].__copy | Should -BeTrue
        $result.SubtitleTracks[0].__assignUndeterminedLanguage | Should -BeFalse
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
        $result.SubtitleTracks[0].__copy | Should -BeFalse
        $result.SubtitleTracks[0].__process | Should -BeTrue
        $result.SubtitleTracks[0].__assignUndeterminedLanguage | Should -BeTrue
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
            $result.SubtitleTracks[0].__assignUndeterminedLanguage | Should -BeFalse -Because "language=$lang"
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
            $result.SubtitleTracks[0].__copy | Should -BeFalse -Because "language=$lang"
            $result.SubtitleTracks[0].__process | Should -BeTrue -Because "language=$lang"
            $result.SubtitleTracks[0].__assignUndeterminedLanguage | Should -BeTrue -Because "language=$lang"
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
                -RewriteMode $false

            $result.VideoTracks[0].__copy | Should -BeFalse
            $result.VideoTracks[0].__process | Should -BeTrue
            $result.VideoTracks[0].__recode | Should -BeFalse
            $result.VideoTracks[0].__assignUndeterminedLanguage | Should -BeTrue
        }
    }

    It 'ne pose pas __assignUndeterminedLanguage si tags.language est déjà affecté' {
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
                    tags        = @{ language = 'jpn' }
                    disposition = @{ attached_pic = 0 }
                }
            )
        }

        $result = Invoke-SelectVideoStreamsUnderTest -FfprobeOutput $ffprobe
        $result.VideoTracks[0].__assignUndeterminedLanguage | Should -BeFalse
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
        $video.VideoTracks[0].__copy | Should -BeFalse
        $video.VideoTracks[0].__process | Should -BeTrue
        $video.VideoTracks[0].__assignUndeterminedLanguage | Should -BeTrue

        $subs = Invoke-SelectSubtitleStreamsUnderTest -FfprobeOutput $ffprobe -SubTitlesToKeep @('fr', 'en', 'fre') -DirectoryName $TestDrive
        @($subs.SubtitleTracks).Count | Should -Be 2
        $subs.SubtitleTracks[0].__copy | Should -BeFalse
        $subs.SubtitleTracks[0].__assignUndeterminedLanguage | Should -BeTrue
        $subs.SubtitleTracks[1].__copy | Should -BeTrue
        $subs.SubtitleTracks[1].__assignUndeterminedLanguage | Should -BeFalse
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
