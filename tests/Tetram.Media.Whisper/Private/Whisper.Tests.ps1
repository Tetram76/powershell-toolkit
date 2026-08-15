# Étendre la suite autour des unités privées de Tetram.Media.Whisper.
#
# Tout passe par InModuleScope 'Tetram.Media.Whisper' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Aucune de ces fonctions n'appelle le binaire.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootWhisper = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootWhisper = Join-Path $script:RepoRootWhisper 'Tetram.Media.Whisper'
    Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
}

# La fonction est pure et déterministe : chaque cas assert la séquence entière plutôt qu'un fragment.
# Aucun paramètre n'est donc fourni sans être couvert, et toute régression d'ordre est vue partout.
Describe 'Get-WhisperArguments' {
    It 'produit la séquence par défaut, dans l''ordre, et sans --language' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\Films\a.mkv') -Format @('srt') -Model 'large-v2'
            $got | Should -Be @(
                'D:\Films\a.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
            )
        }
    }

    It 'passe chaque source comme argument nu, sans préfixe file_list=' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\a.mkv', 'D:\b.mkv', 'D:\c.mkv') -Format @('srt') -Model 'large-v2'
            $got | Should -Be @(
                'D:\a.mkv'
                'D:\b.mkv'
                'D:\c.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
            )
        }
    }

    It 'liste plusieurs formats derrière un seul --output_format' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\a.mkv') -Format @('srt', 'vtt') -Model 'large-v2'
            $got | Should -Be @(
                'D:\a.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt', 'vtt'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
            )
        }
    }

    It 'reprend le modèle demandé' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\a.mkv') -Format @('srt') -Model 'large-v3-turbo'
            $got | Should -Be @(
                'D:\a.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt'
                '--check_files'
                '--model', 'large-v3-turbo'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
            )
        }
    }

    It 'insère --language entre --ff_track et --postfix quand UseLanguage est fourni' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\a.mkv') -Format @('srt') -Model 'large-v2' -UseLanguage 'fr'
            $got | Should -Be @(
                'D:\a.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--language', 'fr'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
            )
        }
    }
}

Describe 'Resolve-WhisperSource' {
    It 'transmet un masque tel quel, sans énumérer les fichiers' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            1..3 | ForEach-Object { Set-Content -LiteralPath (Join-Path $Work "f$_.mkv") -Value 'x' }
            $got = @(Resolve-WhisperSource -Path @((Join-Path $Work '*.mkv')))
            $got.Count | Should -Be 1
            $got[0] | Should -Be (Join-Path $Work '*.mkv')
        }
    }

    It 'transmet un dossier tel quel' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'films'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $got = @(Resolve-WhisperSource -Path @($dir))
            $got | Should -Be @($dir)
        }
    }

    It 'transmet un fichier-liste tel quel, sans le lire' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $lst = Join-Path $Work 'lot.lst'
            Set-Content -LiteralPath $lst -Value 'D:\Films\a.mkv'
            $got = @(Resolve-WhisperSource -Path @($lst))
            $got | Should -Be @($lst)
        }
    }

    It 'transmet un chemin inexistant sans erreur' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $missing = Join-Path $Work 'absent.mkv'
            $got = @(Resolve-WhisperSource -Path @($missing))
            $got | Should -Be @($missing)
        }
    }

    It 'résout une entrée à crochets sans neutraliser les crochets du résultat' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Set-Content -LiteralPath (Join-Path $Work 'film[1].mkv') -Value 'x'
            $got = @(Resolve-WhisperSource -Path @((Join-Path $Work 'film[1].mkv')))
            $got.Count | Should -Be 1
            $got[0] | Should -Be (Join-Path $Work 'film[1].mkv')
        }
    }

    It 'ne produit rien pour une entrée à crochets sans correspondance' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $got = @(Resolve-WhisperSource -Path @((Join-Path $Work 'rien[9].mkv')))
            $got.Count | Should -Be 0
        }
    }

    It 'concatène -Path puis -LiteralPath' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $mask = Join-Path $Work '*.mkv'
            $literal = Join-Path $Work 'film[1].mkv'
            $got = @(Resolve-WhisperSource -Path @($mask) -LiteralPath @($literal))
            $got[0] | Should -Be $mask
            $got[1] | Should -Be (Join-Path $Work 'film[1].mkv')
        }
    }

    It 'ne résout jamais -LiteralPath, même avec un masque dedans' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $entry = Join-Path $Work '*.mkv'
            $got = @(Resolve-WhisperSource -LiteralPath @($entry))
            $got | Should -Be @($entry)
        }
    }
}

Describe 'Get-WhisperPath' {
    It 'retourne l''override quand c''est un fichier' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $exe = Join-Path $Work 'ailleurs.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            Get-WhisperPath -OverridePath $exe | Should -Be $exe
        }
    }

    It 'rejette un override qui est un dossier' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'dossier-exe'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            { Get-WhisperPath -OverridePath $dir } | Should -Throw '*pas un dossier*'
        }
    }

    It 'rejette un override inexistant' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            { Get-WhisperPath -OverridePath (Join-Path $Work 'absent.exe') } | Should -Throw '*inexistant*'
        }
    }

    It 'prend le binaire du dossier du module quand il existe' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $fakeRoot = Join-Path $Work 'purfview'
            New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
            $exe = Join-Path $fakeRoot 'faster-whisper-xxl.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            $saved = $script:WhisperRoot
            try {
                $script:WhisperRoot = $fakeRoot
                Get-WhisperPath | Should -Be $exe
            }
            finally {
                $script:WhisperRoot = $saved
            }
        }
    }

    It 'échoue avec un message qui indique où poser la distribution' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'faster-whisper-xxl' }
            $saved = $script:WhisperRoot
            try {
                $script:WhisperRoot = Join-Path $Work 'vide'
                { Get-WhisperPath } | Should -Throw '*Purfview*'
            }
            finally {
                $script:WhisperRoot = $saved
            }
        }
    }
}
