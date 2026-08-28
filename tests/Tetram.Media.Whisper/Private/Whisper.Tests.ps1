# Étendre la suite autour des unités privées de Tetram.Media.Whisper.
#
# Tout passe par InModuleScope 'Tetram.Media.Whisper' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Get-Whisper* n'appelle aucun binaire. Invoke-Whisper s'exerce via pwsh (stand-in),
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
    It 'produit la séquence unitaire par défaut, sans --batch_recursive ni --language' {
        InModuleScope 'Tetram.Media.Whisper' {
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\Films\a.mkv' -Model 'large-v2' -OutputDir $outDir
            $got | Should -Be @(
                'D:\Films\a.mkv'
                '--output_dir', $outDir
                '--output_format', 'json'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
                '--beep_off'
            )
            $got | Should -Not -Contain '--batch_recursive'
            (Get-Command Get-WhisperArguments).Parameters['Source'].ParameterType | Should -Be ([string])
        }
    }

    It 'n''accepte plus Format' {
        InModuleScope 'Tetram.Media.Whisper' {
            (Get-Command Get-WhisperArguments).Parameters.ContainsKey('Format') | Should -BeFalse
        }
    }

    It 'passe --ff_track avec la piste demandée' {
        InModuleScope 'Tetram.Media.Whisper' {
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\a.mkv' -Model 'large-v2' -OutputDir $outDir -AudioTrack 2
            $ff = [array]::IndexOf(@($got), '--ff_track')
            $got[$ff + 1] | Should -Be '2'
        }
    }

    It 'reprend le modèle demandé' {
        InModuleScope 'Tetram.Media.Whisper' {
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\a.mkv' -Model 'large-v3-turbo' -OutputDir $outDir
            $got | Should -Be @(
                'D:\a.mkv'
                '--output_dir', $outDir
                '--output_format', 'json'
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
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\a.mkv' -Model 'large-v2' -UseLanguage 'fr' -OutputDir $outDir
            $got | Should -Be @(
                'D:\a.mkv'
                '--output_dir', $outDir
                '--output_format', 'json'
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
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\a.mkv' -Model 'kotoba-v2' -UseLanguage 'ja' -OutputDir $outDir
            $got | Should -Be @(
                'D:\a.mkv'
                '--output_dir', $outDir
                '--output_format', 'json'
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
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\a.mkv' -Model 'large-v3' -OutputDir $outDir
            $got | Should -Be @(
                'D:\a.mkv'
                '--output_dir', $outDir
                '--output_format', 'json'
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

Describe 'Resolve-WhisperMediaFile' {
    It 'retourne le chemin concret d''un fichier existant' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $media = Join-Path $Work 'Episode.mkv'
            Set-Content -LiteralPath $media -Value 'x'
            Resolve-WhisperMediaFile -LiteralPath $media | Should -Be (Get-Item -LiteralPath $media).FullName
        }
    }

    It 'traite les crochets comme un nom de fichier, pas comme un glob' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Set-Content -LiteralPath (Join-Path $Work 'Episode[1].mkv') -Value 'x'
            Set-Content -LiteralPath (Join-Path $Work 'Episode1.mkv') -Value 'x'
            $got = Resolve-WhisperMediaFile -LiteralPath (Join-Path $Work 'Episode[1].mkv')
            $got | Should -Be (Get-Item -LiteralPath (Join-Path $Work 'Episode[1].mkv')).FullName
            $got | Should -Not -Be (Get-Item -LiteralPath (Join-Path $Work 'Episode1.mkv')).FullName
        }
    }

    It 'refuse un chemin inexistant' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            { Resolve-WhisperMediaFile -LiteralPath (Join-Path $Work 'absent.mkv') } | Should -Throw '*fichier unique*'
        }
    }

    It 'refuse un dossier' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'films'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            { Resolve-WhisperMediaFile -LiteralPath $dir } | Should -Throw '*pas un dossier*'
        }
    }

    It 'refuse un masque qui n''est pas un nom de fichier littéral' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            1..2 | ForEach-Object { Set-Content -LiteralPath (Join-Path $Work "f$_.mkv") -Value 'x' }
            { Resolve-WhisperMediaFile -LiteralPath (Join-Path $Work '*.mkv') } | Should -Throw '*fichier unique*'
        }
    }

    It 'refuse un fichier-liste Purfview' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $lst = Join-Path $Work 'lot.lst'
            Set-Content -LiteralPath $lst -Value 'D:\Films\a.mkv'
            { Resolve-WhisperMediaFile -LiteralPath $lst } | Should -Throw '*fichier-liste*'
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

Describe 'New-WhisperTempDirectory' {
    It 'crée un dossier GUID sous TEMP, sans stem média' {
        InModuleScope 'Tetram.Media.Whisper' {
            $dir = New-WhisperTempDirectory
            try {
                $gotDir = [IO.Path]::GetFullPath((Split-Path -Parent $dir)).TrimEnd('\', '/')
                $wantDir = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
                $gotDir | Should -Be $wantDir
                [IO.Path]::GetFileName($dir) | Should -Match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                [IO.Path]::GetFileName($dir) | Should -Not -Match 'Episode'
                Test-Path -LiteralPath $dir -PathType Container | Should -BeTrue
            }
            finally {
                Remove-WhisperTempDirectory -Path $dir
            }
            Test-Path -LiteralPath $dir | Should -BeFalse
        }
    }

    It 'ne retourne pas un chemin si New-Item échoue' {
        InModuleScope 'Tetram.Media.Whisper' {
            Mock New-Item { throw 'TEMP inaccessible' }
            { New-WhisperTempDirectory } | Should -Throw '*TEMP inaccessible*'
        }
    }
}
