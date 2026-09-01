using namespace System

Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# EncoderArgs.psm1 — construction des arguments ffmpeg (V/A) + assemblage global
# Sous-module privé de Tetram.Media.Reencode (chargé via NestedModules).
# Pas d'Export-ModuleMember : les fonctions restent dans le scope du module.
# -----------------------------------------------------------------------------

function Get-VideoEncoderArgs
{
    param(
        [ValidateSet('HEVC', 'AV1')] [string] $VideoCodec,
        [ValidateSet('Low', 'Medium', 'High')] [string] $Quality,
        [bool] $TargetIs10Bit,
        [string] $PixFmt,
        [int] $StreamIndex
    )

    $codec = switch ($VideoCodec)
    {
        'AV1' {
            'libsvtav1'
        }
        default {
            'libx265'
        }
    }
    $crf = switch ($VideoCodec)
    {
        'AV1' {
            switch ($Quality)
            {
                'High' {
                    24
                } 'Medium' {
                    28
                } 'Low' {
                    36
                } default {
                    28
                }
            }
        }
        default {
            switch ($Quality)
            {
                'High' {
                    18
                } 'Medium' {
                    21
                } 'Low' {
                    28
                } default {
                    21
                }
            }
        }
    }
    $preset = switch ($VideoCodec)
    {
        'AV1' {
            switch ($Quality)
            {
                'High' {
                    4
                } 'Medium' {
                    6
                } 'Low' {
                    8
                } default {
                    6
                }
            }
        }
        default {
            switch ($Quality)
            {
                'High' {
                    'slow'
                } 'Medium' {
                    'medium'
                } 'Low' {
                    'fast'
                } default {
                    'medium'
                }
            }
        }
    }

    $cpuArgs = @(
        "-c:v:$StreamIndex", $codec
        "-crf:v:$StreamIndex", $crf
        "-preset:v:$StreamIndex", $preset
        "-pix_fmt:v:$StreamIndex", $PixFmt
    )

    if ($VideoCodec -eq 'AV1')
    {
        $cpuArgs += @("-svtav1-params:v:$StreamIndex", 'tune=0')
    }
    if ($VideoCodec -eq 'HEVC')
    {
        $x265Profile = if ($PixFmt -like 'yuv444*')
        {
            ($TargetIs10Bit ? 'main444-10' : 'main444-8')
        }
        elseif ($PixFmt -like 'yuv422*')
        {
            ($TargetIs10Bit ? 'main422-10' : 'main422-8')
        }
        else
        {
            ($TargetIs10Bit ? 'main10' : 'main')
        }
        $cpuArgs += @("-profile:v:$StreamIndex", $x265Profile)
    }

    return $cpuArgs
}

function Get-AudioEncoderArgs
{
    param(
        [int] $StreamIndex,
        [bool] $Process,
        [string] $TargetCodec,
        [string] $TargetBitrate,
        [string] $ChannelMapFilter
    )

    if (-not $Process)
    {
        return @("-c:a:$StreamIndex", 'copy')
    }

    $arguments = @(
        "-c:a:$StreamIndex", ($TargetCodec -eq 'opus' ? 'libopus' : 'aac')
        "-b:a:$StreamIndex", $TargetBitrate
    )
    if ($ChannelMapFilter)
    {
        $arguments += @("-filter:a:$StreamIndex", $ChannelMapFilter)
    }
    if ($TargetCodec -eq 'opus')
    {
        $arguments += @(
            "-vbr:a:$StreamIndex", 'on'
            "-compression_level:a:$StreamIndex", '10'
            "-application:a:$StreamIndex", 'audio'
        )
    }

    return $arguments
}

function Get-FFmpegArgs
{
    param(
    # Paramètres issus de la ligne de commande
        [string] $VideoCodec,
        [string] $Quality,
        [string] $Upscale,
        [int] $UpscaleWidth,
        [int] $UpscaleHeight,
        [string] $UpscaleFit,
        [int] $ConfigUpscaleWidth,
        [bool] $ClearStreamsTitle,

    # Paramètres issus de l'analyse
        [object[]] $VideoTracks,
        [bool] $IsSource10Bit,
        [string] $SourceChroma,
        [object[]] $AudioTracks,
        [object[]] $SubtitleTracks,
        [object[]] $AttachmentTracks
    )

    $targetIs10Bit = switch ($Quality)
    {
        'High'   {
            $true
        }
        'Medium' {
            $IsSource10Bit
        }
        'Low'    {
            $false
        }
        default  {
            $IsSource10Bit
        }
    }

    $targetChroma = switch ($Quality)
    {
        'Low'    {
            '420'
        }
        default  {
            $SourceChroma
        }
    }

    $pixFmt = switch ($targetChroma)
    {
        '444' {
            if ($targetIs10Bit)
            {
                'yuv444p10le'
            }
            else
            {
                'yuv444p'
            }
        }
        '422' {
            if ($targetIs10Bit)
            {
                'yuv422p10le'
            }
            else
            {
                'yuv422p'
            }
        }
        default {
            if ($targetIs10Bit)
            {
                'yuv420p10le'
            }
            else
            {
                'yuv420p'
            }
        }
    }

    $ffmpegArgs = @()
    $undeterminedLanguageArgs = @()

    $SelectedVideoTracks = ($VideoTracks ?? @()) | Where-Object { $_.__process -or $_.__copy } | Select-Object _index, __process, __recode, __deinterlace, __upscale, color_space, __assignUndeterminedLanguage
    Write-Verbose "SelectedVideoTracks:`n $( $SelectedVideoTracks | Format-List | Out-String )"
    $new_index = 0
    foreach ($stream in $SelectedVideoTracks)
    {
        $ffmpegArgs += @(
            '-map', "0:v:$( $stream._index )"
        )
        if ([bool]$stream.__recode -or [bool]$stream.__deinterlace -or [bool]$stream.__upscale)
        {
            $filters = @()
            if ($stream.__deinterlace)
            {
                $filters += 'yadif=0'
            }
            if ($stream.__upscale)
            {
                if ($UpscaleFit -and $UpscaleWidth -ne $null -and $UpscaleHeight -ne $null)
                {
                    $filters += "scale=w=$UpscaleWidth:h=$UpscaleHeight:force_original_aspect_ratio=decrease:flags=lanczos"
                }
                else
                {
                    $targetH = Resolve-UpscaleHeight -Value $Upscale
                    $filters += ('scale={0}:{1}:flags=lanczos' -f $ConfigUpscaleWidth, $targetH)
                }
            }
            $colorRemap = Get-ColorSpaceRemapFilter -ColorSpace ([string]$stream.color_space) -TargetChroma $targetChroma
            if ($colorRemap)
            {
                $filters += $colorRemap
            }
            if ($filters.Count -gt 0)
            {
                $ffmpegArgs += @("-vf:v:$new_index", ($filters -join ','))
            }
            $ffmpegArgs += Get-VideoEncoderArgs `
                -VideoCodec $VideoCodec `
                -Quality $Quality `
                -TargetIs10Bit $targetIs10Bit `
                -PixFmt $pixFmt `
                -StreamIndex $new_index
        }
        else
        {
            $ffmpegArgs += @("-c:v:$new_index", 'copy')
        }
        if ($stream.__assignUndeterminedLanguage)
        {
            $undeterminedLanguageArgs += @("-metadata:s:v:$new_index", 'language=und')
        }
        $new_index++
    }

    $SelectedAudioTracks = ($AudioTracks ?? @()) | Where-Object { $_.__process -or $_.__copy } | Select-Object _index, __process, __recode, __targetAudioCodec, __targetAudioBitrate, __targetAudioFilter, __assignUndeterminedLanguage
    Write-Verbose "SelectedAudioTracks:`n $( $SelectedAudioTracks | Format-List | Out-String )"
    $new_index = 0
    foreach ($stream in $SelectedAudioTracks)
    {
        $ffmpegArgs += @('-map', "0:a:$( $stream._index )")
        $ffmpegArgs += Get-AudioEncoderArgs `
            -StreamIndex $new_index `
            -Process ([bool]$stream.__recode) `
            -TargetCodec ([string]$stream.__targetAudioCodec) `
            -TargetBitrate ([string]$stream.__targetAudioBitrate) `
            -ChannelMapFilter ([string]$stream.__targetAudioFilter)

        if ($stream.__assignUndeterminedLanguage)
        {
            $undeterminedLanguageArgs += @("-metadata:s:a:$new_index", 'language=und')
        }
        $new_index++
    }

    $SelectedSubtitleTracks = ($SubtitleTracks ?? @()) | Where-Object { $_.__process -or $_.__copy } | Select-Object _index, __process, __recode, __assignUndeterminedLanguage
    Write-Verbose "SelectedSubtitleTracks:`n $( $SelectedSubtitleTracks | Format-List | Out-String )"
    $new_index = 0
    foreach ($stream in $SelectedSubtitleTracks)
    {
        $ffmpegArgs += @(
            '-map', "0:s:$( $stream._index )"
            "-c:s:$new_index", ($stream.__recode ? 'mov_text' : 'copy')
        )
        if ($stream.__assignUndeterminedLanguage)
        {
            $undeterminedLanguageArgs += @("-metadata:s:s:$new_index", 'language=und')
        }
        $new_index++
    }

    $SelectedAttachmentTracks = ($AttachmentTracks ?? @()) | Where-Object { $_.__process -or $_.__copy } | Select-Object _index, __process, __targetMimetype
    Write-Verbose "SelectedAttachmentTracks:`n $( $SelectedAttachmentTracks | Format-List | Out-String )"
    $new_index = 0
    $attachmentMimetypeArgs = @()
    foreach ($stream in $SelectedAttachmentTracks)
    {
        $ffmpegArgs += @(
            '-map', "0:t:$( $stream._index )"
            "-c:t:$new_index", 'copy'
        )
        if ($stream.__process -and $stream.__targetMimetype)
        {
            # Après -map_metadata 0, sinon le mimetype source (absent / non mappé) écrase celui-ci.
            $attachmentMimetypeArgs += @(
                "-metadata:s:t:$new_index", "mimetype=$( $stream.__targetMimetype )"
            )
        }
        $new_index++
    }

    # keep as much metadata as possible
    $ffmpegArgs += @(
        '-map_metadata', '0'
    )
    # and then, override with custom metadata
    $ffmpegArgs += @(
        '-metadata', 'MOVIE/ENCODER='
        '-metadata', 'MAJOR_BRAND='
        '-metadata', 'MINOR_VERSION='
        '-metadata', 'COMPATIBLE_BRANDS='
        '-metadata', 'ENCODER='
        '-metadata', 'SOFTWARE='
        $( if ($ClearStreamsTitle)
        {
            @('-metadata:s', 'title=')
        } )
        '-metadata:s', '_STATISTICS_TAGS='
        '-metadata:s', '_STATISTICS_TAGS-eng='
        '-metadata:s', 'HANDLER_NAME='
        '-metadata:s', 'VENDOR_ID='
        '-metadata:s', 'BPS='
        '-metadata:s', 'BPS-eng='
        '-metadata:s', 'DURATION-eng='
        '-metadata:s', 'NUMBER_OF_FRAMES-eng='
        '-metadata:s', 'NUMBER_OF_BYTES='
        '-metadata:s', 'NUMBER_OF_BYTES-eng='
        '-metadata:s', '_STATISTICS_WRITING_APP='
        '-metadata:s', '_STATISTICS_WRITING_APP-eng='
        '-metadata:s', '_STATISTICS_WRITING_DATE_UTC='
        '-metadata:s', '_STATISTICS_WRITING_DATE_UTC-eng='
        '-metadata:s', 'encoder='
    )
    $ffmpegArgs += $attachmentMimetypeArgs
    $ffmpegArgs += $undeterminedLanguageArgs

    $ffmpegArgs += @(
        '-map_chapters', '0'
    )

    return $ffmpegArgs
}
