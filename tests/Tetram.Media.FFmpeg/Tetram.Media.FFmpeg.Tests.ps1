# Étendre la suite autour du module SUD Tetram.Media.FFmpeg/Tetram.Media.FFmpeg.psd1 (chemin ffmpeg, vérifs environnement).
#
# RepoRoot (deux niveaux depuis tests/<Module>) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.FFmpeg') -Force
# Couverture résiliente CI : tester ffmpeg absent/présents via Mock, fixtures temp (FFToolsSearchRoot) ou FFToolsVersionReader
# plutôt qu'un `ffmpeg` garanti sur chaque runner ; couvrir sorties erreur attendues (throw actionnable, messages).

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'Tetram.Media.FFmpeg' 'Tetram.Media.FFmpeg.psd1'
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.FFmpeg') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.FFmpeg' -Force -ErrorAction SilentlyContinue
}

Describe 'Tetram.Media.FFmpeg manifest' {
    It 'déclare FFToolsMinVersion = 9.0.1 dans PrivateData' {
        $data = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
        $data.PrivateData.FFToolsMinVersion | Should -Be '9.0.1'
    }
}

function script:New-FakeFFBuild {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FolderName,
        [string]$VersionText, # $null = script qui n'imprime pas de version
        [switch]$OmitBinary
    )

    $bin = Join-Path $Root $FolderName 'bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    if ($OmitBinary) { return }
    $ffmpegName = if ($IsWindows) { 'ffmpeg.exe' } else { 'ffmpeg' }
    $ffprobeName = if ($IsWindows) { 'ffprobe.exe' } else { 'ffprobe' }
    $ffmpegPath = Join-Path $bin $ffmpegName
    $ffprobePath = Join-Path $bin $ffprobeName
    if ($IsWindows) {
        # Stubs .cmd invoqués via cmd ; on crée des .bat renommés ne marchent pas comme .exe.
        # Sur Windows local : utiliser un shim .exe via PowerShell scriptblock injection —
        # la CI est Linux ; pour Windows, les tests s'appuient sur $script:FFToolsVersionReader.
        New-Item -ItemType File -Path $ffmpegPath -Force | Out-Null
        New-Item -ItemType File -Path $ffprobePath -Force | Out-Null
    }
    else {
        $body = if ($VersionText) {
            "#!/bin/sh`necho 'ffmpeg version $VersionText-full_build-www.gyan.dev Copyright (c) 2000-2026'`n"
        }
        else {
            "#!/bin/sh`necho 'not a version line'`n"
        }
        Set-Content -LiteralPath $ffmpegPath -Value $body -NoNewline
        Set-Content -LiteralPath $ffprobePath -Value $body -NoNewline
        & chmod +x $ffmpegPath $ffprobePath
    }
}

Describe 'Resolve-FFToolsDefaultBase' {
    BeforeEach {
        $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ("fftools-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        InModuleScope 'Tetram.Media.FFmpeg' -Parameters @{ TestRoot = $script:TestRoot } {
            param($TestRoot)

            $script:FFToolsSearchRoot = $TestRoot
            $script:FFToolsDefaultBase = $null
            $script:FFToolsBaseResolved = $false
            $script:FFToolsVersionReader = $null
        }
    }
    AfterEach {
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'sélectionne la plus haute version >= min' {
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-8.0.1-full_build' -VersionText '8.0.1'
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-9.0.1-full_build' -VersionText '9.0.1'
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-9.1.0-full_build' -VersionText '9.1.0'
        if ($IsWindows) {
            InModuleScope 'Tetram.Media.FFmpeg' {
                $script:FFToolsVersionReader = {
                    param($LiteralPath)

                    if ($LiteralPath -match '9\.1\.0') { return [version]'9.1.0' }
                    if ($LiteralPath -match '9\.0\.1') { return [version]'9.0.1' }
                    if ($LiteralPath -match '8\.0\.1') { return [version]'8.0.1' }
                    return $null
                }
            }
        }
        $base = InModuleScope 'Tetram.Media.FFmpeg' { Resolve-FFToolsDefaultBase }
        $base | Should -Match 'ffmpeg-9\.1\.0-full_build[\\/]bin$'
    }

    It 'ignore une version < min' {
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-8.0.1-full_build' -VersionText '8.0.1'
        if ($IsWindows) {
            InModuleScope 'Tetram.Media.FFmpeg' {
                $script:FFToolsVersionReader = {
                    param($LiteralPath)

                    [version]'8.0.1'
                }
            }
        }
        $base = InModuleScope 'Tetram.Media.FFmpeg' { Resolve-FFToolsDefaultBase }
        $base | Should -BeNullOrEmpty
    }

    It 'ignore un binaire sans version parsable' {
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-bogus-full_build' -VersionText $null
        if ($IsWindows) {
            InModuleScope 'Tetram.Media.FFmpeg' {
                $script:FFToolsVersionReader = {
                    param($LiteralPath)

                    $null
                }
            }
        }
        $base = InModuleScope 'Tetram.Media.FFmpeg' { Resolve-FFToolsDefaultBase }
        $base | Should -BeNullOrEmpty
    }

    It 'ignore une build ffmpeg sans ffprobe et prend une build complète plus ancienne' {
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-9.0.1-full_build' -VersionText '9.0.1'
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-9.1.0-full_build' -VersionText '9.1.0'
        $probeName = if ($IsWindows) { 'ffprobe.exe' } else { 'ffprobe' }
        Remove-Item -LiteralPath (Join-Path $script:TestRoot 'ffmpeg-9.1.0-full_build' 'bin' $probeName) -Force
        if ($IsWindows) {
            InModuleScope 'Tetram.Media.FFmpeg' {
                $script:FFToolsVersionReader = {
                    param($LiteralPath)

                    if ($LiteralPath -match '9\.1\.0') { return [version]'9.1.0' }
                    if ($LiteralPath -match '9\.0\.1') { return [version]'9.0.1' }
                    return $null
                }
            }
        }
        $base = InModuleScope 'Tetram.Media.FFmpeg' { Resolve-FFToolsDefaultBase }
        $base | Should -Match 'ffmpeg-9\.0\.1-full_build[\\/]bin$'
    }

    It 'Get-FFmpegPath et Get-FfprobePath partagent le même bin' {
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-9.0.1-full_build' -VersionText '9.0.1'
        if ($IsWindows) {
            InModuleScope 'Tetram.Media.FFmpeg' {
                $script:FFToolsVersionReader = {
                    param($LiteralPath)

                    [version]'9.0.1'
                }
            }
        }
        InModuleScope 'Tetram.Media.FFmpeg' {
            $ff = Get-FFmpegPath
            $fp = Get-FfprobePath
            [IO.Path]::GetDirectoryName($ff) | Should -Be ([IO.Path]::GetDirectoryName($fp))
        }
    }

    It 'Get-FFmpegPath -OverridePath retourne override sans scan' {
        $fake = Join-Path $script:TestRoot 'custom-ffmpeg'
        Set-Content -LiteralPath $fake -Value 'x'
        InModuleScope 'Tetram.Media.FFmpeg' -Parameters @{ Fake = $fake } {
            param($Fake)

            Get-FFmpegPath -OverridePath $Fake | Should -Be $Fake
            $script:FFToolsBaseResolved | Should -BeFalse
        }
    }

    It 'Get-FFmpegPath -OverridePath refuse un dossier' {
        InModuleScope 'Tetram.Media.FFmpeg' -Parameters @{ Dir = $script:TestRoot } {
            param($Dir)

            { Get-FFmpegPath -OverridePath $Dir } | Should -Throw -ExpectedMessage '*pas un dossier*'
        }
    }

    It 'Get-FFmpegPath -OverridePath refuse un chemin inexistant (pas de fallback)' {
        $missing = Join-Path $script:TestRoot 'no-such-ffmpeg.exe'
        InModuleScope 'Tetram.Media.FFmpeg' -Parameters @{ Missing = $missing } {
            param($Missing)

            { Get-FFmpegPath -OverridePath $Missing } | Should -Throw -ExpectedMessage '*inexistant*'
        }
    }

    It 'throw un message actionnable si rien trouvé' {
        Mock -ModuleName Tetram.Media.FFmpeg Get-Command { $null } -ParameterFilter { $Name -eq 'ffmpeg' }
        InModuleScope 'Tetram.Media.FFmpeg' {
            $script:FFToolsSearchRoot = Join-Path ([IO.Path]::GetTempPath()) ('empty-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:FFToolsSearchRoot -Force | Out-Null
            $script:FFToolsBaseResolved = $false
            $script:FFToolsDefaultBase = $null
            { Get-FFmpegPath } | Should -Throw -ExpectedMessage '*9.0.1*'
            { Get-FFmpegPath } | Should -Throw -ExpectedMessage '*Tetram.Media.FFmpeg*'
        }
    }

    It 'ignore une fonction ffmpeg/ffprobe de même nom au lieu de renvoyer une Source vide' {
        InModuleScope 'Tetram.Media.FFmpeg' {
            function ffmpeg { 'ne doit jamais être choisie' }
            function ffprobe { 'ne doit jamais être choisie' }
            try {
                $script:FFToolsSearchRoot = Join-Path ([IO.Path]::GetTempPath()) ('empty-' + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $script:FFToolsSearchRoot -Force | Out-Null
                $script:FFToolsBaseResolved = $false
                $script:FFToolsDefaultBase = $null
                { Get-FFmpegPath } | Should -Throw -ExpectedMessage '*Tetram.Media.FFmpeg*'
                { Get-FfprobePath } | Should -Throw -ExpectedMessage '*Tetram.Media.FFmpeg*'
            }
            finally {
                Remove-Item -Path 'function:ffmpeg', 'function:ffprobe' -ErrorAction SilentlyContinue
            }
        }
    }
}
