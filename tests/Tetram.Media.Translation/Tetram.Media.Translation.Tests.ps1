# Étendre la suite autour du module SUD Tetram.Media.Translation (traduction Gemini de sous-titres).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Manifeste : Tetram.Media.Translation/Tetram.Media.Translation.psd1 — Test-ModuleManifest puis Import-Module -Force
# Réseau : mocker Invoke-RestMethod -ModuleName Tetram.Media.Translation ; jamais d'appel Gemini réel.
# $TestDrive pour les fichiers source/sortie ; restaurer GEMINI_API_KEY après chaque test.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranslation = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRootTranslation = Join-Path $script:RepoRootTranslation 'Tetram.Media.Translation'
    $script:ManifestTranslation = Join-Path $script:ModuleRootTranslation 'Tetram.Media.Translation.psd1'
}

Describe 'Tetram.Media.Translation manifest' {
    It 'passe Test-ModuleManifest' {
        { Test-ModuleManifest -Path $script:ManifestTranslation -ErrorAction Stop } | Should -Not -Throw
    }

    It 'embarque Resources/ConvertTo-FrenchSubtitle.prompt.md' {
        $promptPath = Join-Path $script:ModuleRootTranslation 'Resources' 'ConvertTo-FrenchSubtitle.prompt.md'
        Test-Path -LiteralPath $promptPath -PathType Leaf | Should -BeTrue
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
        $script:MinimalAssBonjour = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour`n"
        Set-Content -LiteralPath $script:SubtitlePath -Value $script:MinimalAssHello -Encoding utf8
        Set-Content -LiteralPath $script:TranscriptPath -Value 'こんにちは' -Encoding utf8
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
            if ($LiteralPath -like '*ConvertTo-FrenchSubtitle.prompt.md') {
                return $false
            }
            return Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage "*prompt*"
    }

    It 'lève si GEMINI_API_KEY est absente' {
        $env:GEMINI_API_KEY = $null
        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage "*GEMINI_API_KEY*"
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
        $translated = $script:MinimalAssBonjour

        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            [pscustomobject]@{
                candidates = @(
                    [pscustomobject]@{
                        finishReason = 'STOP'
                        content      = [pscustomobject]@{
                            parts = @(
                                [pscustomobject]@{
                                    thought = $false
                                    text    = $translated
                                }
                            )
                        }
                    }
                )
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

        $output = Join-Path $script:Work 'episode.fr.ass'
        Test-Path -LiteralPath $output -PathType Leaf | Should -BeTrue
        $written = (Get-Content -LiteralPath $output -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
        $written | Should -Not -Match 'Hello'
        $bytes = [IO.File]::ReadAllBytes($output)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'appelle le modèle par défaut gemini-3.6-flash' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            if ($Uri -notlike '*gemini-3.6-flash:generateContent') {
                throw "URI inattendue : $Uri"
            }
            [pscustomobject]@{
                candidates = @(
                    [pscustomobject]@{
                        finishReason = 'STOP'
                        content      = [pscustomobject]@{
                            parts = @(
                                [pscustomobject]@{
                                    thought = $false
                                    text    = $script:MinimalAssBonjour
                                }
                            )
                        }
                    }
                )
            }
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Not -Throw
    }

    It 'lève si Gemini ne retourne aucun candidat' {
        $env:GEMINI_API_KEY = 'test-key'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            [pscustomobject]@{ candidates = @() }
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage "*aucun candidat*"
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
    }

    It 'écrit sur OutputPath quand il est fourni' {
        $env:GEMINI_API_KEY = 'test-key'
        $custom = Join-Path $script:Work 'custom.fr.ass'
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            [pscustomobject]@{
                candidates = @(
                    [pscustomobject]@{
                        finishReason = 'STOP'
                        content      = [pscustomobject]@{
                            parts = @(
                                [pscustomobject]@{ thought = $false; text = $script:MinimalAssBonjour }
                            )
                        }
                    }
                )
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -OutputPath $custom

        $written = (Get-Content -LiteralPath $custom -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
    }

    It 'restaure le timestamp SRT source quand Gemini le corrompt' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.srt'
        Set-Content -LiteralPath $script:SubtitlePath -Value "37`n00:05:59,237 --> 00:06:00,057`nEnglish text`n" -Encoding utf8
        $translated = "37`n00:09:59,237 --> 00:06:00,057`ntexte français`n"
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            [pscustomobject]@{
                candidates = @(
                    [pscustomobject]@{
                        finishReason = 'STOP'
                        content      = [pscustomobject]@{
                            parts = @(
                                [pscustomobject]@{ thought = $false; text = $translated }
                            )
                        }
                    }
                )
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath

        $written = (Get-Content -LiteralPath (Join-Path $script:Work 'episode.fr.srt') -Raw -Encoding utf8) -replace '\r\n', "`n"
        $written | Should -Match '00:05:59,237 --> 00:06:00,057'
        $written | Should -Match 'texte français'
        $written | Should -Not -Match '00:09:59,237'
    }

    It 'n''écrit aucun fichier si le nombre de cues SRT diffère' {
        $env:GEMINI_API_KEY = 'test-key'
        $script:SubtitlePath = Join-Path $script:Work 'episode.srt'
        Set-Content -LiteralPath $script:SubtitlePath -Value "1`n00:00:01,000 --> 00:00:02,000`nA`n`n2`n00:00:03,000 --> 00:00:04,000`nB`n" -Encoding utf8
        $translated = "1`n00:00:01,000 --> 00:00:02,000`nA`n"
        Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
            [pscustomobject]@{
                candidates = @(
                    [pscustomobject]@{
                        finishReason = 'STOP'
                        content      = [pscustomobject]@{
                            parts = @(
                                [pscustomobject]@{ thought = $false; text = $translated }
                            )
                        }
                    }
                )
            }
        }

        { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath } |
            Should -Throw -ExpectedMessage '*cues*'
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.srt') | Should -BeFalse
    }
}
