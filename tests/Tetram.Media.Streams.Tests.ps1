# Étendre la suite autour du module SUD Tetram.Media.Streams (split/merge MKV).
#
# RepoRoot depuis tests/ racine : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
# Manifeste : Tetram.Media.Streams.psd1 — Test-ModuleManifest puis Import-Module -Force
# Privé : InModuleScope 'Tetram.Media.Streams' ; mocks Get-FFmpegPath / Write-ErrorLog / Show-CommandLine
# $TestDrive pour sidecars ; tag Integration seulement si vrai ffmpeg.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootStreams = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestStreams = Join-Path $script:RepoRootStreams 'Tetram.Media.Streams.psd1'
}

Describe 'Tetram.Media.Streams manifest' {
    It 'passe Test-ModuleManifest' {
        { Test-ModuleManifest -Path $script:ManifestStreams -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'Tetram.Media.Streams exports' {
    BeforeAll {
        Import-Module -Name $script:ManifestStreams -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
    }

    It 'exporte uniquement Split-MediaStream et Merge-MediaStream' {
        $names = @(Get-Command -Module 'Tetram.Media.Streams' | Select-Object -ExpandProperty Name | Sort-Object)
        $names | Should -Be @('Merge-MediaStream', 'Split-MediaStream')
    }
}

Describe 'Split-MediaStream erreurs' {
    BeforeAll {
        Import-Module -Name $script:ManifestStreams -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
    }

    It 'ne throw pas si le fichier n''est pas un mkv' {
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        $txt = Join-Path $TestDrive 'x.txt'
        Set-Content -LiteralPath $txt -Value 'nope'
        { Split-MediaStream -LiteralPath $txt } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog -Times 1
    }

    It 'ne throw pas si FFmpeg est introuvable' {
        Mock -ModuleName Tetram.Media.Streams Get-FFmpegPath { throw 'FFmpeg introuvable (test)' }
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        $mkv = Join-Path $TestDrive 'film.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        { Split-MediaStream -LiteralPath $mkv } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog -Times 1
    }
}

Describe 'Split-MediaStream WhatIf' {
    BeforeAll {
        Import-Module -Name $script:ManifestStreams -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
    }

    It 'affiche Show-CommandLine et n''appelle pas Invoke-FFmpeg' {
        $mkv = Join-Path $TestDrive 'film.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        Mock -ModuleName Tetram.Media.Streams Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Streams Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Streams Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Streams Show-CommandLine {}
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'ne doit pas tourner' }
        $probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fra' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        Mock -ModuleName Tetram.Media.Streams Get-StreamsProbeHashtable { $probe }
        Split-MediaStream -LiteralPath $mkv -StreamType Subtitle -Language fra -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Streams Show-CommandLine -Times 1
        Should -Invoke -ModuleName Tetram.Media.Streams Invoke-FFmpeg -Times 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'film.fra.srt') | Should -BeFalse
    }
}

Describe 'Merge-MediaStream' {
    BeforeAll {
        Import-Module -Name $script:ManifestStreams -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:Work = Join-Path $TestDrive ('mw-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Work | Out-Null
        $script:Mkv = Join-Path $script:Work 'film.mkv'
        Set-Content -LiteralPath $script:Mkv -Value 'fake-mkv'
        $script:Srt = Join-Path $script:Work 'film.eng.srt'
        Set-Content -LiteralPath $script:Srt -Value '1'
        $script:Probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        Mock -ModuleName Tetram.Media.Streams Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Streams Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Streams Get-StreamsProbeHashtable { $script:Probe }
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Streams Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Streams Show-CommandLine {}
    }

    It 'WhatIf affiche la commande et ne touche pas aux sidecars' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'no ffmpeg' }
        Merge-MediaStream -LiteralPath $script:Mkv -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Streams Show-CommandLine -Times 1
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
        Test-Path -LiteralPath ($script:Mkv + '.tmp') | Should -BeFalse
    }

    It 'WhatIf -RemoveSidecars laisse les sidecars et n''appelle pas Move-Item' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'no ffmpeg' }
        Mock -ModuleName Tetram.Media.Streams Move-Item { throw 'WhatIf ne doit pas déplacer' }
        Merge-MediaStream -LiteralPath $script:Mkv -WhatIf -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
        Should -Invoke -ModuleName Tetram.Media.Streams Move-Item -Times 0
    }

    It 'RemoveSidecars après succès supprime le srt' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $out = $Arguments[-1]
            Set-Content -LiteralPath $out -Value 'muxed'
            return 0
        }
        Merge-MediaStream -LiteralPath $script:Mkv -Force -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeFalse
        Test-Path -LiteralPath $script:Mkv | Should -BeTrue
    }

    It 'RemoveSidecars ne supprime rien si ffmpeg échoue' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { return 1 }
        Merge-MediaStream -LiteralPath $script:Mkv -Force -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
    }

    It 'RemoveSidecars ne supprime rien si Move-Item échoue' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $out = $Arguments[-1]
            Set-Content -LiteralPath $out -Value 'muxed'
            return 0
        }
        Mock -ModuleName Tetram.Media.Streams Move-Item { throw 'access denied' }
        { Merge-MediaStream -LiteralPath $script:Mkv -Force -RemoveSidecars } | Should -Not -Throw
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
    }

    It 'ne throw pas si Invoke-StreamsFFmpeg lève une exception' {
        Mock -ModuleName Tetram.Media.Streams Invoke-StreamsFFmpeg { throw 'unexpected wrapper' }
        { Merge-MediaStream -LiteralPath $script:Mkv -Force } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog
    }
}
