Set-StrictMode -Version 3.0

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
