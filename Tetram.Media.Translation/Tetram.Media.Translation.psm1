Set-StrictMode -Version 3.0

. (Join-Path $PSScriptRoot 'Private' 'Merge.ps1')

function Get-RawSubtitleOutputPath {
    param([Parameter(Mandatory)][string] $OutputPath)

    $parent = Split-Path -Parent $OutputPath
    $stem = [IO.Path]::GetFileNameWithoutExtension($OutputPath)
    $rawName = "$stem.raw.json"
    if ([string]::IsNullOrEmpty($parent)) {
        return $rawName
    }
    return Join-Path $parent $rawName
}

function ConvertTo-FrenchSubtitle {
    <#
.EXTERNALHELP Tetram.Media.Translation-Help.xml
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string] $SubtitlePath,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string] $TranscriptPath,

        [string] $OutputPath,

        [string] $Model = 'gemini-3.6-flash'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'


    # --- Configuration -----------------------------------------------------------

    $apiKey = $env:GEMINI_API_KEY

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'La variable d''environnement GEMINI_API_KEY n''est pas définie.'
    }


    # --- Chemin de sortie --------------------------------------------------------

    $subtitleFile = Get-Item -LiteralPath $SubtitlePath

    # Avant Gemini : un .txt / .vtt ne doit pas consommer de quota.
    $null = Get-SubtitleMergeKind -Extension $subtitleFile.Extension

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path `
            $subtitleFile.DirectoryName `
            "$($subtitleFile.BaseName).fr$($subtitleFile.Extension)"
    }

    if (Test-Path -LiteralPath $OutputPath) {
        throw "Le fichier de sortie existe déjà : $OutputPath"
    }

    $rawPath = Get-RawSubtitleOutputPath -OutputPath $OutputPath
    if (Test-Path -LiteralPath $rawPath) {
        throw "Le fichier de réponse brute existe déjà : $rawPath"
    }


    # --- Lecture des sources -----------------------------------------------------

    $subtitle = Get-Content -LiteralPath $SubtitlePath -Raw -Encoding UTF8
    $transcript = Get-Content -LiteralPath $TranscriptPath -Raw -Encoding UTF8

    $canonicalCue = @(Get-CanonicalSubtitleCue -Source $subtitle -Extension $subtitleFile.Extension)
    $canonicalJson = ConvertTo-CanonicalCueJson -Cue $canonicalCue


    # --- Prompt ------------------------------------------------------------------

    $promptPath = Join-Path `
        $PSScriptRoot `
        'Resources/ConvertTo-FrenchSubtitle.generate.prompt.md'

    if (-not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
        throw "Le fichier de prompt est introuvable : $promptPath"
    }

    $instructions = Get-Content `
        -LiteralPath $promptPath `
        -Raw `
        -Encoding UTF8

    $subtitlePart = @"
===== SOURCE PRINCIPALE — CUES CANONIQUES =====
$canonicalJson
===== FIN SOURCE PRINCIPALE =====
"@

    $transcriptPart = @"
===== TRANSCRIPTION WHISPER =====
$transcript
===== FIN TRANSCRIPTION WHISPER =====
"@


    # --- Appel Gemini ------------------------------------------------------------

    $body = @{
        contents = @(
            @{
                role  = 'user'
                parts = @(
                    @{ text = $instructions }
                    @{ text = $subtitlePart }
                    @{ text = $transcriptPart }
                )
            }
        )

        generationConfig = @{
            thinkingConfig   = @{
                thinkingLevel = 'low'
            }
            responseMimeType = 'application/json'
            responseSchema   = @{
                type  = 'ARRAY'
                items = @{
                    type       = 'OBJECT'
                    properties = @{
                        cueId = @{
                            type = 'INTEGER'
                        }
                        text  = @{
                            type = 'STRING'
                        }
                    }
                    required   = @('cueId', 'text')
                }
            }
        }
    } | ConvertTo-Json -Depth 12

    $uri = "https://generativelanguage.googleapis.com/v1beta/models/${Model}:generateContent"

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -Headers @{
            'x-goog-api-key' = $apiKey
        } `
        -ContentType 'application/json; charset=utf-8' `
        -Body $body


    # --- Extraction de la réponse ------------------------------------------------

    if (-not $response.candidates -or $response.candidates.Count -eq 0) {
        throw 'Gemini n''a retourné aucun candidat.'
    }

    $candidate = $response.candidates[0]

    if ($candidate.finishReason -ne 'STOP') {
        throw "La génération Gemini ne s'est pas terminée normalement : $($candidate.finishReason)"
    }

    $result = (
        $candidate.content.parts |
            ForEach-Object {
                if ($_.PSObject.Properties['text']) {
                    $_.text
                }
            }
    ) -join ''

    if ([string]::IsNullOrWhiteSpace($result)) {
        throw 'Gemini a retourné un résultat vide.'
    }


    # --- Écriture ---------------------------------------------------------------

    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($rawPath, $result, $utf8)

    try {
        $sourceText = @($canonicalCue | ForEach-Object { $_.text })
        $translationByCueId = ConvertFrom-GeminiCueTranslationJson -Json $result -CueCount $canonicalCue.Count
        Assert-CueTranslationNotEmptied -SourceText $sourceText -TranslationByCueId $translationByCueId
        $mergedResult = Merge-TranslatedSubtitle `
            -Source $subtitle `
            -TranslationByCueId $translationByCueId `
            -Extension $subtitleFile.Extension
    }
    catch {
        Write-Host "Réponse brute Gemini conservée : $rawPath"
        Write-Warning "La reconstruction du sous-titre final a échoué : $($_.Exception.Message)"
        return
    }

    [IO.File]::WriteAllText($OutputPath, $mergedResult, $utf8)

    Write-Host "Réponse brute Gemini : $rawPath"
    Write-Host "Sous-titres traduits : $OutputPath"
}

Export-ModuleMember -Function ConvertTo-FrenchSubtitle
