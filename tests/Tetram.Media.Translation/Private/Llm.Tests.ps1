# Étendre la suite autour de Resolve-LlmModelSpec (syntaxe -Model <name>[options]).
#
# RepoRoot depuis tests/<Module>/Private : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Translation') -Force
# InModuleScope 'Tetram.Media.Translation' : Resolve-LlmModelSpec n'est pas exportée.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranslation = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranslation = Join-Path $script:RepoRootTranslation 'Tetram.Media.Translation'
    Import-Module -Name $script:ModuleRootTranslation -Force -ErrorAction Stop
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
}
