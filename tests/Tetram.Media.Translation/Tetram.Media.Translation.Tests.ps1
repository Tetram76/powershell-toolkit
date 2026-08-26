# Étendre la suite autour du module SUD Tetram.Media.Translation (traduction Gemini/Ollama de sous-titres).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Manifeste : Tetram.Media.Translation/Tetram.Media.Translation.psd1 — Test-ModuleManifest puis Import-Module -Force
# Réseau : mocker Invoke-RestMethod -ModuleName Tetram.Media.Translation ; jamais d'appel Gemini/Ollama réel.
# $TestDrive pour les fichiers source/sortie ; restaurer GEMINI_API_KEY après chaque test.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranslation = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRootTranslation = Join-Path $script:RepoRootTranslation 'Tetram.Media.Translation'
    $script:ManifestTranslation = Join-Path $script:ModuleRootTranslation 'Tetram.Media.Translation.psd1'

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

    function script:Get-CanonicalCuePart($Request) {
        $part = @(
            $Request.contents[0].parts |
                ForEach-Object { $_.text } |
                Where-Object { $_ -match 'CUES CANONIQUES' }
        )
        if ($part.Count -ne 1) {
            throw "part de source principale introuvable (count=$($part.Count))"
        }
        return $part[0]
    }

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
}

Describe 'Tetram.Media.Translation manifest' {
    It 'passe Test-ModuleManifest' {
        { Test-ModuleManifest -Path $script:ManifestTranslation -ErrorAction Stop } | Should -Not -Throw
    }

    It 'embarque Resources/ConvertTo-FrenchSubtitle.generate.prompt.md' {
        $promptPath = Join-Path $script:ModuleRootTranslation 'Resources' 'ConvertTo-FrenchSubtitle.generate.prompt.md'
        Test-Path -LiteralPath $promptPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:ModuleRootTranslation 'Resources' 'ConvertTo-FrenchSubtitle.prompt.md') |
            Should -BeFalse
    }
}

Describe 'Tetram.Media.Translation exports' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootTranslation -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Translation' -Force -ErrorAction SilentlyContinue
    }

    It 'exporte uniquement ConvertTo-FrenchSubtitle' {
        $names = @(Get-Command -Module 'Tetram.Media.Translation' | Select-Object -ExpandProperty Name | Sort-Object)
        $names | Should -Be @('ConvertTo-FrenchSubtitle')
    }
}

Describe 'ConvertTo-FrenchSubtitle' {
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
    }

    AfterEach {
        $env:GEMINI_API_KEY = $script:SavedGeminiKey
    }

    It 'refuse un sous-titre introuvable au binding' {
        { ConvertTo-FrenchSubtitle -SubtitlePath (Join-Path $script:Work 'absent.ass') -TranscriptPath $script:TranscriptPath } |
            Should -Throw
    }

    It 'refuse une transcription introuvable au binding' {
        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath (Join-Path $script:Work 'absent.txt') } |
            Should -Throw
    }

    It 'lève si le fichier de prompt est introuvable' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Test-Path {
            param($LiteralPath, $PathType)
            if ($LiteralPath -like '*ConvertTo-FrenchSubtitle.generate.prompt.md') {
                return $false
            }
            return Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage "*prompt*"
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

    It 'lève si le fichier de sortie existe déjà' {
        $env:GEMINI_API_KEY = 'test-key'
        $existing = Join-Path $script:Work 'episode.fr.ass'
        Set-Content -LiteralPath $existing -Value 'deja la' -Encoding utf8
        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage "*existe déjà*"
    }

    It 'refuse .txt avant tout appel Gemini' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.txt'
        Set-Content -LiteralPath $script:SubtitlePath -Value 'pas un sous-titre' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage '*Extension*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'écrit le résultat UTF-8 sans BOM à côté de la source avec le suffixe .fr' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse $script:HelloJson
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

        $output = Join-Path $script:Work 'episode.fr.ass'
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Test-Path -LiteralPath $output -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $script:HelloJson
        $written = (Get-Content -LiteralPath $output -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
        $written | Should -Not -Match 'Hello'
        foreach ($path in @($output, $raw)) {
            $bytes = [IO.File]::ReadAllBytes($path)
            ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        }
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

    It 'envoie la source principale SRT en cues canoniques distincts des identifiants natifs' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.srt'
        Set-Content -LiteralPath $script:SubtitlePath -Value "10`n00:00:01,000 --> 00:00:02,000`nHello`n`n42`n00:00:03,000 --> 00:00:04,000`nWorld`n" -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
            New-GeminiStopResponse '[{"cueId":1,"text":"Bonjour"},{"cueId":2,"text":"Monde"}]'
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

        $part = Get-CanonicalCuePart $script:LastGeminiBody
        ([regex]::Matches($part, '"cueId"')).Count | Should -Be 2
        $part | Should -Match '"cueId":\s*1'
        $part | Should -Match '"start":\s*"00:00:01,000"'
        $part | Should -Match '"end":\s*"00:00:02,000"'
        $part | Should -Match '"text":\s*"Hello"'
        $part | Should -Match '"cueId":\s*2'
        $part | Should -Match '"start":\s*"00:00:03,000"'
        $part | Should -Match '"end":\s*"00:00:04,000"'
        $part | Should -Match '"text":\s*"World"'
        $part | Should -Not -Match '"cueId":\s*10'
        $part | Should -Not -Match '"cueId":\s*42'
        $part | Should -Not -Match '(?m)^10$'
    }

    It 'envoie la source principale ASS en cues canoniques sans champs techniques' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
            New-GeminiStopResponse $script:HelloJson
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

        $part = Get-CanonicalCuePart $script:LastGeminiBody
        ([regex]::Matches($part, '"cueId"')).Count | Should -Be 1
        $part | Should -Match '"cueId":\s*1'
        $part | Should -Match '"start":\s*"0:00:01.00"'
        $part | Should -Match '"end":\s*"0:00:02.00"'
        $part | Should -Match '"text":\s*"Hello"'
        $part | Should -Not -Match 'Layer'
        $part | Should -Not -Match 'Default'
        $part | Should -Not -Match 'Margin'
        $part | Should -Not -Match 'Style'
    }

    It 'envoie la transcription telle quelle même avec un découpage différent' {
        $env:GEMINI_API_KEY = 'test-key'
        $transcript = "0:00:00.000 --> 0:00:02.500 Hello there friend`n0:00:02.400 --> 0:00:05.000 How are you today extra segment"
        Set-Content -LiteralPath $script:TranscriptPath -Value $transcript -Encoding utf8NoBOM -NoNewline
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
            New-GeminiStopResponse $script:HelloJson
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

        $part = $script:LastGeminiBody.contents[0].parts[2].text
        $part.Contains($transcript) | Should -BeTrue
        $part | Should -Match '===== TRANSCRIPTION WHISPER ====='
        $part | Should -Match '===== FIN TRANSCRIPTION WHISPER ====='
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

    It 'écrit sur OutputPath quand il est fourni' {
        $env:GEMINI_API_KEY = 'test-key'
        $custom = Join-Path $script:Work 'custom.fr.ass'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse $script:HelloJson
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -OutputPath $custom

        $written = (Get-Content -LiteralPath $custom -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        $raw = Join-Path $script:Work 'custom.fr.raw.json'
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
    }

    It 'conserve les timestamps SRT source après une réponse JSON complète' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.srt'
        Set-Content -LiteralPath $script:SubtitlePath -Value "37`n00:05:59,237 --> 00:06:00,057`nEnglish text`n" -Encoding utf8
        $json = '[{"cueId":1,"text":"texte français"}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse $json
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

        $output = Join-Path $script:Work 'episode.fr.srt'
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        $written = (Get-Content -LiteralPath $output -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match '00:05:59,237 --> 00:06:00,057'
        $written | Should -Match 'texte français'
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $json
    }

    It 'conserve le raw.json et n''écrit pas le final si un cueId manque' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.srt'
        Set-Content -LiteralPath $script:SubtitlePath -Value "1`n00:00:01,000 --> 00:00:02,000`nA`n`n2`n00:00:03,000 --> 00:00:04,000`nB`n`n3`n00:00:05,000 --> 00:00:06,000`nC`n`n4`n00:00:07,000 --> 00:00:08,000`nD`n" -Encoding utf8
        $json = '[{"cueId":1,"text":"A"},{"cueId":2,"text":"B"},{"cueId":4,"text":"D"}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse $json
        }

        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -WarningVariable warn -WarningAction Continue
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $json
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.srt') | Should -BeFalse
        "$warn" | Should -Match 'cueId 3 manquant'
    }

    It 'reconstruit selon cueId même si Gemini les renvoie dans le désordre' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.srt'
        Set-Content -LiteralPath $script:SubtitlePath -Value "10`n00:00:01,000 --> 00:00:02,000`nA`n`n20`n00:00:03,000 --> 00:00:04,000`nB`n`n30`n00:00:05,000 --> 00:00:06,000`nC`n" -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse '[{"cueId":3,"text":"Troisième"},{"cueId":1,"text":"Premier"},{"cueId":2,"text":"Deuxième"}]'
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

        $written = (Get-Content -LiteralPath (Join-Path $script:Work 'episode.fr.srt') -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match '(?s)10\n00:00:01,000 --> 00:00:02,000\nPremier'
        $written | Should -Match '(?s)20\n00:00:03,000 --> 00:00:04,000\nDeuxième'
        $written | Should -Match '(?s)30\n00:00:05,000 --> 00:00:06,000\nTroisième'
    }

    It 'conserve le raw.json et n''écrit pas le final si un cueId est dupliqué' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = '[{"cueId":1,"text":"Bonjour"},{"cueId":1,"text":"Salut"}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse $json
        }

        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -WarningVariable warn -WarningAction Continue
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $json
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        "$warn" | Should -Match 'dupliqu'
    }

    It 'conserve le raw.json et n''écrit pas le final si un cueId est hors plage' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = '[{"cueId":1,"text":"Bonjour"},{"cueId":9,"text":"Trop loin"}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse $json
        }

        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -WarningVariable warn -WarningAction Continue
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $json
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        "$warn" | Should -Match 'hors plage'
    }

    It 'conserve le raw.json et n''écrit pas le final si le JSON est invalide' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = 'ceci n''est pas du JSON {'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse $json
        }

        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -WarningVariable warn -WarningAction Continue
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $json
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        "$warn" | Should -Match 'JSON'
    }

    It 'conserve le raw.json et n''écrit pas le final si text est vide sur une source non vide' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = '[{"cueId":1,"text":""}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse $json
        }

        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -WarningVariable warn -WarningAction Continue
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $json
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        "$warn" | Should -Match 'vide'
    }

    It 'conserve le raw.json et n''écrit pas le final si text n''est que des espaces sur une source non vide' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = '[{"cueId":1,"text":" "}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse $json
        }

        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -WarningVariable warn -WarningAction Continue
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $json
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        "$warn" | Should -Match 'vide'
    }

    It 'conserve le raw.json et n''écrit pas le final si Gemini altère une balise ASS' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = '[{"cueId":1,"text":"{\\b1}Bonjour{\\i0}"}]'
        Set-Content -LiteralPath $script:SubtitlePath -Value "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\i1}Hello{\i0}`n" -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            New-GeminiStopResponse $json
        }

        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -WarningVariable warn -WarningAction Continue
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $json
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        "$warn" | Should -Match 'reconstruction'
    }

    It 'refuse un raw.json déjà présent avant tout appel Gemini' {
        $env:GEMINI_API_KEY = 'test-key'
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Set-Content -LiteralPath $raw -Value 'ne-pas-ecraser' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage '*existe déjà*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)).Trim() | Should -Be 'ne-pas-ecraser'
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
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
            Should -Throw -ExpectedMessage '*AllowModelDownload*Ollama*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
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
}
