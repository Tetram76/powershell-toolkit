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

    $default = Join-Path $script:SherpaOnnxRoot 'sherpa-onnx-offline.exe'
    if (Test-Path -LiteralPath $default -PathType Leaf) {
        return $default
    }

    # -CommandType Application : une fonction/alias de même nom primerait sinon sur l'exécutable du PATH.
    $fromPath = Get-Command -Name 'sherpa-onnx-offline' -CommandType Application -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    throw "sherpa-onnx-offline introuvable : posez la distribution dans '$script:SherpaOnnxRoot' (dossier SherpaOnnx du module)."
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

    if ($Model -ne 'reazon-k2-v2') {
        throw "Modèle Sherpa-ONNX non géré : '$Model'."
    }

    if (-not (Test-Path -LiteralPath $script:SherpaOnnxRoot -PathType Container)) {
        throw "Aucun tokens.txt pour reazon-k2-v2 sous '$script:SherpaOnnxRoot'."
    }

    $tokenFiles = @(Get-ChildItem -LiteralPath $script:SherpaOnnxRoot -Recurse -Filter 'tokens.txt' -File -ErrorAction SilentlyContinue)
    if ($tokenFiles.Count -eq 0) {
        throw "Aucun tokens.txt pour reazon-k2-v2 sous '$script:SherpaOnnxRoot'."
    }

    $preferred = @($tokenFiles | Where-Object { $_.DirectoryName -match 'reazon' })
    if ($preferred.Count -eq 0) {
        $preferred = $tokenFiles
    }

    foreach ($tokens in $preferred) {
        $dir = $tokens.DirectoryName
        $encoder = Select-SherpaOnnxOnnxFile -Directory $dir -Prefix 'encoder' -PreferInt8
        $decoder = Select-SherpaOnnxOnnxFile -Directory $dir -Prefix 'decoder'
        $joiner = Select-SherpaOnnxOnnxFile -Directory $dir -Prefix 'joiner' -PreferInt8
        if ($encoder -and $decoder -and $joiner) {
            return [pscustomobject]@{
                Tokens  = $tokens.FullName
                Encoder = $encoder
                Decoder = $decoder
                Joiner  = $joiner
            }
        }
    }

    throw "Fichiers encoder/decoder/joiner incomplets pour reazon-k2-v2 sous '$script:SherpaOnnxRoot'."
}

function Get-SherpaOnnxArguments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $Tokens,
        [Parameter(Mandatory)] [string] $Encoder,
        [Parameter(Mandatory)] [string] $Decoder,
        [Parameter(Mandatory)] [string] $Joiner,
        [Parameter(Mandatory)] [string] $WavPath
    )

    return @(
        "--tokens=$Tokens"
        "--encoder=$Encoder"
        "--decoder=$Decoder"
        "--joiner=$Joiner"
        '--num-threads=1'
        $WavPath
    )
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
        '-c:a', 'pcm_s16le'
        $OutputPath
    )
}

function New-SherpaOnnxTempDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $created = New-Item -ItemType Directory -Path $dir -Force -Confirm:$false -WhatIf:$false -ErrorAction Stop
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
        [string] $UseLanguage
    )

    if ([string]::IsNullOrWhiteSpace($UseLanguage)) {
        return
    }

    if ($UseLanguage -ne 'ja') {
        throw "Le modèle reazon-k2-v2 n'accepte que le japonais (ja) ; UseLanguage='$UseLanguage' est incompatible."
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
        return 0
    }
    if ($value -lt 0) {
        return 0
    }
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
    Show-CommandLine -Exe $exe -Arguments $ffmpegArgs -NoPathDetectionParameters 'map', 'ac', 'c:a', 'hide_banner'
    $code = Invoke-FFmpeg -Arguments $ffmpegArgs -ExePath $exe
    if ($code -ne 0) {
        throw "FFmpeg a échoué (code $code) en préparant l'audio de '$MediaPath' (piste $AudioTrack)."
    }
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw "FFmpeg n'a pas produit le WAV temporaire pour '$MediaPath' (piste $AudioTrack)."
    }
}

function Get-SherpaOnnxWavDuration {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [string] $LiteralPath
    )

    # Même source de vérité que start_time : FFmpeg a écrit le WAV, ffprobe en lit la durée.
    $probeArgs = @(
        '-v', 'error'
        '-show_entries', 'format=duration'
        '-of', 'csv=p=0'
        $LiteralPath
    )
    $raw = Invoke-SherpaOnnxFfprobe -Arguments $probeArgs
    $text = ((@($raw) | ForEach-Object { "$_" }) -join '').Trim()
    $value = 0.0
    if ([string]::IsNullOrWhiteSpace($text) -or $text -eq 'N/A' -or
        -not [double]::TryParse(
            $text,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$value) -or
        $value -le 0) {
        throw "ffprobe n'a pas fourni de durée exploitable pour '$LiteralPath'."
    }
    return $value
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

    Show-CommandLine -Exe $Exe -Arguments $Arguments -NoPathDetectionParameters 'tokens', 'encoder', 'decoder', 'joiner', 'num-threads'

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    foreach ($argument in $Arguments) {
        [void]$psi.ArgumentList.Add($argument)
    }

    # AsJsonString() écrit du UTF-8 ; & $Exe décode selon [Console]::OutputEncoding (souvent OEM).
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

function ConvertFrom-SherpaOnnxTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)] [string] $Model,
        [string] $UseLanguage,
        [int] $AudioTrack = 1,
        [Parameter(Mandatory)] [double] $WavDuration,
        [double] $TimelineOffset = 0
    )

    Assert-SherpaOnnxLanguage -UseLanguage $UseLanguage

    $native = if ($InputObject -is [string]) {
        ConvertFrom-Json -InputObject $InputObject -ErrorAction Stop
    }
    else {
        $InputObject
    }

    if ($null -eq $native) {
        throw "La sortie native Sherpa-ONNX n'est pas un JSON exploitable."
    }

    # Reazon est monolingue ja et ne reçoit pas --language : ja n'est pas une contrainte forcée.
    $language = 'ja'
    $languageSource = 'model'

    $text = ''
    $textProp = $native.PSObject.Properties['text']
    if ($null -ne $textProp -and $null -ne $textProp.Value) {
        $text = [string]$textProp.Value
    }

    $timestamps = @()
    $tsProp = $native.PSObject.Properties['timestamps']
    if ($null -ne $tsProp -and $null -ne $tsProp.Value) {
        $timestamps = @($tsProp.Value)
    }

    $durations = @()
    $durProp = $native.PSObject.Properties['durations']
    if ($null -ne $durProp -and $null -ne $durProp.Value) {
        $durations = @($durProp.Value)
    }

    $tokens = @()
    $tokProp = $native.PSObject.Properties['tokens']
    if ($null -ne $tokProp -and $null -ne $tokProp.Value) {
        $tokens = @($tokProp.Value)
    }

    $shiftedTimestamps = @($timestamps | ForEach-Object { [double]$_ + $TimelineOffset })

    # Reazon (Zipformer Transducer) n'émet pas de durations TDT ; le dernier timestamp token
    # sous-couvre le WAV. Le segment durable couvre l'extrait, pas le dernier token.
    $segStart = $TimelineOffset
    if ($shiftedTimestamps.Count -gt 0) {
        $segStart = $shiftedTimestamps[0]
    }
    $segEnd = $WavDuration + $TimelineOffset

    $segment = [ordered]@{
        start = $segStart
        end   = $segEnd
        text  = $text
    }

    $diagnostics = [ordered]@{}
    $probsProp = $native.PSObject.Properties['ys_log_probs']
    if ($null -ne $probsProp -and $null -ne $probsProp.Value) {
        $probs = @($probsProp.Value)
        if ($probs.Count -gt 0) {
            $diagnostics['ys_log_probs'] = $probs
        }
    }
    if ($tokens.Count -gt 0) {
        $diagnostics['tokens'] = $tokens
    }
    if ($shiftedTimestamps.Count -gt 0) {
        $diagnostics['timestamps'] = $shiftedTimestamps
    }
    if ($durations.Count -gt 0) {
        $diagnostics['durations'] = $durations
    }
    foreach ($name in @('lang', 'emotion', 'event')) {
        $p = $native.PSObject.Properties[$name]
        if ($null -ne $p -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)) {
            $diagnostics[$name] = [string]$p.Value
        }
    }
    if ($diagnostics.Count -gt 0) {
        $segment['diagnostics'] = [pscustomobject]$diagnostics
    }

    return [pscustomobject][ordered]@{
        engine         = 'sherpa-onnx'
        model          = $Model
        language       = $language
        languageSource = $languageSource
        audioTrack     = $AudioTrack
        segments       = @([pscustomobject]$segment)
    }
}

function Invoke-SherpaOnnxTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] $Cmdlet,
        [int] $AudioTrack = 1,
        [string] $UseLanguage,
        [string] $SherpaOnnxPath,
        [switch] $WhatIf
    )

    Assert-SherpaOnnxLanguage -UseLanguage $UseLanguage

    $exe = Get-SherpaOnnxPath -OverridePath $SherpaOnnxPath
    $modelFiles = Get-SherpaOnnxModelFiles -Model $Model

    $previewWav = Join-Path ([IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.wav')
    $ffmpegArgs = Get-SherpaOnnxFfmpegArguments -MediaPath $MediaPath -AudioTrack $AudioTrack -OutputPath $previewWav
    $sherpaArgs = Get-SherpaOnnxArguments `
        -Tokens $modelFiles.Tokens `
        -Encoder $modelFiles.Encoder `
        -Decoder $modelFiles.Decoder `
        -Joiner $modelFiles.Joiner `
        -WavPath $previewWav
    Write-DebugLog -Text ($sherpaArgs -join ' ')
    Show-CommandLine -Exe (Get-FFmpegPath) -Arguments $ffmpegArgs -NoPathDetectionParameters 'map', 'ac', 'c:a', 'hide_banner'
    Show-CommandLine -Exe $exe -Arguments $sherpaArgs -NoPathDetectionParameters 'tokens', 'encoder', 'decoder', 'joiner', 'num-threads'

    if (-not $Cmdlet.ShouldProcess($MediaPath, 'sherpa-onnx-offline')) {
        return
    }
    if ($WhatIf) {
        return
    }

    $tempDir = $null
    $timelineOffset = 0.0
    $wavDuration = $null
    try {
        $timelineOffset = Get-SherpaOnnxTimelineOffset -MediaPath $MediaPath -AudioTrack $AudioTrack
        $tempDir = New-SherpaOnnxTempDirectory
        $wav = Join-Path $tempDir 'audio.wav'
        ConvertTo-SherpaOnnxWav -MediaPath $MediaPath -AudioTrack $AudioTrack -OutputPath $wav
        $wavDuration = Get-SherpaOnnxWavDuration -LiteralPath $wav

        $sherpaArgs = Get-SherpaOnnxArguments `
            -Tokens $modelFiles.Tokens `
            -Encoder $modelFiles.Encoder `
            -Decoder $modelFiles.Decoder `
            -Joiner $modelFiles.Joiner `
            -WavPath $wav

        $state = @{ ExitCode = $null; Stdout = $null }
        Invoke-SherpaOnnx -Exe $exe -Arguments $sherpaArgs -State $state

        if ($null -eq $state['ExitCode']) {
            return
        }
        if ($state['ExitCode'] -ne 0) {
            throw "sherpa-onnx-offline a échoué (code $($state['ExitCode'])) sur '$MediaPath' (modèle $Model)."
        }
        if ([string]::IsNullOrWhiteSpace($state['Stdout'])) {
            throw "Aucune sortie JSON native produite par sherpa-onnx-offline pour '$MediaPath' (modèle $Model)."
        }

        return ConvertFrom-SherpaOnnxTranscript `
            -InputObject $state['Stdout'] `
            -Model $Model `
            -UseLanguage $UseLanguage `
            -AudioTrack $AudioTrack `
            -WavDuration $wavDuration `
            -TimelineOffset $timelineOffset
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
        [int] $AudioTrack = 1,
        [string] $UseLanguage,
        [switch] $WhatIf
    )

    Invoke-SherpaOnnxTranscript -MediaPath $MediaPath -Model $Model -Cmdlet $Cmdlet -AudioTrack $AudioTrack -UseLanguage $UseLanguage -WhatIf:$WhatIf
}
