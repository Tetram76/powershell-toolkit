Set-StrictMode -Version 3.0

. (Join-Path $PSScriptRoot 'Private' 'Merge.ps1')

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


    # --- Lecture des sources -----------------------------------------------------

    $subtitle = Get-Content -LiteralPath $SubtitlePath -Raw -Encoding UTF8
    $transcript = Get-Content -LiteralPath $TranscriptPath -Raw -Encoding UTF8


    # --- Prompt ------------------------------------------------------------------

    $promptPath = Join-Path `
        $PSScriptRoot `
        'Resources/ConvertTo-FrenchSubtitle.prompt.md'

    if (-not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
        throw "Le fichier de prompt est introuvable : $promptPath"
    }

    $instructions = Get-Content `
        -LiteralPath $promptPath `
        -Raw `
        -Encoding UTF8

    $subtitlePart = @"
===== SOUS-TITRES SOURCE =====
$subtitle
===== FIN SOUS-TITRES SOURCE =====
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
            thinkingConfig = @{
                thinkingLevel = 'low'
            }
        }
    } | ConvertTo-Json -Depth 10

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

    $mergedResult = Merge-TranslatedSubtitle `
        -Source $subtitle `
        -Translation $result `
        -Extension $subtitleFile.Extension

    [IO.File]::WriteAllText(
        $OutputPath,
        $mergedResult,
        [Text.UTF8Encoding]::new($false)
    )

    Write-Host "Sous-titres traduits : $OutputPath"
}

Export-ModuleMember -Function ConvertTo-FrenchSubtitle
