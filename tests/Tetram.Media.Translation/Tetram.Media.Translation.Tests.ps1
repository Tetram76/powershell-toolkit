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
        Set-Content -LiteralPath $script:SubtitlePath -Value "Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello" -Encoding utf8
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

    It 'écrit le résultat UTF-8 sans BOM à côté de la source avec le suffixe .fr' {
        $env:GEMINI_API_KEY = 'test-key'
        $translated = "Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour"

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
        Get-Content -LiteralPath $output -Raw -Encoding utf8 | Should -Be $translated
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
                                    text    = 'ok'
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
                                [pscustomobject]@{ thought = $false; text = 'perso' }
                            )
                        }
                    }
                )
            }
        }

        ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -TranscriptPath $script:TranscriptPath -OutputPath $custom

        Get-Content -LiteralPath $custom -Raw -Encoding utf8 | Should -Be 'perso'
        Test-Path -LiteralPath (Join-Path $script:Work 'episode.fr.ass') | Should -BeFalse
    }
}
