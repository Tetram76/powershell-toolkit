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

    function script:New-GeminiCountTokensResponse([int] $TotalTokens = 100) {
        [pscustomobject]@{ totalTokens = $TotalTokens }
    }

    function script:Get-GeminiMockResponse {
        param(
            $Uri,
            [scriptblock] $OnGenerateContent
        )
        if ([string]$Uri -like '*:countTokens') {
            return New-GeminiCountTokensResponse 100
        }
        & $OnGenerateContent
    }

    function script:Reset-GeminiRateHistory {
        InModuleScope 'Tetram.Media.Translation' {
            if (Get-Variable -Name GeminiRateHistory -Scope Script -ErrorAction SilentlyContinue) {
                $script:GeminiRateHistory.Clear()
            }
        }
    }

    function script:Get-GeminiPromptText($Request) {
        return @(
            $Request.contents[0].parts | ForEach-Object { $_.text }
        )
    }

    function script:Get-CanonicalCuePart($Request) {
        return Get-PromptPartByMarker $Request '===== GABARIT TECHNIQUE FINAL ====='
    }

    function script:Get-StructuringSourcePart($Request) {
        return Get-PromptPartByMarker $Request '===== SOURCE LINGUISTIQUE 1 — SOUS-TITRE STRUCTURANT ====='
    }

    function script:Get-PromptPartByMarker($Request, [string] $Marker) {
        # Les instructions nomment les mêmes types : seuls les blocs délimités par ===== sont des sources.
        $escaped = [regex]::Escape($Marker)
        $part = @(
            Get-GeminiPromptText $Request |
                Where-Object { $_ -match $escaped -and $_ -match '(?m)^=====' }
        )
        if ($part.Count -ne 1) {
            throw "part '$Marker' introuvable (count=$($part.Count))"
        }
        return $part[0]
    }

    function script:Get-SecondaryTranscriptJsonFromPrompt($Request, [string] $Marker = 'TRANSCRIPTION AUTOMATIQUE JSON') {
        $part = Get-PromptPartByMarker $Request $Marker
        if ($part -notmatch '(?s)===== SOURCE LINGUISTIQUE \d+ — TRANSCRIPTION AUTOMATIQUE JSON =====\r?\n(.+)\r?\n===== FIN SOURCE LINGUISTIQUE \d+ =====') {
            throw 'JSON de transcription compact introuvable dans le prompt'
        }
        return $Matches[1].Trim()
    }

    function script:Find-InfoLogIndex([string] $Like) {
        for ($i = 0; $i -lt $script:InfoLogs.Count; $i++) {
            if ($script:InfoLogs[$i] -like $Like) {
                return $i
            }
        }
        return -1
    }

    function script:Get-TranslationRawTempFiles {
        @(
            Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter 'tetram-translation-*.json' -File -ErrorAction SilentlyContinue |
                Where-Object { $null -ne $_ }
        )
    }

    function script:Assert-TranslationRawTempCleaned {
        param($Before)
        $beforeNames = @(
            @($Before) |
                Where-Object { $null -ne $_ } |
                ForEach-Object { $_.FullName }
        )
        $leftover = @(
            Get-TranslationRawTempFiles |
                Where-Object { $_.FullName -notin $beforeNames }
        )
        $leftover | Should -HaveCount 0
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

    It 'établit les rôles des sources dans le prompt métier' {
        $promptPath = Join-Path $script:ModuleRootTranslation 'Resources' 'ConvertTo-FrenchSubtitle.generate.prompt.md'
        $prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding utf8

        $prompt | Should -Match 'gabarit technique'
        $prompt | Should -Match 'SOURCE LINGUISTIQUE 1 — SOUS-TITRE STRUCTURANT'
        $prompt | Should -Match "Déterminer l'intention, le sens et les nuances avant de traduire"
        $prompt | Should -Match "Critères d'acceptation de la traduction"
        $prompt | Should -Match "Une traduction plus littérale n'est jamais préférable par principe"
        $prompt | Should -Match 'Convergence et divergence entre plusieurs Whisper'
        $prompt | Should -Match 'pondération locale'
        $prompt | Should -Match "Aucune source n'est autoritaire linguistiquement"
        $prompt | Should -Match 'par son numéro ou sa position'
        $prompt | Should -Match 'JSON compact par segments'
        $prompt | Should -Match 'avg_logprob'
        $prompt | Should -Match 'no_speech_prob'
        $prompt | Should -Match 'même modèle ASR'
        $prompt | Should -Match 'deux votes ASR indépendants'
        $prompt | Should -Match 'pas un signal négatif'
        $prompt | Should -Match 'plus indépendante'
        $prompt | Should -Match 'preuve automatique d''absence'
        $prompt | Should -Not -Match 'Déterminer le sens avant de traduire'
        $prompt | Should -Not -Match 'SOURCE PRINCIPALE'
        $prompt | Should -Not -Match 'JSON brut'
        $prompt | Should -Not -Match 'niveau mot'
        $prompt | Should -Not -Match 'Lorsque la transcription japonaise est claire'
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
        $script:MinimalAssHello = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello`n"
        $script:HelloJson = '[{"cueId":1,"text":"Bonjour"}]'
        Set-Content -LiteralPath $script:SubtitlePath -Value $script:MinimalAssHello -Encoding utf8
        $script:LastGeminiBody = $null
        $script:RestCalls = [System.Collections.Generic.List[object]]::new()
        $script:InfoLogs = [System.Collections.Generic.List[string]]::new()
        Reset-GeminiRateHistory
    }

    AfterEach {
        $env:GEMINI_API_KEY = $script:SavedGeminiKey
    }

    It 'refuse un sous-titre introuvable au binding' {
        { ConvertTo-FrenchSubtitle -SubtitlePath (Join-Path $script:Work 'absent.ass') } |
            Should -Throw
    }

    It 'expose SubtitlePath obligatoire et SecondarySourcePath optionnel multi-fichiers' {
        $cmd = Get-Command -Name ConvertTo-FrenchSubtitle
        $cmd.Parameters.ContainsKey('TranscriptPath') | Should -BeFalse
        @($cmd.Parameters['SubtitlePath'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        $cmd.Parameters['SecondarySourcePath'].ParameterType | Should -Be ([string[]])
        @($cmd.Parameters['SecondarySourcePath'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeFalse
    }

    It 'refuse une source secondaire introuvable au binding' {
        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath (Join-Path $script:Work 'absent.json') } |
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

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
            Should -Throw -ExpectedMessage "*prompt*"
    }

    It 'lève si le fichier de sortie existe déjà' {
        $env:GEMINI_API_KEY = 'test-key'
        $existing = Join-Path $script:Work 'episode.fr.ass'
        Set-Content -LiteralPath $existing -Value 'deja la' -Encoding utf8
        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
            Should -Throw -ExpectedMessage "*existe déjà*"
    }

    It 'refuse .txt avant tout appel Gemini' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.txt'
        Set-Content -LiteralPath $script:SubtitlePath -Value 'pas un sous-titre' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath } |
            Should -Throw -ExpectedMessage '*Extension*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'écrit le résultat UTF-8 sans BOM à côté de la source avec le suffixe .fr' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
        $output = Join-Path $script:Work 'episode.fr.ass'
        Test-Path -LiteralPath $output -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
        $written = (Get-Content -LiteralPath $output -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
        $written | Should -Not -Match 'Hello'
        $bytes = [IO.File]::ReadAllBytes($output)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'envoie un gabarit SRT cueId/start/end sans text, distinct des identifiants natifs' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.srt'
        Set-Content -LiteralPath $script:SubtitlePath -Value "10`n00:00:01,000 --> 00:00:02,000`nHello`n`n42`n00:00:03,000 --> 00:00:04,000`nWorld`n" -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse '[{"cueId":1,"text":"Bonjour"},{"cueId":2,"text":"Monde"}]'
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
        $part = Get-CanonicalCuePart $script:LastGeminiBody
        $part | Should -Match '===== GABARIT TECHNIQUE FINAL ====='
        $part | Should -Match '===== FIN GABARIT TECHNIQUE FINAL ====='
        ([regex]::Matches($part, '"cueId"')).Count | Should -Be 2
        $part | Should -Match '"cueId":\s*1'
        $part | Should -Match '"start":\s*"00:00:01,000"'
        $part | Should -Match '"end":\s*"00:00:02,000"'
        $part | Should -Match '"cueId":\s*2'
        $part | Should -Match '"start":\s*"00:00:03,000"'
        $part | Should -Match '"end":\s*"00:00:04,000"'
        $part | Should -Not -Match '"text"'
        $part | Should -Not -Match '"cueId":\s*10'
        $part | Should -Not -Match '"cueId":\s*42'
        $part | Should -Not -Match '(?m)^10$'

        $structuring = Get-StructuringSourcePart $script:LastGeminiBody
        $structuring | Should -Match '"start":\s*"00:00:01,000"'
        $structuring | Should -Match '"end":\s*"00:00:02,000"'
        $structuring | Should -Match '"text":\s*"Hello"'
        $structuring | Should -Match '"text":\s*"World"'
        $structuring | Should -Not -Match '"cueId"'
    }

    It 'envoie un gabarit ASS cueId/start/end sans text ni champs techniques' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
        $part = Get-CanonicalCuePart $script:LastGeminiBody
        $part | Should -Match '===== GABARIT TECHNIQUE FINAL ====='
        ([regex]::Matches($part, '"cueId"')).Count | Should -Be 1
        $part | Should -Match '"cueId":\s*1'
        $part | Should -Match '"start":\s*"0:00:01.00"'
        $part | Should -Match '"end":\s*"0:00:02.00"'
        $part | Should -Not -Match '"text"'
        $part | Should -Not -Match 'Layer'
        $part | Should -Not -Match 'Default'
        $part | Should -Not -Match 'Margin'
        $part | Should -Not -Match 'Style'

        $structuring = Get-StructuringSourcePart $script:LastGeminiBody
        $structuring | Should -Match '"start":\s*"0:00:01.00"'
        $structuring | Should -Match '"end":\s*"0:00:02.00"'
        $structuring | Should -Match '"text":\s*"Hello"'
        $structuring | Should -Not -Match '"cueId"'
    }

    It 'conserve les markers du text structurant sans les parser' {
        $env:GEMINI_API_KEY = 'test-key'
        Set-Content -LiteralPath $script:SubtitlePath -Value "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\i1}Hello{\i0}`n" -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse '[{"cueId":1,"text":"{\\i1}Bonjour{\\i0}"}]'
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
        $structuring = Get-StructuringSourcePart $script:LastGeminiBody
        if ($structuring -notmatch '(?s)===== SOURCE LINGUISTIQUE 1 — SOUS-TITRE STRUCTURANT =====\r?\n(.+)\r?\n===== FIN SOURCE LINGUISTIQUE 1 =====') {
            throw 'JSON structurant introuvable'
        }
        $got = ConvertFrom-Json -InputObject $Matches[1].Trim()
        $got.text | Should -Be '{\i1}Hello{\i0}'
        $structuring | Should -Not -Match 'requiredMarkers'
    }

    It 'envoie un JSON Tetram secondaire compacté avant le prompt' {
        $env:GEMINI_API_KEY = 'test-key'
        $whisperJson = @'
{
  "engine": "faster-whisper",
  "model": "large-v3",
  "language": "ja",
  "languageSource": "forced",
  "audioTrack": 1,
  "unexpected_root": 123,
  "segments": [
    {
      "start": 12.34,
      "end": 15.67,
      "text": "recognized text",
      "words": [
        {
          "text": "recognized",
          "start": 12.34,
          "end": 12.80,
          "probability": 0.93
        }
      ],
      "diagnostics": {
        "temperature": 0,
        "avg_logprob": -0.42,
        "compression_ratio": 1.31,
        "no_speech_prob": 0.02,
        "tokens": [50364, 1234, 5678]
      },
      "unexpected_segment": "drop me"
    }
  ]
}
'@
        $whisperPath = Join-Path $script:Work 'episode.track 1.ja.large-v3.json'
        Set-Content -LiteralPath $whisperPath -Value $whisperJson -Encoding utf8NoBOM -NoNewline
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath $whisperPath

        $part = Get-PromptPartByMarker $script:LastGeminiBody 'TRANSCRIPTION AUTOMATIQUE JSON'
        $part | Should -Match '===== SOURCE LINGUISTIQUE 2 — TRANSCRIPTION AUTOMATIQUE JSON ====='
        $part | Should -Match '===== FIN SOURCE LINGUISTIQUE 2 ====='
        $part | Should -Not -Match '"cueId"'
        Get-StructuringSourcePart $script:LastGeminiBody | Should -Match '===== SOURCE LINGUISTIQUE 1 — SOUS-TITRE STRUCTURANT ====='
        $part.Contains($whisperJson) | Should -BeFalse

        $compact = Get-SecondaryTranscriptJsonFromPrompt $script:LastGeminiBody
        { ConvertFrom-Json -InputObject $compact -ErrorAction Stop } | Should -Not -Throw
        $compact | Should -Not -Match '[\r\n]'
        $got = ConvertFrom-Json -InputObject $compact
        $got.engine | Should -Be 'faster-whisper'
        $got.model | Should -Be 'large-v3'
        $got.PSObject.Properties.Name | Should -Not -Contain 'vad'
        $got.language | Should -Be 'ja'
        @($got.segments).Count | Should -Be 1
        $segment = @($got.segments)[0]
        $segment.start | Should -Be 12.34
        $segment.end | Should -Be 15.67
        $segment.text | Should -Be 'recognized text'
        $segment.temperature | Should -Be 0
        $segment.avg_logprob | Should -Be -0.42
        $segment.compression_ratio | Should -Be 1.31
        $segment.no_speech_prob | Should -Be 0.02
        $got.PSObject.Properties['languageSource'] | Should -BeNullOrEmpty
        $got.PSObject.Properties['audioTrack'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['diagnostics'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['tokens'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['words'] | Should -BeNullOrEmpty
        $part | Should -Not -Match '"diagnostics"'
        $part | Should -Not -Match '"tokens"'
        $part | Should -Not -Match '"words"'
        $part | Should -Not -Match '"audioTrack"'
        $part | Should -Not -Match '"languageSource"'
        $part | Should -Not -Match 'drop me'
        $part | Should -Not -Match '"unexpected_root"'
        $part | Should -Not -Match '"unexpected_segment"'
        $part | Should -Not -Match '50364'
    }

    It 'envoie un sous-titre secondaire en start/end/text sans cueId ni métadonnées techniques' {
        $env:GEMINI_API_KEY = 'test-key'
        $altSrt = Join-Path $script:Work 'episode.alt.srt'
        $altAss = Join-Path $script:Work 'episode.other.ass'
        Set-Content -LiteralPath $altSrt -Value "99`n00:00:10,000 --> 00:00:11,000`nTexte alternatif`n" -Encoding utf8
        Set-Content -LiteralPath $altAss -Value "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 5,0:00:20.00,0:00:21.00,Default,,10,20,30,,Autre version`n" -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath @($altSrt, $altAss)

        $srtPart = Get-PromptPartByMarker $script:LastGeminiBody 'SOURCE LINGUISTIQUE 2 — SOUS-TITRE'
        $srtPart | Should -Match '"start":\s*"00:00:10,000"'
        $srtPart | Should -Match '"end":\s*"00:00:11,000"'
        $srtPart | Should -Match '"text":\s*"Texte alternatif"'
        $srtPart | Should -Not -Match '"cueId"'

        $assPart = Get-PromptPartByMarker $script:LastGeminiBody 'SOURCE LINGUISTIQUE 3 — SOUS-TITRE'
        $assPart | Should -Match '"start":\s*"0:00:20.00"'
        $assPart | Should -Match '"end":\s*"0:00:21.00"'
        $assPart | Should -Match '"text":\s*"Autre version"'
        $assPart | Should -Not -Match '"cueId"'
        $assPart | Should -Not -Match 'Layer'
        $assPart | Should -Not -Match 'Style'
        $assPart | Should -Not -Match 'Margin'
        $assPart | Should -Not -Match 'Default'
    }

    It 'envoie toutes les sources mixtes dans le prompt, dans l''ordre fourni' {
        $env:GEMINI_API_KEY = 'test-key'
        $altSrt = Join-Path $script:Work 'episode.alt.srt'
        $whisperPath = Join-Path $script:Work 'episode.track 1.ja.large-v3-turbo.json'
        $altAss = Join-Path $script:Work 'episode.other.ass'
        $whisperJson = '{"engine":"faster-whisper","model":"large-v3-turbo","language":"ja","languageSource":"forced","audioTrack":1,"segments":[]}'
        Set-Content -LiteralPath $altSrt -Value "1`n00:00:10,000 --> 00:00:11,000`nAlt SRT`n" -Encoding utf8
        Set-Content -LiteralPath $whisperPath -Value $whisperJson -Encoding utf8NoBOM -NoNewline
        Set-Content -LiteralPath $altAss -Value "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:20.00,0:00:21.00,Default,,0,0,0,,Alt ASS`n" -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath @($altSrt, $whisperPath, $altAss)

        $texts = Get-GeminiPromptText $script:LastGeminiBody
        $joined = $texts -join "`n"
        $joined | Should -Match '===== GABARIT TECHNIQUE FINAL ====='
        $joined | Should -Match '===== SOURCE LINGUISTIQUE 1 — SOUS-TITRE STRUCTURANT ====='
        $joined | Should -Match '===== SOURCE LINGUISTIQUE 2 — SOUS-TITRE ====='
        $joined | Should -Match '===== SOURCE LINGUISTIQUE 3 — TRANSCRIPTION AUTOMATIQUE JSON ====='
        $joined | Should -Match '===== SOURCE LINGUISTIQUE 4 — SOUS-TITRE ====='
        $joined | Should -Not -Match 'SOURCE PRINCIPALE'
        $joined | Should -Not -Match '===== SOURCE SECONDAIRE'
        $joined.IndexOf('SOURCE LINGUISTIQUE 1') | Should -BeLessThan $joined.IndexOf('SOURCE LINGUISTIQUE 2')
        $joined.IndexOf('SOURCE LINGUISTIQUE 2') | Should -BeLessThan $joined.IndexOf('SOURCE LINGUISTIQUE 3')
        $joined.IndexOf('SOURCE LINGUISTIQUE 3') | Should -BeLessThan $joined.IndexOf('SOURCE LINGUISTIQUE 4')
        Get-GeminiPromptText $script:LastGeminiBody |
            Where-Object { $_ -match '(?m)^===== SOURCE LINGUISTIQUE' } |
            ForEach-Object { $_ | Should -Not -Match '"cueId"' }
        $joined | Should -Match 'Alt SRT'
        $whisperCompact = Get-SecondaryTranscriptJsonFromPrompt $script:LastGeminiBody
        $whisperGot = ConvertFrom-Json -InputObject $whisperCompact
        @($whisperGot.segments).Count | Should -Be 0
        $whisperGot.engine | Should -Be 'faster-whisper'
        $whisperGot.model | Should -Be 'large-v3-turbo'
        $whisperGot.PSObject.Properties.Name | Should -Not -Contain 'vad'
        $whisperCompact | Should -Not -Match '"languageSource"'
        $whisperCompact | Should -Not -Match '"audioTrack"'
        $joined | Should -Match 'Alt ASS'
    }

    It 'envoie sous-titre, Whisper et les deux VAD Reazon comme transcriptions automatiques' {
        $env:GEMINI_API_KEY = 'test-key'
        $altSrt = Join-Path $script:Work 'episode.alt.srt'
        $whisperPath = Join-Path $script:Work 'episode.track 1.ja.large-v2.json'
        $sileroPath = Join-Path $script:Work 'episode.track 1.ja.reazon-k2-v2.silero.json'
        $tenPath = Join-Path $script:Work 'episode.track 1.ja.reazon-k2-v2.ten.json'
        $whisperJson = '{"engine":"faster-whisper","model":"large-v2","language":"ja","languageSource":"forced","audioTrack":1,"segments":[{"start":1.0,"end":2.0,"text":"whisper"}]}'
        $sileroJson = '{"engine":"sherpa-onnx","model":"reazon-k2-v2","vad":"silero","language":"ja","languageSource":"model","audioTrack":1,"segments":[{"start":1.0,"end":2.0,"text":"silero"}]}'
        $tenJson = '{"engine":"sherpa-onnx","model":"reazon-k2-v2","vad":"ten","language":"ja","languageSource":"model","audioTrack":1,"segments":[{"start":1.1,"end":2.1,"text":"ten"}]}'
        Set-Content -LiteralPath $altSrt -Value "1`n00:00:10,000 --> 00:00:11,000`nAlt SRT`n" -Encoding utf8
        Set-Content -LiteralPath $whisperPath -Value $whisperJson -Encoding utf8NoBOM -NoNewline
        Set-Content -LiteralPath $sileroPath -Value $sileroJson -Encoding utf8NoBOM -NoNewline
        Set-Content -LiteralPath $tenPath -Value $tenJson -Encoding utf8NoBOM -NoNewline
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                $script:LastGeminiBody = ConvertFrom-GeminiRequestBody $Body
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath @($altSrt, $whisperPath, $sileroPath, $tenPath)

        $texts = Get-GeminiPromptText $script:LastGeminiBody
        $joined = $texts -join "`n"
        $joined | Should -Match '===== SOURCE LINGUISTIQUE 2 — SOUS-TITRE ====='
        $joined | Should -Match '===== SOURCE LINGUISTIQUE 3 — TRANSCRIPTION AUTOMATIQUE JSON ====='
        $joined | Should -Match '===== SOURCE LINGUISTIQUE 4 — TRANSCRIPTION AUTOMATIQUE JSON ====='
        $joined | Should -Match '===== SOURCE LINGUISTIQUE 5 — TRANSCRIPTION AUTOMATIQUE JSON ====='
        $joined | Should -Not -Match 'TRANSCRIPTION WHISPER JSON'
        $joined.IndexOf('SOURCE LINGUISTIQUE 2') | Should -BeLessThan $joined.IndexOf('SOURCE LINGUISTIQUE 3')
        $joined.IndexOf('SOURCE LINGUISTIQUE 3') | Should -BeLessThan $joined.IndexOf('SOURCE LINGUISTIQUE 4')
        $joined.IndexOf('SOURCE LINGUISTIQUE 4') | Should -BeLessThan $joined.IndexOf('SOURCE LINGUISTIQUE 5')

        $autoParts = @(
            Get-GeminiPromptText $script:LastGeminiBody |
                Where-Object { $_ -match 'TRANSCRIPTION AUTOMATIQUE JSON' }
        )
        $autoParts.Count | Should -Be 3
        $compacts = @(
            $autoParts | ForEach-Object {
                if ($_ -notmatch '(?s)===== SOURCE LINGUISTIQUE \d+ — TRANSCRIPTION AUTOMATIQUE JSON =====\r?\n(.+)\r?\n===== FIN SOURCE LINGUISTIQUE \d+ =====') {
                    throw 'JSON compact introuvable'
                }
                ConvertFrom-Json -InputObject $Matches[1].Trim()
            }
        )
        $compacts[0].engine | Should -Be 'faster-whisper'
        $compacts[0].model | Should -Be 'large-v2'
        $compacts[0].PSObject.Properties.Name | Should -Not -Contain 'vad'
        $compacts[1].engine | Should -Be 'sherpa-onnx'
        $compacts[1].model | Should -Be 'reazon-k2-v2'
        $compacts[1].vad | Should -Be 'silero'
        $compacts[2].engine | Should -Be 'sherpa-onnx'
        $compacts[2].model | Should -Be 'reazon-k2-v2'
        $compacts[2].vad | Should -Be 'ten'
        $compacts[1].segments[0].PSObject.Properties.Name | Should -Not -Contain 'avg_logprob'
    }

    It 'refuse un engine inconnu avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        $badJson = Join-Path $script:Work 'unknown-engine.json'
        Set-Content -LiteralPath $badJson -Value '{"engine":"unknown-engine","model":"x","language":"ja","languageSource":"forced","audioTrack":1,"segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath $badJson } |
            Should -Throw -ExpectedMessage '*Tetram*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'refuse un JSON Sherpa sans vad avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        $badJson = Join-Path $script:Work 'reazon-sans-vad.json'
        Set-Content -LiteralPath $badJson -Value '{"engine":"sherpa-onnx","model":"reazon-k2-v2","language":"ja","languageSource":"model","audioTrack":1,"segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath $badJson } |
            Should -Throw -ExpectedMessage '*Tetram*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'refuse un JSON secondaire invalide avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        $badJson = Join-Path $script:Work 'broken.json'
        Set-Content -LiteralPath $badJson -Value '{ ceci n''est pas du JSON' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath $badJson } |
            Should -Throw -ExpectedMessage '*JSON*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'refuse un JSON sans contrat Tetram avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        $badJson = Join-Path $script:Work 'no-segments.json'
        Set-Content -LiteralPath $badJson -Value '{"text":"x"}' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath $badJson } |
            Should -Throw -ExpectedMessage '*Tetram*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'refuse un JSON Whisper legacy avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        $legacyJson = Join-Path $script:Work 'legacy-whisper.json'
        Set-Content -LiteralPath $legacyJson -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"...","avg_logprob":-0.4}]}' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath $legacyJson } |
            Should -Throw -ExpectedMessage '*Tetram*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'refuse un segment Tetram sans start, end ou text avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        $badJson = Join-Path $script:Work 'incomplete-segment.json'
        Set-Content -LiteralPath $badJson -Value '{"engine":"faster-whisper","model":"large-v3","language":"ja","languageSource":"forced","audioTrack":1,"segments":[{"start":1.0,"end":2.0}]}' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath $badJson } |
            Should -Throw -ExpectedMessage '*Tetram*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'refuse une extension secondaire non supportée avant tout appel réseau' {
        $env:GEMINI_API_KEY = 'test-key'
        $badTxt = Join-Path $script:Work 'notes.txt'
        Set-Content -LiteralPath $badTxt -Value 'pas une source' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            throw 'Gemini ne devait pas être appelé'
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath $badTxt } |
            Should -Throw -ExpectedMessage '*Extension*'
        Should -Invoke -ModuleName Tetram.Media.Translation Invoke-RestMethod -Times 0
    }

    It 'reconstruit exclusivement depuis la source principale malgré des secondaires divergents' {
        $env:GEMINI_API_KEY = 'test-key'
        $altSrt = Join-Path $script:Work 'episode.alt.srt'
        Set-Content -LiteralPath $altSrt -Value "1`n00:05:00,000 --> 00:05:01,000`nAutre cue`n`n2`n00:05:02,000 --> 00:05:03,000`nEncore`n" -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -SecondarySourcePath $altSrt

        $written = (Get-Content -LiteralPath (Join-Path $script:Work 'episode.fr.ass') -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
        $written | Should -Not -Match 'Autre cue'
        $written | Should -Not -Match 'Encore'
        $written | Should -Not -Match '00:05:00'
        @($written -split "`n" | Where-Object { $_ -like 'Dialogue:*' }).Count | Should -Be 1
    }

    It 'écrit sur OutputPath quand il est fourni' {
        $env:GEMINI_API_KEY = 'test-key'
        $custom = Join-Path $script:Work 'custom.fr.ass'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -OutputPath $custom

        $written = (Get-Content -LiteralPath $custom -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Work 'custom.fr.raw.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
    }

    It 'conserve les timestamps SRT source après une réponse JSON complète' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.srt'
        Set-Content -LiteralPath $script:SubtitlePath -Value "37`n00:05:59,237 --> 00:06:00,057`nEnglish text`n" -Encoding utf8
        $json = '[{"cueId":1,"text":"texte français"}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $json
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
        $output = Join-Path $script:Work 'episode.fr.srt'
        $written = (Get-Content -LiteralPath $output -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match '00:05:59,237 --> 00:06:00,057'
        $written | Should -Match 'texte français'
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
    }

    It 'n''écrit pas le final ni de raw durable si un cueId manque' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.srt'
        Set-Content -LiteralPath $script:SubtitlePath -Value "1`n00:00:01,000 --> 00:00:02,000`nA`n`n2`n00:00:03,000 --> 00:00:04,000`nB`n`n3`n00:00:05,000 --> 00:00:06,000`nC`n`n4`n00:00:07,000 --> 00:00:08,000`nD`n" -Encoding utf8
        $json = '[{"cueId":1,"text":"A"},{"cueId":2,"text":"B"},{"cueId":4,"text":"D"}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $json
            }
        }

        $beforeTemp = Get-TranslationRawTempFiles
        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -WarningVariable warn -WarningAction Continue
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.srt') | Should -BeFalse
        Assert-TranslationRawTempCleaned -Before $beforeTemp
        "$warn" | Should -Match 'cueId 3 manquant'
    }

    It 'reconstruit selon cueId même si Gemini les renvoie dans le désordre' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.srt'
        Set-Content -LiteralPath $script:SubtitlePath -Value "10`n00:00:01,000 --> 00:00:02,000`nA`n`n20`n00:00:03,000 --> 00:00:04,000`nB`n`n30`n00:00:05,000 --> 00:00:06,000`nC`n" -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse '[{"cueId":3,"text":"Troisième"},{"cueId":1,"text":"Premier"},{"cueId":2,"text":"Deuxième"}]'
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
        $written = (Get-Content -LiteralPath (Join-Path $script:Work 'episode.fr.srt') -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match '(?s)10\n00:00:01,000 --> 00:00:02,000\nPremier'
        $written | Should -Match '(?s)20\n00:00:03,000 --> 00:00:04,000\nDeuxième'
        $written | Should -Match '(?s)30\n00:00:05,000 --> 00:00:06,000\nTroisième'
    }

    It 'n''écrit pas le final ni de raw durable si un cueId est dupliqué' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = '[{"cueId":1,"text":"Bonjour"},{"cueId":1,"text":"Salut"}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $json
            }
        }

        $beforeTemp = Get-TranslationRawTempFiles
        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -WarningVariable warn -WarningAction Continue
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        Assert-TranslationRawTempCleaned -Before $beforeTemp
        "$warn" | Should -Match 'dupliqu'
    }

    It 'n''écrit pas le final ni de raw durable si un cueId est hors plage' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = '[{"cueId":1,"text":"Bonjour"},{"cueId":9,"text":"Trop loin"}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $json
            }
        }

        $beforeTemp = Get-TranslationRawTempFiles
        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -WarningVariable warn -WarningAction Continue
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        Assert-TranslationRawTempCleaned -Before $beforeTemp
        "$warn" | Should -Match 'hors plage'
    }

    It 'n''écrit pas le final ni de raw durable si le JSON est invalide' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = 'ceci n''est pas du JSON {'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $json
            }
        }

        $beforeTemp = Get-TranslationRawTempFiles
        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -WarningVariable warn -WarningAction Continue
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        Assert-TranslationRawTempCleaned -Before $beforeTemp
        "$warn" | Should -Match 'JSON'
    }

    It 'n''écrit pas le final ni de raw durable si text est vide sur une source non vide' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = '[{"cueId":1,"text":""}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $json
            }
        }

        $beforeTemp = Get-TranslationRawTempFiles
        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -WarningVariable warn -WarningAction Continue
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        Assert-TranslationRawTempCleaned -Before $beforeTemp
        "$warn" | Should -Match 'vide'
    }

    It 'n''écrit pas le final ni de raw durable si text n''est que des espaces sur une source non vide' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = '[{"cueId":1,"text":" "}]'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $json
            }
        }

        $beforeTemp = Get-TranslationRawTempFiles
        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -WarningVariable warn -WarningAction Continue
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        Assert-TranslationRawTempCleaned -Before $beforeTemp
        "$warn" | Should -Match 'vide'
    }

    It 'n''écrit pas le final ni de raw durable si Gemini altère une balise ASS' {
        $env:GEMINI_API_KEY = 'test-key'
        $json = '[{"cueId":1,"text":"{\\b1}Bonjour{\\i0}"}]'
        Set-Content -LiteralPath $script:SubtitlePath -Value "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\i1}Hello{\i0}`n" -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $json
            }
        }

        $beforeTemp = Get-TranslationRawTempFiles
        $warn = $null
        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -WarningVariable warn -WarningAction Continue
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
        Assert-TranslationRawTempCleaned -Before $beforeTemp
        "$warn" | Should -Match 'reconstruction'
    }

    It 'n''est pas bloqué par un .raw.json historique déjà présent à côté de la sortie' {
        $env:GEMINI_API_KEY = 'test-key'
        $raw = Join-Path $script:Work 'episode.fr.raw.json'
        Set-Content -LiteralPath $raw -Value 'ne-pas-ecraser' -Encoding utf8
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                New-GeminiStopResponse $script:HelloJson
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') -PathType Leaf | Should -BeTrue
        [IO.File]::ReadAllText($raw, [Text.UTF8Encoding]::new($false)).Trim() | Should -Be 'ne-pas-ecraser'
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

        It 'annonce raw puis reconstruction et nettoie le temporaire si le JSON métier est invalide' {
            $env:GEMINI_API_KEY = 'test-key'
            $json = 'ceci n''est pas du JSON {'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                Get-GeminiMockResponse -Uri $Uri -OnGenerateContent {
                    New-GeminiStopResponse $json
                }
            }

            $beforeTemp = Get-TranslationRawTempFiles
            $warn = $null
            ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -WarningVariable warn -WarningAction Continue

            $script:InfoLogs | Should -Contain 'Réponse brute du modèle reçue'
            $script:InfoLogs | Should -Contain 'Reconstruction du sous-titre final...'
            (Find-InfoLogIndex 'Réponse brute du modèle reçue') | Should -BeLessThan (Find-InfoLogIndex 'Reconstruction du sous-titre final...')
            @($script:InfoLogs | Where-Object { $_ -like '*enregistrée*' -or $_ -like '*conservée*' }) | Should -HaveCount 0
            "$warn" | Should -Match 'reconstruction'
            Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.raw.json') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
            Assert-TranslationRawTempCleaned -Before $beforeTemp
        }

    }
}
