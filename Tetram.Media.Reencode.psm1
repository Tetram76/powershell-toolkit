using namespace System
using namespace System.IO

Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# Types et enums
# -----------------------------------------------------------------------------
class EncodingResult {
    [long] $OriginalSize = 0
    [long] $ReencodedSize = 0
    [TimeSpan] $Duration = 0
    [TimeSpan] $ElapsedTime = 0
    [int] $Count = 0

    EncodingResult() {
	}
    
	EncodingResult([long] $o, [long] $r) {
		$this.OriginalSize = $o; 
		$this.ReencodedSize = $r; 
		$this.Count = 1 
	}
	
    EncodingResult([long] $o, [long] $r, [TimeSpan] $d, [TimeSpan] $e) {
        $this.OriginalSize = $o;
		$this.ReencodedSize = $r;
		$this.Duration = $d; 
		$this.ElapsedTime = $e; 
		$this.Count = 1
    }

    [void] Add([EncodingResult] $Other) {
		$this.OriginalSize += $Other.OriginalSize
		$this.ReencodedSize += $Other.ReencodedSize
		$this.Duration += $Other.Duration
		$this.ElapsedTime += $Other.ElapsedTime
		$this.Count += $Other.Count
    }
	
    [string] SizeReport() {
        if ($this.Count -eq 0 -or $this.OriginalSize -eq 0 -or $this.ReencodedSize -eq 0) { return '' }
        $saved = $this.OriginalSize - $this.ReencodedSize
        return ("{0} reencoded into {1} ({2:0.00}:1, {3:0.00} %, {4} disk space saved)" -f
            (Format-FileSize -Size $this.OriginalSize),
            (Format-FileSize -Size $this.ReencodedSize),
            ($this.OriginalSize / $this.ReencodedSize),
            ($saved / $this.OriginalSize * 100),
            (Format-FileSize -Size $saved))
    }
	
    [string] TimeReport() {
        if ($this.Count -eq 0 -or $this.Duration -eq 0 -or $this.ElapsedTime -eq 0) { return '' }
        return ("{0} reencoded in {1} (Speed: x{2:0.00})" -f
            (Format-Duration -TimeSpan $this.Duration),
            (Format-Duration -TimeSpan $this.ElapsedTime),
            ($this.Duration / $this.ElapsedTime))
    }
	
	[void] WriteReport([ConsoleColor] $Color, [string] $Prefix, [bool] $Force) {
        if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
            if ($this.Count -eq 0) { Write-InfoLog -Color $Color ("{0}no reencoded file" -f $Prefix) -Force:$Force; return }
            Write-InfoLog -Color $Color ($Prefix + "$($this.Count) reencoded file(s)") -Force:$Force
        }
        $size = $this.SizeReport(); if ($size) { Write-InfoLog -Color $Color $size -Force:$Force }
        if ($this.Duration -gt 0) {
            $time = $this.TimeReport(); if ($time) { Write-InfoLog -Color $Color $time -Force:$Force }
        }
    }
}

enum Upscale {
    x      = -1
    x720p  = 720
    x1080p = 1080
    x2160p = 2160
    x4320p = 4320
}

# -----------------------------------------------------------------------------
# Helpers média (internes au module)
# -----------------------------------------------------------------------------
function Set-StreamProcessingState {
    param(
		[Parameter(Mandatory)] [pscustomobject] $stream,
        [bool] $keepStream
	)
	
    $hasTrueProperty = $stream.PSObject.Properties |
        Where-Object { $_.Name -like '__*' -and $_.Value -eq $true } |
        ForEach-Object { $true } | Select-Object -First 1 -OutVariable hasResult
    if (-not $hasResult) { $hasTrueProperty = $false }

    $stream | Add-Member -NotePropertyName '__process' -NotePropertyValue $hasTrueProperty -Force
    $stream | Add-Member -NotePropertyName '__copy'    -NotePropertyValue ($keepStream -and -not $hasTrueProperty) -Force
}

function Get-FFprobeJson([string] $FFPROBE, [string] $File) {
    $ffprobeArgs = @(
		$File,
		'-v', 'quiet'
		'-show_format'
		'-show_streams'
		'-of', 'json'
	)
	
    $out = & $FFPROBE $ffprobeArgs | Out-String
    if (-not $?) { Write-ErrorLog "Can't get media info for '$File'"; return $null }
    try { 
		return (ConvertFrom-Json -InputObject $out -AsHashtable)
	} catch {
        Write-ErrorLog "Invalid ffprobe json for '$File' — $($_.Exception.Message)"; return $null
    }
}

function Invoke-FFmpeg {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
		[string] $FFMPEG,
        [Parameter(Mandatory)]
		[string] $InputFile,
		[Parameter()]
		[string[]] $DynamicArgs = @(), 
        [Parameter()]
		[string] $OutputFile,
		
        [Parameter(Mandatory)]
		[string] $TargetLabel,
        
        [Parameter(Mandatory)]
        [hashtable] $State
    )

	[bool] $IsCheckMode = [string]::IsNullOrWhiteSpace($OutputFile)

    $ffmpegArgs = @(
        '-hide_banner'
		'-v', ($IsCheckMode ? 'error' : '+level')
        '-analyzeduration', '200M'
        '-probesize', '200M'
		'-i', $InputFile
    )
    $ffmpegArgs += $DynamicArgs

    if ($IsCheckMode) {
		# ensures "null" muxer if not defined yet
        if (-not ($DynamicArgs -match '^-f$' -or $DynamicArgs -match '^null$')) {
            $ffmpegArgs += @('-f', 'null')
        }    
	} else {
        $ffmpegArgs += $OutputFile
    }

    $State.Attempts++
	Show-CommandLine $FFMPEG $ffmpegArgs -NoPathDetectionParameters 'metadata*'

    if ($PSCmdlet.ShouldProcess($TargetLabel, "ffmpeg $($IsCheckMode ? 'check' : 'run') on $TargetLabel")) {
        & $FFMPEG $ffmpegArgs
        return $?
    }
	
    Write-InfoLog -Color Magenta "[WhatIf] Would run ffmpeg ($($IsCheckMode ? 'check' : 'run')) on $TargetLabel"
    return $true
}

function Get-SortedFileList {
    param(
		[Object[]] $Files, 
		[string] $Sort
	)
	
    switch ($Sort) {
        'NewestFirst'  { $Files | Sort-Object LastWriteTime -Descending }
        'OldestFirst'  { $Files | Sort-Object LastWriteTime }
        'SmallerFirst' { $Files | Sort-Object Length }
        'LargerFirst'  { $Files | Sort-Object Length -Descending }
        default        { $Files | Sort-Object Name }
    }
}

# -----------------------------------------------------------------------------
# Fonctions privées de traitement
# -----------------------------------------------------------------------------

function Initialize-ReencodeState {
    param(
        [string] $TempPath
    )
    
    $state = @{
        ErrorLog = 'reencode-errors.log'
        BaseTempFilename = Join-Path $TempPath ([guid]::NewGuid().ToString())
        Attempts = 0
        SessionResult = [EncodingResult]::new()
    }
    
    return $state
}

function Write-ErrorLogWithFile {
    param(
        [string] $Text,
        [string] $ErrorLog
    )
    Write-ErrorLog $Text
    ("{0}: {1}" -f (Get-Date -Format 'u'), $Text) | Out-File -Append -Encoding UTF8 $ErrorLog
}

function Get-NFOTimestamps {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string] $Filename,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )
    
    $LastWriteTimeFixes = @{}
    $NFOFilename = [Path]::ChangeExtension($Filename, '.nfo')
    
    if (-not [File]::Exists($NFOFilename)) {
        return $LastWriteTimeFixes
    }
    
    $FileDirectory = Get-Item -LiteralPath ([Path]::GetDirectoryName($Filename))
    $xml = Get-Content -LiteralPath $NFOFilename -ErrorAction SilentlyContinue
    $NFO = $null
    
    if ($xml) {
        $NFO = [xml](Select-String -InputObject $xml -Pattern '.*?<([^\?^\!.]*?)>.*?</\1>').Matches.Value
    }
    
    if ($NFO) {
        try {
            $DatePremiered = $NFO.SelectSingleNode("./episodedetails") ? $NFO.episodedetails.premiered : $NFO.movie.premiered
            if ($DatePremiered) {
                $LastWriteTime = [datetime]::ParseExact($DatePremiered, "yyyy-MM-dd", $null)
                $OriginalFile = Get-Item -LiteralPath $Filename
                if ($Cmdlet.ShouldProcess($Filename, "Set original file times from premiered=$DatePremiered")) {
                    $OriginalFile.CreationTime = $LastWriteTime
                    $OriginalFile.LastWriteTime = $LastWriteTime
                }
                if ($FileDirectory.LastWriteTime -gt $LastWriteTime) {
                    $LastWriteTimeFixes[$FileDirectory] = $LastWriteTime
                }
            }
        } catch {
            Write-DebugLog "get content nfo from $NFOFilename failed"
            Write-DebugLog $_
        }
    }
    
    $NFOFilesCandidates = @(
        [Path]::Combine($FileDirectory, 'tvshow.nfo')
        [Path]::Combine([Directory]::GetParent($FileDirectory), 'tvshow.nfo')
        [Path]::Combine([Directory]::GetParent([Directory]::GetParent($FileDirectory)), 'tvshow.nfo')
    )
    
    :NFOLoop foreach ($nfoPath in $NFOFilesCandidates) {
        if ([File]::Exists($nfoPath)) {
            $n = [xml](Get-Content -LiteralPath $nfoPath -ErrorAction SilentlyContinue)
            if ($n) {
                try {
                    $DatePremiered = $n.tvshow.premiered
                    if ($DatePremiered) {
                        $LastWriteTimeFixes[(Get-Item -LiteralPath ([Path]::GetDirectoryName($nfoPath)))] =
                            [datetime]::ParseExact($DatePremiered, "yyyy-MM-dd", $null)
                    }
                    break NFOLoop
                } catch {
                    Write-DebugLog "get content nfo from $nfoPath failed"
                    Write-DebugLog $_
                }
            }
        }
    }
    
    return $LastWriteTimeFixes
}

function Select-VideoStreams {
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
    try {
		$videoStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'video' }
		$VideoTracks = $videoStreams | Select-Object codec_name, profile, height, width, disposition
		$i = -1
		
		foreach ($stream in $VideoTracks) {
			$stream | Add-Member -NotePropertyName '_index' -NotePropertyValue (++$i)
			$keepStream = -not (($stream.disposition.attached_pic -eq 1) -or ($stream.codec_name -eq 'mjpeg'))
			$isHEVC = ($stream.codec_name -ieq 'hevc') -and ($stream.profile -like 'main*')
			$keepVideoCodec = $isHEVC -or ($stream.codec_name -ieq 'av1') -or ($stream.codec_name -ieq 'vc1')
			if ($VideoCodec -eq 'AV1' -and $AllowVideoCodecUpgrade -and $isHEVC) { $keepVideoCodec = $false }
			if ($ForceRecodeVideo) { $keepVideoCodec = $false }
			
			$upscaleStream = $false
			if ($UpscaleFit -and $UpscaleWidth -ne $null -and $UpscaleHeight -ne $null) {
				$upscaleStream = ($UpscaleWidth -gt $stream.width) -and ($UpscaleHeight -gt $stream.height)
			} elseif ($Upscale) {
				if ([int][Upscale]::Parse([string]"x$Upscale").value__ -gt $stream.height) {
					$upscaleStream = $true
				}
				if ([int][Upscale]::Parse([string]"x$Upscale").value__ -eq $stream.height) {
					$upscaleStream = ($ConfigUpscaleWidth -ne -1) -and ($ConfigUpscaleWidth -ne $stream.width)
				}
			} else {
				if ($ConfigUpscaleWidth -gt $stream.width) { $upscaleStream = $true }
			}
			
			if ($RewriteMode) {
				$stream | Add-Member -NotePropertyName '__deinterlace' -NotePropertyValue $false -Force
				$stream | Add-Member -NotePropertyName '__upscale' -NotePropertyValue $false -Force
				$stream | Add-Member -NotePropertyName '__recode' -NotePropertyValue $false -Force
			} else {
				$stream | Add-Member -NotePropertyName '__deinterlace' -NotePropertyValue ($keepStream -and $Deinterlace) -Force
				$stream | Add-Member -NotePropertyName '__upscale' -NotePropertyValue ($keepStream -and $upscaleStream) -Force
				$stream | Add-Member -NotePropertyName '__recode' -NotePropertyValue ($keepStream -and -not $keepVideoCodec) -Force
			}

			Set-StreamProcessingState $stream $keepStream | Out-Null
		}
		
		$isSource10Bit = @($videoStreams | Where-Object { Test-Is10BitVideoStream $_ }).Count -gt 0
		
		$chromaRank = @{ '420' = 0; '422' = 1; '444' = 2 }
		$sourceChroma = '420'
		foreach ($vs in $videoStreams) {
			$c = Get-SourceChromaMode $vs
			if ($chromaRank[$c] -gt $chromaRank[$sourceChroma]) {
				$sourceChroma = $c
			}
		}
		
		Write-Verbose "Select-VideoStreams >>`n $($VideoTracks | Format-List | Out-String)"
		return @{
			VideoTracks = $VideoTracks
			IsSource10Bit = $isSource10Bit
			SourceChroma = $sourceChroma
		}
	}
	catch {
		Write-Verbose "EE Select-VideoStreams >>`n ($_.Exception)"
		throw
	}
}

function Select-AudioStreams {
    param(
        [hashtable] $FfprobeOutput,
        [string] $FinalExtension,
        [string] $Quality,
        [bool] $RewriteMode
    )
    Write-Verbose ">> Select-AudioStreams"
	try {
		$audioStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'audio' }
		$AudioTracks = $audioStreams | Select-Object codec_name, channels, channel_layout, bit_rate
		$targetAudioCodec = Get-TargetAudioCodec -FinalExtension $FinalExtension
		$i = -1
		
		foreach ($stream in $AudioTracks) {
			$stream | Add-Member -NotePropertyName '_index' -NotePropertyValue (++$i) -Force
			
			$codec = [string]$stream.codec_name
			
			$recodeForContainer = ($codec -ieq 'nellymoser')
			if ($FinalExtension -ieq '.mp4') {
				$recodeForContainer = $recodeForContainer -or
					($codec -ieq 'flac') -or
					($codec -ilike 'wm*') -or
					($codec -in 'pcm_u8','adpcm_ima_wav')
			}
			
			$channels = if ($stream.channels) { [int]$stream.channels } else { 2 }
			$currentBps = if ($stream.bit_rate) { [int]$stream.bit_rate } else { 0 }
			$layout = [string]$stream.channel_layout
			
			$isLossless = Test-IsLosslessAudioCodec $codec
			
			$targetBitrateLabel = Get-TargetAudioBitrate -Codec $targetAudioCodec -Quality $Quality -Channels $channels
			$targetBps = ConvertTo-IntBitrateK $targetBitrateLabel
			
			$hasGain = ($currentBps -gt 0) -and ($targetBps -gt 0) -and ($targetBps -lt [int]($currentBps / 1.05))
			
			$likelyGainCodecs = @('dts','eac3','ac3','truehd')
			$alreadyTargetNoGain =
				($codec -ieq $targetAudioCodec) -and (
					($currentBps -le 0) -or
					($targetBps -gt 0 -and $currentBps -le $targetBps)
				)
			
			$recodeForQuality = switch ($Quality) {
				'High'   { $isLossless }
				'Medium' { $isLossless }
				'Low'    {
					if ($alreadyTargetNoGain) { $false }
					if ($isLossless) { $true }
					if ($hasGain) { $true }
					if ($likelyGainCodecs -contains ($codec.ToLowerInvariant())) { $true }
					$false
				}
				default  { $isLossless }
			}
			
			$opusLayoutFix = $null
			if ($targetAudioCodec -eq 'opus' -and $layout -match 'side') {
				if ($channels -eq 5) {
					$opusLayoutFix = "channelmap=FL-FL|FR-FR|FC-FC|SL-BL|SR-BR:5.0"
				}
				elseif ($channels -eq 6) {
					$opusLayoutFix = "channelmap=FL-FL|FR-FR|FC-FC|LFE-LFE|SL-BL|SR-BR:5.1"
				}
			}

			$recode = if ($RewriteMode) { $false } else { $recodeForContainer -or $recodeForQuality }
			$stream | Add-Member -NotePropertyName '__recode' -NotePropertyValue $recode -Force
			
			if ($recode) {
				$stream | Add-Member -NotePropertyName '__targetAudioCodec' -NotePropertyValue $targetAudioCodec -Force
				$stream | Add-Member -NotePropertyName '__targetAudioBitrate' -NotePropertyValue $targetBitrateLabel -Force
			
				if ($opusLayoutFix) {
					$stream | Add-Member -NotePropertyName '__targetAudioFilter' -NotePropertyValue $opusLayoutFix -Force
				}
			}
			
			Set-StreamProcessingState $stream $true | Out-Null
		}
		
		Write-Verbose "Select-AudioStreams >>`n $($AudioTracks | Format-List | Out-String)"
		return $AudioTracks
	}
	catch {
		Write-Verbose "EE Select-AudioStreams`n ($_.Exception)"
		throw
	}
}

function Select-SubtitleStreams {
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
	try {
		$subtitleStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'subtitle' }
		$SubtitleTracks = $subtitleStreams | Select-Object codec_name, tags
		
		if (-not $RewriteMode) {
			if ($SubtitleTracks -and $FinalExtension -ieq '.mp4' -and -not $AllowSubTitlesConversion) {
				return $null
			}
		}
		
		$assSubtitles = $SubtitleTracks | Where-Object { $_.codec_name -eq 'ass' }
		if (-not $assSubtitles) {
			$BaseName = [Path]::GetFileNameWithoutExtension($Filename)
			$assSubtitles = Get-ChildItem -Path $DirectoryName -Filter "$BaseName.*.ass"
		}
		if (-not $RewriteMode) {
			if ($assSubtitles -and $FinalExtension -ieq '.mp4' -and $AllowSubTitlesConversion) {
				return $null
			}
		}
		
		$i = -1
		foreach ($stream in $SubtitleTracks) {
			$stream | Add-Member -NotePropertyName '_index' -NotePropertyValue (++$i)
			if (-not ($stream.PSObject.Properties.Name -contains "tags") -or -not ($stream.tags.Keys -contains "language")) {
				$keepStream = $true
			} else {
				$keepStream = [bool]((@('un','und') + $SubTitlesToKeep) | Where-Object { $_ -ieq $stream.tags.language })
			}
			if ($RewriteMode -and $FinalExtension -ieq '.mp4') {
				# En rewrite, seul mov_text peut être copié dans un conteneur mp4
				$keepStream = $keepStream -and ($stream.codec_name -ieq 'mov_text')
			}
			$recode = if ($RewriteMode) { $false } else { $FinalExtension -ieq '.mp4' -and $AllowSubTitlesConversion }
			$stream | Add-Member -NotePropertyName '__recode' -NotePropertyValue ($keepStream -and $recode) -Force

			Set-StreamProcessingState $stream $keepStream | Out-Null
		}
		
		Write-Verbose "Select-SubtitleStreams >>`n $($SubtitleTracks | Format-List | Out-String)"
		return @{
			SubtitleTracks = $SubtitleTracks
			HasAssSubtitles = [bool]($SubtitleTracks | Where-Object { $_.codec_name -eq 'ass' -and ($_.__copy -or $_.__process) })
		}
	}
	catch {
		Write-Verbose "EE Select-SubtitleStreams >>`n ($_.Exception)"
		throw
	}
}

function Select-AttachmentStreams {
    param(
        [hashtable] $FfprobeOutput,
        [bool] $HasAssSubtitles
    )
    Write-Verbose ">> Select-AttachmentStreams"
	try {
		$attachmentStreams = @($FfprobeOutput.streams) | Where-Object { $_.codec_type -eq 'attachment' }
		$AttachmentTracks = $attachmentStreams | Select-Object codec_name, tags
		$i = -1
		foreach ($stream in $AttachmentTracks) {
			$stream | Add-Member -NotePropertyName '_index' -NotePropertyValue (++$i)
			$isFont = ($stream.codec_name -in @('ttf', 'otf')) -or
			          ($stream.tags.mimetype -match '\bfont\b|truetype|opentype') -or
			          ($stream.tags.filename -match '\.(ttf|otf|woff2?|ttc)$')
			$keepStream = (-not $isFont) -or $HasAssSubtitles
			Set-StreamProcessingState $stream $keepStream | Out-Null
		}
		
		Write-Verbose "Select-AttachmentStreams >>`n $($AttachmentTracks | Format-List | Out-String)"
		return $AttachmentTracks
	}
	catch {
		Write-Verbose "EE Select-AttachmentStreams >>`n ($_.Exception)"
		throw
	}
}

function Get-VideoEncoderArgs {
    param(
        [ValidateSet('HEVC', 'AV1')] [string] $VideoCodec,
        [ValidateSet('Low','Medium','High')] [string] $Quality,
        [bool] $TargetIs10Bit,
        [string] $PixFmt,
        [int] $StreamIndex
    )

    $codec = switch ($VideoCodec) {
        'AV1' { 'libsvtav1' }
        default { 'libx265' }
    }
    $crf = switch ($VideoCodec) {
        'AV1' { switch ($Quality) { 'High' {24} 'Medium' {28} 'Low' {36} default {28} } }
        default { switch ($Quality) { 'High' {18} 'Medium' {21} 'Low' {28} default {21} } }
    }
    $preset = switch ($VideoCodec) {
        'AV1' { switch ($Quality) { 'High' {4} 'Medium' {6} 'Low' {8} default {6} } }
        default { switch ($Quality) { 'High' { 'slow' } 'Medium' { 'medium' } 'Low' { 'fast' } default { 'medium' } } }
    }

    $cpuArgs = @(
        "-c:v:$StreamIndex", $codec
        "-crf:v:$StreamIndex", $crf
        "-preset:v:$StreamIndex", $preset
        "-pix_fmt:v:$StreamIndex", $PixFmt
    )

    if ($VideoCodec -eq 'AV1') {
        $cpuArgs += @("-svtav1-params:v:$StreamIndex", 'tune=0')
    }
    if ($VideoCodec -eq 'HEVC') {
        $x265Profile = if ($PixFmt -like 'yuv444*') {
            ($TargetIs10Bit ? 'main444-10' : 'main444-8')
        } elseif ($PixFmt -like 'yuv422*') {
            ($TargetIs10Bit ? 'main422-10' : 'main422-8')
        } else {
            ($TargetIs10Bit ? 'main10' : 'main')
        }
        $cpuArgs += @("-profile:v:$StreamIndex", $x265Profile)
    }

    return $cpuArgs
}

function Get-AudioEncoderArgs {
    param(
        [int] $StreamIndex,
        [bool] $Process,
        [string] $TargetCodec,
        [string] $TargetBitrate,
        [string] $ChannelMapFilter
    )

    if (-not $Process) {
        return @("-c:a:$StreamIndex", 'copy')
    }

    $args = @(
        "-c:a:$StreamIndex", ($TargetCodec -eq 'opus' ? 'libopus' : 'aac')
        "-b:a:$StreamIndex", $TargetBitrate
    )
    if ($ChannelMapFilter) {
        $args += @("-filter:a:$StreamIndex", $ChannelMapFilter)
    }
    if ($TargetCodec -eq 'opus') {
        $args += @(
            "-vbr:a:$StreamIndex", 'on'
            "-compression_level:a:$StreamIndex", '10'
            "-application:a:$StreamIndex", 'audio'
        )
    }

    return $args
}

function Get-FFmpegArgs {
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
    
    $targetIs10Bit = switch ($Quality) {
        'High'   { $true }
        'Medium' { $IsSource10Bit }
        'Low'    { $false }
        default  { $IsSource10Bit }
    }
    
    $targetChroma = switch ($Quality) {
        'Low'    { '420' }
        default  { $SourceChroma }
    }
    
    $pixFmt = switch ($targetChroma) {
        '444' { if ($targetIs10Bit) { 'yuv444p10le' } else { 'yuv444p' } }
        '422' { if ($targetIs10Bit) { 'yuv422p10le' } else { 'yuv422p' } }
        default { if ($targetIs10Bit) { 'yuv420p10le' } else { 'yuv420p' } }
    }
    
    $ffmpegArgs = @()
    
    $SelectedVideoTracks = ($VideoTracks ?? @()) | Where-Object { $_.__process -or $_.__copy } | Select-Object _index, __process, __deinterlace, __upscale
	Write-Verbose "SelectedVideoTracks:`n $($SelectedVideoTracks | Format-List | Out-String)"
    $new_index = 0
    foreach ($stream in $SelectedVideoTracks) {
        $ffmpegArgs += @(
            '-map', "0:v:$($stream._index)"
        )
        if ($stream.__process) {
            $filters = @()
            if ($stream.__deinterlace) { $filters += 'yadif=0' }
            if ($stream.__upscale) {
                if ($UpscaleFit -and $UpscaleWidth -ne $null -and $UpscaleHeight -ne $null) {
                    $filters += "scale=w=$UpscaleWidth:h=$UpscaleHeight:force_original_aspect_ratio=decrease:flags=lanczos"
                } else {
                    $targetH = ([int][Upscale]::Parse([string]"x$Upscale")).value__
                    $filters += ('scale={0}:{1}:flags=lanczos' -f $ConfigUpscaleWidth, $targetH)
                }
            }
            if ($filters.Count -gt 0) {
                $ffmpegArgs += @("-vf:v:$new_index", ($filters -join ','))
            }
            $ffmpegArgs += Get-VideoEncoderArgs `
                -VideoCodec $VideoCodec `
                -Quality $Quality `
                -TargetIs10Bit $targetIs10Bit `
                -PixFmt $pixFmt `
                -StreamIndex $new_index
        } else {
            $ffmpegArgs += @("-c:v:$new_index", 'copy')
        }
        $new_index++
    }
    
    $SelectedAudioTracks = ($AudioTracks ?? @()) | Where-Object { $_.__process -or $_.__copy } | Select-Object _index, __process, __targetAudioCodec, __targetAudioBitrate, __targetAudioFilter
	Write-Verbose "SelectedAudioTracks:`n $($SelectedAudioTracks | Format-List | Out-String)"
    $new_index = 0
    foreach ($stream in $SelectedAudioTracks) {
        $ffmpegArgs += @('-map', "0:a:$($stream._index)")
        $ffmpegArgs += Get-AudioEncoderArgs `
            -StreamIndex $new_index `
            -Process ([bool]$stream.__process) `
            -TargetCodec ([string]$stream.__targetAudioCodec) `
            -TargetBitrate ([string]$stream.__targetAudioBitrate) `
            -ChannelMapFilter ([string]$stream.__targetAudioFilter)
        
        $new_index++
    }
    
    $SelectedSubtitleTracks = ($SubtitleTracks ?? @()) | Where-Object { $_.__process -or $_.__copy } | Select-Object _index, __process
	Write-Verbose "SelectedSubtitleTracks:`n $($SelectedSubtitleTracks | Format-List | Out-String)"
    $new_index = 0
    foreach ($stream in $SelectedSubtitleTracks) {
        $ffmpegArgs += @(
            '-map', "0:s:$($stream._index)"
            "-c:s:$new_index", ($stream.__process ? 'mov_text' : 'copy')
        )
        $new_index++
    }
    
    $SelectedAttachmentTracks = ($AttachmentTracks ?? @()) | Where-Object { $_.__copy } | Select-Object _index
	Write-Verbose "SelectedAttachmentTracks:`n $($SelectedAttachmentTracks | Format-List | Out-String)"
    $new_index = 0
    foreach ($stream in $SelectedAttachmentTracks) {
        $ffmpegArgs += @(
            '-map', "0:t:$($stream._index)"
            "-c:t:$new_index", 'copy'
        )
        $new_index++
    }
    
    $ffmpegArgs += @(
        '-map_metadata', '0'
        '-metadata', 'MOVIE/ENCODER='
        $(if ($ClearStreamsTitle) { @('-metadata:s','title=') })
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

function Invoke-ReencodeFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string] $Filename,
        [hashtable] $State,
        [hashtable] $Config,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )
    Write-Verbose "Starting analysis of '$Filename'"
	
    $OriginalFile = Get-Item -LiteralPath $Filename
    if (-not $OriginalFile) {
        Write-ErrorLogWithFile -Text "Can't get access to '$Filename'" -ErrorLog $State.ErrorLog
        return
    }
    
    $TempFilename = ""
    
    try {
        if ($OriginalFile.IsReadOnly) {
            Write-InfoLog "Skip read-only file '$Filename'"
            return
        }
        $OriginalFileSize = $OriginalFile.Length
        
        $LastWriteTimeFixes = Get-NFOTimestamps -Filename $Filename -Cmdlet $Cmdlet
        
        $OriginalFileCreationTime = $OriginalFile.CreationTime
        $OriginalFileLastWriteTime = $OriginalFile.LastWriteTime
        $OriginalFileLastAccessTime = $OriginalFile.LastAccessTime
        
        foreach ($item in $LastWriteTimeFixes.GetEnumerator()) {
            if ($Cmdlet.ShouldProcess($item.Key.FullName, "Fix directory times from premiered")) {
                $item.Key.CreationTime = $item.Value
                $item.Key.LastWriteTime = $item.Value
            }
        }
        
        $ffprobeOutput = Get-FFprobeJson -FFPROBE $Config.FFPROBEPath -File $Filename
        if (-not $ffprobeOutput) { return }
        
        if (-not ($ffprobeOutput.format.Keys -contains "duration") -and -not $Config.ForceRecodeVideo -and -not $Config.Rewrite) {
            Write-InfoLog "Skip '$Filename' that does not look like a convertable format"
            return
        }
        
        if ($Config.CheckOnly) {
            $ok = Invoke-FFmpeg -FFMPEG $Config.FFMPEGPath `
                -InputFile $Filename `
                -DynamicArgs @() `
                -TargetLabel $Filename `
                -State $State
            if (-not $ok) {
                Write-ErrorLogWithFile -Text "ffmpeg check failed for '$Filename'" -ErrorLog $State.ErrorLog
            }
            return
        }
        
        $FinalExtension = ($Config.KeepExtension ? $OriginalFile.Extension : $Config.OutputExtension)
        
        $videoResult = Select-VideoStreams `
            -FfprobeOutput $ffprobeOutput `
            -ForceRecodeVideo $Config.ForceRecodeVideo `
            -VideoCodec $Config.VideoCodec `
            -AllowVideoCodecUpgrade $Config.AllowVideoCodecUpgrade `
            -Deinterlace $Config.Deinterlace `
            -Upscale $Config.Upscale `
            -UpscaleWidth $Config.UpscaleWidth `
            -UpscaleHeight $Config.UpscaleHeight `
            -UpscaleFit $Config.UpscaleFit `
            -ConfigUpscaleWidth $Config.UpscaleWidth `
            -RewriteMode $Config.Rewrite
        
        $AudioTracks = Select-AudioStreams `
            -FfprobeOutput $ffprobeOutput `
            -FinalExtension $FinalExtension `
            -Quality $Config.Quality `
            -RewriteMode $Config.Rewrite
        
        $subtitleResult = Select-SubtitleStreams `
            -FfprobeOutput $ffprobeOutput `
            -FinalExtension $FinalExtension `
            -AllowSubTitlesConversion $Config.AllowSubTitlesConversion `
            -RewriteMode $Config.Rewrite `
            -SubTitlesToKeep $Config.SubTitlesToKeep `
            -Filename $Filename `
            -DirectoryName $OriginalFile.DirectoryName
        
        if ($null -eq $subtitleResult) {
            $subtitleStreams = $ffprobeOutput.streams | Where-Object { $_.codec_type -eq 'subtitle' }
            $SubtitleTracks = $subtitleStreams | Select-Object codec_name, tags
            if ($SubtitleTracks -and $FinalExtension -ieq '.mp4' -and -not $Config.AllowSubTitlesConversion) {
                Write-InfoLog -Color Yellow "Skip '$Filename' because $FinalExtension format requires subtitles conversion"
            } else {
                Write-InfoLog -Color Yellow "Skip '$Filename' because ass subtitles cannot be properly converted"
            }
            return
        }
        
        $AttachmentTracks = Select-AttachmentStreams `
            -FfprobeOutput $ffprobeOutput `
            -HasAssSubtitles $subtitleResult.HasAssSubtitles
		
        $hasVideoToConvert = @(@($videoResult.VideoTracks) | Where-Object { -not $_.__copy }).Count
        $hasAudioToConvert = @(@($AudioTracks) | Where-Object { -not $_.__copy }).Count
        $hasSubtitlesToConvert = @(@($subtitleResult.SubtitleTracks) | Where-Object { -not $_.__copy }).Count
        
        $hasTracksDropped = (
            @(@($videoResult.VideoTracks) | Where-Object { -not $_.__copy -and -not $_.__process }).Count -gt 0 -or
            @(@($AudioTracks) | Where-Object { -not $_.__copy -and -not $_.__process }).Count -gt 0 -or
            @(@($subtitleResult.SubtitleTracks) | Where-Object { -not $_.__copy -and -not $_.__process }).Count -gt 0
        )
        
        if ($Config.Rewrite) {
            if (-not $hasTracksDropped) {
                Write-InfoLog "No stream filtering needed for '$Filename'"
                return
            }
        } else {
            if (($hasVideoToConvert -eq 0) -and ($hasAudioToConvert -eq 0) -and ($hasSubtitlesToConvert -eq 0) -and
                ($OriginalFile.Extension -ieq $FinalExtension) -and -not $hasTracksDropped) {
                Write-InfoLog "No reencoding needed for '$Filename'"
                return
            }
        }
        
        $mediaDuration = ($ffprobeOutput.format.Keys -contains "duration") ? $ffprobeOutput.format.duration : 0
        
        $NewFilename = $OriginalFile.BaseName + $FinalExtension
        $TempFilename = $State.BaseTempFilename + $FinalExtension
        $NewFilePath = Join-Path -Path $OriginalFile.DirectoryName -ChildPath $NewFilename
        
        if (([string]$OriginalFile.FullName -ne $NewFilePath) -and [File]::Exists($NewFilePath)) {
            Write-InfoLog -Color Yellow "Skip '$Filename' to avoid already existing file override" -Force
            return
        }
        
        Write-InfoLog "Processing '$Filename'..." -Force
        if (Test-Path $TempFilename -PathType Leaf) {
            if ($Cmdlet.ShouldProcess($TempFilename, 'Remove temp file')) {
                Remove-Item $TempFilename -Force
            }
        }
        
        $ffmpegArgs = Get-FFmpegArgs `
            -VideoCodec $Config.VideoCodec `
            -Quality $Config.Quality `
            -Upscale $Config.Upscale `
            -UpscaleWidth $Config.UpscaleWidth `
            -UpscaleHeight $Config.UpscaleHeight `
            -UpscaleFit $Config.UpscaleFit `
            -ConfigUpscaleWidth $Config.UpscaleWidth `
            -ClearStreamsTitle $Config.ClearStreamsTitle `
            -VideoTracks $videoResult.VideoTracks `
            -IsSource10Bit $videoResult.IsSource10Bit `
            -SourceChroma $videoResult.SourceChroma `
            -AudioTracks $AudioTracks `
            -SubtitleTracks $subtitleResult.SubtitleTracks `
            -AttachmentTracks $AttachmentTracks
        
        $start = Get-Date
        $ok = Invoke-FFmpeg -FFMPEG $Config.FFMPEGPath `
            -InputFile $Filename `
            -DynamicArgs $ffmpegArgs `
            -OutputFile $TempFilename `
            -TargetLabel $Filename `
            -State $State
        
        if (-not $ok) { return }
        
        if ($Cmdlet.ShouldProcess($TempFilename, "Move temp over original '$Filename'")) {
            Move-Item -Path $TempFilename -Destination $Filename -Force
        }
        
        $NewFile = Get-Item -LiteralPath $Filename
        if ($NewFile) {
            if ($Cmdlet.ShouldProcess($NewFile.FullName, "Rename to '$NewFilename'")) {
                $NewFile = $NewFile | Rename-Item -NewName $NewFilename -Force -PassThru
            }
            if ($Cmdlet.ShouldProcess($NewFile.FullName, "Restore timestamps")) {
                $NewFile.CreationTime = $OriginalFileCreationTime
                $NewFile.LastWriteTime = $OriginalFileLastWriteTime
                $NewFile.LastAccessTime = $OriginalFileLastAccessTime
            }
            foreach ($item in $LastWriteTimeFixes.GetEnumerator()) {
                if ($Cmdlet.ShouldProcess($item.Key.FullName, "Fix directory times (post)")) {
                    $item.Key.CreationTime = $item.Value
                    $item.Key.LastWriteTime = $item.Value
                }
            }
            
            $NewFileSize = $NewFile.Length
            $Result = if ($mediaDuration) {
                $Duration = [TimeSpan]::FromSeconds([double]::Parse($mediaDuration, [cultureinfo] ''))
                [EncodingResult]::new($OriginalFileSize, $NewFileSize, $Duration, (Get-Date) - $start)
            } else {
                [EncodingResult]::new($OriginalFileSize, $NewFileSize)
            }
            
            Write-Log -Color Magenta "Successfully reencoded $Filename"
            if ($NewFile.FullName -ne $Filename) {
                Write-Log -Color Magenta "                    to $($NewFile.FullName)"
            }
            $Result.WriteReport('Magenta', '', $true)
            
            $State.SessionResult.Add($Result)
			if ($State.SessionResult.Count -gt 1) {
				$State.SessionResult.WriteReport('DarkMagenta', 'So far, ', $true)
			}
        }
    }
    catch {
        Write-ErrorLogWithFile -Text "Error while treating $($OriginalFile.FullName)" -ErrorLog $State.ErrorLog
		Write-Verbose $_.Exception
        throw
    }
    finally {
        if ([System.IO.File]::Exists($TempFilename)) {
            if ($Cmdlet.ShouldProcess($TempFilename, 'Cleanup temp file')) {
                Remove-Item $TempFilename -Force
            }
        }
    }
}

function Invoke-PathScan {
    param(
        [ValidateScript({ Test-Path $_ }, ErrorMessage = "{0} is not a valid path")]
        [string] $Path = "",
        [switch] $Recurse,
        [switch] $SubPath,
        [hashtable] $State,
        [hashtable] $Config,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )
    
    $LiteralPath = $Path
    if ($SubPath) { $LiteralPath = [Management.Automation.WildcardPattern]::Unescape($LiteralPath) }
    
    if (-not [File]::Exists($LiteralPath)) {
        if (-not $SubPath) {
            Write-InfoLog "Scanning '$LiteralPath' $($Recurse ? 'recursively' : '')..."
        }
        if ($Recurse) {
            Get-SortedFileList (Get-ChildItem -Path $LiteralPath -Directory -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -ine "Plex Versions" -and $_.Name -ine ".deletedByTMM" }) $Config.Sort |
            ForEach-Object {
                $NotReadOnly = ($_.Attributes -band [FileAttributes]::ReadOnly) -ne [FileAttributes]::ReadOnly
                if ($NotReadOnly -or $Config.ScanReadOnlyDirectory) {
                    Invoke-PathScan -Path ([Management.Automation.WildcardPattern]::Escape($_.FullName)) -Recurse -SubPath -State $State -Config $Config -Cmdlet $Cmdlet
                }
            }
        }
    }
    
    if ([Directory]::Exists($LiteralPath) -and -not $LiteralPath.EndsWith('*')) {
        if ((Get-ChildItem -LiteralPath $LiteralPath -Include $Config.InputMasks -Force | Select-Object -First 1 | Measure-Object).Count -eq 0) {
            return
        }
        $LiteralPath = [Management.Automation.WildcardPattern]::Escape($LiteralPath) + '\*'
    }
    
    Get-SortedFileList (Get-ChildItem -Path $LiteralPath -File -Attributes !ReadOnly -Include $Config.InputMasks -Force -ErrorAction SilentlyContinue) $Config.Sort |
    ForEach-Object {
        if (-not ([string]$_.FullName).Contains('-trailer.', [StringComparison]::InvariantCultureIgnoreCase)) {
            Invoke-ReencodeFile -Filename $_.FullName -State $State -Config $Config -Cmdlet $Cmdlet
        }
    }
}

function Invoke-PathList {
    param(
        [string[]] $Paths,
        [hashtable] $State,
        [hashtable] $Config,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )
    
    foreach ($PathItem in $Paths) {
        $DoRecurse = ([string]$PathItem).StartsWith('+')
        $p = ([string]$PathItem).Substring(($DoRecurse ? 1 : 0))
        Invoke-PathScan -Path $p -Recurse:($Config.Recurse -or $DoRecurse) -State $State -Config $Config -Cmdlet $Cmdlet
    }
}

function Invoke-FileList {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string] $ListFile,
        [hashtable] $State,
        [hashtable] $Config,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )
    
    Write-InfoLog -Color Blue "Using file list in '$ListFile'..."
    $ListContent = Get-Content $ListFile
    
    $ListContent | ForEach-Object {
        $currentLine = [string]$_
        $DoRecurse = $currentLine.StartsWith('+')
        $p = $currentLine.Substring(($DoRecurse ? 1 : 0))
        Invoke-PathScan -Path $p -Recurse:($Config.Recurse -or $DoRecurse) -State $State -Config $Config -Cmdlet $Cmdlet
        
        if ($Config.UpdateList) {
            if ($Cmdlet.ShouldProcess($ListFile, "Remove processed entry")) {
                $NewListContent = Get-Content $ListFile | Where-Object { [string]$_ -ne $currentLine }
                Set-Content $ListFile -Value $NewListContent
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Fonction publique
# -----------------------------------------------------------------------------
function Invoke-ReencodeMedia {
    [CmdletBinding(
        PositionalBinding = $false,
        DefaultParametersetName = 'SetExtensionFromPath',
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    param (
        [Parameter(Position = 0, ParameterSetName = 'CheckFromPath')]
        [Parameter(Position = 0, ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(Position = 0, ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(Position = 0, ParameterSetName = 'RewriteFromPath')]
        [string[]] $Path = ".",
        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [switch] $Recurse,

        [Parameter(Mandatory, ParameterSetName = 'CheckFromFile')]
        [Parameter(Mandatory, ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(Mandatory, ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(Mandatory, ParameterSetName = 'RewriteFromFile')]
        [ValidateScript({ [File]::Exists($_) }, ErrorMessage = "{0} is not a valid filename")]
        [string] $ListFile,
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [switch] $UpdateList,

        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [ValidateSet('NewestFirst','OldestFirst','SmallerFirst','LargerFirst')]
        [string] $Sort,

        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [switch] $ScanReadOnlyDirectory,

        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [ValidateNotNullOrEmpty()]
        [string[]] $InputMasks = @('*.mkv', '*.mp4', '*.avi', '*.wmv', '*.mov', '*.flv', '*.mpeg', '*.mpg', '*.heic', '*.ts', '*.webm'),

        [Parameter(Mandatory, ParameterSetName = 'RewriteFromPath')]
        [Parameter(Mandatory, ParameterSetName = 'RewriteFromFile')]
        [switch] $Rewrite,

        [Parameter(Mandatory, ParameterSetName = 'CheckFromPath')]
        [Parameter(Mandatory, ParameterSetName = 'CheckFromFile')]
        [switch] $CheckOnly,

        [Parameter(Mandatory, ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(Mandatory, ParameterSetName = 'KeepExtensionFromFile')]
        [switch] $KeepExtension,

        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [ValidateScript({ $_ -match '^\.[^.\\/:*?"<>|\r\n]+$' }, ErrorMessage = "{0} is not a valid extension with a leading point")]
        [string] $OutputExtension = '.mkv',

        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [ValidateSet('HEVC', 'AV1')]
        [string] $VideoCodec = 'HEVC',
        
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [switch] $ClearStreamsTitle,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [switch] $ForceRecodeVideo,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [switch] $AllowVideoCodecUpgrade,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [ValidateSet('Low','Medium','High')]
        [string] $Quality = 'Medium',
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [ValidateSet('720p','1080p','2160p','4320p')]
        [string] $Upscale,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [ValidateScript({ ($_ -eq -1) -or ($_ -gt 0) })]
        [int] $UpscaleWidth = -1,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath', Mandatory = $false)]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile', Mandatory = $false)]
        [Parameter(ParameterSetName = 'SetExtensionFromPath', Mandatory = $false)]
        [Parameter(ParameterSetName = 'SetExtensionFromFile', Mandatory = $false)]
        [ValidatePattern('^\d+[xX]\d+$')]
        [string] $UpscaleFit,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [switch] $Deinterlace,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [switch] $AllowSubTitlesConversion,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [string[]] $SubTitlesToKeep = @('fr','fre','fr-FR','en','eng','en-US','en-GB'),

        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [ValidateScript({ [Directory]::Exists($_) }, ErrorMessage = "{0} is not a valid path")]
        [string] $TempPath = $env:TEMP,

		[Parameter(ParameterSetName = 'CheckFromPath')]
		[Parameter(ParameterSetName = 'CheckFromFile')]
		[Parameter(ParameterSetName = 'KeepExtensionFromPath')]
		[Parameter(ParameterSetName = 'KeepExtensionFromFile')]
		[Parameter(ParameterSetName = 'SetExtensionFromPath')]
		[Parameter(ParameterSetName = 'SetExtensionFromFile')]
		[Parameter(ParameterSetName = 'RewriteFromPath')]
		[Parameter(ParameterSetName = 'RewriteFromFile')]
		[ValidateScript({ [System.IO.Directory]::Exists($_) }, ErrorMessage = "{0} is not a valid folder")]
		[string] $FFToolsBase = '.\',

		[Parameter(ParameterSetName = 'CheckFromPath')]
		[Parameter(ParameterSetName = 'CheckFromFile')]
		[Parameter(ParameterSetName = 'KeepExtensionFromPath')]
		[Parameter(ParameterSetName = 'KeepExtensionFromFile')]
		[Parameter(ParameterSetName = 'SetExtensionFromPath')]
		[Parameter(ParameterSetName = 'SetExtensionFromFile')]
		[Parameter(ParameterSetName = 'RewriteFromPath')]
		[Parameter(ParameterSetName = 'RewriteFromFile')]
		[ValidateScript({ [System.IO.File]::Exists($_) }, ErrorMessage = "{0} is not a valid filename")]
		[string] $FFMPEGPath = (Join-Path $FFToolsBase ($IsWindows ? 'ffmpeg.exe'  : 'ffmpeg')),

		[Parameter(ParameterSetName = 'CheckFromPath')]
		[Parameter(ParameterSetName = 'CheckFromFile')]
		[Parameter(ParameterSetName = 'KeepExtensionFromPath')]
		[Parameter(ParameterSetName = 'KeepExtensionFromFile')]
		[Parameter(ParameterSetName = 'SetExtensionFromPath')]
		[Parameter(ParameterSetName = 'SetExtensionFromFile')]
		[Parameter(ParameterSetName = 'RewriteFromPath')]
		[Parameter(ParameterSetName = 'RewriteFromFile')]
		[ValidateScript({ [System.IO.File]::Exists($_) }, ErrorMessage = "{0} is not a valid filename")]
		[string] $FFPROBEPath = (Join-Path $FFToolsBase ($IsWindows ? 'ffprobe.exe' : 'ffprobe'))
    )

    $state = Initialize-ReencodeState -TempPath $TempPath
    
    $upscaleWidth = $UpscaleWidth
    $upscaleHeight = $null
    if ($UpscaleFit) {
        $parts = $UpscaleFit -split '[xX]'
        $upscaleWidth = [int]$parts[0]
        $upscaleHeight = [int]$parts[1]
    }

    $resolvedFFmpegPath = Get-FFmpegPath -OverridePath $FFMPEGPath
    $resolvedFFprobePath = Get-FfprobePath -OverridePath $FFPROBEPath
    
    $config = @{
        # Parcours / sélection
        Recurse = $Recurse
        Sort = $Sort
        ScanReadOnlyDirectory = $ScanReadOnlyDirectory
        InputMasks = $InputMasks

        # Mode / format cible
        CheckOnly = $CheckOnly
        Rewrite = [bool]$Rewrite
        KeepExtension = [bool]$Rewrite -or [bool]$KeepExtension
        OutputExtension = $OutputExtension

        # Vidéo
        VideoCodec = $VideoCodec
        ForceRecodeVideo = $ForceRecodeVideo
        AllowVideoCodecUpgrade = $AllowVideoCodecUpgrade
        Quality = $Quality
        Deinterlace = $Deinterlace
        Upscale = $Upscale
        UpscaleWidth = $upscaleWidth
        UpscaleHeight = $upscaleHeight
        UpscaleFit = $UpscaleFit

        # Sous-titres / metadata
        AllowSubTitlesConversion = $AllowSubTitlesConversion
        SubTitlesToKeep = $SubTitlesToKeep
        ClearStreamsTitle = $ClearStreamsTitle

        # Liste
        UpdateList = $UpdateList

        # Outils
        FFMPEGPath = $resolvedFFmpegPath
        FFPROBEPath = $resolvedFFprobePath
    }

    try {
        if ($ListFile) {
            Invoke-FileList -ListFile $ListFile -State $state -Config $config -Cmdlet $PSCmdlet
        } else {
            Invoke-PathList -Paths $Path -State $state -Config $config -Cmdlet $PSCmdlet
        }
    }
    finally {
        $state.SessionResult.WriteReport('Green', 'This session, ', $true)
        Write-InfoLog -Color Green "On $($state.Attempts) ffmpeg invocation(s)" -Force
    }
}

Export-ModuleMember -Function Invoke-ReencodeMedia
