# Étendre la suite autour du module SUD Tetram.Media.Translation (orchestration ConvertTo-FrenchSubtitle).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Manifeste : Tetram.Media.Translation/Tetram.Media.Translation.psd1 — Test-ModuleManifest puis Import-Module -Force
# Réseau : mocker Invoke-RestMethod -ModuleName Tetram.Media.Translation ; jamais d'appel Gemini/Ollama réel.
# $TestDrive pour les fichiers source/sortie ; restaurer GEMINI_API_KEY après chaque test.
# Providers : tests/Tetram.Media.Translation/Private/Llm.Gemini.Tests.ps1 et Llm.Ollama.Tests.ps1.

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

    function script:Find-InfoLogIndex([string] $Like) {
        for ($i = 0; $i -lt $script:InfoLogs.Count; $i++) {
            if ($script:InfoLogs[$i] -like $Like) {
                return $i
            }
        }
        return -1
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

    It 'rend Write-InfoLog disponible dans le session state du module' {
        $cmd = InModuleScope 'Tetram.Media.Translation' {
            Get-Command -Name Write-InfoLog -ErrorAction Stop
        }
        $cmd.Name | Should -Be 'Write-InfoLog'
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
        $script:InfoLogs = [System.Collections.Generic.List[string]]::new()
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

        It 'annonce raw puis reconstruction et conserve le raw si le JSON métier est invalide' {
            $env:GEMINI_API_KEY = 'test-key'
            $json = 'ceci n''est pas du JSON {'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                New-GeminiStopResponse $json
            }

            $warn = $null
            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -WarningVariable warn -WarningAction Continue

            $raw = Join-Path $script:Work 'episode.fr.raw.json'
            $script:InfoLogs | Should -Contain "Réponse brute du modèle enregistrée : $raw"
            $script:InfoLogs | Should -Contain 'Reconstruction du sous-titre final...'
            (Find-InfoLogIndex "Réponse brute du modèle enregistrée : $raw") | Should -BeLessThan (Find-InfoLogIndex 'Reconstruction du sous-titre final...')
            "$warn" | Should -Match 'reconstruction'
            Test-Path -LiteralPath $raw -PathType Leaf | Should -BeTrue
            [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)) | Should -Be $json
            Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        }

    }
}
