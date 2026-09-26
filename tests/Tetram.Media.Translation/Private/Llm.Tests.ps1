# Étendre la suite autour de Llm.ps1 (Resolve-LlmModelSpec, Invoke-TranslationLlm, chargement paresseux).
#
# RepoRoot depuis tests/<Module>/Private : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Translation') -Force
# InModuleScope 'Tetram.Media.Translation' : Resolve-LlmModelSpec et Invoke-TranslationLlm ne sont pas exportées.
# Providers : Llm.Gemini.Tests.ps1 / Llm.Ollama.Tests.ps1.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranslation = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranslation = Join-Path $script:RepoRootTranslation 'Tetram.Media.Translation'
    Import-Module -Name $script:ModuleRootTranslation -Force -ErrorAction Stop

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
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Translation' -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-LlmModelSpec' {
    It 'parse un modèle sans option' {
        $spec = InModuleScope 'Tetram.Media.Translation' {
            Resolve-LlmModelSpec -Model 'qwen3.5:9b'
        }

        $spec.Name | Should -Be 'qwen3.5:9b'
        $spec.Options.Count | Should -Be 0
        $spec.Options.ContainsKey('thinking') | Should -BeFalse
    }

    It 'distingue thinking présent sans valeur de thinking absent' {
        $spec = InModuleScope 'Tetram.Media.Translation' {
            Resolve-LlmModelSpec -Model 'model[thinking]'
        }

        $spec.Name | Should -Be 'model'
        $spec.Options.ContainsKey('thinking') | Should -BeTrue
        $spec.Options['thinking'] | Should -Be $null
    }

    It 'parse thinking avec une valeur' {
        $spec = InModuleScope 'Tetram.Media.Translation' {
            Resolve-LlmModelSpec -Model 'model[thinking=high]'
        }

        $spec.Name | Should -Be 'model'
        $spec.Options.ContainsKey('thinking') | Should -BeTrue
        $spec.Options['thinking'] | Should -Be 'high'
    }

    It 'normalise espaces et casse de thinking' {
        $spec = InModuleScope 'Tetram.Media.Translation' {
            Resolve-LlmModelSpec -Model 'model[ THINKING = Medium ]'
        }

        $spec.Name | Should -Be 'model'
        $spec.Options.ContainsKey('thinking') | Should -BeTrue
        $spec.Options['thinking'] | Should -Be 'medium'
    }

    It 'conserve le nom du modèle hors trim du spec' {
        $spec = InModuleScope 'Tetram.Media.Translation' {
            Resolve-LlmModelSpec -Model '  qwen3.5:9b[thinking]  '
        }

        $spec.Name | Should -Be 'qwen3.5:9b'
        $spec.Options.ContainsKey('thinking') | Should -BeTrue
        $spec.Options['thinking'] | Should -Be $null
    }

    It 'lève pour une option inconnue avant tout usage réseau' {
        {
            InModuleScope 'Tetram.Media.Translation' {
                Resolve-LlmModelSpec -Model 'model[fast]'
            }
        } | Should -Throw -ExpectedMessage '*Option de modèle inconnue : fast*'
        {
            InModuleScope 'Tetram.Media.Translation' {
                Resolve-LlmModelSpec -Model 'model[fast]'
            }
        } | Should -Throw -ExpectedMessage '*Options reconnues : thinking*'
    }

    It 'lève pour une option dupliquée' {
        {
            InModuleScope 'Tetram.Media.Translation' {
                Resolve-LlmModelSpec -Model 'model[thinking,thinking]'
            }
        } | Should -Throw -ExpectedMessage '*dupliqu*'
    }

    It 'lève pour une valeur vide' {
        {
            InModuleScope 'Tetram.Media.Translation' {
                Resolve-LlmModelSpec -Model 'model[thinking=]'
            }
        } | Should -Throw -ExpectedMessage '*Valeur d''option vide*'
    }

    It 'lève pour une option sans nom' {
        {
            InModuleScope 'Tetram.Media.Translation' {
                Resolve-LlmModelSpec -Model 'model[=high]'
            }
        } | Should -Throw -ExpectedMessage '*Option sans nom*'
    }

    It 'lève pour des crochets non fermés' {
        {
            InModuleScope 'Tetram.Media.Translation' {
                Resolve-LlmModelSpec -Model 'model[thinking'
            }
        } | Should -Throw -ExpectedMessage '*invalide*'
    }

    It 'lève pour une liste d''options vide' {
        {
            InModuleScope 'Tetram.Media.Translation' {
                Resolve-LlmModelSpec -Model 'model[]'
            }
        } | Should -Throw -ExpectedMessage '*invalide*'
    }

    It 'lève si le nom de modèle est vide' {
        {
            InModuleScope 'Tetram.Media.Translation' {
                Resolve-LlmModelSpec -Model '[thinking]'
            }
        } | Should -Throw -ExpectedMessage '*vide*'
    }

    It 'lève si le suffixe d''options n''est pas terminal' {
        {
            InModuleScope 'Tetram.Media.Translation' {
                Resolve-LlmModelSpec -Model 'model[thinking]extra'
            }
        } | Should -Throw -ExpectedMessage '*invalide*'
    }

    It 'lève si le nom de modèle contient un crochet fermant parasite' {
        {
            InModuleScope 'Tetram.Media.Translation' {
                Resolve-LlmModelSpec -Model 'model][thinking]'
            }
        } | Should -Throw -ExpectedMessage '*crochet*'
    }
}

Describe 'chargement paresseux des providers LLM' {
    It 'charge la couche LLM commune sans définir Invoke-ProviderTranslationLlm' {
        $names = InModuleScope 'Tetram.Media.Translation' {
            @(
                Get-Command -Name Invoke-TranslationLlm -ErrorAction SilentlyContinue
                Get-Command -Name Invoke-ProviderTranslationLlm -ErrorAction SilentlyContinue
                Get-Command -Name Invoke-GeminiTranslationLlm -ErrorAction SilentlyContinue
                Get-Command -Name Invoke-OllamaTranslationLlm -ErrorAction SilentlyContinue
            ) | ForEach-Object { $_.Name } | Sort-Object
        }

        $names | Should -Be @('Invoke-TranslationLlm')
    }

    Context 'isolation du fichier non demandé' {
        BeforeEach {
            $script:SavedGeminiKey = $env:GEMINI_API_KEY
            $script:Work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:Work | Out-Null
            $script:SubtitlePath = Join-Path $script:Work 'episode.ass'
            $script:HelloJson = '[{"cueId":1,"text":"Bonjour"}]'
            Set-Content -LiteralPath $script:SubtitlePath -Value "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello`n" -Encoding utf8
            $script:SavedLlmPrivateRoot = InModuleScope 'Tetram.Media.Translation' {
                $script:LlmPrivateRoot
            }
        }

        AfterEach {
            $env:GEMINI_API_KEY = $script:SavedGeminiKey
            $savedRoot = $script:SavedLlmPrivateRoot
            InModuleScope 'Tetram.Media.Translation' -Parameters @{ SavedRoot = $savedRoot } {
                param($SavedRoot)
                $script:LlmPrivateRoot = $SavedRoot
            }
        }

        It 'n''exécute pas Llm.Ollama.ps1 pour -Provider Gemini' {
            $tempRoot = Join-Path $TestDrive 'llm-private-gemini'
            New-Item -ItemType Directory -Path $tempRoot | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:SavedLlmPrivateRoot 'Llm.Gemini.ps1') -Destination $tempRoot
            Set-Content -LiteralPath (Join-Path $tempRoot 'Llm.Ollama.ps1') -Value "throw 'Ollama ne devait pas être chargé'" -Encoding utf8

            InModuleScope 'Tetram.Media.Translation' -Parameters @{ TempRoot = $tempRoot } {
                param($TempRoot)
                $script:LlmPrivateRoot = $TempRoot
            }

            $env:GEMINI_API_KEY = 'test-key'
            Mock -ModuleName Tetram.Media.Translation Invoke-RestMethod {
                if ($Uri -like '*:countTokens') {
                    return [pscustomobject]@{ totalTokens = 100 }
                }
                New-GeminiStopResponse $script:HelloJson
            }

            { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Provider Gemini } |
                Should -Not -Throw
        }

        It 'n''exécute pas Llm.Gemini.ps1 pour -Provider Ollama' {
            $tempRoot = Join-Path $TestDrive 'llm-private-ollama'
            New-Item -ItemType Directory -Path $tempRoot | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:SavedLlmPrivateRoot 'Llm.Ollama.ps1') -Destination $tempRoot
            Set-Content -LiteralPath (Join-Path $tempRoot 'Llm.Gemini.ps1') -Value "throw 'Gemini ne devait pas être chargé'" -Encoding utf8

            InModuleScope 'Tetram.Media.Translation' -Parameters @{ TempRoot = $tempRoot } {
                param($TempRoot)
                $script:LlmPrivateRoot = $TempRoot
            }

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

            { ConvertTo-FrenchSubtitle -SubtitlePath $script:SubtitlePath -Provider Ollama } |
                Should -Not -Throw
        }
    }
}
