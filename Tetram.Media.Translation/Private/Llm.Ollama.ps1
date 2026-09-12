Set-StrictMode -Version 3.0

# Ollama est un démon HTTP local : on ne cherche pas ollama.exe et on ne le démarre pas.

$script:OllamaBaseUri = 'http://localhost:11434'
$script:OllamaTagsTimeoutSec = 5

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

    Write-InfoLog -Text "Téléchargement du modèle Ollama '$Model'..." -Force

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

    Write-InfoLog -Text "Modèle Ollama '$Model' téléchargé." -Force
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

function Invoke-ProviderTranslationLlm {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Model,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $PromptPart,

        [switch] $AllowModelDownload
    )

    if ([string]::IsNullOrWhiteSpace($Model)) {
        $Model = 'qwen3.5:9b'
    }

    $modelSpec = Resolve-LlmModelSpec -Model $Model

    # Certaines familles Ollama activent thinking par défaut ; le flag doit être
    # envoyé même à false pour que '<model>' et '<model>[thinking]' restent distincts.
    $think = Get-OllamaThinkPreference -ModelSpec $modelSpec
    $modelName = $modelSpec.Name

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

    Write-InfoLog -Text "Invocation d'Ollama avec '$modelName' (thinking=$($think.ToString().ToLowerInvariant()))..." -Force

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
