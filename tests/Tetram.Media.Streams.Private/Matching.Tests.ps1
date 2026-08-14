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

Describe 'Get-StreamsFlippedCasePath' {
    It 'inverse la casse de tous les caracteres du nom, pas seulement le premier' {
        $p = Join-Path $TestDrive 'film.mkv'
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ P = $p } {
            param($P)
            Split-Path -Leaf (Get-StreamsFlippedCasePath -Path $P) | Should -BeExactly 'FILM.MKV'
        }
    }
    It 'ne produit pas de chemin alternatif si aucun caractere n''a de casse' {
        $p = Join-Path $TestDrive ([char]0x5F71)
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ P = $p } {
            param($P)
            Get-StreamsFlippedCasePath -Path $P | Should -BeNullOrEmpty
        }
    }
}

Describe 'Test-StreamsDirectoryCaseSensitive' {
    It 'declare le FS sensible si les deux casses sont deux inodes distincts' {
        $dir = Join-Path $TestDrive 'two-ino'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $lower = Join-Path $dir 'film.mkv'
        $upper = Join-Path $dir 'FILM.MKV'
        New-Item -ItemType File -Path $lower | Out-Null
        try { New-Item -ItemType File -Path $upper -ErrorAction Stop | Out-Null }
        catch {
            Set-ItResult -Skipped -Because 'le FS n''a pas accepte une 2e casse'
            return
        }
        $names = @(Get-ChildItem -LiteralPath $dir -File | ForEach-Object Name)
        $hasLower = @($names | Where-Object { $_ -ceq 'film.mkv' }).Count -eq 1
        $hasUpper = @($names | Where-Object { $_ -ceq 'FILM.MKV' }).Count -eq 1
        if (-not ($hasLower -and $hasUpper)) {
            Set-ItResult -Skipped -Because 'une seule entree disque pour les deux casses'
            return
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Lower = $lower } {
            param($Lower)
            $idHere = Get-StreamsFileIdentity -Path $Lower
            $idOther = Get-StreamsFileIdentity -Path (Get-StreamsFlippedCasePath -Path $Lower)
            $idHere | Should -Not -BeNullOrEmpty
            $idOther | Should -Not -BeNullOrEmpty
            ($idHere -cne $idOther) | Should -BeTrue
            Test-StreamsDirectoryCaseSensitive -ExistingPath $Lower | Should -BeTrue
            Get-StreamsNameComparison -ExistingPath $Lower | Should -Be ([StringComparison]::Ordinal)
        }
    }
}

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
    It 'n''associe pas un sidecar dont le basename diffère seulement par la casse si le FS est sensible' {
        $dir = Join-Path $TestDrive 'cs'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        $other = Join-Path $dir 'Film.eng.srt'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path $other | Out-Null
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Mkv = $mkv; Other = $other } {
            param($Dir, $Mkv, $Other)
            $sides = @(Get-SidecarFiles -Directory $Dir -Basename 'film' -ExcludePath @($Mkv) -NameComparison ([StringComparison]::Ordinal))
            $sides.Count | Should -Be 0
        }
    }
    It 'reste insensible si LiteralPath et le nom disque ne different que par la casse' {
        $dir = Join-Path $TestDrive 'altcase'
        New-Item -ItemType Directory -Path $dir | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'Film.mkv') | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'Film.eng.srt') | Out-Null
        $caller = Join-Path $dir 'film.mkv'
        if (-not (Test-Path -LiteralPath $caller -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'FS sensible : film.mkv n''ouvre pas Film.mkv'
            return
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Caller = $caller } {
            param($Dir, $Caller)
            Get-StreamsNameComparison -ExistingPath $Caller | Should -Be ([StringComparison]::OrdinalIgnoreCase)
            $base = [IO.Path]::GetFileNameWithoutExtension($Caller)
            $sides = @(Get-SidecarFiles -Directory $Dir -Basename $base -ExcludePath @($Caller) -ExistingPath $Caller)
            $sides.Count | Should -Be 1
        }
    }
    It 'trouve un sidecar dont seul la casse du basename diffère si le FS est insensible' {
        $dir = Join-Path $TestDrive 'ci'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        $side = Join-Path $dir 'Film.eng.srt'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path $side | Out-Null
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Mkv = $mkv } {
            param($Dir, $Mkv)
            if (-not $IsWindows) { return }
            Get-StreamsNameComparison -ExistingPath $Mkv | Should -Be ([StringComparison]::OrdinalIgnoreCase)
            $sides = @(Get-SidecarFiles -Directory $Dir -Basename 'film' -ExcludePath @($Mkv) -ExistingPath $Mkv)
            $sides.Count | Should -Be 1
        }
    }
    It 'sonde la casse via le MKV existant sans créer de fichier' {
        $dir = Join-Path $TestDrive 'probe'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.srt') | Out-Null
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Mkv = $mkv } {
            param($Dir, $Mkv)
            $before = @(Get-ChildItem -LiteralPath $Dir -File | ForEach-Object Name | Sort-Object)
            $null = Test-StreamsDirectoryCaseSensitive -ExistingPath $Mkv
            $null = Get-SidecarFiles -Directory $Dir -Basename 'film' -ExcludePath @($Mkv) -ExistingPath $Mkv
            Get-ChildItem -LiteralPath $Dir -Filter '*.tmp' -File | Should -BeNullOrEmpty
            $after = @(Get-ChildItem -LiteralPath $Dir -File | ForEach-Object Name | Sort-Object)
            $after | Should -Be $before
        }
    }
    It 'ignore les sidecars vidéo/audio (référence split, pas de mux)' {
        $dir = Join-Path $TestDrive 'ref'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.h264') | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.aac') | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.srt') | Out-Null
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Mkv = $mkv } {
            param($Dir, $Mkv)
            $sides = @(Get-SidecarFiles -Directory $Dir -Basename 'film' -ExcludePath @($Mkv))
            $sides.Count | Should -Be 1
            $sides[0].Class | Should -Be 'Subtitle'
            $sides[0].Extension | Should -Be '.srt'
        }
    }
    It 'accepte un MKV sans descripteur mappé et n''ajoute que les sidecars' {
        $dir = Join-Path $TestDrive 'empty-desc'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.srt') | Out-Null
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Mkv = $mkv } {
            param($Dir, $Mkv)
            $sides = @(Get-SidecarFiles -Directory $Dir -Basename 'film' -ExcludePath @($Mkv))
            { Resolve-MergeActions -MkvDescriptors @() -Sidecars $sides } | Should -Not -Throw
            $act = Resolve-MergeActions -MkvDescriptors @() -Sidecars $sides
            $act.Adds.Count | Should -Be 1
            $act.Keeps.Count | Should -Be 0
            $act.Replaces.Count | Should -Be 0
        }
    }
}

Describe 'Build-MergeFFmpegArgs unmapped keep' {
    It 'émet -map 0:2 pour un flux data keep intercalé' {
        $dir = Join-Path $TestDrive 'um'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.srt') | Out-Null
        $probe = @{
            streams = @(
                @{ index = 2; codec_type = 'data'; codec_name = 'bin_data'; tags = @{}; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
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

Describe 'Build-MergeFFmpegArgs muxer temporaire' {
    It 'émet -f matroska immédiatement avant le chemin de sortie' {
        $dir = Join-Path $TestDrive 'mux'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.srt') | Out-Null
        $probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Mkv = $mkv; Probe = $probe } {
            param($Dir, $Mkv, $Probe)
            $desc = @(Get-MediaStreamDescriptors -Probe $Probe)
            $sides = @(Get-SidecarFiles -Directory $Dir -Basename 'film' -ExcludePath @($Mkv))
            $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars $sides
            $out = Join-Path $Dir 'out.mkv.tmp'
            $ffmpegArgs = @(Build-MergeFFmpegArgs -MkvPath $Mkv -Actions $act -OutputPath $out)
            $oi = [array]::IndexOf($ffmpegArgs, $out)
            $oi | Should -BeGreaterThan 1
            $ffmpegArgs[$oi - 2] | Should -Be '-f'
            $ffmpegArgs[$oi - 1] | Should -Be 'matroska'
        }
    }
}

Describe 'Build-MergeFFmpegArgs attachments keep' {
    It 'mappe la pièce jointe MKV et ignore un sidecar .ttf' {
        $dir = Join-Path $TestDrive 'att'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        $font = Join-Path $dir 'film.Replaced.ttf'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path $font | Out-Null
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Mkv = $mkv } {
            param($Dir, $Mkv)
            $keep = New-StreamDescriptorObject -Class 'Attachment' -Extension '.ttf' -StreamIndex 4 -AttachmentNameSanitized 'KeepFont'
            $sides = @(Get-SidecarFiles -Directory $Dir -Basename 'film' -ExcludePath @($Mkv))
            $sides.Count | Should -Be 0
            $act = Resolve-MergeActions -MkvDescriptors @($keep) -Sidecars $sides
            $act.Replaces.Count | Should -Be 0
            $ffmpegArgs = @(Build-MergeFFmpegArgs -MkvPath $Mkv -Actions $act -OutputPath ($Mkv + '.tmp'))
            $ffmpegArgs | Should -Not -Contain '-attach'
            $hasKeepMap = $false
            for ($i = 0; $i -lt $ffmpegArgs.Count - 1; $i++) {
                if ($ffmpegArgs[$i] -eq '-map' -and $ffmpegArgs[$i + 1] -eq '0:4') { $hasKeepMap = $true }
            }
            $hasKeepMap | Should -BeTrue
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
