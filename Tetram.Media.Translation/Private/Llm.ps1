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

    if ($null -ne $response -and $response.PSObject.Properties['error'] -and -not [string]::IsNullOrWhiteSpace([string]$response.error)) {
        throw @"
Le téléchargement du modèle Ollama '$Model' a échoué.

Installez-le manuellement :
  ollama pull $Model

$($response.error)
"@
    }

    if ($null -ne $response -and $response.PSObject.Properties['status'] -and -not [string]::IsNullOrWhiteSpace([string]$response.status) -and [string]$response.status -ne 'success') {
        throw @"
Le téléchargement du modèle Ollama '$Model' a échoué.

Installez-le manuellement :
  ollama pull $Model

$($response.status)
"@
    }
}

function Invoke-GeminiTranslationLlm {
    param(
        [Parameter(Mandatory)][string] $Model,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $PromptPart
    )

    $apiKey = $env:GEMINI_API_KEY
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
        [Parameter(Mandatory)][string] $Model,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $PromptPart,
        [switch] $AllowModelDownload
    )

    $tags = Get-OllamaTags
    $installed = Test-OllamaModelListed -Model $Model -TagResponse $tags
    if (-not $installed) {
        if (-not $AllowModelDownload) {
            throw @"
Le modèle Ollama '$Model' n'est pas installé localement.

Solutions :
  - relancez la commande avec -AllowModelDownload ;
  - ou installez le modèle manuellement :
      ollama pull $Model
"@
        }

        Invoke-OllamaModelPull -Model $Model
    }

    $uri = "$script:OllamaBaseUri/api/chat"
    $body = @{
        model    = $Model
        messages = @(
            @{
                role    = 'user'
                content = ($PromptPart -join "`n`n")
            }
        )
        stream   = $false
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

    switch ($Provider) {
        'Gemini' {
            return Invoke-GeminiTranslationLlm -Model $Model -PromptPart $PromptPart
        }
        'Ollama' {
            return Invoke-OllamaTranslationLlm `
                -Model $Model `
                -PromptPart $PromptPart `
                -AllowModelDownload:$AllowModelDownload
        }
    }
}
