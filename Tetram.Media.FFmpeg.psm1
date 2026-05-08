Set-StrictMode -Version 3.0

$script:FFToolsDefaultBase = Join-Path $PSScriptRoot 'RecodeVideo\ffmpeg-8.0.1-full_build\bin'
$script:AmfProbeCache = @{}

function Get-AmfBaseArgs {
    param([Parameter(Mandatory)] [string] $PixFmt)

    @(
        '-rc', 'qvbr'
        '-usage', 'transcoding'
        '-profile', 'main'
        '-pix_fmt', $PixFmt
        '-preencode', 'true'
        '-vbaq', 'true'
        '-high_motion_quality_boost_enable', 'true'
        '-preanalysis', 'true'
        '-pa_taq_mode', '2'
        '-pa_paq_mode', 'caq'
        '-pa_caq_strength', 'medium'
        '-pa_lookahead_buffer_depth', '41'
        '-pa_high_motion_quality_boost_mode', 'auto'
        '-pa_scene_change_detection_enable', 'true'
    )
}

function Get-FFmpegPath {
    param([string]$OverridePath)

    if (-not [string]::IsNullOrWhiteSpace($OverridePath) -and (Test-Path $OverridePath)) {
        return $OverridePath
    }

    $defaultPath = Join-Path $script:FFToolsDefaultBase 'ffmpeg.exe'
    if ($script:FFToolsDefaultBase -and (Test-Path $defaultPath)) {
        return $defaultPath
    }

    $fromPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
    return $fromPath ? $fromPath.Source : $null
}

function Get-FfprobePath {
    param([string]$OverridePath)

    if (-not [string]::IsNullOrWhiteSpace($OverridePath) -and (Test-Path $OverridePath)) {
        return $OverridePath
    }
    $defaultPath = Join-Path $script:FFToolsDefaultBase 'ffprobe.exe'
    if ($script:FFToolsDefaultBase -and (Test-Path $defaultPath)) {
        return $defaultPath
    }
    $fromPath = Get-Command ffprobe -ErrorAction SilentlyContinue
    return $fromPath ? $fromPath.Source : $null
}

function Test-FFmpegAmfEncoderAvailable {
    param(
        [Parameter(Mandatory)] [string]$FFmpegPath,
        [Parameter(Mandatory)] [ValidateSet('hevc_amf', 'av1_amf')] [string]$Encoder,
        [string]$PixFmt = 'yuv420p'
    )

    if (-not (Test-Path -LiteralPath $FFmpegPath -PathType Leaf)) {
        return $false
    }

    $cacheKey = "$Encoder|$PixFmt"
    if ($script:AmfProbeCache.ContainsKey($cacheKey)) {
        return $script:AmfProbeCache[$cacheKey]
    }

    $encodersOutput = & $FFmpegPath '-hide_banner' '-encoders' 2>&1 | Out-String
    if (-not $encodersOutput -or $encodersOutput -notmatch "(?m)\b$([regex]::Escape($Encoder))\b") {
        $script:AmfProbeCache[$cacheKey] = $false
        return $false
    }

    $qvbrProbeLevel = if ($Encoder -eq 'av1_amf') { '40' } else { '32' }
    $baseAmf = Get-AmfBaseArgs -PixFmt $PixFmt
    $amfOpts = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $baseAmf.Count; $i += 2) {
        $opt = $baseAmf[$i]
        $val = $baseAmf[$i + 1]
        $amfOpts.Add($opt)
        $amfOpts.Add($val)
        if ($opt -eq '-rc' -and $val -eq 'qvbr') {
            $amfOpts.Add('-qvbr_quality_level')
            $amfOpts.Add($qvbrProbeLevel)
        }
        elseif ($opt -eq '-usage' -and $val -eq 'transcoding') {
            $amfOpts.Add('-quality')
            $amfOpts.Add('balanced')
        }
    }

    $probeArgs = @(
        '-hide_banner'
        '-loglevel', 'error'
        '-f', 'lavfi'
        '-i', 'color=size=320x240:rate=1:duration=0.04:color=black'
        '-c:v', $Encoder
    ) + $amfOpts.ToArray() + @(
        '-frames:v', '1'
        '-f', 'null', '-'
    )

    & $FFmpegPath @probeArgs 2>&1 | Out-Null

    $ok = ($LASTEXITCODE -eq 0)
    $script:AmfProbeCache[$cacheKey] = $ok
    return $ok
}

function Invoke-FFmpeg {
    param(
        [Parameter(Mandatory)] [string]$Arguments,
        [string]$ExePath, # Permet d'injecter le chemin résolu par le script parent
        [switch]$CaptureOutput
    )
    
    $exe = if ($ExePath) { $ExePath } else { Get-FFmpegPath }
    if (-not $exe) { throw "FFmpeg est introuvable sur ce système." }

    if ($CaptureOutput) {
        return Start-Process -FilePath $exe -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -RedirectStandardError $null
    } else {
        Write-Verbose "Execution: $exe $Arguments"
        $proc = Start-Process -FilePath $exe -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
        return $proc.ExitCode
    }
}

function Get-MediaFastHash {
    param([Parameter(Mandatory)][string]$Path)
    
    $f = [System.IO.File]::OpenRead($Path)
    $size = $f.Length
    $buffer = New-Object byte[] 307200 # 300 Ko
    
    try {
        $f.Read($buffer, 0, 102400) | Out-Null
        if ($size -gt 204800) {
            $f.Seek([math]::Floor($size / 2) - 51200, [System.IO.SeekOrigin]::Begin) | Out-Null
            $f.Read($buffer, 102400, 102400) | Out-Null
        }
        if ($size -gt 307200) {
            $f.Seek(-102400, [System.IO.SeekOrigin]::End) | Out-Null
            $f.Read($buffer, 204800, 102400) | Out-Null
        }
    } finally { $f.Close() }

    $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash($buffer)
    return "$size-$([System.BitConverter]::ToString($hash).Replace('-','').Substring(0,8))"
}

Export-ModuleMember -Function Get-FFmpegPath, Get-FfprobePath, Get-AmfBaseArgs, Test-FFmpegAmfEncoderAvailable, Invoke-FFmpeg, Get-MediaFastHash