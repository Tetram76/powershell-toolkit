# Étendre la suite autour de CodecMap.ps1 (codec ffprobe → extension/classe).
#
# RepoRoot : (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Streams.psd1') -Force
# InModuleScope 'Tetram.Media.Streams' { Get-ElementaryExtension ... }

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams.psd1') -Force -ErrorAction Stop
}
AfterAll {
    Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-ElementaryExtension' {
    It 'mappe <Codec> vers <Ext> / <Class>' -TestCases @(
        @{ Codec = 'h264'; Type = 'video'; Pic = $false; Ext = '.h264'; Class = 'Video' }
        @{ Codec = 'avc'; Type = 'video'; Pic = $false; Ext = '.h264'; Class = 'Video' }
        @{ Codec = 'hevc'; Type = 'video'; Pic = $false; Ext = '.hevc'; Class = 'Video' }
        @{ Codec = 'h265'; Type = 'video'; Pic = $false; Ext = '.hevc'; Class = 'Video' }
        @{ Codec = 'av1'; Type = 'video'; Pic = $false; Ext = '.ivf'; Class = 'Video' }
        @{ Codec = 'vp9'; Type = 'video'; Pic = $false; Ext = '.ivf'; Class = 'Video' }
        @{ Codec = 'mpeg2video'; Type = 'video'; Pic = $false; Ext = '.m2v'; Class = 'Video' }
        @{ Codec = 'vc1'; Type = 'video'; Pic = $false; Ext = '.vc1'; Class = 'Video' }
        @{ Codec = 'aac'; Type = 'audio'; Pic = $false; Ext = '.aac'; Class = 'Audio' }
        @{ Codec = 'subrip'; Type = 'subtitle'; Pic = $false; Ext = '.srt'; Class = 'Subtitle' }
        @{ Codec = 'mjpeg'; Type = 'video'; Pic = $true; Ext = '.jpg'; Class = 'Cover' }
        @{ Codec = 'png'; Type = 'video'; Pic = $true; Ext = '.png'; Class = 'Cover' }
    ) {
        InModuleScope 'Tetram.Media.Streams' -Parameters $_ {
            param($Codec, $Type, $Pic, $Ext, $Class)
            $r = Get-ElementaryExtension -CodecName $Codec -CodecType $Type -AttachedPic $Pic
            $r.Extension | Should -Be $Ext
            $r.Class | Should -Be $Class
        }
    }
    It 'classe tout attached_pic en Cover, hors table A/V' {
        InModuleScope 'Tetram.Media.Streams' {
            $h264 = Get-ElementaryExtension -CodecName 'h264' -CodecType 'video' -AttachedPic $true
            $h264.Class | Should -Be 'Cover'
            $webp = Get-ElementaryExtension -CodecName 'webp' -CodecType 'video' -AttachedPic $true
            $webp.Class | Should -Be 'Cover'
            $mjpeg = Get-ElementaryExtension -CodecName 'mjpeg' -CodecType 'video' -AttachedPic $true
            $mjpeg.Class | Should -Be 'Cover'
            $mjpeg.Extension | Should -Be '.jpg'
        }
    }

    It 'retourne null pour mpeg4, mov_text, alac et pcm' {
        InModuleScope 'Tetram.Media.Streams' {
            Get-ElementaryExtension -CodecName 'mpeg4' -CodecType 'video' -AttachedPic $false | Should -BeNullOrEmpty
            Get-ElementaryExtension -CodecName 'mov_text' -CodecType 'subtitle' -AttachedPic $false | Should -BeNullOrEmpty
            Get-ElementaryExtension -CodecName 'alac' -CodecType 'audio' -AttachedPic $false | Should -BeNullOrEmpty
            Get-ElementaryExtension -CodecName 'pcm_s16le' -CodecType 'audio' -AttachedPic $false | Should -BeNullOrEmpty
            Get-ElementaryExtension -CodecName 'pcm_s16be' -CodecType 'audio' -AttachedPic $false | Should -BeNullOrEmpty
            Get-ElementaryExtension -CodecName '' -CodecType 'video' -AttachedPic $false | Should -BeNullOrEmpty
        }
    }
}
