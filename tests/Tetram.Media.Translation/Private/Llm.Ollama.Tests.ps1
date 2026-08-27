# Étendre la suite autour de Llm.Ollama.ps1 (Invoke-OllamaTranslationLlm).
#
# RepoRoot depuis tests/<Module>/Private : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Translation') -Force
# Réseau : mocker Invoke-RestMethod -ModuleName Tetram.Media.Translation ; jamais d'appel Ollama réel.
# $TestDrive pour les fichiers source/sortie ; restaurer GEMINI_API_KEY après chaque test.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranslation = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranslation = Join-Path $script:RepoRootTranslation 'Tetram.Media.Translation'

    function script:New-OllamaTagsResponse([string[]] $Name) {
        [pscustomobject]@{
            models = @(
                $Name | ForEach-Object {
                    [pscustomobject]@{
                        name  = $_
                        model = $_
                    }
                }
            )
        }
    }

    function script:New-OllamaChatResponse([string] $Content, [bool] $Done = $true) {
        [pscustomobject]@{
            done    = $Done
            message = [pscustomobject]@{
                role    = 'assistant'
                content = $Content
            }
        }
    }

    function script:ConvertFrom-OllamaRequestBody([string] $Body) {
        ConvertFrom-Json -InputObject $Body -Depth 20
    }

    function script:Get-RestCall([string] $Suffix) {
        return @($script:RestCalls | Where-Object { $_.Uri -like "*$Suffix" })
    }

    function script:Add-CurrentRestCall {
        param($Uri, $Method, $Body = $null)
        # GET /api/tags n'envoie pas -Body ; le paramètre doit rester optionnel sous StrictMode.
        $script:RestCalls.Add([pscustomobject]@{
            Uri    = [string]$Uri
            Method = [string]$Method
            Body   = $Body
        })
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

Describe 'Llm.Ollama' {
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

    It 'n''exige pas GEMINI_API_KEY avec Provider Ollama' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'llama3.2'
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $script:HelloJson
            }
            throw "URI inattendue : $u"
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2 } |
            Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') -PathType Leaf | Should -BeTrue
    }

    It 'utilise qwen3.5:9b par défaut avec Provider Ollama' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'qwen3.5:9b'
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $script:HelloJson
            }
            throw "URI inattendue : $u"
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama

        $chat = @(Get-RestCall '/api/chat')
        $chat.Count | Should -Be 1
        $parsed = ConvertFrom-OllamaRequestBody $chat[0].Body
        $parsed.model | Should -Be 'qwen3.5:9b'
        $parsed.think | Should -BeFalse
    }

    It 'lève une erreur actionnable si Ollama est inaccessible' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                throw 'Unable to connect to the remote server'
            }
            throw "URI inattendue : $u"
        }

        $err = $null
        try {
            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2
        }
        catch {
            $err = $_
        }

        $err | Should -Not -BeNullOrEmpty
        "$err" | Should -Match 'http://localhost:11434'
        "$err" | Should -Match 'winget install --id Ollama.Ollama -e'
        "$err" | Should -Match 'https://ollama.com/download/windows'
        "$err" | Should -Match 'ollama serve'
        @(Get-RestCall '/api/chat').Count | Should -Be 0
    }

    It 'appelle /api/chat sans pull si le modèle Ollama est déjà installé' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'llama3.2'
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $script:HelloJson
            }
            throw "URI inattendue : $u"
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2

        @(Get-RestCall '/api/pull').Count | Should -Be 0
        $chat = @(Get-RestCall '/api/chat')
        $chat.Count | Should -Be 1
        $parsed = ConvertFrom-OllamaRequestBody $chat[0].Body
        $parsed.model | Should -Be 'llama3.2'
        $parsed.think | Should -BeFalse
        $parsed.stream | Should -BeFalse
        $parsed.messages.Count | Should -Be 1
        $parsed.messages[0].role | Should -Be 'user'
        $parsed.format.type | Should -Be 'array'
        $parsed.format.items.properties.cueId.type | Should -Be 'integer'
        $parsed.format.items.properties.text.type | Should -Be 'string'
        @($parsed.format.items.required) | Should -Be @('cueId', 'text')
    }

    It 'considère présent un modèle Ollama demandé sans tag si tags retourne :latest' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'exemple:latest'
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $script:HelloJson
            }
            throw "URI inattendue : $u"
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model exemple

        @(Get-RestCall '/api/pull').Count | Should -Be 0
        @(Get-RestCall '/api/chat').Count | Should -Be 1
    }

    It 'n''appelle pas /api/pull si le modèle Ollama est déjà présent même avec AllowModelDownload' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'llama3.2'
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $script:HelloJson
            }
            throw "URI inattendue : $u"
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2 -AllowModelDownload

        @(Get-RestCall '/api/pull').Count | Should -Be 0
        @(Get-RestCall '/api/chat').Count | Should -Be 1
    }

    It 'lève si le modèle Ollama est absent sans AllowModelDownload' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'autre-modele'
            }
            throw "URI inattendue : $u"
        }

        $err = $null
        try {
            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2
        }
        catch {
            $err = $_
        }

        $err | Should -Not -BeNullOrEmpty
        "$err" | Should -Match '-AllowModelDownload'
        "$err" | Should -Match 'ollama pull llama3.2'
        @(Get-RestCall '/api/pull').Count | Should -Be 0
        @(Get-RestCall '/api/chat').Count | Should -Be 0
    }

    It 'télécharge puis génère si le modèle Ollama est absent avec AllowModelDownload' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'autre-modele'
            }
            if ($u -like '*/api/pull') {
                return [pscustomobject]@{ status = 'success' }
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $script:HelloJson
            }
            throw "URI inattendue : $u"
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2 -AllowModelDownload

        $script:RestCalls.Count | Should -Be 3
        $script:RestCalls[0].Uri | Should -Match '/api/tags'
        $script:RestCalls[1].Uri | Should -Match '/api/pull'
        $script:RestCalls[2].Uri | Should -Match '/api/chat'
        $pull = ConvertFrom-OllamaRequestBody $script:RestCalls[1].Body
        $pull.model | Should -Be 'llama3.2'
        $pull.stream | Should -BeFalse
    }

    It 'envoie think false pour Ollama sans option thinking' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'qwen3.5:9b'
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $script:HelloJson
            }
            throw "URI inattendue : $u"
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model 'qwen3.5:9b'

        $chat = @(Get-RestCall '/api/chat')
        $parsed = ConvertFrom-OllamaRequestBody $chat[0].Body
        $parsed.model | Should -Be 'qwen3.5:9b'
        $parsed.think | Should -BeFalse
        "$($chat[0].Body)" | Should -Not -Match '\[thinking'
    }

    It 'envoie think true pour Ollama [thinking] sans suffixe dans le nom du modèle' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'qwen3.5:9b'
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $script:HelloJson
            }
            throw "URI inattendue : $u"
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model 'qwen3.5:9b[thinking]'

        $chat = @(Get-RestCall '/api/chat')
        $chat.Count | Should -Be 1
        $parsed = ConvertFrom-OllamaRequestBody $chat[0].Body
        $parsed.model | Should -Be 'qwen3.5:9b'
        $parsed.think | Should -BeTrue
        "$($chat[0].Body)" | Should -Not -Match '\[thinking'
        foreach ($call in $script:RestCalls) {
            $call.Uri | Should -Not -Match '\[thinking'
            if ($null -ne $call.Body) {
                "$($call.Body)" | Should -Not -Match '\[thinking'
            }
        }
    }

    It 'refuse Ollama [thinking=high] avant /api/tags' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            Add-CurrentRestCall -Uri $Uri -Method $Method -Body $Body
            throw 'Ollama ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model 'qwen3.5:9b[thinking=high]' } |
            Should -Throw -ExpectedMessage '*réservée à Gemini*'
        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model 'qwen3.5:9b[thinking=high]' } |
            Should -Throw -ExpectedMessage '*Avec Ollama, utilisez soit*'
        @(Get-RestCall '/api/tags').Count | Should -Be 0
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'propose ollama pull du nom réel si Ollama [thinking] est absent sans AllowModelDownload' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'autre-modele'
            }
            throw "URI inattendue : $u"
        }

        $err = $null
        try {
            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model 'qwen3.5:9b[thinking]'
        }
        catch {
            $err = $_
        }

        $err | Should -Not -BeNullOrEmpty
        "$err" | Should -Match 'ollama pull qwen3.5:9b'
        "$err" | Should -Not -Match 'qwen3.5:9b\[thinking\]'
        @(Get-RestCall '/api/pull').Count | Should -Be 0
        @(Get-RestCall '/api/chat').Count | Should -Be 0
    }

    It 'télécharge le nom réel si Ollama [thinking] est absent avec AllowModelDownload' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'autre-modele'
            }
            if ($u -like '*/api/pull') {
                return [pscustomobject]@{ status = 'success' }
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $script:HelloJson
            }
            throw "URI inattendue : $u"
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model 'qwen3.5:9b[thinking]' -AllowModelDownload

        $pull = ConvertFrom-OllamaRequestBody (Get-RestCall '/api/pull')[0].Body
        $pull.model | Should -Be 'qwen3.5:9b'
        $chat = ConvertFrom-OllamaRequestBody (Get-RestCall '/api/chat')[0].Body
        $chat.model | Should -Be 'qwen3.5:9b'
        $chat.think | Should -BeTrue
        foreach ($call in $script:RestCalls) {
            $call.Uri | Should -Not -Match '\[thinking'
            if ($null -ne $call.Body) {
                "$($call.Body)" | Should -Not -Match '\[thinking'
            }
        }
    }

    It 'n''appelle pas /api/chat si le téléchargement Ollama échoue' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'autre-modele'
            }
            if ($u -like '*/api/pull') {
                throw 'pull model manifest: file does not exist'
            }
            throw "URI inattendue : $u"
        }

        $err = $null
        try {
            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2 -AllowModelDownload
        }
        catch {
            $err = $_
        }

        $err | Should -Not -BeNullOrEmpty
        "$err" | Should -Match 'llama3.2'
        "$err" | Should -Match 'ollama pull llama3.2'
        @(Get-RestCall '/api/chat').Count | Should -Be 0
    }

    It 'n''appelle pas /api/chat si /api/pull retourne $null' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'autre-modele'
            }
            if ($u -like '*/api/pull') {
                return $null
            }
            throw "URI inattendue : $u"
        }

        $err = $null
        try {
            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2 -AllowModelDownload
        }
        catch {
            $err = $_
        }

        $err | Should -Not -BeNullOrEmpty
        "$err" | Should -Match 'llama3.2'
        "$err" | Should -Match 'ollama pull llama3.2'
        @(Get-RestCall '/api/chat').Count | Should -Be 0
    }

    It 'n''appelle pas /api/chat si /api/pull n''a pas status success' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $u = [string]$Uri
            Add-CurrentRestCall -Uri $u -Method $Method -Body $Body
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'autre-modele'
            }
            if ($u -like '*/api/pull') {
                return [pscustomobject]@{ digest = 'abc' }
            }
            throw "URI inattendue : $u"
        }

        $err = $null
        try {
            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2 -AllowModelDownload
        }
        catch {
            $err = $_
        }

        $err | Should -Not -BeNullOrEmpty
        "$err" | Should -Match 'llama3.2'
        "$err" | Should -Match 'ollama pull llama3.2'
        @(Get-RestCall '/api/chat').Count | Should -Be 0
    }

    It 'écrit raw et final pour une réponse Ollama JSON complète' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            $u = [string]$Uri
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'llama3.2'
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $script:HelloJson
            }
            throw "URI inattendue : $u"
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2

        $output = Join-Path $script:Work 'episode.fr.ass'
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Test-Path -LiteralPath $output -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $script:HelloJson
        $written = (Get-Content -LiteralPath $output -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
    }

    It 'conserve le raw.json Ollama et n''écrit pas le final si le JSON métier est invalide' {
        $env:GEMINI_API_KEY = $null
        $json = 'ceci n''est pas du JSON {'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            $u = [string]$Uri
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'llama3.2'
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse $json
            }
            throw "URI inattendue : $u"
        }

        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2 -WarningVariable warn -WarningAction Continue
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $json
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        "$warn" | Should -Match 'reconstruction'
    }

    It 'lève si le contenu Ollama est vide sans écrire de raw' {
        $env:GEMINI_API_KEY = $null
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            $u = [string]$Uri
            if ($u -like '*/api/tags') {
                return New-OllamaTagsResponse 'llama3.2'
            }
            if ($u -like '*/api/chat') {
                return New-OllamaChatResponse '   '
            }
            throw "URI inattendue : $u"
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2 } |
            Should -Throw -ExpectedMessage '*vide*'
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
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

        It 'journalise l''invocation Ollama sans thinking' {
            $env:GEMINI_API_KEY = $null
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                $u = [string]$Uri
                if ($u -like '*/api/tags') {
                    return New-OllamaTagsResponse 'qwen3.5:9b'
                }
                if ($u -like '*/api/chat') {
                    return New-OllamaChatResponse $script:HelloJson
                }
                throw "URI inattendue : $u"
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model 'qwen3.5:9b'

            $script:InfoLogs | Should -Contain "Invocation d'Ollama avec 'qwen3.5:9b' (thinking=false)..."
        }

        It 'journalise l''invocation Ollama [thinking] sans le suffixe dans le nom' {
            $env:GEMINI_API_KEY = $null
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                $u = [string]$Uri
                if ($u -like '*/api/tags') {
                    return New-OllamaTagsResponse 'qwen3.5:9b'
                }
                if ($u -like '*/api/chat') {
                    return New-OllamaChatResponse $script:HelloJson
                }
                throw "URI inattendue : $u"
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model 'qwen3.5:9b[thinking]'

            $script:InfoLogs | Should -Contain "Invocation d'Ollama avec 'qwen3.5:9b' (thinking=true)..."
            @($script:InfoLogs | Where-Object { $_ -like '*qwen3.5:9b[thinking]*' }) | Should -HaveCount 0
        }

        It 'journalise le téléchargement Ollama puis l''invocation dans cet ordre' {
            $env:GEMINI_API_KEY = $null
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                $u = [string]$Uri
                if ($u -like '*/api/tags') {
                    return New-OllamaTagsResponse 'autre-modele'
                }
                if ($u -like '*/api/pull') {
                    return [pscustomobject]@{ status = 'success' }
                }
                if ($u -like '*/api/chat') {
                    return New-OllamaChatResponse $script:HelloJson
                }
                throw "URI inattendue : $u"
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model 'qwen3.5:9b' -AllowModelDownload

            $download = Find-InfoLogIndex "Téléchargement du modèle Ollama 'qwen3.5:9b'..."
            $done = Find-InfoLogIndex "Modèle Ollama 'qwen3.5:9b' téléchargé."
            $invoke = Find-InfoLogIndex "Invocation d'Ollama avec 'qwen3.5:9b' (thinking=false)..."
            $download | Should -BeGreaterOrEqual 0
            $done | Should -BeGreaterThan $download
            $invoke | Should -BeGreaterThan $done
        }

        It 'n''annonce pas de téléchargement si le modèle Ollama est déjà présent' {
            $env:GEMINI_API_KEY = $null
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                $u = [string]$Uri
                if ($u -like '*/api/tags') {
                    return New-OllamaTagsResponse 'qwen3.5:9b'
                }
                if ($u -like '*/api/chat') {
                    return New-OllamaChatResponse $script:HelloJson
                }
                throw "URI inattendue : $u"
            }

            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model 'qwen3.5:9b'

            @($script:InfoLogs | Where-Object { $_ -like '*Téléchargement du modèle*' }) | Should -HaveCount 0
            $script:InfoLogs | Should -Contain "Invocation d'Ollama avec 'qwen3.5:9b' (thinking=false)..."
        }

        It 'n''annonce ni succès de pull ni invocation si le téléchargement Ollama échoue' {
            $env:GEMINI_API_KEY = $null
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                $u = [string]$Uri
                if ($u -like '*/api/tags') {
                    return New-OllamaTagsResponse 'autre-modele'
                }
                if ($u -like '*/api/pull') {
                    throw 'pull model manifest: file does not exist'
                }
                throw "URI inattendue : $u"
            }

            {
                ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2 -AllowModelDownload
            } | Should -Throw

            $script:InfoLogs | Should -Contain "Téléchargement du modèle Ollama 'llama3.2'..."
            @($script:InfoLogs | Where-Object { $_ -like '*téléchargé*' }) | Should -HaveCount 0
            @($script:InfoLogs | Where-Object { $_ -like '*Invocation d''Ollama*' }) | Should -HaveCount 0
        }

        It 'n''annonce ni téléchargement ni invocation si le modèle Ollama est absent sans AllowModelDownload' {
            $env:GEMINI_API_KEY = $null
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                $u = [string]$Uri
                if ($u -like '*/api/tags') {
                    return New-OllamaTagsResponse 'autre-modele'
                }
                throw "URI inattendue : $u"
            }

            {
                ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2
            } | Should -Throw -ExpectedMessage '*AllowModelDownload*'

            @($script:InfoLogs | Where-Object { $_ -like '*Téléchargement du modèle*' }) | Should -HaveCount 0
            @($script:InfoLogs | Where-Object { $_ -like '*Invocation d''Ollama*' }) | Should -HaveCount 0
        }

        It 'n''annonce pas l''invocation Ollama si /api/tags échoue' {
            $env:GEMINI_API_KEY = $null
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                $u = [string]$Uri
                if ($u -like '*/api/tags') {
                    throw 'Unable to connect to the remote server'
                }
                throw "URI inattendue : $u"
            }

            {
                ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -Provider Ollama -Model llama3.2
            } | Should -Throw -ExpectedMessage '*localhost:11434*'

            @($script:InfoLogs | Where-Object { $_ -like '*Invocation d''Ollama*' }) | Should -HaveCount 0
        }

    }
}
