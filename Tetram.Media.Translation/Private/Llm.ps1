Set-StrictMode -Version 3.0

# $PSScriptRoot de ce fichier (Private/), pas celui du psm1 : le dispatcher retrouve les providers.
$script:LlmPrivateRoot = $PSScriptRoot

function Get-CueTranslationJsonSchema {
    return @{
        type  = 'array'
        items = @{
            type                 = 'object'
            properties           = @{
                cueId = @{
                    type = 'integer'
                }
                text  = @{
                    type = 'string'
                }
            }
            required             = @('cueId', 'text')
            additionalProperties = $false
        }
    }
}

function New-LlmModelOptionTable {
    return [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
}

function Resolve-LlmModelSpec {
    param([Parameter(Mandatory)][string] $Model)

    $spec = $Model.Trim()
    if ([string]::IsNullOrWhiteSpace($spec)) {
        throw 'Le nom de modèle est vide.'
    }

    if ($spec.IndexOf('[') -lt 0) {
        if ($spec.Contains(']')) {
            throw 'Syntaxe de modèle invalide : crochet fermant sans suffixe d''options.'
        }

        return [pscustomobject]@{
            Name    = $spec
            Options = New-LlmModelOptionTable
        }
    }

    if (-not $spec.EndsWith(']', [StringComparison]::Ordinal)) {
        throw 'Syntaxe de modèle invalide : crochets non fermés.'
    }

    $open = $spec.IndexOf('[')
    $name = $spec.Substring(0, $open).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'Le nom de modèle est vide.'
    }

    # Sinon model][thinking] serait un Name valide (model]) : le ] n'est contrôlé que dans le suffixe.
    if ($name.Contains('[') -or $name.Contains(']')) {
        throw 'Syntaxe de modèle invalide : le nom de modèle ne doit pas contenir de crochets.'
    }

    $inner = $spec.Substring($open + 1, $spec.Length - $open - 2)
    if ($inner.Contains('[') -or $inner.Contains(']')) {
        throw 'Syntaxe de modèle invalide : le suffixe d''options doit être terminal.'
    }

    if ([string]::IsNullOrWhiteSpace($inner)) {
        throw 'Syntaxe de modèle invalide : liste d''options vide.'
    }

    $options = New-LlmModelOptionTable
    foreach ($rawPart in ($inner -split ',')) {
        $part = $rawPart.Trim()
        if ([string]::IsNullOrWhiteSpace($part)) {
            throw 'Option sans nom.'
        }

        $eq = $part.IndexOf('=')
        $optName = $null
        $optValue = $null
        if ($eq -lt 0) {
            $optName = $part
        }
        else {
            $optName = $part.Substring(0, $eq).Trim()
            $optValue = $part.Substring($eq + 1).Trim()
            if ([string]::IsNullOrWhiteSpace($optName)) {
                throw 'Option sans nom.'
            }
            if ([string]::IsNullOrWhiteSpace($optValue)) {
                throw 'Valeur d''option vide.'
            }
        }

        if ($options.ContainsKey($optName)) {
            throw "Option de modèle dupliquée : $optName."
        }

        $canonical = $null
        foreach ($recognized in @('thinking')) {
            if ($optName.Equals($recognized, [StringComparison]::OrdinalIgnoreCase)) {
                $canonical = $recognized
                break
            }
        }
        if ($null -eq $canonical) {
            throw @"
Option de modèle inconnue : $optName.
Options reconnues : thinking.
"@
        }

        # Seule thinking normalise sa valeur : les futures options pourront garder la casse d'origine.
        if ($null -ne $optValue -and $canonical -eq 'thinking') {
            $optValue = $optValue.ToLowerInvariant()
        }

        $options[$canonical] = $optValue
    }

    return [pscustomobject]@{
        Name    = $name
        Options = $options
    }
}

function Invoke-TranslationLlm {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Gemini', 'Ollama')]
        [string] $Provider,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $Model,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $PromptPart,

        [switch] $AllowModelDownload
    )

    $script:LastLlmResponseTokenCount = $null

    switch ($Provider) {
        'Gemini' {
            . (Join-Path $script:LlmPrivateRoot 'Llm.Gemini.ps1')
        }

        'Ollama' {
            . (Join-Path $script:LlmPrivateRoot 'Llm.Ollama.ps1')
        }
    }

    return Invoke-ProviderTranslationLlm `
        -Model $Model `
        -PromptPart $PromptPart `
        -AllowModelDownload:$AllowModelDownload
}
