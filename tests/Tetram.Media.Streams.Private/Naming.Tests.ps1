# Étendre la suite autour du SUD Naming.ps1 (grammaire des noms de sidecars).
#
# RepoRoot (deux `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Streams.psd1') ; InModuleScope 'Tetram.Media.Streams' { … }

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams.psd1') -Force -ErrorAction Stop
}
AfterAll { Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue }

Describe 'ConvertTo / ConvertFrom-StreamFileName' {
    It 'round-trip eng + forced + commentary + collision 2' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{
                Class = 'Subtitle'; Language = 'eng'
                Flags = @('forced', 'commentary'); Extension = '.srt'
                CollisionIndex = 2; AttachmentNameSanitized = ''
            }
            $name = ConvertTo-StreamFileName -Basename 'film' -Descriptor $d
            $name | Should -Be 'film.eng.forced.commentary.2.srt'
            $p = ConvertFrom-StreamFileName -Basename 'film' -FileName $name
            $p.Language | Should -Be 'eng'
            $p.Flags | Should -Be @('forced', 'commentary')
            $p.CollisionIndex | Should -Be 2
            $p.Class | Should -Be 'Subtitle'
        }
    }
    It 'round-trip un tag langue tel quel (BCP-47)' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{
                Class = 'Subtitle'; Language = 'pt-BR'
                Flags = @(); Extension = '.srt'
                CollisionIndex = 1; AttachmentNameSanitized = ''
            }
            $name = ConvertTo-StreamFileName -Basename 'film' -Descriptor $d
            $name | Should -Be 'film.pt-BR.srt'
            $p = ConvertFrom-StreamFileName -Basename 'film' -FileName $name
            $p | Should -Not -BeNullOrEmpty
            $p.Language | Should -Be 'pt-BR'
        }
    }
    It 'aligne le préfixe basename sur la sensibilité du système de fichiers' {
        InModuleScope 'Tetram.Media.Streams' {
            $ignore = ConvertFrom-StreamFileName -Basename 'film' -FileName 'Film.eng.srt' -Comparison ([StringComparison]::OrdinalIgnoreCase)
            $ignore | Should -Not -BeNullOrEmpty
            $ignore.Language | Should -Be 'eng'
            $ordinal = ConvertFrom-StreamFileName -Basename 'film' -FileName 'Film.eng.srt' -Comparison ([StringComparison]::Ordinal)
            $ordinal | Should -BeNullOrEmpty
        }
    }
    It 'omet la langue und / vide' {
        InModuleScope 'Tetram.Media.Streams' {
            foreach ($lang in @('', 'und', 'UNK')) {
                $d = [pscustomobject]@{
                    Class = 'Audio'; Language = $lang; Flags = @(); Extension = '.aac'
                    CollisionIndex = 1; AttachmentNameSanitized = ''
                }
                ConvertTo-StreamFileName -Basename 'film' -Descriptor $d | Should -Be 'film.aac'
            }
        }
    }
    It 'écrit les flags dans l''ordre spec même si Flags est dans le désordre' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{
                Class = 'Audio'; Language = 'eng'
                Flags = @('dub', 'default'); Extension = '.aac'
                CollisionIndex = 1; AttachmentNameSanitized = ''
            }
            ConvertTo-StreamFileName -Basename 'film' -Descriptor $d | Should -Be 'film.eng.default.dub.aac'
        }
    }
    It 'lit comment/comments comme commentary' {
        InModuleScope 'Tetram.Media.Streams' {
            $p = ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.eng.comments.aac'
            $p.Flags | Should -Be @('commentary')
        }
    }
    It 'ne traite pas dub comme langue' {
        InModuleScope 'Tetram.Media.Streams' {
            $p = ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.dub.aac'
            $p.Language | Should -Be ''
            $p.Flags | Should -Be @('dub')
        }
    }
    It 'cover et chapters exigent le jeton de classe' {
        InModuleScope 'Tetram.Media.Streams' {
            (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.cover.jpg').Class | Should -Be 'Cover'
            ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.jpg' | Should -BeNullOrEmpty
            (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.chapters.ffmeta').Class | Should -Be 'Chapter'
            ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.ffmeta' | Should -BeNullOrEmpty
        }
    }
    It 'ignore les conteneurs' {
        InModuleScope 'Tetram.Media.Streams' {
            ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.mkv' | Should -BeNullOrEmpty
            ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.mp4' | Should -BeNullOrEmpty
        }
    }
    It 'parse une police sanitisée' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{
                Class = 'Attachment'; Language = ''; Flags = @()
                Extension = '.ttf'; CollisionIndex = 1
                AttachmentNameSanitized = 'Arial_Bold'
            }
            $name = ConvertTo-StreamFileName -Basename 'film' -Descriptor $d
            $name | Should -Be 'film.Arial_Bold.ttf'
            $p = ConvertFrom-StreamFileName -Basename 'film' -FileName $name
            $p.Class | Should -Be 'Attachment'
            $p.AttachmentNameSanitized | Should -Be 'Arial_Bold'
        }
    }
    It 'rejette un jeton libre sur sous-titre, pas sur la grammaire connue' {
        InModuleScope 'Tetram.Media.Streams' {
            ConvertFrom-StreamFileName -Basename 'Movie' -FileName 'Movie.Part2.eng.srt' | Should -BeNullOrEmpty
            $p = ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.eng.forced.commentary.2.srt'
            $p | Should -Not -BeNullOrEmpty
            $p.Class | Should -Be 'Subtitle'
            $p.Language | Should -Be 'eng'
            $p.Flags | Should -Be @('forced', 'commentary')
            $p.CollisionIndex | Should -Be 2
        }
    }
}
