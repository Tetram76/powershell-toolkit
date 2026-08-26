Set-StrictMode -Version 3.0

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

    $instructions = @'
Tu es chargé de produire des sous-titres français à partir de deux sources :

1. le fichier de sous-titres extrait de la vidéo ;
2. une transcription Whisper de la piste audio japonaise.

Les deux sources sont complémentaires.

Utilise la transcription Whisper pour comprendre le dialogue japonais, lever les
ambiguïtés et corriger si nécessaire une mauvaise interprétation du sous-titre
source.

Produis une traduction française naturelle et adaptée à des sous-titres.

Contraintes impératives :

- conserve le format exact du fichier de sous-titres source ;
- conserve l'ordre des événements ;
- conserve les timecodes existants ;
- conserve les styles, positions, métadonnées et autres champs techniques ;
- conserve les tags de formatage ;
- traduis uniquement le texte destiné à être lu par le spectateur ;
- ne supprime ni n'ajoute de dialogue sans nécessité manifeste ;
- ne modifie pas la transcription Whisper ;
- n'invente pas de contenu absent des sources ;
- utilise le contexte des répliques pour produire un français naturel et cohérent ;
- conserve la cohérence des noms, tutoiements/vouvoiements et registres de langue
  au cours de l'épisode.

Ta réponse doit contenir UNIQUEMENT le contenu complet du fichier de sous-titres
traduit.

Ne mets pas le résultat dans un bloc Markdown.
N'ajoute aucune explication avant ou après le fichier.
'@

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

    [IO.File]::WriteAllText(
        $OutputPath,
        $result,
        [Text.UTF8Encoding]::new($false)
    )

    Write-Host "Sous-titres traduits : $OutputPath"
}

Export-ModuleMember -Function ConvertTo-FrenchSubtitle
