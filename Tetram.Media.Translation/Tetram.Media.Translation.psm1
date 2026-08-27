Set-StrictMode -Version 3.0

@(
    'Tetram.Common'
) | ForEach-Object {
    Import-Module -Name (Join-Path $PSScriptRoot '..' $_) -Force
}

. (Join-Path $PSScriptRoot 'Private' 'Merge.ps1')
. (Join-Path $PSScriptRoot 'Private' 'Llm.ps1')

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

        [ValidateSet('Gemini', 'Ollama')]
        [string] $Provider = 'Gemini',

        [string] $Model,

        [switch] $AllowModelDownload
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'


    # --- Chemin de sortie --------------------------------------------------------

    $subtitleFile = Get-Item -LiteralPath $SubtitlePath

    # Un .txt / .vtt n'est pas une source : échouer avant quota Gemini ou pull Ollama.
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


    # --- Appel LLM ----------------------------------------------------------------

    $promptPart = @(
        $instructions
        $subtitlePart
        $transcriptPart
    )

    $result = Invoke-TranslationLlm `
        -Provider $Provider `
        -Model $Model `
        -PromptPart $promptPart `
        -AllowModelDownload:$AllowModelDownload


    # --- Écriture ---------------------------------------------------------------

    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($rawPath, $result, $utf8)

    Write-InfoLog -Text "Réponse brute du modèle enregistrée : $rawPath" -Force

    try {
        Write-InfoLog -Text 'Reconstruction du sous-titre final...' -Force
        $sourceText = @($canonicalCue | ForEach-Object { $_.text })
        $translationByCueId = ConvertFrom-CueTranslationJson -Json $result -CueCount $canonicalCue.Count
        Assert-CueTranslationNotEmptied -SourceText $sourceText -TranslationByCueId $translationByCueId
        $mergedResult = Merge-TranslatedSubtitle `
            -Source $subtitle `
            -TranslationByCueId $translationByCueId `
            -Extension $subtitleFile.Extension
    }
    catch {
        Write-Host "Réponse brute du modèle conservée : $rawPath"
        Write-Warning "La reconstruction du sous-titre final a échoué : $($_.Exception.Message)"
        return
    }

    [IO.File]::WriteAllText($OutputPath, $mergedResult, $utf8)

    Write-Host "Réponse brute du modèle : $rawPath"
    Write-Host "Sous-titres traduits : $OutputPath"
}

Export-ModuleMember -Function ConvertTo-FrenchSubtitle
