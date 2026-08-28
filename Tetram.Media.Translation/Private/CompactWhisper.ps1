Set-StrictMode -Version 3.0

# Reconstruire un objet réduit : un strip sur l'objet désérialisé laisserait
# words/tokens/diagnostics au ConvertTo-Json et ferait dépasser le TPM Gemini.

function ConvertTo-CompactWhisperJson {
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    $whisper = if ($InputObject -is [string]) {
        ConvertFrom-Json -InputObject $InputObject -ErrorAction Stop
    }
    else {
        $InputObject
    }

    $structureError = "La source JSON n'a pas la structure Tetram attendue."

    if ($null -eq $whisper) {
        throw $structureError
    }

    foreach ($name in @('engine', 'model', 'language', 'languageSource', 'audioTrack', 'segments')) {
        $prop = $whisper.PSObject.Properties[$name]
        if ($null -eq $prop -or $null -eq $prop.Value) {
            throw $structureError
        }
    }

    if ($whisper.engine -ne 'faster-whisper') {
        throw $structureError
    }

    $segmentsProp = $whisper.PSObject.Properties['segments']
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

            [pscustomobject]$compact
        }
    )

    $root = [ordered]@{
        language = $whisper.language
        segments = $compactSegments
    }

    return ConvertTo-Json -InputObject ([pscustomobject]$root) -Depth 3 -Compress
}
