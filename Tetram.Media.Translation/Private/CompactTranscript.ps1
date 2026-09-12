Set-StrictMode -Version 3.0

# Reconstruire un objet réduit : un strip sur l'objet désérialisé laisserait
# words/tokens/diagnostics au ConvertTo-Json et ferait dépasser le TPM Gemini.

function ConvertTo-CompactTranscriptJson {
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    $transcript = if ($InputObject -is [string]) {
        ConvertFrom-Json -InputObject $InputObject -ErrorAction Stop
    }
    else {
        $InputObject
    }

    $structureError = "La source JSON n'a pas la structure Tetram attendue."

    if ($null -eq $transcript) {
        throw $structureError
    }

    foreach ($name in @('engine', 'model', 'language', 'languageSource', 'audioTrack', 'segments')) {
        $prop = $transcript.PSObject.Properties[$name]
        if ($null -eq $prop -or $null -eq $prop.Value) {
            throw $structureError
        }
    }

    $engine = [string]$transcript.engine
    if ($engine -notin @('faster-whisper', 'sherpa-onnx')) {
        throw $structureError
    }

    $vad = $null
    if ($engine -eq 'sherpa-onnx') {
        $vadProp = $transcript.PSObject.Properties['vad']
        if ($null -eq $vadProp -or [string]::IsNullOrWhiteSpace([string]$vadProp.Value)) {
            throw $structureError
        }
        $vad = [string]$vadProp.Value
    }

    $segmentsProp = $transcript.PSObject.Properties['segments']
    $compactSegments = @(
        foreach ($segment in @($segmentsProp.Value)) {
            if ($null -eq $segment) {
                throw $structureError
            }

            $startProp = $segment.PSObject.Properties['start']
            $endProp = $segment.PSObject.Properties['end']
            $textProp = $segment.PSObject.Properties['text']
            if ($null -eq $startProp -or $null -eq $endProp -or $null -eq $textProp) {
                throw $structureError
            }

            $compact = [ordered]@{
                start = $startProp.Value
                end   = $endProp.Value
                text  = $textProp.Value
            }

            if ($engine -eq 'faster-whisper') {
                $diagnosticsProp = $segment.PSObject.Properties['diagnostics']
                if ($null -ne $diagnosticsProp -and $null -ne $diagnosticsProp.Value) {
                    $diagnostics = $diagnosticsProp.Value
                    foreach ($name in @('temperature', 'avg_logprob', 'compression_ratio', 'no_speech_prob')) {
                        $diag = $diagnostics.PSObject.Properties[$name]
                        if ($null -ne $diag -and $null -ne $diag.Value) {
                            $compact[$name] = $diag.Value
                        }
                    }
                }
            }

            [pscustomobject]$compact
        }
    )

    $root = [ordered]@{
        engine = $engine
        model  = [string]$transcript.model
    }
    if ($null -ne $vad) {
        $root['vad'] = $vad
    }
    $root['language'] = $transcript.language
    $root['segments'] = $compactSegments

    return ConvertTo-Json -InputObject ([pscustomobject]$root) -Depth 3 -Compress
}
