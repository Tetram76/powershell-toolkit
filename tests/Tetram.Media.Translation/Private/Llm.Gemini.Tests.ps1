# Étendre la suite autour de Llm.Gemini.ps1 (Invoke-ProviderTranslationLlm).
#
# RepoRoot depuis tests/<Module>/Private : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Translation') -Force
# Réseau : mocker Invoke-RestMethod -ModuleName Tetram.Media.Translation ; jamais d'appel Gemini réel.
# $TestDrive pour les fichiers source/sortie ; restaurer GEMINI_API_KEY après chaque test.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranslation = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranslation = Join-Path $script:RepoRootTranslation 'Tetram.Media.Translation'

    function script:New-GeminiStopResponse {
        param(
            [Parameter(Mandatory)][string] $Text,
            [int] $TotalTokenCount
        )

        $response = [pscustomobject]@{
            candidates = @(
                [pscustomobject]@{
                    finishReason = 'STOP'
                    content      = [pscustomobject]@{
                        parts = @(
                            [pscustomobject]@{
                                thought = $false
                                text    = $Text
                            }
                        )
                    }
                }
            )
        }

        if ($PSBoundParameters.ContainsKey('TotalTokenCount')) {
            $response | Add-Member -NotePropertyName usageMetadata -NotePropertyValue ([pscustomobject]@{
                    totalTokenCount = $TotalTokenCount
                })
        }

        return $response
    }

    function script:ConvertFrom-GeminiRequestBody([string] $Body) {
        ConvertFrom-Json -InputObject $Body -Depth 20
    }

    function script:New-GeminiCountTokensResponse([int] $TotalTokens = 100) {
        [pscustomobject]@{ totalTokens = $TotalTokens }
    }

    function script:Get-RestCall([string] $Suffix) {
        return @($script:RestCalls | Where-Object { $_.Uri -like "*$Suffix" })
    }

    function script:Add-CurrentRestCall {
        param($Uri, $Body)
        $script:RestCalls.Add([pscustomobject]@{
            Uri  = [string]$Uri
            Body = $Body
        })
    }

    function script:Reset-GeminiRateHistory {
        InModuleScope 'Tetram.Media.Translation' {
            if (Get-Variable -Name GeminiRateHistory -Scope Script -ErrorAction SilentlyContinue) {
                $script:GeminiRateHistory.Clear()
            }
        }
    }

    function script:Initialize-GeminiProvider {
        InModuleScope 'Tetram.Media.Translation' {
            . (Join-Path $script:LlmPrivateRoot 'Llm.Gemini.ps1')
        }
    }

    function script:Get-GeminiRateHistory {
        InModuleScope 'Tetram.Media.Translation' {
            if (-not (Get-Variable -Name GeminiRateHistory -Scope Script -ErrorAction SilentlyContinue)) {
                return ,[object[]]@()
            }
            return ,[object[]]@($script:GeminiRateHistory)
        }
    }

    function script:Set-GeminiRateHistory {
        param([Parameter(Mandatory)][object[]] $Entry)
        InModuleScope 'Tetram.Media.Translation' -Parameters @{ Entry = $Entry } {
            param($Entry)
            . (Join-Path $script:LlmPrivateRoot 'Llm.Gemini.ps1')
            if (-not (Get-Variable -Name GeminiRateHistory -Scope Script -ErrorAction SilentlyContinue)) {
                $script:GeminiRateHistory = [System.Collections.Generic.List[object]]::new()
            }
            $script:GeminiRateHistory.Clear()
            foreach ($item in @($Entry)) {
                $script:GeminiRateHistory.Add($item)
            }
        }
    }

    function script:Get-GeminiMockResponse {
        param(
            $Uri,
            [scriptblock] $OnGenerateContent
        )
        if ([string]$Uri -like '*:countTokens') {
            return New-GeminiCountTokensResponse $script:CountTokensTotal
        }
        & $OnGenerateContent
    }

    function script:Find-InfoLogIndex([string] $Like) {
        for ($i = 0; $i -lt $script:InfoLogs.Count; $i++) {
            if ($script:InfoLogs[$i] -like $Like) {
                return $i
            }
        }
        return -1
    }

}

Describe 'Llm.Gemini' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootTranslation -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Translation' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:SavedGeminiKey = $env:GEMINI_API_KEY
        # Un dossier par test : le fichier de sortie par défaut (episode.fr.ass) ne doit
        # pas fuir d'un It à l'autre via le même $TestDrive.
        $script:Work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Work | Out-Null
        $script:SubtitlePath = Join-Path $script:Work 'episode.ass'
        $script:MinimalAssHello = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello`n"
        $script:HelloJson = '[{"cueId":1,"text":"Bonjour"}]'
        Set-Content -LiteralPath $script:SubtitlePath -Value $script:MinimalAssHello -Encoding utf8
        $script:LastGeminiBody = $null
        $script:RestCalls = [System.Collections.Generic.List[object]]::new()
        $script:InfoLogs = [System.Collections.Generic.List[string]]::new()
        $script:CountTokensTotal = 100
        Reset-GeminiRateHistory
    }

    AfterEach {
        $env:GEMINI_API_KEY = $script:SavedGeminiKey
    }

    It 'lève si GEMINI_API_KEY est absente' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
            Should -Throw -ExpectedMessage "*GEMINI_API_KEY*"
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'appelle le modèle par défaut gemini-3.6-flash' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                if ($Uri -notlike '*gemini-3.6-flash:generateContent') {
                    throw "URI inattendue : $Uri"
                }
                New-GeminiStopResponse $script:HelloJson
            }
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
            Should -Not -Throw
    }

    It 'conserve thinkingLevel low dans generationConfig' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
        $script:LastGeminiBody.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'low'
    }

    It 'utilise thinkingLevel low pour un modèle Gemini explicite sans option' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                if ($Uri -notlike '*gemini-3.6-flash:generateContent*') {
                    throw "URI inattendue : $Uri"
                }
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Model 'gemini-3.6-flash'

        $script:LastGeminiBody.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'low'
    }

    It 'utilise thinkingLevel medium pour Gemini [thinking] sans envoyer le suffixe dans l''URI' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                if ($Uri -like '*thinking*') {
                    throw "URI inattendue : $Uri"
                }
                if ($Uri -notlike '*gemini-3.6-flash:generateContent*') {
                    throw "URI inattendue : $Uri"
                }
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Model 'gemini-3.6-flash[thinking]'

        $script:LastGeminiBody.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'medium'
    }

    It 'utilise thinkingLevel high pour Gemini [thinking=high]' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                if ($Uri -like '*thinking*') {
                    throw "URI inattendue : $Uri"
                }
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Model 'gemini-3.6-flash[thinking=high]'

        $script:LastGeminiBody.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'high'
    }

    It 'utilise thinkingLevel minimal pour Gemini [thinking=minimal]' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Model 'gemini-3.6-flash[thinking=minimal]'

        $script:LastGeminiBody.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'minimal'
    }

    It 'refuse un niveau Gemini inconnu avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Model 'gemini-3.6-flash[thinking=turbo]' } |
            Should -Throw -ExpectedMessage '*Niveau de thinking Gemini inconnu : turbo*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'refuse une option de modèle inconnue avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Model 'gemini-3.6-flash[fast]' } |
            Should -Throw -ExpectedMessage '*Option de modèle inconnue : fast*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'demande une sortie JSON structurée cueId/text' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
        $config = $script:LastGeminiBody.generationConfig
        $config.responseMimeType | Should -Be 'application/json'
        $names = @($config.responseSchema.items.properties.PSObject.Properties.Name | Sort-Object)
        $names | Should -Be @('cueId', 'text')
    }

    It 'lève si Gemini ne retourne aucun candidat' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                [pscustomobject]@{ candidates = @() }
            }
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
            Should -Throw -ExpectedMessage "*aucun candidat*"
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
    }

    It 'lève si finishReason n''est pas STOP' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                [pscustomobject]@{
                    candidates = @(
                        [pscustomobject]@{
                            finishReason = 'MAX_TOKENS'
                            content      = [pscustomobject]@{
                                parts = @(
                                    [pscustomobject]@{ thought = $false; text = 'tronqué' }
                                )
                            }
                        }
                    )
                }
            }
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
            Should -Throw -ExpectedMessage "*MAX_TOKENS*"
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
    }

    It 'lève si le texte utile est vide' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                [pscustomobject]@{
                    candidates = @(
                        [pscustomobject]@{
                            finishReason = 'STOP'
                            content      = [pscustomobject]@{
                                parts = @(
                                    [pscustomobject]@{ thought = $true }
                                )
                            }
                        }
                    )
                }
            }
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
            Should -Throw -ExpectedMessage "*résultat vide*"
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
    }

    It 'utilise le modèle Gemini fourni' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                if ($Uri -notlike '*gemini-custom:generateContent') {
                    throw "URI inattendue : $Uri"
                }
                New-GeminiStopResponse $script:HelloJson
            }
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Model 'gemini-custom' } |
            Should -Not -Throw
    }

    It 'refuse AllowModelDownload avec Provider Gemini avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Provider Gemini -AllowModelDownload } |
            Should -Throw -ExpectedMessage '*AllowModelDownload*Gemini*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    Context 'jalons de progression' {
        BeforeEach {
            Mock -ModuleName Tetram.Media.Translation Write-InfoLog {
                param(
                    [string] $Text,
                    [switch] $Force
                )
                $script:InfoLogs.Add([string]$Text)
            }
        }

        It 'journalise l''invocation Gemini par défaut avec thinking=low' {
            $env:GEMINI_API_KEY = 'test-key'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                    New-GeminiStopResponse $script:HelloJson
                }
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
            $script:InfoLogs | Should -Contain "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=low, 100 tokens estimés)..."
            Should -Invoke -ModuleName Tetram.Media.Translation Write-InfoLog -Times 1 -ParameterFilter {
                [bool]$Force -and $Text -eq "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=low, 100 tokens estimés)..."
            }
        }

        It 'reprend le totalTokens de countTokens dans le jalon d''invocation' {
            $env:GEMINI_API_KEY = 'test-key'
            $script:CountTokensTotal = 2500
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                    New-GeminiStopResponse $script:HelloJson
                }
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
            $script:InfoLogs | Should -Contain "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=low, 2500 tokens estimés)..."
        }

        It 'journalise l''invocation Gemini [thinking] avec thinking=medium' {
            $env:GEMINI_API_KEY = 'test-key'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                    New-GeminiStopResponse $script:HelloJson
                }
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Model 'gemini-3.6-flash[thinking]'

            $script:InfoLogs | Should -Contain "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=medium, 100 tokens estimés)..."
            @($script:InfoLogs | Where-Object { $_ -like '*gemini-3.6-flash[thinking]*' }) | Should -HaveCount 0
        }

        It 'n''annonce ni raw ni reconstruction si le transport Gemini échoue' {
            $env:GEMINI_API_KEY = 'test-key'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                    [pscustomobject]@{ candidates = @() }
                }
            }

            {
                ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
            } | Should -Throw -ExpectedMessage '*aucun candidat*'

            $script:InfoLogs | Should -Contain "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=low, 100 tokens estimés)..."
            @($script:InfoLogs | Where-Object { $_ -like '*Réponse brute*' }) | Should -HaveCount 0
            @($script:InfoLogs | Where-Object { $_ -like '*Reconstruction*' }) | Should -HaveCount 0
        }

        It 'annonce raw puis reconstruction après une réponse Gemini valide' {
            $env:GEMINI_API_KEY = 'test-key'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                    New-GeminiStopResponse $script:HelloJson
                }
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
            $raw = Join-Path $script:Work 'episode.fr.raw.json'
            $invoke = Find-InfoLogIndex "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=low, 100 tokens estimés)..."
            $rawLog = Find-InfoLogIndex "Réponse brute du modèle enregistrée : $raw"
            $rebuild = Find-InfoLogIndex 'Reconstruction du sous-titre final...'
            $invoke | Should -BeGreaterOrEqual 0
            $rawLog | Should -BeGreaterThan $invoke
            $rebuild | Should -BeGreaterThan $rawLog
            $script:InfoLogs[$rawLog] | Should -Not -Match 'tokens réels'
        }

        It 'ajoute totalTokenCount au jalon raw quand usageMetadata est présent' {
            $env:GEMINI_API_KEY = 'test-key'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                    New-GeminiStopResponse $script:HelloJson -TotalTokenCount 42
                }
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
            $raw = Join-Path $script:Work 'episode.fr.raw.json'
            $script:InfoLogs | Should -Contain "Réponse brute du modèle enregistrée : $raw (42 tokens réels)"
        }

    }

    Context 'guards Free Tier RPM/TPM' {
        BeforeEach {
            $env:GEMINI_API_KEY = 'test-key'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                Add-CurrentRestCall -Uri $Uri -Body $Body
                if ($Uri -like '*:countTokens') {
                    return New-GeminiCountTokensResponse $script:CountTokensTotal
                }
                if ($Uri -like '*:generateContent') {
                    return New-GeminiStopResponse $script:HelloJson
                }
                throw "URI inattendue : $Uri"
            }
        }

        It 'définit les constantes Free Tier RPM=5 TPM=250000 RPD=20' {
            Initialize-GeminiProvider
            $limits = InModuleScope 'Tetram.Media.Translation' {
                [pscustomobject]@{
                    Rpm = $script:GeminiFreeTierRpm
                    Tpm = $script:GeminiFreeTierTpm
                    Rpd = $script:GeminiFreeTierRpd
                }
            }

            $limits.Rpm | Should -Be 5
            $limits.Tpm | Should -Be 250000
            $limits.Rpd | Should -Be 20
        }

        It 'appelle countTokens avant generateContent' {
            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath

            $script:RestCalls.Count | Should -Be 2
            $script:RestCalls[0].Uri | Should -BeLike '*:countTokens'
            $script:RestCalls[1].Uri | Should -BeLike '*:generateContent'
        }

        It 'envoie à countTokens le generateContentRequest complet' {
            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath

            $countBody = ConvertFrom-GeminiRequestBody (Get-RestCall 'countTokens')[0].Body
            $generateBody = ConvertFrom-GeminiRequestBody (Get-RestCall 'generateContent')[0].Body
            $counted = $countBody.generateContentRequest
            $counted | Should -Not -BeNullOrEmpty
            $counted.model | Should -Be 'models/gemini-3.6-flash'
            ($counted.contents | ConvertTo-Json -Depth 12 -Compress) |
                Should -Be ($generateBody.contents | ConvertTo-Json -Depth 12 -Compress)
            ($counted.generationConfig | ConvertTo-Json -Depth 12 -Compress) |
                Should -Be ($generateBody.generationConfig | ConvertTo-Json -Depth 12 -Compress)
        }

        It 'refuse generateContent si la requête seule atteint la limite TPM' {
            $script:CountTokensTotal = 250000

            { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
                Should -Throw -ExpectedMessage "*gemini-3.6-flash*250000*"

            Get-RestCall 'countTokens' | Should -HaveCount 1
            Get-RestCall 'generateContent' | Should -HaveCount 0
        }

        It 'refuse une sixième requête dans une fenêtre de moins de 60 secondes' {
            $now = [DateTimeOffset]::UtcNow
            Set-GeminiRateHistory -Entry @(
                @{ Timestamp = $now.AddSeconds(-10); InputTokens = 10 }
                @{ Timestamp = $now.AddSeconds(-8); InputTokens = 10 }
                @{ Timestamp = $now.AddSeconds(-6); InputTokens = 10 }
                @{ Timestamp = $now.AddSeconds(-4); InputTokens = 10 }
                @{ Timestamp = $now.AddSeconds(-2); InputTokens = 10 }
            )

            { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
                Should -Throw -ExpectedMessage '*requêtes/minute*'

            Get-RestCall 'generateContent' | Should -HaveCount 0
        }

        It 'refuse generateContent si le cumul TPM projeté atteint la limite' {
            $script:CountTokensTotal = 136000
            Set-GeminiRateHistory -Entry @(
                @{ Timestamp = [DateTimeOffset]::UtcNow.AddSeconds(-5); InputTokens = 132000 }
            )

            { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
                Should -Throw -ExpectedMessage '*268000*132000*136000*250000*'

            Get-RestCall 'generateContent' | Should -HaveCount 0
        }

        It 'purge les entrées âgées d''au moins 60 secondes et ne les compte plus' {
            $script:CountTokensTotal = 100
            Set-GeminiRateHistory -Entry @(
                @{ Timestamp = [DateTimeOffset]::UtcNow.AddSeconds(-61); InputTokens = 249000 }
            )

            { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } | Should -Not -Throw

            Get-RestCall 'generateContent' | Should -HaveCount 1
            $history = Get-GeminiRateHistory
            $history.Count | Should -Be 1
            $history[0].InputTokens | Should -Be 100
        }

        It 'enregistre la requête autorisée juste avant generateContent même si Gemini échoue ensuite' {
            $script:CountTokensTotal = 1234
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                Add-CurrentRestCall -Uri $Uri -Body $Body
                if ($Uri -like '*:countTokens') {
                    return New-GeminiCountTokensResponse $script:CountTokensTotal
                }
                if ($Uri -like '*:generateContent') {
                    throw 'réseau Gemini simulé'
                }
                throw "URI inattendue : $Uri"
            }

            { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
                Should -Throw -ExpectedMessage '*réseau Gemini simulé*'

            Get-RestCall 'generateContent' | Should -HaveCount 1
            $history = Get-GeminiRateHistory
            $history.Count | Should -Be 1
            $history[0].InputTokens | Should -Be 1234
        }

        It 'ne remet pas l''historique à zéro lors du rechargement paresseux de Llm.Gemini.ps1' {
            Set-GeminiRateHistory -Entry @(
                @{ Timestamp = [DateTimeOffset]::UtcNow; InputTokens = 42 }
            )
            Initialize-GeminiProvider

            $history = Get-GeminiRateHistory
            $history.Count | Should -Be 1
            $history[0].InputTokens | Should -Be 42
        }
    }
}
