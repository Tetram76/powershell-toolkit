# Étendre la suite autour de Invoke-ReencodeFile (orchestrateur privé : extension finale, skip, NoTranscode).
#
# RepoRoot (trois `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode') ; InModuleScope 'Tetram.Media.Reencode' { … }
# Fichiers factices sous $TestDrive ; mocker Get-FFprobeJson / Invoke-FFmpeg / Write-InfoLog — pas de binaire ffmpeg.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootReencodeFile = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootReencodeFile 'Tetram.Media.Reencode') -Force -ErrorAction Stop

    function script:New-ReencodeFileTestConfig {
        param(
            [bool] $NoTranscode = $false,
            [string] $Quality = 'Medium',
            [string] $VideoCodec = 'HEVC'
        )

        @{
            CheckOnly                = $false
            NoTranscode              = $NoTranscode
            ForceRecodeVideo         = $false
            VideoCodec               = $VideoCodec
            AllowVideoCodecUpgrade   = $false
            Deinterlace              = $false
            Upscale                  = ''
            UpscaleWidth             = 0
            UpscaleHeight            = $null
            UpscaleFit               = ''
            Quality                  = $Quality
            AllowSubTitlesConversion = $false
            SubTitlesToKeep          = @('fr', 'en', 'fre', 'eng')
            ClearStreamsTitle        = $false
            FFMPEGPath               = 'ffmpeg'
            FFPROBEPath              = 'ffprobe'
        }
    }

    function script:New-HevcStream {
        @{
            codec_type  = 'video'
            codec_name  = 'hevc'
            profile     = 'Main'
            width       = 1920
            height      = 1080
            pix_fmt     = 'yuv420p'
            color_space = 'bt709'
            disposition = @{ attached_pic = 0 }
        }
    }

    function script:New-AacStream {
        [pscustomobject]@{
            codec_type     = 'audio'
            codec_name     = 'aac'
            channels       = 2
            channel_layout = 'stereo'
            bit_rate       = '192000'
        }
    }

    function script:Invoke-ReencodeFileUnderTest {
        param(
            [Parameter(Mandatory)] [string] $Filename,
            [Parameter(Mandatory)] [hashtable] $Config,
            [Parameter(Mandatory)] [string] $TempPath
        )

        InModuleScope 'Tetram.Media.Reencode' -Parameters @{
            Filename = $Filename
            Config   = $Config
            TempPath = $TempPath
        } {
            param($Filename, $Config, $TempPath)

            $state = Initialize-ReencodeState -TempPath $TempPath

            function Invoke-BoundFile {
                [CmdletBinding(SupportsShouldProcess)]
                param()
                Invoke-ReencodeFile -Filename $Filename -State $state -Config $Config -Cmdlet $PSCmdlet
            }

            Invoke-BoundFile -WhatIf
        }
    }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Reencode' -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-ReencodeFile — extension finale' {

    BeforeEach {
        $script:InfoLogs = [System.Collections.Generic.List[string]]::new()
        $script:FfmpegOutputFiles = [System.Collections.Generic.List[string]]::new()

        Mock -ModuleName Tetram.Media.Reencode Write-InfoLog {
            param([string] $Text)
            [void]$script:InfoLogs.Add($Text)
        }
        Mock -ModuleName Tetram.Media.Reencode Invoke-FFmpeg {
            param($OutputFile)
            if ($OutputFile)
            {
                [void]$script:FfmpegOutputFiles.Add($OutputFile)
            }
            return $true
        }
    }

    It 'écrit un temporaire .mkv pour une source MP4 en réencodage normal' {
        $file = Join-Path $TestDrive 'movie.mp4'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @((New-HevcStream), (New-AacStream))
            }
        }

        Invoke-ReencodeFileUnderTest -Filename $file -Config (New-ReencodeFileTestConfig) -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 1
        [System.IO.Path]::GetExtension($script:FfmpegOutputFiles[0]) | Should -BeExactly '.mkv'
    }

    It 'écrit un temporaire .mkv pour une source AVI en réencodage normal' {
        $file = Join-Path $TestDrive 'clip.avi'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @((New-HevcStream), (New-AacStream))
            }
        }

        Invoke-ReencodeFileUnderTest -Filename $file -Config (New-ReencodeFileTestConfig) -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 1
        [System.IO.Path]::GetExtension($script:FfmpegOutputFiles[0]) | Should -BeExactly '.mkv'
    }

    It 'conserve l''extension source en NoTranscode lorsqu''une piste est retirée' {
        $file = Join-Path $TestDrive 'show.mp4'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @(
                    (New-HevcStream)
                    (New-AacStream)
                    @{ codec_type = 'subtitle'; codec_name = 'mov_text'; tags = @{ language = 'jpn' } }
                )
            }
        }

        Invoke-ReencodeFileUnderTest -Filename $file -Config (New-ReencodeFileTestConfig -NoTranscode $true) -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 1
        [System.IO.Path]::GetExtension($script:FfmpegOutputFiles[0]) | Should -BeExactly '.mp4'
    }
}

Describe 'Invoke-ReencodeFile — rien à faire' {

    BeforeEach {
        $script:InfoLogs = [System.Collections.Generic.List[string]]::new()
        $script:FfmpegOutputFiles = [System.Collections.Generic.List[string]]::new()

        Mock -ModuleName Tetram.Media.Reencode Write-InfoLog {
            param([string] $Text)
            [void]$script:InfoLogs.Add($Text)
        }
        Mock -ModuleName Tetram.Media.Reencode Invoke-FFmpeg {
            param($OutputFile)
            if ($OutputFile)
            {
                [void]$script:FfmpegOutputFiles.Add($OutputFile)
            }
            return $true
        }
    }

    It 'ignore un MKV déjà conforme en réencodage normal' {
        $file = Join-Path $TestDrive 'ready.mkv'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @((New-HevcStream), (New-AacStream))
            }
        }

        Invoke-ReencodeFileUnderTest -Filename $file -Config (New-ReencodeFileTestConfig) -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 0
        $script:InfoLogs | Should -Contain "No reencoding needed for '$file'"
    }

    It 'n''écrit pas en NoTranscode si copie intégrale sans filtrage ni correction' {
        $file = Join-Path $TestDrive 'ready.mkv'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @((New-HevcStream), (New-AacStream))
            }
        }

        Invoke-ReencodeFileUnderTest -Filename $file -Config (New-ReencodeFileTestConfig -NoTranscode $true) -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 0
        $script:InfoLogs | Should -Contain "No stream filtering needed for '$file'"
    }

    It 'lance ffmpeg en NoTranscode quand une piste est retirée' {
        $file = Join-Path $TestDrive 'extra-sub.mkv'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @(
                    (New-HevcStream)
                    (New-AacStream)
                    @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'jpn' } }
                )
            }
        }

        Invoke-ReencodeFileUnderTest -Filename $file -Config (New-ReencodeFileTestConfig -NoTranscode $true) -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 1
        [System.IO.Path]::GetExtension($script:FfmpegOutputFiles[0]) | Should -BeExactly '.mkv'
    }

    It 'lance ffmpeg en NoTranscode quand un attachment exige une correction de mimetype' {
        $file = Join-Path $TestDrive 'ass-font.mkv'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @(
                    (New-HevcStream)
                    (New-AacStream)
                    @{ codec_type = 'subtitle'; codec_name = 'ass'; tags = @{ language = 'fre' } }
                    @{ codec_type = 'attachment'; codec_name = $null; tags = @{ mimetype = 'application/x-truetype-font'; filename = 'Arial' } }
                )
            }
        }

        Invoke-ReencodeFileUnderTest -Filename $file -Config (New-ReencodeFileTestConfig -NoTranscode $true) -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 1
    }

    It 'accepte un fichier sans durée en NoTranscode au lieu de le skipper comme non convertible' {
        $file = Join-Path $TestDrive 'noduration.mkv'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ }
                streams = @(
                    (New-HevcStream)
                    (New-AacStream)
                    @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'jpn' } }
                )
            }
        }

        Invoke-ReencodeFileUnderTest -Filename $file -Config (New-ReencodeFileTestConfig -NoTranscode $true) -TempPath $TestDrive

        $script:InfoLogs | Should -Not -Contain "Skip '$file' that does not look like a convertable format"
        $script:FfmpegOutputFiles.Count | Should -Be 1
    }
}
