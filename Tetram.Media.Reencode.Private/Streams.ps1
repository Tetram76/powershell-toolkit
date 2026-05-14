using namespace System
using namespace System.IO

Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# Streams.psm1 — sélection / catégorisation des pistes (V/A/S/T)
# Sous-module privé de Tetram.Media.Reencode (chargé via NestedModules).
# Pas d'Export-ModuleMember : les fonctions restent dans le scope du module.
# -----------------------------------------------------------------------------

function Set-StreamProcessingState
{
    param(
        [Parameter(Mandatory)] [pscustomobject] $stream,
        [bool] $keepStream
    )

    $hasTrueProperty = $stream.PSObject.Properties |
            Where-Object { $_.Name -like '__*' -and $_.Value -eq $true } |
            ForEach-Object { $true } | Select-Object -First 1 -OutVariable hasResult
    if (-not $hasResult)
    {
        $hasTrueProperty = $false
    }

    $stream | Add-Member -NotePropertyName '__process' -NotePropertyValue $hasTrueProperty -Force
    $stream | Add-Member -NotePropertyName '__copy'    -NotePropertyValue ($keepStream -and -not $hasTrueProperty) -Force
}

function Select-VideoStreams
{
    param(
        [hashtable] $FfprobeOutput,
        [bool] $ForceRecodeVideo,
        [ValidateSet('HEVC', 'AV1')] [string] $VideoCodec,
        [bool] $AllowVideoCodecUpgrade,
        [bool] $Deinterlace,
        [string] $Upscale,
        [int] $UpscaleWidth,
        [int] $UpscaleHeight,
        [string] $UpscaleFit,
        [int] $ConfigUpscaleWidth,
        [bool] $RewriteMode
    )
    Write-Verbose ">> Select-VideoStreams"
    try
    {
        $videoStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'video' }
        $VideoTracks = $videoStreams | Select-Object codec_name, profile, height, width, disposition
        $i = -1

        foreach ($stream in $VideoTracks)
        {
            $stream | Add-Member -NotePropertyName '_index' -NotePropertyValue (++$i)
            $keepStream = -not (($stream.disposition.attached_pic -eq 1) -or ($stream.codec_name -eq 'mjpeg'))
            $isHEVC = ($stream.codec_name -ieq 'hevc') -and ($stream.profile -like 'main*')
            $keepVideoCodec = $isHEVC -or ($stream.codec_name -ieq 'av1') -or ($stream.codec_name -ieq 'vc1')
            if ($VideoCodec -eq 'AV1' -and $AllowVideoCodecUpgrade -and $isHEVC)
            {
                $keepVideoCodec = $false
            }
            if ($ForceRecodeVideo)
            {
                $keepVideoCodec = $false
            }

            $upscaleStream = $false
            if ($UpscaleFit -and $UpscaleWidth -ne $null -and $UpscaleHeight -ne $null)
            {
                $upscaleStream = ($UpscaleWidth -gt $stream.width) -and ($UpscaleHeight -gt $stream.height)
            }
            elseif ($Upscale)
            {
                $upscaleTargetHeight = Resolve-UpscaleHeight -Value $Upscale
                if ($upscaleTargetHeight -gt $stream.height)
                {
                    $upscaleStream = $true
                }
                if ($upscaleTargetHeight -eq $stream.height)
                {
                    $upscaleStream = ($ConfigUpscaleWidth -ne -1) -and ($ConfigUpscaleWidth -ne $stream.width)
                }
            }
            else
            {
                if ($ConfigUpscaleWidth -gt $stream.width)
                {
                    $upscaleStream = $true
                }
            }

            if ($RewriteMode)
            {
                $stream | Add-Member -NotePropertyName '__deinterlace' -NotePropertyValue $false -Force
                $stream | Add-Member -NotePropertyName '__upscale' -NotePropertyValue $false -Force
                $stream | Add-Member -NotePropertyName '__recode' -NotePropertyValue $false -Force
            }
            else
            {
                $stream | Add-Member -NotePropertyName '__deinterlace' -NotePropertyValue ($keepStream -and $Deinterlace) -Force
                $stream | Add-Member -NotePropertyName '__upscale' -NotePropertyValue ($keepStream -and $upscaleStream) -Force
                $stream | Add-Member -NotePropertyName '__recode' -NotePropertyValue ($keepStream -and -not $keepVideoCodec) -Force
            }

            Set-StreamProcessingState $stream $keepStream | Out-Null
        }

        $isSource10Bit = @($videoStreams | Where-Object { Test-Is10BitVideoStream $_ }).Count -gt 0

        $chromaRank = @{ '420' = 0; '422' = 1; '444' = 2 }
        $sourceChroma = '420'
        foreach ($vs in $videoStreams)
        {
            $c = Get-SourceChromaMode $vs
            if ($chromaRank[$c] -gt $chromaRank[$sourceChroma])
            {
                $sourceChroma = $c
            }
        }

        Write-Verbose "Select-VideoStreams >>`n $( $VideoTracks | Format-List | Out-String )"
        return @{
            VideoTracks = $VideoTracks
            IsSource10Bit = $isSource10Bit
            SourceChroma = $sourceChroma
        }
    }
    catch
    {
        Write-Verbose "EE Select-VideoStreams >>`n ($_.Exception)"
        throw
    }
}

function Select-AudioStreams
{
    param(
        [hashtable] $FfprobeOutput,
        [string] $FinalExtension,
        [string] $Quality,
        [bool] $RewriteMode
    )
    Write-Verbose ">> Select-AudioStreams"
    try
    {
        $audioStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'audio' }
        $AudioTracks = $audioStreams | Select-Object codec_name, channels, channel_layout, bit_rate
        $targetAudioCodec = Get-TargetAudioCodec -FinalExtension $FinalExtension
        $i = -1

        foreach ($stream in $AudioTracks)
        {
            $stream | Add-Member -NotePropertyName '_index' -NotePropertyValue (++$i) -Force

            $codec = [string]$stream.codec_name

            $recodeForContainer = ($codec -ieq 'nellymoser')
            if ($FinalExtension -ieq '.mp4')
            {
                $recodeForContainer = $recodeForContainer -or
                        ($codec -ieq 'flac') -or
                        ($codec -ilike 'wm*') -or
                        ($codec -in 'pcm_u8', 'adpcm_ima_wav')
            }

            $channels = if ($stream.channels)
            {
                [int]$stream.channels
            }
            else
            {
                2
            }
            $currentBps = if ($stream.bit_rate)
            {
                [int]$stream.bit_rate
            }
            else
            {
                0
            }
            $layout = [string]$stream.channel_layout

            $isLossless = Test-IsLosslessAudioCodec $codec

            $targetBitrateLabel = Get-TargetAudioBitrate -Codec $targetAudioCodec -Quality $Quality -Channels $channels
            $targetBps = ConvertTo-IntBitrateK $targetBitrateLabel

            $hasGain = ($currentBps -gt 0) -and ($targetBps -gt 0) -and ($targetBps -lt [int]($currentBps / 1.05))

            $likelyGainCodecs = @('dts', 'eac3', 'ac3', 'truehd')
            $alreadyTargetNoGain =
            ($codec -ieq $targetAudioCodec) -and (
            ($currentBps -le 0) -or
                    ($targetBps -gt 0 -and $currentBps -le $targetBps)
            )

            $recodeForQuality = switch ($Quality)
            {
                'High'   {
                    $isLossless
                }
                'Medium' {
                    $isLossless
                }
                'Low'    {
                    if ($alreadyTargetNoGain)
                    {
                        $false
                    }
                    if ($isLossless)
                    {
                        $true
                    }
                    if ($hasGain)
                    {
                        $true
                    }
                    if ($likelyGainCodecs -contains ($codec.ToLowerInvariant()))
                    {
                        $true
                    }
                    $false
                }
                default  {
                    $isLossless
                }
            }

            $opusLayoutFix = $null
            if ($targetAudioCodec -eq 'opus' -and $layout -match 'side')
            {
                if ($channels -eq 5)
                {
                    $opusLayoutFix = "channelmap=FL-FL|FR-FR|FC-FC|SL-BL|SR-BR:5.0"
                }
                elseif ($channels -eq 6)
                {
                    $opusLayoutFix = "channelmap=FL-FL|FR-FR|FC-FC|LFE-LFE|SL-BL|SR-BR:5.1"
                }
            }

            $recode = if ($RewriteMode)
            {
                $false
            }
            else
            {
                $recodeForContainer -or $recodeForQuality
            }
            $stream | Add-Member -NotePropertyName '__recode' -NotePropertyValue $recode -Force

            if ($recode)
            {
                $stream | Add-Member -NotePropertyName '__targetAudioCodec' -NotePropertyValue $targetAudioCodec -Force
                $stream | Add-Member -NotePropertyName '__targetAudioBitrate' -NotePropertyValue $targetBitrateLabel -Force

                if ($opusLayoutFix)
                {
                    $stream | Add-Member -NotePropertyName '__targetAudioFilter' -NotePropertyValue $opusLayoutFix -Force
                }
            }

            Set-StreamProcessingState $stream $true | Out-Null
        }

        Write-Verbose "Select-AudioStreams >>`n $( $AudioTracks | Format-List | Out-String )"
        return $AudioTracks
    }
    catch
    {
        Write-Verbose "EE Select-AudioStreams`n ($_.Exception)"
        throw
    }
}

function Select-SubtitleStreams
{
    param(
        [hashtable] $FfprobeOutput,
        [string] $FinalExtension,
        [bool] $AllowSubTitlesConversion,
        [bool] $RewriteMode,
        [string[]] $SubTitlesToKeep,
        [string] $Filename,
        [string] $DirectoryName
    )
    Write-Verbose ">> Select-SubtitleStreams"
    try
    {
        $subtitleStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'subtitle' }
        $SubtitleTracks = $subtitleStreams | Select-Object codec_name, tags

        if (-not $RewriteMode)
        {
            if ($SubtitleTracks -and $FinalExtension -ieq '.mp4' -and -not $AllowSubTitlesConversion)
            {
                return $null
            }
        }

        $assSubtitles = $SubtitleTracks | Where-Object { $_.codec_name -eq 'ass' }
        if (-not $assSubtitles)
        {
            $BaseName = [Path]::GetFileNameWithoutExtension($Filename)
            $assSubtitles = Get-ChildItem -Path $DirectoryName -Filter "$BaseName.*.ass"
        }
        if (-not $RewriteMode)
        {
            if ($assSubtitles -and $FinalExtension -ieq '.mp4' -and $AllowSubTitlesConversion)
            {
                return $null
            }
        }

        $i = -1
        foreach ($stream in $SubtitleTracks)
        {
            $stream | Add-Member -NotePropertyName '_index' -NotePropertyValue (++$i)
            if (-not ($stream.PSObject.Properties.Name -contains "tags") -or -not ($stream.tags.Keys -contains "language"))
            {
                $keepStream = $true
            }
            else
            {
                $keepStream = [bool]((@('un', 'und') + $SubTitlesToKeep) | Where-Object { $_ -ieq $stream.tags.language })
            }
            if ($RewriteMode -and $FinalExtension -ieq '.mp4')
            {
                # En rewrite, seul mov_text peut être copié dans un conteneur mp4
                $keepStream = $keepStream -and ($stream.codec_name -ieq 'mov_text')
            }
            $recode = if ($RewriteMode)
            {
                $false
            }
            else
            {
                $FinalExtension -ieq '.mp4' -and $AllowSubTitlesConversion
            }
            $stream | Add-Member -NotePropertyName '__recode' -NotePropertyValue ($keepStream -and $recode) -Force

            Set-StreamProcessingState $stream $keepStream | Out-Null
        }

        Write-Verbose "Select-SubtitleStreams >>`n $( $SubtitleTracks | Format-List | Out-String )"
        return @{
            SubtitleTracks = $SubtitleTracks
            HasAssSubtitles = [bool]($SubtitleTracks | Where-Object { $_.codec_name -eq 'ass' -and ($_.__copy -or $_.__process) })
        }
    }
    catch
    {
        Write-Verbose "EE Select-SubtitleStreams >>`n ($_.Exception)"
        throw
    }
}

function Select-AttachmentStreams
{
    param(
        [hashtable] $FfprobeOutput,
        [bool] $HasAssSubtitles
    )
    Write-Verbose ">> Select-AttachmentStreams"
    try
    {
        $attachmentStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'attachment' }
        $AttachmentTracks = $attachmentStreams | Select-Object codec_name, tags
        $i = -1
        foreach ($stream in $AttachmentTracks)
        {
            $stream | Add-Member -NotePropertyName '_index' -NotePropertyValue (++$i)
            $isFont = ($stream.codec_name -in @('ttf', 'otf')) -or
                    ($stream.tags.mimetype -match '\bfont\b|truetype|opentype') -or
                    ($stream.tags.filename -match '\.(ttf|otf|woff2?|ttc)$')
            $keepStream = (-not $isFont) -or $HasAssSubtitles
            Set-StreamProcessingState $stream $keepStream | Out-Null
        }

        Write-Verbose "Select-AttachmentStreams >>`n $( $AttachmentTracks | Format-List | Out-String )"
        return $AttachmentTracks
    }
    catch
    {
        Write-Verbose "EE Select-AttachmentStreams >>`n ($_.Exception)"
        throw
    }
}
