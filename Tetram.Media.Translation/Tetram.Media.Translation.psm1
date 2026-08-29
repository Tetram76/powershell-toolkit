Set-StrictMode -Version 3.0

@(
    'Tetram.Common'
) | ForEach-Object {
    Import-Module -Name (Join-Path $PSScriptRoot '..' $_) -Force
}

. (Join-Path $PSScriptRoot 'Private' 'CompactTranscript.ps1')
. (Join-Path $PSScriptRoot 'Private' 'Merge.ps1')
. (Join-Path $PSScriptRoot 'Private' 'Llm.ps1')

function ConvertTo-SecondarySourcePromptPart {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][int] $Index
    )

    $extension = [IO.Path]::GetExtension($Path)
    if ($extension.Equals('.json', [StringComparison]::OrdinalIgnoreCase)) {
        $rawJson = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        try {
            $transcript = ConvertFrom-Json -InputObject $rawJson -ErrorAction Stop
        }
        catch {
            throw "La source secondaire n'est pas un JSON valide : $Path"
        }

        try {
            $compactJson = ConvertTo-CompactTranscriptJson -InputObject $transcript
        }
        catch {
            throw "La source secondaire n'a pas la structure Tetram attendue : $Path"
        }

        return @"
===== SOURCE LINGUISTIQUE $Index — TRANSCRIPTION AUTOMATIQUE JSON =====
$compactJson
===== FIN SOURCE LINGUISTIQUE $Index =====
"@
    }

    $file = Get-Item -LiteralPath $Path
    $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $cue = @(Get-CanonicalSubtitleCue -Source $source -Extension $file.Extension)
    $json = ConvertTo-SecondarySubtitleCueJson -Cue $cue

    return @"
===== SOURCE LINGUISTIQUE $Index — SOUS-TITRE =====
$json
===== FIN SOURCE LINGUISTIQUE $Index =====
"@
}

function New-RawTranslationTempPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path ([IO.Path]::GetTempPath()) ("tetram-translation-" + [guid]::NewGuid().ToString('N') + '.json')
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

        [AllowEmptyCollection()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string[]] $SecondarySourcePath,

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


    # --- Lecture des sources -----------------------------------------------------

    $subtitle = Get-Content -LiteralPath $SubtitlePath -Raw -Encoding UTF8

    $canonicalCue = @(Get-CanonicalSubtitleCue -Source $subtitle -Extension $subtitleFile.Extension)
    $templateJson = ConvertTo-TechnicalTemplateCueJson -Cue $canonicalCue
    $structuringJson = ConvertTo-SecondarySubtitleCueJson -Cue $canonicalCue


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

    $templatePart = @"
===== GABARIT TECHNIQUE FINAL =====
$templateJson
===== FIN GABARIT TECHNIQUE FINAL =====
"@

    $structuringPart = @"
===== SOURCE LINGUISTIQUE 1 — SOUS-TITRE STRUCTURANT =====
$structuringJson
===== FIN SOURCE LINGUISTIQUE 1 =====
"@


    # --- Appel LLM ----------------------------------------------------------------

    $promptPart = @(
        $instructions
        $templatePart
        $structuringPart
    )

    # foreach sur $null n'itère pas ; @($null) produirait une itération vide.
    # La source structurante occupe l'index 1 ; les SecondarySourcePath commencent à 2.
    $secondaryIndex = 1
    foreach ($path in $SecondarySourcePath) {
        $secondaryIndex++
        $promptPart += ConvertTo-SecondarySourcePromptPart -Path $path -Index $secondaryIndex
    }

    $result = Invoke-TranslationLlm `
        -Provider $Provider `
        -Model $Model `
        -PromptPart $promptPart `
        -AllowModelDownload:$AllowModelDownload


    # --- Écriture ---------------------------------------------------------------

    $utf8 = [Text.UTF8Encoding]::new($false)
    $rawPath = New-RawTranslationTempPath
    try {
        [IO.File]::WriteAllText($rawPath, $result, $utf8)

        $rawLog = 'Réponse brute du modèle reçue'
        if ($null -ne $script:LastLlmResponseTokenCount) {
            $rawLog = "$rawLog ($($script:LastLlmResponseTokenCount) tokens réels)"
        }
        Write-InfoLog -Text $rawLog -Force

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
            Write-Warning "La reconstruction du sous-titre final a échoué : $($_.Exception.Message)"
            return
        }

        [IO.File]::WriteAllText($OutputPath, $mergedResult, $utf8)

        Write-Host "Sous-titres traduits : $OutputPath"
    }
    finally {
        if ($rawPath -and (Test-Path -LiteralPath $rawPath)) {
            Remove-Item -LiteralPath $rawPath -Force -Confirm:$false -WhatIf:$false -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function ConvertTo-FrenchSubtitle
