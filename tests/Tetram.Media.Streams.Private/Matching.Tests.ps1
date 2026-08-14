# Étendre la suite autour de Matching.ps1 (sidecars, replace/add/keep, args merge).
#
# RepoRoot : (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module Tetram.Media.Streams.psd1 ; InModuleScope ; $TestDrive pour fichiers

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams.psd1') -Force -ErrorAction Stop
}
AfterAll { Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue }

Describe 'Get-SidecarFiles / Resolve-MergeActions' {
    It 'exclut film.mkv, remplace les deux eng, ajoute spa' {
        $dir = Join-Path $TestDrive 'm'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.srt') | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.2.srt') | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.spa.srt') | Out-Null
        $probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 5; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Mkv = $mkv; Probe = $probe } {
            param($Dir, $Mkv, $Probe)
            $desc = @(Get-MediaStreamDescriptors -Probe $Probe)
            $sides = @(Get-SidecarFiles -Directory $Dir -Basename 'film' -ExcludePath @($Mkv))
            $sides.FullName | Should -Not -Contain $Mkv
            $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars $sides
            $act.Replaces.Count | Should -Be 2
            $act.Keeps.Count | Should -Be 0
            $act.Adds.Count | Should -Be 1
            $act.Adds[0].Language | Should -Be 'spa'
            $ffmpegArgs = Build-MergeFFmpegArgs -MkvPath $Mkv -Actions $act -OutputPath (Join-Path $Dir 'out.mkv')
            ($ffmpegArgs -join ' ') | Should -Match '-map 1:0'
            ($ffmpegArgs -join ' ') | Should -Match 'language=eng'
            ($ffmpegArgs -join ' ') | Should -Match 'language=spa'
        }
    }
}

Describe 'Build-MergeFFmpegArgs unmapped keep' {
    It 'émet -map 0:2 pour une piste mpeg4 keep intercalée' {
        $dir = Join-Path $TestDrive 'um'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.srt') | Out-Null
        $probe = @{
            streams = @(
                @{ index = 2; codec_type = 'video'; codec_name = 'mpeg4'; tags = @{}; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Mkv = $mkv; Probe = $probe } {
            param($Dir, $Mkv, $Probe)
            $desc = @(Get-MediaStreamDescriptors -Probe $Probe)
            $desc = @(Add-UnmappedKeepDescriptors -Descriptors $desc -Probe $Probe)
            $sides = @(Get-SidecarFiles -Directory $Dir -Basename 'film' -ExcludePath @($Mkv))
            $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars $sides
            $ffmpegArgs = Build-MergeFFmpegArgs -MkvPath $Mkv -Actions $act -OutputPath (Join-Path $Dir 'out.mkv')
            $pair = $false
            for ($i = 0; $i -lt $ffmpegArgs.Count - 1; $i++) {
                if ($ffmpegArgs[$i] -eq '-map' -and $ffmpegArgs[$i + 1] -eq '0:2') { $pair = $true; break }
            }
            $pair | Should -BeTrue
        }
    }
}

Describe 'Get-FfmpegDispositionValue' {
    It 'joint comment pour commentary' {
        InModuleScope 'Tetram.Media.Streams' {
            Get-FfmpegDispositionValue -Flags @('commentary', 'default') | Should -Be 'default+comment'
            Get-FfmpegDispositionValue -Flags @() | Should -Be '0'
        }
    }
}
