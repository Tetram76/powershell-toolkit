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

    It 'exporte uniquement Split-MediaStream et Merge-MediaSubtitle' {
        $names = @(Get-Command -Module 'Tetram.Media.Streams' | Select-Object -ExpandProperty Name | Sort-Object)
        $names | Should -Be @('Merge-MediaSubtitle', 'Split-MediaStream')
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

    It 'rejette tout le split si un codec n''est pas dans la table' {
        $mkv = Join-Path $TestDrive 'unmapped.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        Mock -ModuleName Tetram.Media.Streams Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Streams Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Streams Write-InfoLog {}
        $script:ShowCalled = 0
        Mock -ModuleName Tetram.Media.Streams Show-CommandLine { $script:ShowCalled++ }
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'ne doit pas extraire' }
        $probe = @{
            streams = @(
                @{ index = 0; codec_type = 'audio'; codec_name = 'alac'; tags = @{}; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fra' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        Mock -ModuleName Tetram.Media.Streams Get-StreamsProbeHashtable { $probe }
        Split-MediaStream -LiteralPath $mkv -StreamType Subtitle -Language fra -Force
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog
        $script:ShowCalled | Should -Be 0
        Should -Invoke -ModuleName Tetram.Media.Streams Invoke-FFmpeg -Times 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'unmapped.fra.srt') | Should -BeFalse
    }

    It 'ignore un flux data et extrait les A/V/S' {
        $mkv = Join-Path $TestDrive 'with-data.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        Mock -ModuleName Tetram.Media.Streams Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Streams Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Streams Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Streams Show-CommandLine {}
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'ne doit pas extraire sous WhatIf' }
        $probe = @{
            streams = @(
                @{ index = 1; codec_type = 'data'; codec_name = 'bin_data'; tags = @{}; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fra' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        Mock -ModuleName Tetram.Media.Streams Get-StreamsProbeHashtable { $probe }
        Split-MediaStream -LiteralPath $mkv -StreamType Subtitle -Language fra -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog -Times 0
        Should -Invoke -ModuleName Tetram.Media.Streams Show-CommandLine -Times 1
    }

    It 'résout ~ avant ffprobe' {
        $name = 'streams-tilde-' + [guid]::NewGuid().ToString('N') + '.mkv'
        $homeMkv = Join-Path $HOME $name
        Set-Content -LiteralPath $homeMkv -Value 'fake'
        $expected = (Resolve-Path -LiteralPath $homeMkv).Path
        try {
            Mock -ModuleName Tetram.Media.Streams Get-FFmpegPath { 'ffmpeg' }
            Mock -ModuleName Tetram.Media.Streams Get-FfprobePath { 'ffprobe' }
            Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
            Mock -ModuleName Tetram.Media.Streams Write-InfoLog {}
            Mock -ModuleName Tetram.Media.Streams Show-CommandLine {}
            Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'ne doit pas tourner' }
            $script:ProbePathSeen = $null
            Mock -ModuleName Tetram.Media.Streams Get-StreamsProbeHashtable {
                param($Ffprobe, $LiteralPath)
                $script:ProbePathSeen = $LiteralPath
                @{ streams = @() }
            }
            Split-MediaStream -LiteralPath ('~/' + $name) -WhatIf
            $script:ProbePathSeen | Should -Be $expected
        }
        finally {
            Remove-Item -LiteralPath $homeMkv -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Split-MediaStream extract failure' {
    BeforeAll {
        Import-Module -Name $script:ManifestStreams -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:Mkv = Join-Path $TestDrive 'film.mkv'
        Set-Content -LiteralPath $script:Mkv -Value 'fake'
        $script:Sidecar = Join-Path $TestDrive 'film.fra.srt'
        $script:Probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fra' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        Mock -ModuleName Tetram.Media.Streams Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Streams Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Streams Get-StreamsProbeHashtable { $script:Probe }
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Streams Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Streams Show-CommandLine {}
    }

    AfterEach {
        if ($script:FfmpegOut -and (Test-Path -LiteralPath $script:FfmpegOut)) {
            Remove-Item -LiteralPath $script:FfmpegOut -Force -ErrorAction SilentlyContinue
        }
        $script:FfmpegOut = $null
    }

    It 'ne laisse pas de sidecar si ffmpeg échoue' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $script:FfmpegOut = $Arguments[-1]
            Set-Content -LiteralPath $Arguments[-1] -Value 'partial'
            return 1
        }
        Split-MediaStream -LiteralPath $script:Mkv -StreamType Subtitle -Language fra -Force
        Test-Path -LiteralPath $script:Sidecar | Should -BeFalse
        Test-Path -LiteralPath $script:FfmpegOut | Should -BeFalse
        Get-ChildItem -LiteralPath $TestDrive -Filter '*.tmp*' -File | Should -BeNullOrEmpty
    }

    It 'conserve un sidecar existant si ffmpeg échoue' {
        Set-Content -LiteralPath $script:Sidecar -Value 'good'
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $script:FfmpegOut = $Arguments[-1]
            Set-Content -LiteralPath $Arguments[-1] -Value 'partial'
            return 1
        }
        Split-MediaStream -LiteralPath $script:Mkv -StreamType Subtitle -Language fra -Force
        Get-Content -LiteralPath $script:Sidecar | Should -Be 'good'
    }

    It 'écrit FFmpeg dans TEMP (GUID + extension sidecar), pas à côté du MKV' {
        $script:FfmpegOut = $null
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $script:FfmpegOut = $Arguments[-1]
            Set-Content -LiteralPath $Arguments[-1] -Value 'ok'
            return 0
        }
        Split-MediaStream -LiteralPath $script:Mkv -StreamType Subtitle -Language fra -Force
        [IO.Path]::GetExtension($script:FfmpegOut) | Should -Be '.srt'
        $gotDir = [IO.Path]::GetFullPath((Split-Path -Parent $script:FfmpegOut)).TrimEnd('\', '/')
        $wantDir = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
        $gotDir | Should -Be $wantDir
        Test-Path -LiteralPath $script:FfmpegOut | Should -BeFalse
        Get-Content -LiteralPath $script:Sidecar | Should -Be 'ok'
    }

    It 'refuse un dossier qui occupe le chemin sidecar' {
        if (Test-Path -LiteralPath $script:Sidecar) {
            Remove-Item -LiteralPath $script:Sidecar -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:Sidecar | Out-Null
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'ne doit pas extraire' }
        Split-MediaStream -LiteralPath $script:Mkv -StreamType Subtitle -Language fra -Force
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog
        Should -Invoke -ModuleName Tetram.Media.Streams Invoke-FFmpeg -Times 0
        Get-ChildItem -LiteralPath $script:Sidecar -File | Should -BeNullOrEmpty
    }
}

Describe 'Merge-MediaSubtitle' {
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
        $script:FfmpegOut = $null
    }
    AfterEach {
        if ($script:FfmpegOut -and (Test-Path -LiteralPath $script:FfmpegOut)) {
            Remove-Item -LiteralPath $script:FfmpegOut -Force -ErrorAction SilentlyContinue
        }
        $script:FfmpegOut = $null
    }

    It 'écrit FFmpeg dans TEMP (GUID + .mkv), pas à côté du MKV' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $script:FfmpegOut = $Arguments[-1]
            Set-Content -LiteralPath $Arguments[-1] -Value 'muxed'
            return 0
        }
        Merge-MediaSubtitle -LiteralPath $script:Mkv -Force
        [IO.Path]::GetExtension($script:FfmpegOut) | Should -Be '.mkv'
        $gotDir = [IO.Path]::GetFullPath((Split-Path -Parent $script:FfmpegOut)).TrimEnd('\', '/')
        $wantDir = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
        $gotDir | Should -Be $wantDir
        [IO.Path]::GetFileName($script:FfmpegOut) | Should -Not -Match 'film'
        Test-Path -LiteralPath $script:FfmpegOut | Should -BeFalse
        Get-Content -LiteralPath $script:Mkv | Should -Be 'muxed'
        Test-Path -LiteralPath ($script:Mkv + '.tmp') | Should -BeFalse
    }

    It 'WhatIf affiche la commande et ne touche pas aux sidecars' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'no ffmpeg' }
        Merge-MediaSubtitle -LiteralPath $script:Mkv -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Streams Show-CommandLine -Times 1
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
        Test-Path -LiteralPath ($script:Mkv + '.tmp') | Should -BeFalse
    }

    It 'WhatIf -RemoveSidecars laisse les sidecars et n''appelle pas Move-Item' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'no ffmpeg' }
        Mock -ModuleName Tetram.Media.Streams Move-Item { throw 'WhatIf ne doit pas déplacer' }
        Merge-MediaSubtitle -LiteralPath $script:Mkv -WhatIf -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
        Should -Invoke -ModuleName Tetram.Media.Streams Move-Item -Times 0
    }

    It 'RemoveSidecars après succès supprime le srt' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $script:FfmpegOut = $Arguments[-1]
            Set-Content -LiteralPath $script:FfmpegOut -Value 'muxed'
            return 0
        }
        Merge-MediaSubtitle -LiteralPath $script:Mkv -Force -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeFalse
        Test-Path -LiteralPath $script:Mkv | Should -BeTrue
    }

    It 'RemoveSidecars ne supprime pas un sidecar non muxé' {
        $other = Join-Path $script:Work 'other.eng.srt'
        Set-Content -LiteralPath $other -Value 'keep'
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $script:FfmpegOut = $Arguments[-1]
            Set-Content -LiteralPath $script:FfmpegOut -Value 'muxed'
            return 0
        }
        Merge-MediaSubtitle -LiteralPath $script:Mkv -Force -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeFalse
        Test-Path -LiteralPath $other | Should -BeTrue
    }

    It 'RemoveSidecars ne supprime pas un sidecar vidéo de référence' {
        $h264 = Join-Path $script:Work 'film.h264'
        Set-Content -LiteralPath $h264 -Value 'ref'
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $script:FfmpegOut = $Arguments[-1]
            Set-Content -LiteralPath $script:FfmpegOut -Value 'muxed'
            return 0
        }
        Merge-MediaSubtitle -LiteralPath $script:Mkv -Force -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeFalse
        Test-Path -LiteralPath $h264 | Should -BeTrue
    }

    It 'RemoveSidecars ne supprime rien si ffmpeg échoue' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { return 1 }
        Merge-MediaSubtitle -LiteralPath $script:Mkv -Force -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
    }

    It 'RemoveSidecars ne supprime rien si Move-Item échoue' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $script:FfmpegOut = $Arguments[-1]
            Set-Content -LiteralPath $script:FfmpegOut -Value 'muxed'
            return 0
        }
        Mock -ModuleName Tetram.Media.Streams Move-Item { throw 'access denied' }
        { Merge-MediaSubtitle -LiteralPath $script:Mkv -Force -RemoveSidecars } | Should -Not -Throw
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
    }

    It 'RemoveSidecars ne supprime rien si le temp est absent' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { return 0 }
        Merge-MediaSubtitle -LiteralPath $script:Mkv -Force -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog -ParameterFilter { $Text -like '*Temp file missing*' }
    }

    It 'ne throw pas si Invoke-StreamsFFmpeg lève une exception' {
        Mock -ModuleName Tetram.Media.Streams Invoke-StreamsFFmpeg { throw 'unexpected wrapper' }
        { Merge-MediaSubtitle -LiteralPath $script:Mkv -Force } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog
    }

    It 'muxe les sous-titres même si un codec audio n''est pas dans la table' {
        $script:Probe = @{
            streams = @(
                @{ index = 0; codec_type = 'audio'; codec_name = 'alac'; tags = @{}; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $script:FfmpegOut = $Arguments[-1]
            Set-Content -LiteralPath $script:FfmpegOut -Value 'muxed'
            return 0
        }
        Merge-MediaSubtitle -LiteralPath $script:Mkv -Force
        Should -Invoke -ModuleName Tetram.Media.Streams Invoke-FFmpeg -Times 1
        Get-Content -LiteralPath $script:Mkv | Should -Be 'muxed'
    }

    It 'refuse un dossier -Destination même si le nom finit par .mkv' {
        $dirDest = Join-Path $script:Work 'out.mkv'
        New-Item -ItemType Directory -Path $dirDest | Out-Null
        Merge-MediaSubtitle -LiteralPath $script:Mkv -Destination $dirDest -Force
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Streams Get-StreamsProbeHashtable -Times 0
    }

    It 'résout ~ avant ffprobe' {
        $name = 'streams-tilde-m-' + [guid]::NewGuid().ToString('N') + '.mkv'
        $homeMkv = Join-Path $HOME $name
        $homeSrt = Join-Path $HOME ($name -replace '\.mkv$', '.eng.srt')
        Set-Content -LiteralPath $homeMkv -Value 'fake-mkv'
        Set-Content -LiteralPath $homeSrt -Value '1'
        $expected = (Resolve-Path -LiteralPath $homeMkv).Path
        try {
            $script:ProbePathSeen = $null
            Mock -ModuleName Tetram.Media.Streams Get-StreamsProbeHashtable {
                param($Ffprobe, $LiteralPath)
                $script:ProbePathSeen = $LiteralPath
                $script:Probe
            }
            Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'no ffmpeg' }
            Merge-MediaSubtitle -LiteralPath ('~/' + $name) -WhatIf
            $script:ProbePathSeen | Should -Be $expected
        }
        finally {
            Remove-Item -LiteralPath $homeMkv, $homeSrt -Force -ErrorAction SilentlyContinue
        }
    }
}
