# Étendre la suite autour de Matching.ps1 (replace/add/keep, args merge).
#
# RepoRoot : (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module Tetram.Media.Streams.psd1 ; InModuleScope
# Merge-MediaSubtitle traite un seul sidecar explicite (-Path) : plus de scan de dossier
# (Get-SidecarFiles a disparu). Les sidecars de test sont construits via ConvertFrom-StreamFileName.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams.psd1') -Force -ErrorAction Stop
}
AfterAll { Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue }

Describe 'Resolve-MergeActions' {
    It 'remplace les deux eng, ajoute spa' {
        $probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 5; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $desc = @(Get-MediaStreamDescriptors -Probe $Probe)
            $sides = @(
                (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.eng.srt')
                (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.eng.2.srt')
                (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.spa.srt')
            )
            for ($i = 0; $i -lt $sides.Count; $i++) { $sides[$i] | Add-Member -NotePropertyName FullName -NotePropertyValue "sidecar$i" -Force }
            $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars $sides
            $act.Replaces.Count | Should -Be 2
            $act.Keeps.Count | Should -Be 0
            $act.Adds.Count | Should -Be 1
            $act.Adds[0].Language | Should -Be 'spa'
            $ffmpegArgs = Build-MergeFFmpegArgs -MkvPath 'film.mkv' -Actions $act -OutputPath 'out.mkv'
            ($ffmpegArgs -join ' ') | Should -Match '-map 1:0'
            ($ffmpegArgs -join ' ') | Should -Match 'language=eng'
            ($ffmpegArgs -join ' ') | Should -Match 'language=spa'
        }
    }
    It 'ajoute film.spa.2.srt meme sans film.spa.srt (pas de collision = ajout, quel que soit l''index)' {
        InModuleScope 'Tetram.Media.Streams' {
            $side = ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.spa.2.srt'
            $side | Add-Member -NotePropertyName FullName -NotePropertyValue 'sidecar0' -Force
            $act = Resolve-MergeActions -MkvDescriptors @() -Sidecars @($side)
            $act.Adds.Count | Should -Be 1
        }
    }
    It 'accepte film.spa.srt + film.spa.2.srt ensemble (sequence complete depuis 1)' {
        InModuleScope 'Tetram.Media.Streams' {
            $sides = @(
                (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.spa.srt')
                (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.spa.2.srt')
            )
            for ($i = 0; $i -lt $sides.Count; $i++) { $sides[$i] | Add-Member -NotePropertyName FullName -NotePropertyValue "sidecar$i" -Force }
            $act = Resolve-MergeActions -MkvDescriptors @() -Sidecars $sides
            $act.Adds.Count | Should -Be 2
        }
    }
    It 'accepte un sidecar .2. si une piste spa existante (gardee) occupe deja l''index 1' {
        $probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'spa' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $desc = @(Get-MediaStreamDescriptors -Probe $Probe)
            $side = ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.spa.2.srt'
            $side | Add-Member -NotePropertyName FullName -NotePropertyValue 'sidecar0' -Force
            $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars @($side)
            $act.Keeps.Count | Should -Be 1
            $act.Adds.Count | Should -Be 1
        }
    }
    It 'accepte un MKV sans descripteur mappé et n''ajoute que les sidecars' {
        InModuleScope 'Tetram.Media.Streams' {
            $side = ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.eng.srt'
            $side | Add-Member -NotePropertyName FullName -NotePropertyValue 'sidecar0' -Force
            { Resolve-MergeActions -MkvDescriptors @() -Sidecars @($side) } | Should -Not -Throw
            $act = Resolve-MergeActions -MkvDescriptors @() -Sidecars @($side)
            $act.Adds.Count | Should -Be 1
            $act.Keeps.Count | Should -Be 0
            $act.Replaces.Count | Should -Be 0
        }
    }
}

Describe 'Build-MergeFFmpegArgs unmapped keep' {
    It 'émet -map 0:2 pour un flux data keep intercalé' {
        $probe = @{
            streams = @(
                @{ index = 2; codec_type = 'data'; codec_name = 'bin_data'; tags = @{}; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $desc = @(Get-MediaStreamDescriptors -Probe $Probe)
            $desc = @(Add-UnmappedKeepDescriptors -Descriptors $desc -Probe $Probe)
            $side = ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.eng.srt'
            $side | Add-Member -NotePropertyName FullName -NotePropertyValue 'sidecar0' -Force
            $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars @($side)
            $ffmpegArgs = Build-MergeFFmpegArgs -MkvPath 'film.mkv' -Actions $act -OutputPath 'out.mkv'
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
        $probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $desc = @(Get-MediaStreamDescriptors -Probe $Probe)
            $side = ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.eng.srt'
            $side | Add-Member -NotePropertyName FullName -NotePropertyValue 'sidecar0' -Force
            $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars @($side)
            $out = 'out.mkv.tmp'
            $ffmpegArgs = @(Build-MergeFFmpegArgs -MkvPath 'film.mkv' -Actions $act -OutputPath $out)
            $oi = [array]::IndexOf($ffmpegArgs, $out)
            $oi | Should -BeGreaterThan 1
            $ffmpegArgs[$oi - 2] | Should -Be '-f'
            $ffmpegArgs[$oi - 1] | Should -Be 'matroska'
        }
    }
}

Describe 'Build-MergeFFmpegArgs attachments keep' {
    It 'mappe la pièce jointe MKV et ignore un sidecar sans match' {
        InModuleScope 'Tetram.Media.Streams' {
            $keep = New-StreamDescriptorObject -Class 'Attachment' -Extension '.ttf' -StreamIndex 4 -AttachmentNameSanitized 'KeepFont'
            $act = Resolve-MergeActions -MkvDescriptors @($keep) -Sidecars @()
            $act.Replaces.Count | Should -Be 0
            $ffmpegArgs = @(Build-MergeFFmpegArgs -MkvPath 'film.mkv' -Actions $act -OutputPath 'film.mkv.tmp')
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
