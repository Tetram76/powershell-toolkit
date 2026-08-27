Set-StrictMode -Version 3.0

# Reconstruire un objet réduit : retirer des propriétés sur l'objet désérialisé
# laisserait tokens/words au ConvertTo-Json et ferait dépasser le TPM Gemini.

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

    if ($null -eq $whisper) {
        throw "La source JSON n'a pas la structure Whisper attendue."
    }

    $segmentsProp = $whisper.PSObject.Properties['segments']
    if ($null -eq $segmentsProp -or $null -eq $segmentsProp.Value) {
        throw "La source JSON n'a pas la structure Whisper attendue."
    }

    $compactSegments = @(
        foreach ($segment in @($segmentsProp.Value)) {
            if ($null -eq $segment) {
                throw "La source JSON n'a pas la structure Whisper attendue."
            }

            $startProp = $segment.PSObject.Properties['start']
            $endProp = $segment.PSObject.Properties['end']
            $textProp = $segment.PSObject.Properties['text']
            if ($null -eq $startProp -or $null -eq $endProp -or $null -eq $textProp) {
                throw "La source JSON n'a pas la structure Whisper attendue."
            }

            $compact = [ordered]@{
                start = $startProp.Value
                end   = $endProp.Value
                text  = $textProp.Value
            }

            foreach ($name in @('temperature', 'avg_logprob', 'compression_ratio', 'no_speech_prob')) {
                $diag = $segment.PSObject.Properties[$name]
                if ($null -ne $diag -and $null -ne $diag.Value) {
                    $compact[$name] = $diag.Value
                }
            }

            [pscustomobject]$compact
        }
    )

    $root = [ordered]@{}
    $languageProp = $whisper.PSObject.Properties['language']
    if ($null -ne $languageProp -and $null -ne $languageProp.Value) {
        $root['language'] = $languageProp.Value
    }
    $root['segments'] = $compactSegments

    return ConvertTo-Json -InputObject ([pscustomobject]$root) -Depth 3 -Compress
}
