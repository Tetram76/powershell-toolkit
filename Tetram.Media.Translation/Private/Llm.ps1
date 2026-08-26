Set-StrictMode -Version 3.0

# Ollama est un démon HTTP local : on ne cherche pas ollama.exe et on ne le démarre pas.

$script:OllamaBaseUri = 'http://localhost:11434'
$script:OllamaTagsTimeoutSec = 5

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

function Test-OllamaModelListed {
    param(
        [Parameter(Mandatory)][string] $Model,
        $TagResponse
    )

    $installed = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $TagResponse -and $TagResponse.PSObject.Properties['models'] -and $null -ne $TagResponse.models) {
        foreach ($entry in @($TagResponse.models)) {
            if ($null -eq $entry) {
                continue
            }
            foreach ($propName in @('name', 'model')) {
                $prop = $entry.PSObject.Properties[$propName]
                if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
                    $installed.Add([string]$prop.Value)
                }
            }
        }
    }

    foreach ($name in $installed) {
        if ($name.Equals($Model, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        # :latest est le tag implicite d'Ollama ; sans tag dans la demande, l'omettre serait un faux négatif.
        if ($Model.IndexOf(':') -lt 0 -and $name.Equals("${Model}:latest", [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-OllamaTags {
    $uri = "$script:OllamaBaseUri/api/tags"
    try {
        return Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec $script:OllamaTagsTimeoutSec
    }
    catch {
        throw @"
Ollama n'est pas accessible sur http://localhost:11434.

Vérifiez qu'Ollama est installé et démarré.

Installation Windows :
  winget install --id Ollama.Ollama -e

Téléchargement officiel :
  https://ollama.com/download/windows

Si Ollama est déjà installé, démarrez l'application Ollama
ou lancez :
  ollama serve

$($_.Exception.Message)
"@
    }
}

function Invoke-OllamaModelPull {
    param([Parameter(Mandatory)][string] $Model)

    $uri = "$script:OllamaBaseUri/api/pull"
    $body = @{
        model  = $Model
        stream = $false
    } | ConvertTo-Json -Compress

    try {
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $uri `
            -ContentType 'application/json; charset=utf-8' `
            -Body $body
    }
    catch {
        throw @"
Le téléchargement du modèle Ollama '$Model' a échoué.

Installez-le manuellement :
  ollama pull $Model

$($_.Exception.Message)
"@
    }

    # /api/pull en stream=false termine par { "status": "success" } ; un HTTP 200
    # sans ce statut (corps vide ou objet partiel) n'est pas un pull réussi.
    $status = $null
    if ($null -ne $response -and $response.PSObject.Properties['status']) {
        $status = [string]$response.status
    }
    if ([string]::IsNullOrWhiteSpace($status) -or -not $status.Equals('success', [StringComparison]::OrdinalIgnoreCase)) {
        $detail = $null
        if ($null -ne $response -and $response.PSObject.Properties['error'] -and -not [string]::IsNullOrWhiteSpace([string]$response.error)) {
            $detail = [string]$response.error
        }
        elseif (-not [string]::IsNullOrWhiteSpace($status)) {
            $detail = $status
        }

        throw @"
Le téléchargement du modèle Ollama '$Model' a échoué.

Installez-le manuellement :
  ollama pull $Model

$detail
"@
    }
}

function Get-GeminiThinkingLevel {
    param([Parameter(Mandatory)] $ModelSpec)

    # Google documente medium par défaut pour plusieurs Flash ; le projet force low
    # tant que le Model spec ne demande pas explicitement thinking.
    $level = 'low'
    if ($ModelSpec.Options.ContainsKey('thinking')) {
        $value = $ModelSpec.Options['thinking']
        if ($null -eq $value) {
            $level = 'medium'
        }
        else {
            $level = [string]$value
        }
    }

    $recognized = @('minimal', 'low', 'medium', 'high')
    if ($level -notin $recognized) {
        throw @"
Niveau de thinking Gemini inconnu : $level.
Niveaux reconnus : minimal, low, medium, high.
"@
    }

    return $level
}

function Get-OllamaThinkPreference {
    param([Parameter(Mandatory)] $ModelSpec)

    if (-not $ModelSpec.Options.ContainsKey('thinking')) {
        return $false
    }

    if ($null -ne $ModelSpec.Options['thinking']) {
        throw @"
L'option thinking avec une valeur est actuellement réservée à Gemini.
Avec Ollama, utilisez soit '<model>', soit '<model>[thinking]'.
"@
    }

    return $true
}

function Invoke-GeminiTranslationLlm {
    param(
        [Parameter(Mandatory)] $ModelSpec,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $PromptPart
    )

    $apiKey = $env:GEMINI_API_KEY
    $modelName = $ModelSpec.Name
    $thinkingLevel = Get-GeminiThinkingLevel -ModelSpec $ModelSpec
    $part = @(
        $PromptPart | ForEach-Object {
            @{ text = $_ }
        }
    )

    $body = @{
        contents = @(
            @{
                role  = 'user'
                parts = $part
            }
        )

        generationConfig = @{
            thinkingConfig   = @{
                thinkingLevel = $thinkingLevel
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

    $uri = "https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent"

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -Headers @{
            'x-goog-api-key' = $apiKey
        } `
        -ContentType 'application/json; charset=utf-8' `
        -Body $body

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

    return $result
}

function Invoke-OllamaTranslationLlm {
    param(
        [Parameter(Mandatory)] $ModelSpec,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $PromptPart,
        [switch] $AllowModelDownload
    )

    # Certaines familles Ollama activent thinking par défaut ; le flag doit être
    # envoyé même à false pour que '<model>' et '<model>[thinking]' restent distincts.
    $think = Get-OllamaThinkPreference -ModelSpec $ModelSpec
    $modelName = $ModelSpec.Name

    $tags = Get-OllamaTags
    $installed = Test-OllamaModelListed -Model $modelName -TagResponse $tags
    if (-not $installed) {
        if (-not $AllowModelDownload) {
            throw @"
Le modèle Ollama '$modelName' n'est pas installé localement.

Solutions :
  - relancez la commande avec -AllowModelDownload ;
  - ou installez le modèle manuellement :
      ollama pull $modelName
"@
        }

        Invoke-OllamaModelPull -Model $modelName
    }

    $uri = "$script:OllamaBaseUri/api/chat"
    $body = @{
        model    = $modelName
        messages = @(
            @{
                role    = 'user'
                content = ($PromptPart -join "`n`n")
            }
        )
        stream   = $false
        think    = $think
        format   = Get-CueTranslationJsonSchema
    } | ConvertTo-Json -Depth 12

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -ContentType 'application/json; charset=utf-8' `
        -Body $body

    if ($null -eq $response) {
        throw 'Ollama n''a retourné aucune réponse.'
    }

    if ($response.PSObject.Properties['done'] -and -not [bool]$response.done) {
        throw 'La génération Ollama ne s''est pas terminée.'
    }

    if (-not $response.PSObject.Properties['message'] -or $null -eq $response.message) {
        throw 'Ollama n''a pas retourné de message.'
    }

    if (-not $response.message.PSObject.Properties['content']) {
        throw 'Ollama n''a pas retourné de contenu.'
    }

    $result = [string]$response.message.content
    if ([string]::IsNullOrWhiteSpace($result)) {
        throw 'Ollama a retourné un résultat vide.'
    }

    return $result
}

function Invoke-TranslationLlm {
    param(
        [Parameter(Mandatory)][ValidateSet('Gemini', 'Ollama')][string] $Provider,
        [Parameter(Mandatory)][string] $Model,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $PromptPart,
        [switch] $AllowModelDownload
    )

    $modelSpec = Resolve-LlmModelSpec -Model $Model

    switch ($Provider) {
        'Gemini' {
            return Invoke-GeminiTranslationLlm -ModelSpec $modelSpec -PromptPart $PromptPart
        }
        'Ollama' {
            return Invoke-OllamaTranslationLlm `
                -ModelSpec $modelSpec `
                -PromptPart $PromptPart `
                -AllowModelDownload:$AllowModelDownload
        }
    }
}
