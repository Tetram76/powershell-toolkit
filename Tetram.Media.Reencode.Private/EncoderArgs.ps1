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

    $args = @(
        "-c:a:$StreamIndex", ($TargetCodec -eq 'opus' ? 'libopus' : 'aac')
        "-b:a:$StreamIndex", $TargetBitrate
    )
    if ($ChannelMapFilter)
    {
        $args += @("-filter:a:$StreamIndex", $ChannelMapFilter)
    }
    if ($TargetCodec -eq 'opus')
    {
        $args += @(
            "-vbr:a:$StreamIndex", 'on'
            "-compression_level:a:$StreamIndex", '10'
            "-application:a:$StreamIndex", 'audio'
        )
    }

    return $args
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

    $SelectedVideoTracks = ($VideoTracks ?? @()) | Where-Object { $_.__process -or $_.__copy } | Select-Object _index, __process, __deinterlace, __upscale
    Write-Verbose "SelectedVideoTracks:`n $( $SelectedVideoTracks | Format-List | Out-String )"
    $new_index = 0
    foreach ($stream in $SelectedVideoTracks)
    {
        $ffmpegArgs += @(
            '-map', "0:v:$( $stream._index )"
        )
        if ($stream.__process)
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
        $new_index++
    }

    $SelectedAudioTracks = ($AudioTracks ?? @()) | Where-Object { $_.__process -or $_.__copy } | Select-Object _index, __process, __targetAudioCodec, __targetAudioBitrate, __targetAudioFilter
    Write-Verbose "SelectedAudioTracks:`n $( $SelectedAudioTracks | Format-List | Out-String )"
    $new_index = 0
    foreach ($stream in $SelectedAudioTracks)
    {
        $ffmpegArgs += @('-map', "0:a:$( $stream._index )")
        $ffmpegArgs += Get-AudioEncoderArgs `
            -StreamIndex $new_index `
            -Process ([bool]$stream.__process) `
            -TargetCodec ([string]$stream.__targetAudioCodec) `
            -TargetBitrate ([string]$stream.__targetAudioBitrate) `
            -ChannelMapFilter ([string]$stream.__targetAudioFilter)

        $new_index++
    }

    $SelectedSubtitleTracks = ($SubtitleTracks ?? @()) | Where-Object { $_.__process -or $_.__copy } | Select-Object _index, __process
    Write-Verbose "SelectedSubtitleTracks:`n $( $SelectedSubtitleTracks | Format-List | Out-String )"
    $new_index = 0
    foreach ($stream in $SelectedSubtitleTracks)
    {
        $ffmpegArgs += @(
            '-map', "0:s:$( $stream._index )"
            "-c:s:$new_index", ($stream.__process ? 'mov_text' : 'copy')
        )
        $new_index++
    }

    $SelectedAttachmentTracks = ($AttachmentTracks ?? @()) | Where-Object { $_.__copy } | Select-Object _index
    Write-Verbose "SelectedAttachmentTracks:`n $( $SelectedAttachmentTracks | Format-List | Out-String )"
    $new_index = 0
    foreach ($stream in $SelectedAttachmentTracks)
    {
        $ffmpegArgs += @(
            '-map', "0:t:$( $stream._index )"
            "-c:t:$new_index", 'copy'
        )
        $new_index++
    }

    $ffmpegArgs += @(
        '-map_metadata', '0'
        '-metadata', 'MOVIE/ENCODER='
        $( if ($ClearStreamsTitle)
        {
            @('-metadata:s', 'title=')
        } )
        '-metadata:s', '_STATISTICS_TAGS='
        '-metadata:s', '_STATISTICS_TAGS-eng='
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
        '-map_chapters', '0'
    )

    return $ffmpegArgs
}
