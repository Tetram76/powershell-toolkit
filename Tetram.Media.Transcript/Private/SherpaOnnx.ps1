Set-StrictMode -Version 3.0

# Dot-source depuis Private/ : $PSScriptRoot n'est pas la racine du module.
$script:SherpaOnnxRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'SherpaOnnx'
$script:SherpaOnnxFfmpegModule = Join-Path (Split-Path -Parent $PSScriptRoot) '..' 'Tetram.Media.FFmpeg'

# Dépendance interne au backend Sherpa : le chemin générique de transcription n'importe pas FFmpeg.
Import-Module -Name $script:SherpaOnnxFfmpegModule -Force

function Get-SherpaOnnxPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $OverridePath
    )

    if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
        if (Test-Path -LiteralPath $OverridePath -PathType Leaf) {
            return $OverridePath
        }
        if (Test-Path -LiteralPath $OverridePath) {
            throw "Le chemin doit désigner un exécutable, pas un dossier : '$OverridePath'"
        }
        throw "Exécutable Sherpa-ONNX inexistant : '$OverridePath'"
    }

    # VAD + ASR hors-ligne : c'est ce binaire qui accepte --silero-vad-model.
    $default = Join-Path $script:SherpaOnnxRoot 'sherpa-onnx-vad-with-offline-asr.exe'
    if (Test-Path -LiteralPath $default -PathType Leaf) {
        return $default
    }

    # -CommandType Application : une fonction/alias de même nom primerait sinon sur l'exécutable du PATH.
    $fromPath = Get-Command -Name 'sherpa-onnx-vad-with-offline-asr' -CommandType Application -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    throw "sherpa-onnx-vad-with-offline-asr introuvable : posez la distribution dans '$script:SherpaOnnxRoot' (dossier SherpaOnnx du module)."
}

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

function Select-SherpaOnnxOnnxFile {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [string] $Prefix,
        [switch] $PreferInt8
    )

    $files = @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$Prefix*.onnx" })
    if ($files.Count -eq 0) {
        return $null
    }

    $int8 = @($files | Where-Object { $_.Name -like '*.int8.onnx' })
    $fp32 = @($files | Where-Object { $_.Name -notlike '*.int8.onnx' })

    # Recette Reazon INT8 documentée : encoder/joiner int8, decoder FP32.
    if ($PreferInt8) {
        if ($int8.Count -gt 0) { return $int8[0].FullName }
        if ($fp32.Count -gt 0) { return $fp32[0].FullName }
    }
    else {
        if ($fp32.Count -gt 0) { return $fp32[0].FullName }
        if ($int8.Count -gt 0) { return $int8[0].FullName }
    }

    return $null
}

function Get-SherpaOnnxModelFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Model
    )

    # Convention : SherpaOnnx/models/<nom-canonique> ; pas de scan ni de repli sur un autre dossier.
    $modelDir = Join-Path $script:SherpaOnnxRoot 'models' $Model
    if ($Model -notin @('reazon-k2-v2', 'parakeet-0.6b-ja', 'sensevoice-small')) {
        throw "Modèle Sherpa-ONNX non géré : '$Model'."
    }
    if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) {
        throw "Dossier modèle introuvable : '$modelDir'."
    }

    $tokens = Join-Path $modelDir 'tokens.txt'
    switch ($Model) {
        'reazon-k2-v2' {
            $encoder = Select-SherpaOnnxOnnxFile -Directory $modelDir -Prefix 'encoder' -PreferInt8
            $decoder = Select-SherpaOnnxOnnxFile -Directory $modelDir -Prefix 'decoder'
            $joiner = Select-SherpaOnnxOnnxFile -Directory $modelDir -Prefix 'joiner' -PreferInt8
            if (-not (Test-Path -LiteralPath $tokens -PathType Leaf) -or -not $encoder -or -not $decoder -or -not $joiner) {
                throw "Fichiers encoder/decoder/joiner incomplets pour '$modelDir'."
            }
            return [pscustomobject]@{
                Tokens  = $tokens
                Encoder = $encoder
                Decoder = $decoder
                Joiner  = $joiner
            }
        }
        'parakeet-0.6b-ja' {
            $nemo = Join-Path $modelDir 'model.int8.onnx'
            if (-not (Test-Path -LiteralPath $tokens -PathType Leaf) -or -not (Test-Path -LiteralPath $nemo -PathType Leaf)) {
                throw "Fichiers tokens/model.int8.onnx incomplets pour '$modelDir'."
            }
            return [pscustomobject]@{
                Tokens       = $tokens
                NemoCtcModel = $nemo
            }
        }
        'sensevoice-small' {
            $senseVoice = Join-Path $modelDir 'model.int8.onnx'
            if (-not (Test-Path -LiteralPath $tokens -PathType Leaf) -or -not (Test-Path -LiteralPath $senseVoice -PathType Leaf)) {
                throw "Fichiers tokens/model.int8.onnx incomplets pour '$modelDir'."
            }
            return [pscustomobject]@{
                Tokens          = $tokens
                SenseVoiceModel = $senseVoice
            }
        }
    }

    throw "Modèle Sherpa-ONNX non géré : '$Model'."
}

function Get-SherpaOnnxAsrArguments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] $ModelFiles
    )

    switch ($Model) {
        'reazon-k2-v2' {
            return @(
                "--tokens=$($ModelFiles.Tokens)"
                "--encoder=$($ModelFiles.Encoder)"
                "--decoder=$($ModelFiles.Decoder)"
                "--joiner=$($ModelFiles.Joiner)"
            )
        }
        'parakeet-0.6b-ja' {
            return @(
                "--tokens=$($ModelFiles.Tokens)"
                "--nemo-ctc-model=$($ModelFiles.NemoCtcModel)"
            )
        }
        'sensevoice-small' {
            return @(
                "--tokens=$($ModelFiles.Tokens)"
                "--sense-voice-model=$($ModelFiles.SenseVoiceModel)"
                '--sense-voice-language=ja'
            )
        }
        default {
            throw "Modèle Sherpa-ONNX non géré : '$Model'."
        }
    }
}

function Get-SherpaOnnxLanguageContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Model
    )

    switch ($Model) {
        { $_ -in @('reazon-k2-v2', 'parakeet-0.6b-ja') } {
            return [pscustomobject]@{
                Language       = 'ja'
                LanguageSource = 'model'
            }
        }
        'sensevoice-small' {
            return [pscustomobject]@{
                Language       = 'ja'
                LanguageSource = 'forced'
            }
        }
        default {
            throw "Modèle Sherpa-ONNX non géré : '$Model'."
        }
    }
}

function Get-SherpaOnnxArguments {
    [CmdletBinding(DefaultParameterSetName = 'ReazonSilero')]
    [OutputType([string[]])]
    param(
        [Parameter(ParameterSetName = 'ReazonSilero', Mandatory)]
        [Parameter(ParameterSetName = 'ReazonTen', Mandatory)]
        [string] $Tokens,
        [Parameter(ParameterSetName = 'ReazonSilero', Mandatory)]
        [Parameter(ParameterSetName = 'ReazonTen', Mandatory)]
        [string] $Encoder,
        [Parameter(ParameterSetName = 'ReazonSilero', Mandatory)]
        [Parameter(ParameterSetName = 'ReazonTen', Mandatory)]
        [string] $Decoder,
        [Parameter(ParameterSetName = 'ReazonSilero', Mandatory)]
        [Parameter(ParameterSetName = 'ReazonTen', Mandatory)]
        [string] $Joiner,
        [Parameter(ParameterSetName = 'AsrSilero', Mandatory)]
        [Parameter(ParameterSetName = 'AsrTen', Mandatory)]
        [string[]] $AsrArguments,
        [Parameter(ParameterSetName = 'ReazonSilero', Mandatory)]
        [Parameter(ParameterSetName = 'AsrSilero', Mandatory)]
        [string] $SileroVadModel,
        [Parameter(ParameterSetName = 'ReazonTen', Mandatory)]
        [Parameter(ParameterSetName = 'AsrTen', Mandatory)]
        [string] $TenVadModel,
        [Parameter(Mandatory)] [string] $WavPath
    )

    $arguments = if ($PSBoundParameters.ContainsKey('AsrArguments')) {
        @($AsrArguments)
    }
    else {
        @(
            "--tokens=$Tokens"
            "--encoder=$Encoder"
            "--decoder=$Decoder"
            "--joiner=$Joiner"
        )
    }

    # Silero et Ten sont deux pipelines VAD incompatibles sur le même binaire : un seul jeu de flags par invocation.
    if ($PSBoundParameters.ContainsKey('SileroVadModel')) {
        $arguments += @(
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
        $arguments += @(
            "--ten-vad-model=$TenVadModel"
            '--ten-vad-threshold=0.5'
            '--ten-vad-min-silence-duration=0.5'
            '--ten-vad-min-speech-duration=0.25'
            '--ten-vad-max-speech-duration=6'
            '--ten-vad-window-size=256'
        )
    }

    $arguments += $WavPath
    return $arguments
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

function Assert-SherpaOnnxLanguage {
    [CmdletBinding()]
    param(
        [string] $UseLanguage,
        [string] $Model
    )

    if ([string]::IsNullOrWhiteSpace($UseLanguage)) {
        return
    }

    if ($UseLanguage -ne 'ja') {
        $label = if ([string]::IsNullOrWhiteSpace($Model)) { 'Sherpa-ONNX' } else { $Model }
        throw "Le modèle $label n'accepte que le japonais (ja) ; UseLanguage='$UseLanguage' est incompatible."
    }
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

function Invoke-SherpaOnnx {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [hashtable] $State
    )

    $State['ExitCode'] = $null
    $State['Stdout'] = $null

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    foreach ($argument in $Arguments) {
        [void]$psi.ArgumentList.Add($argument)
    }

    # Le binaire VAD écrit le japonais en UTF-8 ; & $Exe décode selon [Console]::OutputEncoding (souvent OEM).
    $process = $null
    $savedOutputEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $process = [System.Diagnostics.Process]::Start($psi)
        $State['Stdout'] = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        $State['ExitCode'] = $process.ExitCode
    }
    finally {
        [Console]::OutputEncoding = $savedOutputEncoding
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Convert-SherpaOnnxVadLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Line,
        [Parameter(Mandatory)] [double] $TimelineOffset
    )

    # Préfixe natif "start -- end:" ; le texte ASR peut lui-même contenir ':'.
    $separator = $Line.IndexOf(' -- ')
    $colon = if ($separator -ge 0) { $Line.IndexOf(':', $separator + 4) } else { -1 }
    if ($separator -lt 0 -or $colon -lt 0) {
        throw "Ligne de sortie Sherpa-ONNX inattendue : '$Line'."
    }

    $startToken = $Line.Substring(0, $separator).Trim()
    $endToken = $Line.Substring($separator + 4, $colon - ($separator + 4)).Trim()
    $text = $Line.Substring($colon + 1)
    if ($text.StartsWith(' ')) {
        $text = $text.Substring(1)
    }

    $start = 0.0
    $end = 0.0
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $style = [Globalization.NumberStyles]::Float
    if (-not [double]::TryParse($startToken, $style, $culture, [ref]$start) -or
        -not [double]::TryParse($endToken, $style, $culture, [ref]$end)) {
        throw "Ligne de sortie Sherpa-ONNX inattendue : '$Line'."
    }
    if ($end -lt $start) {
        throw "Segment Sherpa-ONNX invalide : end ($endToken) < start ($startToken)."
    }

    # Sherpa imprime déjà %.3f ; l'addition de TimelineOffset réintroduit le bruit binaire du double.
    return [pscustomobject][ordered]@{
        start = [math]::Round($start + $TimelineOffset, 3)
        end   = [math]::Round($end + $TimelineOffset, 3)
        text  = $text
    }
}

function ConvertFrom-SherpaOnnxTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)] [string] $Model,
        [string] $Vad,
        [string] $UseLanguage,
        [int] $AudioTrack = 1,
        [double] $TimelineOffset = 0
    )

    Assert-SherpaOnnxLanguage -UseLanguage $UseLanguage -Model $Model

    $languageContract = Get-SherpaOnnxLanguageContract -Model $Model
    $language = $languageContract.Language
    $languageSource = $languageContract.LanguageSource

    $segments = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ([string]$InputObject -split '\r?\n')) {
        if ($line.Length -eq 0) {
            continue
        }
        $segments.Add((Convert-SherpaOnnxVadLine -Line $line -TimelineOffset $TimelineOffset))
    }

    if ($segments.Count -eq 0) {
        throw "Aucun segment de transcription exploitable dans la sortie Sherpa-ONNX."
    }

    $root = [ordered]@{
        engine         = 'sherpa-onnx'
        model          = $Model
    }
    if (-not [string]::IsNullOrWhiteSpace($Vad)) {
        $root['vad'] = $Vad
    }
    $root['language'] = $language
    $root['languageSource'] = $languageSource
    $root['audioTrack'] = $AudioTrack
    $root['segments'] = @($segments.ToArray())
    return [pscustomobject]$root
}

function Invoke-SherpaOnnxTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)] $Result,
        [int] $AudioTrack = 1,
        [string] $UseLanguage,
        [string] $SherpaOnnxPath,
        [switch] $WhatIf
    )

    Assert-SherpaOnnxLanguage -UseLanguage $UseLanguage -Model $Model

    $exe = Get-SherpaOnnxPath -OverridePath $SherpaOnnxPath
    $modelFiles = Get-SherpaOnnxModelFiles -Model $Model
    $sileroVad = Get-SherpaOnnxVadModelPath -Exe $exe -FileName 'silero_vad.onnx'
    $tenVad = Get-SherpaOnnxVadModelPath -Exe $exe -FileName 'ten-vad.onnx'

    # Chemin figé avant ShouldProcess : l'affichage et l'exécution doivent citer les mêmes arguments.
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $wav = Join-Path $tempDir 'audio.wav'
    $ffmpegArgs = Get-SherpaOnnxFfmpegArguments -MediaPath $MediaPath -AudioTrack $AudioTrack -OutputPath $wav
    $asrArgs = Get-SherpaOnnxAsrArguments -Model $Model -ModelFiles $modelFiles
    $sileroArgs = Get-SherpaOnnxArguments -AsrArguments $asrArgs -SileroVadModel $sileroVad -WavPath $wav
    $tenArgs = Get-SherpaOnnxArguments -AsrArguments $asrArgs -TenVadModel $tenVad -WavPath $wav
    Write-DebugLog -Text ($sileroArgs -join ' ')
    Write-DebugLog -Text ($tenArgs -join ' ')
    $sherpaNoPath = 'tokens', 'encoder', 'decoder', 'joiner', 'nemo-ctc-model', 'sense-voice-model', 'silero-vad-model', 'ten-vad-model', 'num-threads'
    Show-CommandLine -Exe (Get-FFmpegPath) -Arguments $ffmpegArgs -NoPathDetectionParameters 'map', 'ac', 'c:a', 'hide_banner'
    Show-CommandLine -Exe $exe -Arguments $sileroArgs -NoPathDetectionParameters $sherpaNoPath
    Show-CommandLine -Exe $exe -Arguments $tenArgs -NoPathDetectionParameters $sherpaNoPath

    if (-not $Cmdlet.ShouldProcess($MediaPath, 'sherpa-onnx-vad-with-offline-asr')) {
        return
    }
    if ($WhatIf) {
        return
    }

    $timelineOffset = 0.0
    try {
        $timelineOffset = Get-SherpaOnnxTimelineOffset -MediaPath $MediaPath -AudioTrack $AudioTrack
        [void](New-SherpaOnnxTempDirectory -Path $tempDir)
        ConvertTo-SherpaOnnxWav -MediaPath $MediaPath -AudioTrack $AudioTrack -OutputPath $wav

        foreach ($run in @(
                [pscustomobject]@{ Arguments = $sileroArgs; Vad = 'silero' }
                [pscustomobject]@{ Arguments = $tenArgs; Vad = 'ten' }
            )) {
            $state = @{ ExitCode = $null; Stdout = $null }
            Invoke-SherpaOnnx -Exe $exe -Arguments $run.Arguments -State $state

            if ($null -eq $state['ExitCode']) {
                return
            }
            if ($state['ExitCode'] -ne 0) {
                throw "sherpa-onnx-vad-with-offline-asr a échoué (code $($state['ExitCode'])) sur '$MediaPath' (modèle $Model, vad $($run.Vad))."
            }
            if ([string]::IsNullOrWhiteSpace($state['Stdout'])) {
                throw "Aucun segment de transcription produit par sherpa-onnx-vad-with-offline-asr pour '$MediaPath' (modèle $Model, vad $($run.Vad))."
            }

            $transcript = ConvertFrom-SherpaOnnxTranscript `
                -InputObject $state['Stdout'] `
                -Model $Model `
                -Vad $run.Vad `
                -UseLanguage $UseLanguage `
                -AudioTrack $AudioTrack `
                -TimelineOffset $timelineOffset
            [void]$Result.Transcripts.Add($transcript)
        }
    }
    finally {
        Remove-SherpaOnnxTempDirectory -Path $tempDir
    }
}

function Invoke-ProviderTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)] $Result,
        [int] $AudioTrack = 1,
        [string] $UseLanguage,
        [switch] $WhatIf
    )

    Invoke-SherpaOnnxTranscript -MediaPath $MediaPath -Model $Model -Cmdlet $Cmdlet -AudioTrack $AudioTrack -UseLanguage $UseLanguage -Result $Result -WhatIf:$WhatIf
}
