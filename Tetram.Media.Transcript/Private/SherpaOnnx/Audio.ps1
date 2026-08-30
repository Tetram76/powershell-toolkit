Set-StrictMode -Version 3.0

function Get-SherpaOnnxChunkFfmpegArguments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $MasterWav,
        [Parameter(Mandatory)] [double] $Start,
        [Parameter(Mandatory)] [double] $End,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    $culture = [Globalization.CultureInfo]::InvariantCulture
    $startText = $Start.ToString('G15', $culture)
    $endText = $End.ToString('G15', $culture)

    # atrim après -i : un -ss avant l'entrée ferait un seek approximatif sur le WAV maître.
    return @(
        '-hide_banner'
        '-loglevel', 'error'
        '-nostats'
        '-y'
        '-i', $MasterWav
        '-af', "atrim=start=${startText}:end=${endText},asetpts=PTS-STARTPTS"
        '-c:a', 'pcm_s16le'
        $OutputPath
    )
}

function New-SherpaOnnxChunkWav {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MasterWav,
        [Parameter(Mandatory)] [double] $Start,
        [Parameter(Mandatory)] [double] $End,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force -Confirm:$false -WhatIf:$false)
    }

    $ffmpegArgs = Get-SherpaOnnxChunkFfmpegArguments -MasterWav $MasterWav -Start $Start -End $End -OutputPath $OutputPath
    $code = Invoke-FFmpeg -Arguments $ffmpegArgs -ExePath (Get-FFmpegPath)
    if ($code -ne 0) {
        throw "FFmpeg a échoué (code $code) en découpant le chunk '$OutputPath'."
    }
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw "FFmpeg n'a pas produit le chunk '$OutputPath'."
    }
}

function Get-SherpaOnnxFfmpegArguments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [int] $AudioTrack,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    return @(
        '-hide_banner'
        '-y'
        '-i', $MediaPath
        '-map', "0:a:$($AudioTrack - 1)"
        '-vn'
        '-ac', '1'
        '-ar', '16000'
        '-c:a', 'pcm_s16le'
        $OutputPath
    )
}

function New-SherpaOnnxTempDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    }
    $created = New-Item -ItemType Directory -Path $Path -Force -Confirm:$false -WhatIf:$false -ErrorAction Stop
    return $created.FullName
}

function Remove-SherpaOnnxTempDirectory {
    [CmdletBinding()]
    param(
        [string] $Path
    )

    if (-not $Path) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Remove-Item -LiteralPath $Path -Recurse -Force -Confirm:$false -WhatIf:$false -ErrorAction SilentlyContinue
}

function Invoke-SherpaOnnxFfprobe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Arguments
    )

    $exe = Get-FfprobePath
    $output = & $exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe a échoué (code $LASTEXITCODE) : $($Arguments[-1])"
    }
    return $output
}

function Get-SherpaOnnxTimelineOffset {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [int] $AudioTrack
    )

    # L'extraction WAV remet la piste à t=0 ; start_time replace les timestamps sur la timeline du média.
    $probeArgs = @(
        '-v', 'error'
        '-select_streams', "a:$($AudioTrack - 1)"
        '-show_entries', 'stream=start_time'
        '-of', 'csv=p=0'
        $MediaPath
    )
    $raw = Invoke-SherpaOnnxFfprobe -Arguments $probeArgs
    $text = ((@($raw) | ForEach-Object { "$_" }) -join '').Trim()
    if ([string]::IsNullOrWhiteSpace($text) -or $text -eq 'N/A') {
        return 0
    }

    $value = 0.0
    if (-not [double]::TryParse(
            $text,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$value)) {
        throw "start_time illisible pour la piste $AudioTrack de '$MediaPath' : '$text'."
    }

    # Un start_time négatif est un offset média réel (edit list / priming), pas une erreur de probe.
    return $value
}

function ConvertTo-SherpaOnnxWav {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [int] $AudioTrack,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    $ffmpegArgs = Get-SherpaOnnxFfmpegArguments -MediaPath $MediaPath -AudioTrack $AudioTrack -OutputPath $OutputPath
    $exe = Get-FFmpegPath
    $code = Invoke-FFmpeg -Arguments $ffmpegArgs -ExePath $exe
    if ($code -ne 0) {
        throw "FFmpeg a échoué (code $code) en préparant l'audio de '$MediaPath' (piste $AudioTrack)."
    }
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw "FFmpeg n'a pas produit le WAV temporaire pour '$MediaPath' (piste $AudioTrack)."
    }
}
