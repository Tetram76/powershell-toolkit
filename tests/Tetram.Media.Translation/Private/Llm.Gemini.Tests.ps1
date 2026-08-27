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

    function script:New-GeminiStopResponse([string] $Text) {
        [pscustomobject]@{
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
    }

    function script:ConvertFrom-GeminiRequestBody([string] $Body) {
        ConvertFrom-Json -InputObject $Body -Depth 20
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
        $script:TranscriptPath = Join-Path $script:Work 'episode.whisper.txt'
        $script:MinimalAssHello = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello`n"
        $script:HelloJson = '[{"cueId":1,"text":"Bonjour"}]'
        Set-Content -LiteralPath $script:SubtitlePath -Value $script:MinimalAssHello -Encoding utf8
        Set-Content -LiteralPath $script:TranscriptPath -Value 'こんにちは' -Encoding utf8
        $script:LastGeminiBody = $null
        $script:RestCalls = [System.Collections.Generic.List[object]]::new()
        $script:InfoLogs = [System.Collections.Generic.List[string]]::new()
    }

    AfterEach {
        $env:GEMINI_API_KEY = $script:SavedGeminiKey
    }

    It 'lève si GEMINI_API_KEY est absente' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage "*GEMINI_API_KEY*"
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'appelle le modèle par défaut gemini-3.6-flash' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            if ($Uri -notlike '*gemini-3.6-flash:generateContent') {
                throw "URI inattendue : $Uri"
            }
            New-GeminiStopResponse $script:HelloJson
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Not -Throw
    }

    It 'conserve thinkingLevel low dans generationConfig' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
            New-GeminiStopResponse $script:HelloJson
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

        $script:LastGeminiBody.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'low'
    }

    It 'utilise thinkingLevel low pour un modèle Gemini explicite sans option' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            if ($Uri -notlike '*gemini-3.6-flash:generateContent*') {
                throw "URI inattendue : $Uri"
            }
            $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
            New-GeminiStopResponse $script:HelloJson
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Model 'gemini-3.6-flash'

        $script:LastGeminiBody.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'low'
    }

    It 'utilise thinkingLevel medium pour Gemini [thinking] sans envoyer le suffixe dans l''URI' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            if ($Uri -like '*thinking*') {
                throw "URI inattendue : $Uri"
            }
            if ($Uri -notlike '*gemini-3.6-flash:generateContent*') {
                throw "URI inattendue : $Uri"
            }
            $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
            New-GeminiStopResponse $script:HelloJson
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Model 'gemini-3.6-flash[thinking]'

        $script:LastGeminiBody.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'medium'
    }

    It 'utilise thinkingLevel high pour Gemini [thinking=high]' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            if ($Uri -like '*thinking*') {
                throw "URI inattendue : $Uri"
            }
            $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
            New-GeminiStopResponse $script:HelloJson
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Model 'gemini-3.6-flash[thinking=high]'

        $script:LastGeminiBody.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'high'
    }

    It 'utilise thinkingLevel minimal pour Gemini [thinking=minimal]' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
            New-GeminiStopResponse $script:HelloJson
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Model 'gemini-3.6-flash[thinking=minimal]'

        $script:LastGeminiBody.generationConfig.thinkingConfig.thinkingLevel | Should -Be 'minimal'
    }

    It 'refuse un niveau Gemini inconnu avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Model 'gemini-3.6-flash[thinking=turbo]' } |
            Should -Throw -ExpectedMessage '*Niveau de thinking Gemini inconnu : turbo*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'refuse une option de modèle inconnue avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Model 'gemini-3.6-flash[fast]' } |
            Should -Throw -ExpectedMessage '*Option de modèle inconnue : fast*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'demande une sortie JSON structurée cueId/text' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
            New-GeminiStopResponse $script:HelloJson
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

        $config = $script:LastGeminiBody.generationConfig
        $config.responseMimeType | Should -Be 'application/json'
        $names = @($config.responseSchema.items.properties.PSObject.Properties.Name | Sort-Object)
        $names | Should -Be @('cueId', 'text')
    }

    It 'lève si Gemini ne retourne aucun candidat' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            [pscustomobject]@{ candidates = @() }
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage "*aucun candidat*"
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
    }

    It 'lève si finishReason n''est pas STOP' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
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

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage "*MAX_TOKENS*"
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
    }

    It 'lève si le texte utile est vide' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
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

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage "*résultat vide*"
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
    }

    It 'utilise le modèle Gemini fourni' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            if ($Uri -notlike '*gemini-custom:generateContent') {
                throw "URI inattendue : $Uri"
            }
            New-GeminiStopResponse $script:HelloJson
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Model 'gemini-custom' } |
            Should -Not -Throw
    }

    It 'refuse AllowModelDownload avec Provider Gemini avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Gemini -AllowModelDownload } |
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
                New-GeminiStopResponse $script:HelloJson
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

            $script:InfoLogs | Should -Contain "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=low)..."
            Should -Invoke -ModuleName Tetram.Media.Translation Write-InfoLog -Times 1 -ParameterFilter {
                [bool]$Force -and $Text -eq "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=low)..."
            }
        }

        It 'journalise l''invocation Gemini [thinking] avec thinking=medium' {
            $env:GEMINI_API_KEY = 'test-key'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                New-GeminiStopResponse $script:HelloJson
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Model 'gemini-3.6-flash[thinking]'

            $script:InfoLogs | Should -Contain "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=medium)..."
            @($script:InfoLogs | Where-Object { $_ -like '*gemini-3.6-flash[thinking]*' }) | Should -HaveCount 0
        }

        It 'n''annonce ni raw ni reconstruction si le transport Gemini échoue' {
            $env:GEMINI_API_KEY = 'test-key'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                [pscustomobject]@{ candidates = @() }
            }

            {
                ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath
            } | Should -Throw -ExpectedMessage '*aucun candidat*'

            $script:InfoLogs | Should -Contain "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=low)..."
            @($script:InfoLogs | Where-Object { $_ -like '*Réponse brute*' }) | Should -HaveCount 0
            @($script:InfoLogs | Where-Object { $_ -like '*Reconstruction*' }) | Should -HaveCount 0
        }

        It 'annonce raw puis reconstruction après une réponse Gemini valide' {
            $env:GEMINI_API_KEY = 'test-key'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                New-GeminiStopResponse $script:HelloJson
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

            $raw = Join-Path $script:Work 'episode.fr.raw.json'
            $invoke = Find-InfoLogIndex "Invocation de Gemini avec 'gemini-3.6-flash' (thinking=low)..."
            $rawLog = Find-InfoLogIndex "Réponse brute du modèle enregistrée : $raw"
            $rebuild = Find-InfoLogIndex 'Reconstruction du sous-titre final...'
            $invoke | Should -BeGreaterOrEqual 0
            $rawLog | Should -BeGreaterThan $invoke
            $rebuild | Should -BeGreaterThan $rawLog
        }

    }
}
