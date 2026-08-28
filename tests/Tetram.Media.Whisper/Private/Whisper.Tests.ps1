# Étendre la suite autour des unités privées de Tetram.Media.Whisper.
#
# Tout passe par InModuleScope 'Tetram.Media.Whisper' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Get-Whisper* / Resolve-* n'appellent aucun binaire. Invoke-Whisper s'exerce via pwsh (stand-in),
# jamais via faster-whisper-xxl.

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
                '--beep_off'
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
                '--beep_off'
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
                '--beep_off'
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
                '--beep_off'
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
                '--beep_off'
            )
        }
    }

    It 'ajoute les options Kotoba après la séquence générique pour kotoba-v2' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\a.mkv') -Format @('srt') -Model 'kotoba-v2' -UseLanguage 'ja'
            $got | Should -Be @(
                'D:\a.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt'
                '--check_files'
                '--model', 'kotoba-v2'
                '--ff_track', '1'
                '--language', 'ja'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
                '--beep_off'
                '--condition_on_previous_text', 'False'
                '-prompt', 'None'
                '--word_timestamps', 'False'
                '--chunk_length', '15'
                '--compute_type', 'float16'
            )
        }
    }

    It 'n''ajoute aucune option Kotoba pour large-v3' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\a.mkv') -Format @('srt') -Model 'large-v3'
            $got | Should -Be @(
                'D:\a.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt'
                '--check_files'
                '--model', 'large-v3'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
                '--beep_off'
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

    It 'résout une classe de caractères entre crochets vers les fichiers correspondants' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Set-Content -LiteralPath (Join-Path $Work 'clip1.mkv') -Value 'x'
            Set-Content -LiteralPath (Join-Path $Work 'clip2.mkv') -Value 'x'
            Set-Content -LiteralPath (Join-Path $Work 'clip12.mkv') -Value 'x'
            $got = @(Resolve-WhisperSource -Path @((Join-Path $Work 'clip[12].mkv')))
            $got.Count | Should -Be 2
            $got | Should -Contain (Join-Path $Work 'clip1.mkv')
            $got | Should -Contain (Join-Path $Work 'clip2.mkv')
            $got | Should -Not -Contain (Join-Path $Work 'clip12.mkv')
        }
    }

    It 'fusionne interprétation littérale et classe de caractères sans doublon' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Set-Content -LiteralPath (Join-Path $Work 'film[1].mkv') -Value 'x'
            Set-Content -LiteralPath (Join-Path $Work 'film1.mkv') -Value 'x'
            $got = @(Resolve-WhisperSource -Path @((Join-Path $Work 'film[1].mkv')))
            $got.Count | Should -Be 2
            $got | Should -Contain (Join-Path $Work 'film[1].mkv')
            $got | Should -Contain (Join-Path $Work 'film1.mkv')
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

    It 'transmet un masque * / ? sans l''absolutiser' {
        InModuleScope 'Tetram.Media.Whisper' {
            @(Resolve-WhisperSource -Path @('.\*.mkv')) | Should -Be @('.\*.mkv')
            @(Resolve-WhisperSource -Path @('*.mkv')) | Should -Be @('*.mkv')
        }
    }

    It 'ne prend pas le ? du préfixe Win32 \\?\ pour un joker' {
        InModuleScope 'Tetram.Media.Whisper' {
            $long = '\\?\C:\Videos\film.mkv'
            @(Resolve-WhisperSource -Path @($long)) | Should -Be @($long)
        }
    }

    It 'transmet -LiteralPath tel quel, sans absolutiser' {
        InModuleScope 'Tetram.Media.Whisper' {
            @(Resolve-WhisperSource -LiteralPath @('film[1].mkv')) | Should -Be @('film[1].mkv')
        }
    }

    It 'développe ~ sans tester l''existence' {
        InModuleScope 'Tetram.Media.Whisper' {
            @(Resolve-WhisperSource -Path @('~\Videos\film.mkv')) | Should -Be @((Join-Path $HOME 'Videos\film.mkv'))
            @(Resolve-WhisperSource -Path @('~/Videos/film.mkv')) | Should -Be @((Join-Path $HOME 'Videos/film.mkv'))
        }
    }

    It 'développe ~ sans casser le masque qui le suit' {
        InModuleScope 'Tetram.Media.Whisper' {
            $expected = Join-Path $HOME 'Videos\*.mkv'
            @(Resolve-WhisperSource -Path @('~\Videos\*.mkv')) | Should -Be @($expected)
        }
    }

    It 'ne développe pas ~ dans -LiteralPath' {
        InModuleScope 'Tetram.Media.Whisper' {
            @(Resolve-WhisperSource -LiteralPath @('~\Videos\film.mkv')) | Should -Be @('~\Videos\film.mkv')
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

    It 'ignore une fonction de même nom au lieu de renvoyer une Source vide' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            function faster-whisper-xxl { 'ne doit jamais être choisie' }
            $saved = $script:WhisperRoot
            try {
                $script:WhisperRoot = Join-Path $Work 'vide'
                { Get-WhisperPath } | Should -Throw '*Purfview*'
            }
            finally {
                $script:WhisperRoot = $saved
                Remove-Item -Path 'function:faster-whisper-xxl' -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Invoke-Whisper' {
    It 'affiche la ligne de commande avant toute exécution' {
        InModuleScope 'Tetram.Media.Whisper' {
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $false }
            $state = @{}
            Invoke-Whisper -Exe 'binaire-absent-xyz.exe' -Arguments @('a.mkv', '--task', 'transcribe') -Cmdlet $cmdlet -State $state
            Should -Invoke Show-CommandLine -Times 1
        }
    }

    It 'laisse ExitCode à $null et n''exécute rien si ShouldProcess refuse' {
        InModuleScope 'Tetram.Media.Whisper' {
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $false }
            $state = @{}
            Invoke-Whisper -Exe 'binaire-absent-xyz.exe' -Arguments @('a.mkv') -Cmdlet $cmdlet -State $state
            $state['ExitCode'] | Should -BeNullOrEmpty
        }
    }

    It 'relève le code de sortie du binaire' {
        InModuleScope 'Tetram.Media.Whisper' {
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $true }
            $state = @{}
            Invoke-Whisper -Exe (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', 'exit 3') -Cmdlet $cmdlet -State $state
            $state['ExitCode'] | Should -Be 3
        }
    }

    It 'préserve les frontières d''arguments, y compris les chemins à espaces' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $true }
            $helper = Join-Path $Work 'ecrit-args.ps1'
            Set-Content -LiteralPath $helper -Value 'param($Destination, $Contenu) Set-Content -LiteralPath $Destination -Value $Contenu'
            $out = Join-Path $Work 'sortie avec espaces.txt'
            $state = @{}
            Invoke-Whisper -Exe (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', $helper, $out, 'ok') -Cmdlet $cmdlet -State $state
            Get-Content -LiteralPath $out | Should -Be 'ok'
        }
    }
}
