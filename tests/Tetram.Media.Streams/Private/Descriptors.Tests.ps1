# Étendre la suite autour de Descriptors.ps1 (probe → descripteurs + collision source).
#
# RepoRoot : (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module Tetram.Media.Streams.psd1 ; InModuleScope

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams') -Force -ErrorAction Stop
}
AfterAll { Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue }

Describe 'Get-MediaStreamDescriptors collision' {
    It 'numérote deux subrip eng 1 puis 2 dans l''ordre ffprobe' {
        $probe = @{
            streams = @(
                @{ index = 0; codec_type = 'video'; codec_name = 'h264'; tags = @{}; disposition = @{ default = 1; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 5; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            $subs = @($all | Where-Object { $_.Class -eq 'Subtitle' })
            $subs.Count | Should -Be 2
            $subs[0].CollisionIndex | Should -Be 1
            $subs[1].CollisionIndex | Should -Be 2
            $subs[0].StreamIndex | Should -Be 3
            $subs[1].StreamIndex | Should -Be 5
            (ConvertTo-StreamFileName -Basename 'film' -Descriptor $subs[0]) | Should -Be 'film.eng.srt'
            (ConvertTo-StreamFileName -Basename 'film' -Descriptor $subs[1]) | Should -Be 'film.eng.2.srt'
        }
    }
    It 'filtre StreamType Subtitle et Language eng' {
        $probe = @{
            streams = @(
                @{ index = 1; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fra' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 2; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 3; codec_type = 'audio'; codec_name = 'aac'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            $sel = @(Select-MediaStreamDescriptors -Descriptors $all -StreamType @('Subtitle') -Language @('eng'))
            $sel.Count | Should -Be 1
            $sel[0].Language | Should -Be 'eng'
            $sel[0].Class | Should -Be 'Subtitle'
        }
    }

    It 'ignore Cover et retient A/V/S si aucun filtre n''est fourni' {
        $probe = @{
            streams = @(
                @{ index = 0; codec_type = 'video'; codec_name = 'h264'; tags = @{}; disposition = @{ attached_pic = 0 } }
                @{ index = 1; codec_type = 'video'; codec_name = 'mjpeg'; tags = @{}; disposition = @{ attached_pic = 1 } }
                @{ index = 2; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fra' }; disposition = @{} }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            $sel = @(Select-MediaStreamDescriptors -Descriptors $all)
            $sel.Count | Should -Be 2
            ($sel | ForEach-Object { $_.Class }) | Should -Be @('Video', 'Subtitle')
        }
    }

    It 'conserve CollisionIndex 2 si on ne sélectionne que la 2e piste eng' {
        $probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 5; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            $second = $all | Where-Object { $_.StreamIndex -eq 5 }
            $second.CollisionIndex | Should -Be 2
            (ConvertTo-StreamFileName -Basename 'film' -Descriptor $second) | Should -Be 'film.eng.2.srt'
        }
    }
    It 'ajoute un descripteur Chapter si chapters est non vide' {
        $probe = @{
            streams = @()
            chapters = @(@{ id = 1; start_time = '0' })
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            @($all | Where-Object { $_.Class -eq 'Chapter' }).Count | Should -Be 1
        }
    }
    It 'omet mpeg4 des mappés et le liste en unmapped' {
        $probe = @{
            streams = @(
                @{ index = 0; codec_type = 'video'; codec_name = 'mpeg4'; tags = @{}; disposition = @{} }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            @(Get-MediaStreamDescriptors -Probe $Probe).Count | Should -Be 0
            $u = @(Get-UnmappedStreamDescriptors -Probe $Probe)
            $u.Count | Should -Be 1
            $u[0].codec_name | Should -Be 'mpeg4'
        }
    }
    It 'ne throw pas si streams est absent ou codec_name vide' {
        InModuleScope 'Tetram.Media.Streams' {
            { Get-MediaStreamDescriptors -Probe @{ format = @{} } } | Should -Not -Throw
            @(Get-MediaStreamDescriptors -Probe @{ format = @{} }).Count | Should -Be 0
            @(Get-UnmappedStreamDescriptors -Probe @{ format = @{} }).Count | Should -Be 0
            $probe = @{
                streams = @(
                    @{ index = 0; codec_type = 'video'; codec_name = ''; tags = @{}; disposition = @{} }
                )
            }
            { Get-UnmappedStreamDescriptors -Probe $probe } | Should -Not -Throw
            @(Get-UnmappedStreamDescriptors -Probe $probe).Count | Should -Be 1
        }
    }
    It 'ne liste pas un attached_pic comme codec A/V/S non mappé' {
        $probe = @{
            streams = @(
                @{ index = 1; codec_type = 'video'; codec_name = 'webp'; tags = @{}; disposition = @{ attached_pic = 1 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            @(Get-UnmappedStreamDescriptors -Probe $Probe).Count | Should -Be 0
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            $all.Count | Should -Be 1
            $all[0].Class | Should -Be 'Cover'
        }
    }

    It 'normalise langue absente, und et unk en und pour Video/Audio/Subtitle' {
        $probe = @{
            streams = @(
                @{ index = 0; codec_type = 'video'; codec_name = 'h264'; tags = @{}; disposition = @{ attached_pic = 0 } }
                @{ index = 1; codec_type = 'audio'; codec_name = 'aac'; tags = @{ language = 'UND' }; disposition = @{} }
                @{ index = 2; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'unk' }; disposition = @{} }
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fra' }; disposition = @{} }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            ($all | Where-Object { $_.StreamIndex -eq 0 }).Language | Should -Be 'und'
            (ConvertTo-StreamFileName -Basename 'film' -Descriptor ($all | Where-Object { $_.StreamIndex -eq 0 })) | Should -Be 'film.und.h264'
            ($all | Where-Object { $_.StreamIndex -eq 1 }).Language | Should -Be 'und'
            ($all | Where-Object { $_.StreamIndex -eq 2 }).Language | Should -Be 'und'
            ($all | Where-Object { $_.StreamIndex -eq 3 }).Language | Should -Be 'fra'
        }
    }

    It 'lit LANGUAGE (casse OrderedHashtable ffprobe) comme language — jpn n''est pas und' {
        $probe = ConvertFrom-Json -AsHashtable -InputObject '{"streams":[{"index":2,"codec_type":"subtitle","codec_name":"subrip","tags":{"LANGUAGE":"jpn"},"disposition":{}}]}'
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            $all[0].Language | Should -Be 'jpn'
            (ConvertTo-StreamFileName -Basename 'film' -Descriptor $all[0]) | Should -Be 'film.jpn.srt'
        }
    }

    It 'ne liste pas un flux data comme codec A/V/S non mappé' {
        $probe = @{
            streams = @(
                @{ index = 1; codec_type = 'data'; codec_name = 'bin_data'; tags = @{}; disposition = @{} }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            @(Get-UnmappedStreamDescriptors -Probe $Probe).Count | Should -Be 0
        }
    }
    It 'ajoute un keep hors A/V/S pour un flux data' {
        $probe = @{
            streams = @(
                @{ index = 1; codec_type = 'data'; codec_name = 'bin_data'; tags = @{}; disposition = @{} }
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{} }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $desc = @(Get-MediaStreamDescriptors -Probe $Probe)
            $desc = @(Add-UnmappedKeepDescriptors -Descriptors $desc -Probe $Probe)
            $data = @($desc | Where-Object { $_.StreamIndex -eq 1 })
            $data.Count | Should -Be 1
            $data[0].Class | Should -Not -BeIn @('Video', 'Audio', 'Subtitle')
        }
    }
    It 'ajoute un keep pour un codec A/V/S inconnu (le mux copie la piste MKV)' {
        $probe = @{
            streams = @(
                @{ index = 0; codec_type = 'video'; codec_name = 'mpeg4'; tags = @{}; disposition = @{} }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $desc = @(Get-MediaStreamDescriptors -Probe $Probe)
            $desc = @(Add-UnmappedKeepDescriptors -Descriptors $desc -Probe $Probe)
            $keep = @($desc | Where-Object { $_.StreamIndex -eq 0 })
            $keep.Count | Should -Be 1
            $keep[0].Class | Should -Be 'Video'
        }
    }
    It 'force .bin si l''extension d''attachement n''est pas dans l''allowlist' {
        $probe = @{
            streams = @(
                @{ index = 1; codec_type = 'attachment'; codec_name = 'ttf'; tags = @{ filename = 'Arial.ttf'; mimetype = 'font/ttf' }; disposition = @{} }
                @{ index = 2; codec_type = 'attachment'; codec_name = 'mjpeg'; tags = @{ filename = 'poster.jpg'; mimetype = 'image/jpeg' }; disposition = @{} }
                @{ index = 3; codec_type = 'attachment'; codec_name = 'mjpeg'; tags = @{ filename = 'cover.jpg'; mimetype = 'image/jpeg' }; disposition = @{} }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            $all.Count | Should -Be 3
            $all[0].Extension | Should -Be '.ttf'
            $all[0].AttachmentName | Should -Be 'Arial.ttf'
            $all[1].Extension | Should -Be '.bin'
            $all[1].AttachmentName | Should -Be 'poster.jpg'
            (ConvertTo-StreamFileName -Basename 'film' -Descriptor $all[1]) | Should -Be 'film.poster.bin'
            (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.poster.bin').Class | Should -Be 'Attachment'
            $all[2].Extension | Should -Be '.bin'
            (ConvertTo-StreamFileName -Basename 'film' -Descriptor $all[2]) | Should -Be 'film.cover.bin'
            (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.cover.bin').Class | Should -Be 'Attachment'
        }
    }
}
