Set-StrictMode -Version 3.0

$script:GeminiFreeTierRpm = 5
$script:GeminiFreeTierTpm = 250000
# Guard RPD (requêtes/jour) prévu plus tard ; la constante fige la limite connue du compte.
$script:GeminiFreeTierRpd = 20

# Re-dot-source à chaque appel Gemini : ne pas vider un historique déjà présent dans le processus.
if (-not (Get-Variable -Name GeminiRateHistory -Scope Script -ErrorAction SilentlyContinue)) {
    $script:GeminiRateHistory = [System.Collections.Generic.List[object]]::new()
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

function Get-GeminiInputTokenCount {
    param(
        [Parameter(Mandatory)][string] $ModelName,
        [Parameter(Mandatory)] $GenerateRequest,
        [Parameter(Mandatory)][string] $ApiKey
    )

    $uri = "https://generativelanguage.googleapis.com/v1beta/models/${ModelName}:countTokens"
    # contents seul omet thinkingConfig et responseSchema, pourtant comptés dans l'entrée globale du modèle.
    # Le proto CountTokensRequest exige generateContentRequest.model même si l'URI le contient déjà.
    $countGenerateRequest = @{}
    foreach ($key in $GenerateRequest.Keys) {
        $countGenerateRequest[$key] = $GenerateRequest[$key]
    }
    $countGenerateRequest['model'] = "models/$ModelName"
    $body = @{
        generateContentRequest = $countGenerateRequest
    } | ConvertTo-Json -Depth 12

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -Headers @{
            'x-goog-api-key' = $ApiKey
        } `
        -ContentType 'application/json; charset=utf-8' `
        -Body $body

    $totalTokensProperty = $null
    if ($null -ne $response) {
        $totalTokensProperty = $response.PSObject.Properties['totalTokens']
    }

    if ($null -eq $totalTokensProperty -or $null -eq $totalTokensProperty.Value) {
        throw "countTokens Gemini n'a pas retourné de totalTokens valide pour le modèle '$ModelName'."
    }

    try {
        return [int]$totalTokensProperty.Value
    }
    catch {
        throw "countTokens Gemini a retourné un totalTokens non entier pour le modèle '$ModelName' : $($totalTokensProperty.Value)"
    }
}

function Assert-GeminiFreeTierWindow {
    param(
        [Parameter(Mandatory)][string] $ModelName,
        [Parameter(Mandatory)][int] $InputTokens
    )

    if ($InputTokens -ge $script:GeminiFreeTierTpm) {
        throw @"
La requête Gemini '$ModelName' nécessite $InputTokens tokens d'entrée, ce qui atteint ou dépasse la limite Free Tier de $($script:GeminiFreeTierTpm) tokens/minute.
"@
    }

    $now = [DateTimeOffset]::UtcNow
    $cutoff = $now.AddSeconds(-60)
    for ($i = $script:GeminiRateHistory.Count - 1; $i -ge 0; $i--) {
        if ($script:GeminiRateHistory[$i].Timestamp -le $cutoff) {
            $script:GeminiRateHistory.RemoveAt($i)
        }
    }

    $requestCount = $script:GeminiRateHistory.Count
    $windowTokens = 0
    foreach ($entry in $script:GeminiRateHistory) {
        $windowTokens += [int]$entry.InputTokens
    }

    if ($requestCount -ge $script:GeminiFreeTierRpm) {
        throw "Limite Gemini Free Tier de $($script:GeminiFreeTierRpm) requêtes/minute atteinte ($requestCount appels déjà présents dans la fenêtre)."
    }

    $projected = $windowTokens + $InputTokens
    if ($projected -ge $script:GeminiFreeTierTpm) {
        throw "La requête utiliserait $projected tokens d'entrée sur la fenêtre Gemini ($windowTokens déjà comptabilisés + $InputTokens demandés), pour une limite de $($script:GeminiFreeTierTpm) tokens/minute."
    }
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
        $Model = 'gemini-3.6-flash'
    }

    $modelSpec = Resolve-LlmModelSpec -Model $Model
    $thinkingLevel = Get-GeminiThinkingLevel -ModelSpec $modelSpec

    if ($AllowModelDownload) {
        throw '-AllowModelDownload n''est pas applicable avec -Provider Gemini.'
    }

    $apiKey = $env:GEMINI_API_KEY
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'La variable d''environnement GEMINI_API_KEY n''est pas définie.'
    }

    $modelName = $modelSpec.Name
    $part = @(
        $PromptPart | ForEach-Object {
            @{ text = $_ }
        }
    )

    $generateRequest = @{
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
    }

    $inputTokens = Get-GeminiInputTokenCount `
        -ModelName $modelName `
        -GenerateRequest $generateRequest `
        -ApiKey $apiKey

    Assert-GeminiFreeTierWindow -ModelName $modelName -InputTokens $inputTokens

    $script:GeminiRateHistory.Add(@{
            Timestamp   = [DateTimeOffset]::UtcNow
            InputTokens = $inputTokens
        })

    $body = $generateRequest | ConvertTo-Json -Depth 12
    $uri = "https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent"

    Write-InfoLog -Text "Invocation de Gemini avec '$modelName' (thinking=$thinkingLevel)..." -Force

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
