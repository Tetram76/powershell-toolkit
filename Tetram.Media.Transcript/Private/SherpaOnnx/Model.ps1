Set-StrictMode -Version 3.0

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
