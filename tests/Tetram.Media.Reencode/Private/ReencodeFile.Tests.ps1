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
            [bool] $AllowIntegrityMismatch = $false,
            [bool] $RemoveAttachments = $false,
            [string] $Quality = 'Medium',
            [string] $VideoCodec = 'HEVC'
        )

        @{
            CheckOnly                = $false
            NoTranscode              = $NoTranscode
            AllowIntegrityMismatch   = $AllowIntegrityMismatch
            RemoveAttachments        = $RemoveAttachments
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

    function script:Invoke-ReencodeFileForIntegrity {
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
            $state.ErrorLog = Join-Path $TempPath 'reencode-errors.log'

            function Invoke-BoundFile {
                [CmdletBinding(SupportsShouldProcess)]
                param()
                Invoke-ReencodeFile -Filename $Filename -State $state -Config $Config -Cmdlet $PSCmdlet
            }

            Invoke-BoundFile
            $state
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

    It 'lance ffmpeg en NoTranscode lorsque RemoveAttachments retire le seul attachment' {
        $file = Join-Path $TestDrive 'drop-attach.mkv'
        Set-Content -LiteralPath $file -Value 'x'
        $script:CapturedDynamicArgs = @()

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @(
                    (New-HevcStream)
                    (New-AacStream)
                    @{ codec_type = 'attachment'; codec_name = 'mjpeg'; tags = @{ filename = 'cover.jpg' } }
                )
            }
        }
        Mock -ModuleName Tetram.Media.Reencode Invoke-FFmpeg {
            param($OutputFile, $DynamicArgs)
            if ($OutputFile)
            {
                [void]$script:FfmpegOutputFiles.Add($OutputFile)
            }
            $script:CapturedDynamicArgs = @($DynamicArgs)
            return $true
        }

        Invoke-ReencodeFileUnderTest `
            -Filename $file `
            -Config (New-ReencodeFileTestConfig -NoTranscode $true -RemoveAttachments $true) `
            -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 1
        [System.IO.Path]::GetExtension($script:FfmpegOutputFiles[0]) | Should -BeExactly '.mkv'
        ($script:CapturedDynamicArgs -join ' ') | Should -Not -Match '0:t:'
    }

    It 'lance ffmpeg en réencodage normal lorsque RemoveAttachments retire le seul attachment' {
        $file = Join-Path $TestDrive 'drop-attach-reencode.mkv'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @(
                    (New-HevcStream)
                    (New-AacStream)
                    @{ codec_type = 'attachment'; codec_name = 'mjpeg'; tags = @{ filename = 'cover.jpg' } }
                )
            }
        }

        Invoke-ReencodeFileUnderTest `
            -Filename $file `
            -Config (New-ReencodeFileTestConfig -RemoveAttachments $true) `
            -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 1
        [System.IO.Path]::GetExtension($script:FfmpegOutputFiles[0]) | Should -BeExactly '.mkv'
    }

    It 'ne déclenche pas de réécriture si RemoveAttachments est actif sans attachment' {
        $file = Join-Path $TestDrive 'no-attach.mkv'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @((New-HevcStream), (New-AacStream))
            }
        }

        Invoke-ReencodeFileUnderTest `
            -Filename $file `
            -Config (New-ReencodeFileTestConfig -RemoveAttachments $true) `
            -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 0
        $script:InfoLogs | Should -Contain "No reencoding needed for '$file'"

        $script:InfoLogs.Clear()
        $fileNoTranscode = Join-Path $TestDrive 'no-attach-nt.mkv'
        Set-Content -LiteralPath $fileNoTranscode -Value 'x'

        Invoke-ReencodeFileUnderTest `
            -Filename $fileNoTranscode `
            -Config (New-ReencodeFileTestConfig -NoTranscode $true -RemoveAttachments $true) `
            -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 0
        $script:InfoLogs | Should -Contain "No stream filtering needed for '$fileNoTranscode'"
    }

    It 'conserve un attachment non-police sans le switch, sans réécriture' {
        $file = Join-Path $TestDrive 'keep-attach.mkv'
        Set-Content -LiteralPath $file -Value 'x'

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @(
                    (New-HevcStream)
                    (New-AacStream)
                    @{ codec_type = 'attachment'; codec_name = 'mjpeg'; tags = @{ filename = 'cover.jpg' } }
                )
            }
        }

        Invoke-ReencodeFileUnderTest `
            -Filename $file `
            -Config (New-ReencodeFileTestConfig -RemoveAttachments $false) `
            -TempPath $TestDrive

        $script:FfmpegOutputFiles.Count | Should -Be 0
        $script:InfoLogs | Should -Contain "No reencoding needed for '$file'"
    }
}

Describe 'Invoke-ReencodeFile — intégrité hors WhatIf' {

    BeforeEach {
        $script:InfoLogs = [System.Collections.Generic.List[string]]::new()
        $script:WarningLogs = [System.Collections.Generic.List[string]]::new()
        $script:ErrorLogs = [System.Collections.Generic.List[string]]::new()

        Mock -ModuleName Tetram.Media.Reencode Write-InfoLog {
            param([string] $Text)
            [void]$script:InfoLogs.Add($Text)
        }
        Mock -ModuleName Tetram.Media.Reencode Write-InfoWarning {
            param([string] $Text)
            [void]$script:WarningLogs.Add($Text)
        }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLogWithFile {
            param([string] $Text)
            [void]$script:ErrorLogs.Add($Text)
        }
        Mock -ModuleName Tetram.Media.Reencode Write-Log {}
        Mock -ModuleName Tetram.Media.Reencode Invoke-FFmpeg {
            param($OutputFile)
            if ($OutputFile)
            {
                Set-Content -LiteralPath $OutputFile -Value 'encoded-temp'
            }
            return $true
        }
        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @((New-HevcStream), (New-AacStream))
            }
        }
    }

    It 'rejette un mismatch et conserve l''original lorsque AllowIntegrityMismatch est faux' {
        $file = Join-Path $TestDrive 'mismatch-strict.mp4'
        Set-Content -LiteralPath $file -Value 'source-original'

        Mock -ModuleName Tetram.Media.Reencode Test-EncodedFileIntegrity {
            [pscustomobject]@{
                Status   = 'mismatch'
                Method   = 'format'
                Expected = 100.0
                Actual   = 90.0
                Diff     = 10.0
            }
        }

        $state = Invoke-ReencodeFileForIntegrity -Filename $file -Config (New-ReencodeFileTestConfig) -TempPath $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Reencode Test-EncodedFileIntegrity -Times 1
        $state.IntegrityFailureFiles | Should -Contain $file
        $state.IntegrityWarningFiles | Should -Not -Contain $file
        $state.SessionResult.Count | Should -Be 0
        $script:ErrorLogs | Should -Not -BeNullOrEmpty
        $script:WarningLogs | Should -BeNullOrEmpty
        Get-Content -LiteralPath $file -Raw | Should -Match 'source-original'
        Get-ChildItem -LiteralPath $TestDrive -Filter '*.mkv' | Should -HaveCount 0
    }

    It 'accepte un mismatch en warning et installe le temporaire lorsque AllowIntegrityMismatch est vrai' {
        $file = Join-Path $TestDrive 'mismatch-allow.mp4'
        Set-Content -LiteralPath $file -Value 'source-original'

        Mock -ModuleName Tetram.Media.Reencode Test-EncodedFileIntegrity {
            [pscustomobject]@{
                Status   = 'mismatch'
                Method   = 'format'
                Expected = 100.0
                Actual   = 90.0
                Diff     = 10.0
            }
        }

        $state = Invoke-ReencodeFileForIntegrity `
            -Filename $file `
            -Config (New-ReencodeFileTestConfig -AllowIntegrityMismatch $true) `
            -TempPath $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Reencode Test-EncodedFileIntegrity -Times 1
        $state.IntegrityFailureFiles | Should -HaveCount 0
        $state.IntegrityWarningFiles | Should -Contain $file
        $state.SessionResult.Count | Should -Be 1
        $script:ErrorLogs | Should -BeNullOrEmpty
        $script:WarningLogs | Should -Not -BeNullOrEmpty
        $script:WarningLogs[0] | Should -Match 'mismatch-allow'
        $script:WarningLogs[0] | Should -Match 'format'
        $script:WarningLogs[0] | Should -Match '100'
        $script:WarningLogs[0] | Should -Match '90'
        $script:WarningLogs[0] | Should -Match 'AllowIntegrityMismatch'
        Should -Invoke -ModuleName Tetram.Media.Reencode Write-InfoWarning -Times 1 -ParameterFilter {
            $Force -and $Text -match 'AllowIntegrityMismatch'
        }
        Test-Path -LiteralPath $file | Should -BeFalse
        $installed = Join-Path $TestDrive 'mismatch-allow.mkv'
        Test-Path -LiteralPath $installed -PathType Leaf | Should -BeTrue
        Get-Content -LiteralPath $installed -Raw | Should -Match 'encoded-temp'
    }

    It 'accepte un unknown en réencodage sans exiger AllowIntegrityMismatch' {
        $file = Join-Path $TestDrive 'unknown-duration.mp4'
        Set-Content -LiteralPath $file -Value 'source-original'

        Mock -ModuleName Tetram.Media.Reencode Test-EncodedFileIntegrity {
            [pscustomobject]@{
                Status   = 'unknown'
                Method   = 'unknown'
                Expected = $null
                Actual   = $null
                Diff     = $null
            }
        }

        $state = Invoke-ReencodeFileForIntegrity -Filename $file -Config (New-ReencodeFileTestConfig) -TempPath $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Reencode Test-EncodedFileIntegrity -Times 1
        $state.IntegrityFailureFiles | Should -HaveCount 0
        $state.IntegrityWarningFiles | Should -Contain $file
        $state.SessionResult.Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $TestDrive 'unknown-duration.mkv') -PathType Leaf | Should -BeTrue
    }

    It 'n''exécute pas le contrôle de durée en NoTranscode' {
        $file = Join-Path $TestDrive 'notranscode-drop.mkv'
        Set-Content -LiteralPath $file -Value 'source-original'

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
        Mock -ModuleName Tetram.Media.Reencode Test-EncodedFileIntegrity {
            throw 'Test-EncodedFileIntegrity ne doit pas être appelé en NoTranscode'
        }

        $state = Invoke-ReencodeFileForIntegrity `
            -Filename $file `
            -Config (New-ReencodeFileTestConfig -NoTranscode $true) `
            -TempPath $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Reencode Test-EncodedFileIntegrity -Times 0
        $state.IntegrityFailureFiles | Should -HaveCount 0
        $state.IntegrityWarningFiles | Should -HaveCount 0
        $state.SessionResult.Count | Should -Be 1
        Get-Content -LiteralPath $file -Raw | Should -Match 'encoded-temp'
    }
}
