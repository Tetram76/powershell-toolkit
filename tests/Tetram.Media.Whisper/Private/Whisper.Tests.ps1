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
