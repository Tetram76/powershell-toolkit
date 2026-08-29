Set-StrictMode -Version 3.0

function Get-SherpaOnnxVadModelPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string] $FileName
    )

    $dir = Split-Path -Parent $Exe
    if ([string]::IsNullOrWhiteSpace($dir)) {
        $dir = (Get-Location).Path
    }
    $vad = Join-Path $dir $FileName
    if (-not (Test-Path -LiteralPath $vad -PathType Leaf)) {
        throw "$FileName introuvable à côté de '$Exe'."
    }
    return $vad
}

function Get-SherpaOnnxVadArguments {
    [CmdletBinding(DefaultParameterSetName = 'Silero')]
    [OutputType([string[]])]
    param(
        [Parameter(ParameterSetName = 'Silero', Mandatory)]
        [string] $SileroVadModel,
        [Parameter(ParameterSetName = 'Ten', Mandatory)]
        [string] $TenVadModel,
        [Parameter(Mandatory)] [string] $WavPath,
        [Parameter(Mandatory)] [string] $SpeechWavPath
    )

    # Silero et TEN sont deux pipelines incompatibles : un seul jeu de flags par invocation.
    $arguments = if ($PSCmdlet.ParameterSetName -eq 'Silero') {
        @(
            "--silero-vad-model=$SileroVadModel"
            '--silero-vad-threshold=0.40'
            '--silero-vad-min-silence-duration=0.5'
            '--silero-vad-min-speech-duration=0.25'
            '--silero-vad-max-speech-duration=6'
            '--silero-vad-window-size=512'
            '--silero-vad-neg-threshold=-1'
        )
    }
    else {
        @(
            "--ten-vad-model=$TenVadModel"
            '--ten-vad-threshold=0.5'
            '--ten-vad-min-silence-duration=0.5'
            '--ten-vad-min-speech-duration=0.25'
            '--ten-vad-max-speech-duration=6'
            '--ten-vad-window-size=256'
        )
    }

    $arguments += @($WavPath, $SpeechWavPath)
    return $arguments
}

function ConvertFrom-SherpaOnnxVadStdout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Stdout
    )

    $culture = [Globalization.CultureInfo]::InvariantCulture
    $style = [Globalization.NumberStyles]::Float
    $intervals = [System.Collections.Generic.List[object]]::new()

    foreach ($line in ($Stdout -split '\r?\n')) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0) {
            continue
        }

        $separator = $trimmed.IndexOf(' -- ')
        if ($separator -lt 0) {
            continue
        }

        $startToken = $trimmed.Substring(0, $separator).Trim()
        $endToken = $trimmed.Substring($separator + 4).Trim()
        # Un intervalle VAD n'a pas de texte ASR ; une ligne "start -- end: text" n'est pas ce CLI.
        if ($endToken.Contains(':')) {
            continue
        }

        $start = 0.0
        $end = 0.0
        if (-not [double]::TryParse($startToken, $style, $culture, [ref]$start) -or
            -not [double]::TryParse($endToken, $style, $culture, [ref]$end)) {
            continue
        }
        if ($end -lt $start) {
            throw "Intervalle VAD Sherpa-ONNX invalide : end ($endToken) < start ($startToken)."
        }

        $intervals.Add([pscustomobject]@{
                start = $start
                end   = $end
            })
    }

    return @($intervals.ToArray())
}
