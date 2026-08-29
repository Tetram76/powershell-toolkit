Set-StrictMode -Version 3.0

function Get-SherpaOnnxResultValues {
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)] [string] $Name
    )

    $values = [System.Collections.Generic.List[object]]::new()
    $prop = $Result.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) {
        return , $values
    }

    foreach ($item in @($prop.Value)) {
        $values.Add($item)
    }
    # Virgule unaire : PowerShell énumérerait sinon la List et perdrait Count sous StrictMode.
    return , $values
}

function ConvertFrom-SherpaOnnxTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Intervals,
        [Parameter(Mandatory)] $AsrResults,
        [Parameter(Mandatory)] [string] $Model,
        [string] $Vad,
        [string] $UseLanguage,
        [int] $AudioTrack = 1,
        [double] $TimelineOffset = 0
    )

    Assert-SherpaOnnxLanguage -UseLanguage $UseLanguage -Model $Model

    $languageContract = Get-SherpaOnnxLanguageContract -Model $Model
    $intervalList = @($Intervals)
    $asrList = @($AsrResults)
    if ($intervalList.Count -ne $asrList.Count) {
        throw "Le nombre d'intervalles VAD ($($intervalList.Count)) ne correspond pas au nombre de résultats ASR ($($asrList.Count))."
    }

    $segments = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $intervalList.Count; $i++) {
        $asr = $asrList[$i]
        $text = [string]$asr.text
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $interval = $intervalList[$i]
        $segment = [ordered]@{
            start = [math]::Round($TimelineOffset + [double]$interval.start, 3)
            end   = [math]::Round($TimelineOffset + [double]$interval.end, 3)
            text  = $text
        }

        $diagnostics = [ordered]@{}
        $tokens = Get-SherpaOnnxResultValues -Result $asr -Name 'tokens'
        if ($tokens.Count -gt 0) {
            $diagnostics['tokens'] = @($tokens | ForEach-Object { "$_" })
        }

        $timestamps = Get-SherpaOnnxResultValues -Result $asr -Name 'timestamps'
        if ($timestamps.Count -gt 0) {
            # Recalage depuis vadStart de CE segment ; Round 3 : Sherpa n'émet que 2 décimales, l'addition double réintroduit du bruit.
            $diagnostics['timestamps'] = @(
                foreach ($local in $timestamps) {
                    [math]::Round($TimelineOffset + [double]$interval.start + [double]$local, 3)
                }
            )
        }

        $durations = Get-SherpaOnnxResultValues -Result $asr -Name 'durations'
        if ($durations.Count -gt 0) {
            $diagnostics['durations'] = @($durations | ForEach-Object { [double]$_ })
        }

        $logProbs = Get-SherpaOnnxResultValues -Result $asr -Name 'ys_log_probs'
        if ($logProbs.Count -gt 0) {
            $diagnostics['ys_log_probs'] = @($logProbs | ForEach-Object { [double]$_ })
        }

        foreach ($name in @('lang', 'emotion', 'event')) {
            $prop = $asr.PSObject.Properties[$name]
            if ($null -eq $prop -or $null -eq $prop.Value -or [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
                continue
            }
            $diagnostics[$name] = [string]$prop.Value
        }

        if ($diagnostics.Count -gt 0) {
            $segment['diagnostics'] = [pscustomobject]$diagnostics
        }

        $segments.Add([pscustomobject]$segment)
    }

    if ($segments.Count -eq 0) {
        throw "Aucun segment de transcription exploitable dans la sortie Sherpa-ONNX."
    }

    $root = [ordered]@{
        engine = 'sherpa-onnx'
        model  = $Model
    }
    if (-not [string]::IsNullOrWhiteSpace($Vad)) {
        $root['vad'] = $Vad
    }
    $root['language'] = $languageContract.Language
    $root['languageSource'] = $languageContract.LanguageSource
    $root['audioTrack'] = $AudioTrack
    $root['segments'] = @($segments.ToArray())
    return [pscustomobject]$root
}
