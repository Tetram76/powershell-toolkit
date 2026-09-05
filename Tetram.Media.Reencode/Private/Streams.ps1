using namespace System
using namespace System.IO

Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# Streams.psm1 — sélection / catégorisation des pistes (V/A/S/T)
# Sous-module privé de Tetram.Media.Reencode (chargé via NestedModules).
# Pas d'Export-ModuleMember : les fonctions restent dans le scope du module.
# -----------------------------------------------------------------------------

# StrictMode 3 : Select-Object crée tags/disposition même si ffprobe les omet ($null).
# .Keys / .mimetype sur $null ou PSCustomObject lève ; IDictionary n'a pas les mêmes NoteProperties.
# OrderedHashtable (ConvertFrom-Json -AsHashtable) : Contains/indexeur sensibles à la casse ;
# l'ancien garde était Keys -contains (insensible). On résout la clé réelle via -eq.
function Resolve-ProbeMapKey
{
    param([System.Collections.IDictionary] $Map, [string] $Name)
    foreach ($key in @($Map.Keys))
    {
        if ($key -eq $Name)
        {
            return $key
        }
    }
    return $null
}

function Get-ProbeProperty
{
    param($Object, [string] $Name)
    if ($null -eq $Object)
    {
        return $null
    }
    if ($Object -is [System.Collections.IDictionary])
    {
        $key = Resolve-ProbeMapKey $Object $Name
        if ($null -ne $key)
        {
            return $Object[$key]
        }
        return $null
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p)
    {
        return $p.Value
    }
    return $null
}

function Test-ProbeHasProperty
{
    param($Object, [string] $Name)
    if ($null -eq $Object)
    {
        return $false
    }
    if ($Object -is [System.Collections.IDictionary])
    {
        return $null -ne (Resolve-ProbeMapKey $Object $Name)
    }
    return [bool]$Object.PSObject.Properties[$Name]
}

function Test-ProbeHasAssignedLanguage
{
    param($Tags)
    if (-not (Test-ProbeHasProperty $Tags 'language'))
    {
        return $false
    }
    $raw = Get-ProbeProperty $Tags 'language'
    if ($null -eq $raw)
    {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$raw))
    {
        return $false
    }
    # unk = ISO « unknown », pas une langue réelle ; Streams le normalise en und.
    # Sans ça le keep sous-titres (un/und + liste) écarte la piste.
    return -not [string]::Equals([string]$raw, 'unk', [StringComparison]::OrdinalIgnoreCase)
}

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
        [bool] $NoTranscodeMode
    )
    Write-Verbose ">> Select-VideoStreams"
    try
    {
        $videoStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'video' }
        $VideoTracks = $videoStreams | Select-Object codec_name, profile, height, width, disposition, color_space, tags
        $i = -1

        foreach ($stream in $VideoTracks)
        {
            $stream | Add-Member -NotePropertyName '_index' -NotePropertyValue (++$i)
            $attachedPic = Get-ProbeProperty (Get-ProbeProperty $stream 'disposition') 'attached_pic'
            $keepStream = -not (($attachedPic -eq 1) -or ($stream.codec_name -eq 'mjpeg'))
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

            if ($NoTranscodeMode)
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

function Test-FinalVideoIsAV1
{
    param(
        [object[]] $VideoTracks,
        [Parameter(Mandatory)]
        [ValidateSet('HEVC', 'AV1')]
        [string] $VideoCodec
    )

    # VideoCodec configuré ≠ codec réellement produit : une cible AV1 copiée en HEVC
    # ne doit pas déclencher la contrainte audio, une source AV1 copiée si.
    foreach ($stream in @($VideoTracks))
    {
        if ($null -eq $stream)
        {
            continue
        }
        if (-not (([bool]$stream.__process) -or ([bool]$stream.__copy)))
        {
            continue
        }

        $finalCodec = if ([bool]$stream.__recode -or [bool]$stream.__deinterlace -or [bool]$stream.__upscale)
        {
            $VideoCodec
        }
        else
        {
            [string]$stream.codec_name
        }

        if ($finalCodec -ieq 'av1')
        {
            return $true
        }
    }

    return $false
}

function Select-AudioStreams
{
    param(
        [hashtable] $FfprobeOutput,
        [string] $FinalExtension,
        [string] $Quality,
        [bool] $NoTranscodeMode,
        [bool] $FinalVideoIsAV1
    )
    Write-Verbose ">> Select-AudioStreams"
    try
    {
        $audioStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'audio' }
        $AudioTracks = $audioStreams | Select-Object codec_name, channels, channel_layout, bit_rate, tags
        $targetAudioCodec = Get-TargetAudioCodec -FinalExtension $FinalExtension -Quality $Quality
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

            # Low reste sur la politique Opus : AV1 n'impose AAC→EAC3 qu'en High/Medium.
            $forceAacToEac3 =
                $FinalVideoIsAV1 -and
                ($codec -ieq 'aac') -and
                ($Quality -in @('High', 'Medium')) -and
                -not $NoTranscodeMode
            # High/Medium hors MP4 n'acceptent plus Opus : alreadyTargetNoGain ne doit pas figer une copie.
            $forceOpusToEac3 =
                ($FinalExtension -ine '.mp4') -and
                ($Quality -in @('High', 'Medium')) -and
                ($codec -ieq 'opus') -and
                -not $NoTranscodeMode

            $effectiveTargetCodec = if ($forceAacToEac3)
            {
                'eac3'
            }
            else
            {
                $targetAudioCodec
            }
            # High/Medium seulement : un FLAC/TrueHD recodé en AAC sous AV1 recréerait le couple évité.
            # En Low la cible reste Opus (Get-TargetAudioCodec), y compris avec une vidéo finale AV1.
            if ($FinalVideoIsAV1 -and -not $NoTranscodeMode -and $isLossless -and ($Quality -in @('High', 'Medium')))
            {
                $effectiveTargetCodec = 'eac3'
            }

            $targetBitrateLabel = $null
            $targetBps = 0
            if ($effectiveTargetCodec -ine 'eac3')
            {
                $targetBitrateLabel = Get-TargetAudioBitrate -Codec $effectiveTargetCodec -Quality $Quality -Channels $channels
                $targetBps = ConvertTo-IntBitrateK $targetBitrateLabel
            }

            $hasGain = ($currentBps -gt 0) -and ($targetBps -gt 0) -and ($targetBps -lt [int]($currentBps / 1.05))

            $likelyGainCodecs = @('dts', 'eac3', 'ac3', 'truehd')
            $alreadyTargetNoGain =
            ($codec -ieq $effectiveTargetCodec) -and (
            ($currentBps -le 0) -or
                    ($targetBps -gt 0 -and $currentBps -le $targetBps)
            )

            # elseif obligatoire : plusieurs sorties dans un case switch
            # produisent un Object[] truthy (ex. déjà Opus => @$false,$false).
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
                    elseif ($isLossless)
                    {
                        $true
                    }
                    elseif ($hasGain)
                    {
                        $true
                    }
                    elseif ($likelyGainCodecs -contains ($codec.ToLowerInvariant()))
                    {
                        $true
                    }
                    else
                    {
                        $false
                    }
                }
                default  {
                    $isLossless
                }
            }

            $opusLayoutFix = $null
            if ($effectiveTargetCodec -eq 'opus' -and $layout -match 'side')
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

            # Encodeur natif eac3 : layouts jusqu'à 5.1 seulement ; au-delà FFmpeg refuse d'ouvrir le flux.
            $eac3DownmixFilter = $null
            if ($effectiveTargetCodec -ieq 'eac3' -and $channels -gt 6)
            {
                $eac3DownmixFilter = 'aformat=channel_layouts=5.1'
            }

            $recode = if ($NoTranscodeMode)
            {
                $false
            }
            else
            {
                $forceAacToEac3 -or $forceOpusToEac3 -or $recodeForContainer -or $recodeForQuality
            }
            $stream | Add-Member -NotePropertyName '__recode' -NotePropertyValue $recode -Force

            if ($recode)
            {
                $stream | Add-Member -NotePropertyName '__targetAudioCodec' -NotePropertyValue $effectiveTargetCodec -Force
                $stream | Add-Member -NotePropertyName '__targetAudioBitrate' -NotePropertyValue $targetBitrateLabel -Force

                $audioFilter = $opusLayoutFix
                if ($eac3DownmixFilter)
                {
                    $audioFilter = $eac3DownmixFilter
                }
                if ($audioFilter)
                {
                    $stream | Add-Member -NotePropertyName '__targetAudioFilter' -NotePropertyValue $audioFilter -Force
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
        [bool] $NoTranscodeMode,
        [string[]] $SubTitlesToKeep,
        [string] $Filename,
        [string] $DirectoryName
    )
    Write-Verbose ">> Select-SubtitleStreams"
    try
    {
        $subtitleStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'subtitle' }
        $SubtitleTracks = $subtitleStreams | Select-Object codec_name, tags

        if (-not $NoTranscodeMode)
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
        if (-not $NoTranscodeMode)
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
            $tags = Get-ProbeProperty $stream 'tags'
            $language = Get-ProbeProperty $tags 'language'
            if (-not (Test-ProbeHasAssignedLanguage $tags))
            {
                $language = 'und'
            }
            $keepStream = [bool]((@('un', 'und') + $SubTitlesToKeep) | Where-Object { $_ -ieq $language })
            if ($NoTranscodeMode -and $FinalExtension -ieq '.mp4')
            {
                # En NoTranscode, seul mov_text peut être copié dans un conteneur mp4
                $keepStream = $keepStream -and ($stream.codec_name -ieq 'mov_text')
            }
            $recode = if ($NoTranscodeMode)
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

function Get-FontAttachmentTargetMimetype
{
    param(
        [string] $Mimetype,
        [string] $Filename,
        [string] $Codec
    )

    $mime = [string]$Mimetype
    $name = [string]$Filename

    # L'extension est indépendante du FileMediaType Matroska.
    if ($name -match '\.otf$')
    {
        return 'application/vnd.ms-opentype'
    }
    if ($name -match '\.(ttf|woff2?|ttc)$')
    {
        return 'application/x-truetype-font'
    }

    # ffprobe (mkv_mime_tags + av_strstart) pose ttf/otf depuis le mime :
    # application/vnd.ms-opentype → otf, application/x-truetype-font / x-font → ttf.
    # Ce mime n'est alors plus une preuve. font/otf (RFC 8081) n'est pas dans la table
    # (pas de codec) : c'est le seul cas où le mime courant informe encore le type.
    if ($Codec -notin @('ttf', 'otf') -and ($mime -match 'opentype' -or $mime -match '(^|/)otf$'))
    {
        return 'application/vnd.ms-opentype'
    }

    return 'application/x-truetype-font'
}

function Select-AttachmentStreams
{
    param(
        [hashtable] $FfprobeOutput,
        [bool] $HasAssSubtitles,
        [bool] $RemoveAttachments = $false
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
            $tags = Get-ProbeProperty $stream 'tags'
            $isFontByCodec = $stream.codec_name -in @('ttf', 'otf')
            $isFontByMetadata = ((Get-ProbeProperty $tags 'mimetype') -match '\bfont\b|truetype|opentype') -or
                    ((Get-ProbeProperty $tags 'filename') -match '\.(ttf|otf|woff2?|ttc)$')
            $isFont = $isFontByCodec -or $isFontByMetadata
            $keepStream = if ($RemoveAttachments)
            {
                $false
            }
            else
            {
                (-not $isFont) -or $HasAssSubtitles
            }

            if ($keepStream -and $isFont)
            {
                # Matroska n'a pas de codec_id sur les attachments : ffprobe ne remplit
                # codec_name (ttf/otf) que depuis FileMediaType via mkv_mime_tags.
                # Doc FFmpeg (-attach) : -c copy + -metadata:s:t mimetype=...
                $filename = [string](Get-ProbeProperty $tags 'filename')
                $codec = [string]$stream.codec_name
                $filenameDisagreesWithCodec =
                    ($codec -eq 'ttf' -and $filename -match '\.otf$') -or
                    ($codec -eq 'otf' -and $filename -match '\.(ttf|woff2?|ttc)$')

                if ((-not $isFontByCodec) -or $filenameDisagreesWithCodec)
                {
                    $targetMimetype = Get-FontAttachmentTargetMimetype `
                        -Mimetype ([string](Get-ProbeProperty $tags 'mimetype')) `
                        -Filename $filename `
                        -Codec $codec
                    if ($targetMimetype)
                    {
                        $stream | Add-Member -NotePropertyName '__targetMimetype' -NotePropertyValue $targetMimetype -Force
                        $stream | Add-Member -NotePropertyName '__recode' -NotePropertyValue $true -Force
                    }
                }
            }

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
