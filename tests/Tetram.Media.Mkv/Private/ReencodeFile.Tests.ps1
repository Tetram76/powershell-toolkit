# Étendre la suite autour de Invoke-ReencodeFile (orchestrateur privé : extension finale, skip, NoTranscode).
#
# RepoRoot (trois `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Mkv') ; InModuleScope 'Tetram.Media.Remux' { … }
# InModuleScope/Mocks ciblent Remux : Invoke-ReencodeFile et Private/*.ps1 y sont définis ; depuis le parent Mkv, Pester n'intercepte pas Get-FFprobeJson.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootReencodeFile = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootReencodeFile 'Tetram.Media.Mkv') -Force -ErrorAction Stop

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

        InModuleScope 'Tetram.Media.Remux' -Parameters @{
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

        InModuleScope 'Tetram.Media.Remux' -Parameters @{
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
    Remove-Module -Name 'Tetram.Media.Mkv' -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-ReencodeFile — extension finale' {

    BeforeEach {
        $script:InfoLogs = [System.Collections.Generic.List[string]]::new()
        $script:FfmpegOutputFiles = [System.Collections.Generic.List[string]]::new()

        Mock -ModuleName Tetram.Media.Remux Write-InfoLog {
            param([string] $Text)
            [void]$script:InfoLogs.Add($Text)
        }
        Mock -ModuleName Tetram.Media.Remux Invoke-FFmpeg {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Write-InfoLog {
            param([string] $Text)
            [void]$script:InfoLogs.Add($Text)
        }
        Mock -ModuleName Tetram.Media.Remux Invoke-FFmpeg {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @(
                    (New-HevcStream)
                    (New-AacStream)
                    @{ codec_type = 'attachment'; codec_name = 'mjpeg'; tags = @{ filename = 'cover.jpg' } }
                )
            }
        }
        Mock -ModuleName Tetram.Media.Remux Invoke-FFmpeg {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
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

        Mock -ModuleName Tetram.Media.Remux Write-InfoLog {
            param([string] $Text)
            [void]$script:InfoLogs.Add($Text)
        }
        Mock -ModuleName Tetram.Media.Remux Write-InfoWarning {
            param([string] $Text)
            [void]$script:WarningLogs.Add($Text)
        }
        Mock -ModuleName Tetram.Media.Remux Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Remux Write-ErrorLogWithFile {
            param([string] $Text)
            [void]$script:ErrorLogs.Add($Text)
        }
        Mock -ModuleName Tetram.Media.Remux Write-Log {}
        Mock -ModuleName Tetram.Media.Remux Invoke-FFmpeg {
            param($OutputFile)
            if ($OutputFile)
            {
                Set-Content -LiteralPath $OutputFile -Value 'encoded-temp'
            }
            return $true
        }
        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @((New-HevcStream), (New-AacStream))
            }
        }
    }

    It 'rejette un mismatch et conserve l''original lorsque AllowIntegrityMismatch est faux' {
        $file = Join-Path $TestDrive 'mismatch-strict.mp4'
        Set-Content -LiteralPath $file -Value 'source-original'

        Mock -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity {
            [pscustomobject]@{
                Status               = 'mismatch'
                Method               = 'timestamp-span'
                Reason               = 'span-mismatch'
                StreamType           = 'audio'
                SourceRelativeIndex  = 2
                OutputRelativeIndex  = 1
                Expected             = 100.0
                Actual               = 90.0
                Diff                 = 10.0
                Tolerance            = 0.128
            }
        }

        $state = Invoke-ReencodeFileForIntegrity -Filename $file -Config (New-ReencodeFileTestConfig) -TempPath $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity -Times 1
        $state.IntegrityFailureFiles | Should -Contain $file
        $state.IntegrityWarningFiles | Should -Not -Contain $file
        $state.IntegrityWarningMessages | Should -HaveCount 0
        $state.SessionResult.Count | Should -Be 0
        $script:ErrorLogs | Should -Not -BeNullOrEmpty
        $script:WarningLogs | Should -BeNullOrEmpty
        Get-Content -LiteralPath $file -Raw | Should -Match 'source-original'
        Get-ChildItem -LiteralPath $TestDrive -Filter '*.mkv' | Should -HaveCount 0
        $script:ErrorLogs[0] | Should -Match 'timestamp-span'
        $script:ErrorLogs[0] | Should -Match 'span source 100.000s'
        $script:ErrorLogs[0] | Should -Match 'output 90.000s'
        $script:ErrorLogs[0] | Should -Not -Match 'expected s,'
    }

    It 'identifie le flux fautif dans le message de mismatch' {
        $file = Join-Path $TestDrive 'mismatch-stream.mp4'
        Set-Content -LiteralPath $file -Value 'source-original'

        Mock -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity {
            [pscustomobject]@{
                Status               = 'mismatch'
                Method               = 'timestamp-span'
                Reason               = 'span-mismatch'
                Expected             = 100.0
                Actual               = 90.0
                Diff                 = 10.0
                Tolerance            = 0.128
                StreamType           = 'audio'
                SourceRelativeIndex  = 2
                OutputRelativeIndex  = 1
            }
        }

        $state = Invoke-ReencodeFileForIntegrity -Filename $file -Config (New-ReencodeFileTestConfig) -TempPath $TestDrive

        $state.IntegrityFailureFiles | Should -Contain $file
        $script:ErrorLogs[0] | Should -Match '0:a:2'
        $script:ErrorLogs[0] | Should -Match '0:a:1'
        $script:ErrorLogs[0] | Should -Match 'span source 100.000s'
    }

    It 'signale un échec de probe sans message de durée vide' {
        $file = Join-Path $TestDrive 'probe-fail.mp4'
        Set-Content -LiteralPath $file -Value 'source-original'

        Mock -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity {
            [pscustomobject]@{
                Status   = 'mismatch'
                Method   = 'probe'
                Expected = $null
                Actual   = $null
                Diff     = $null
            }
        }

        $state = Invoke-ReencodeFileForIntegrity -Filename $file -Config (New-ReencodeFileTestConfig) -TempPath $TestDrive

        $state.IntegrityFailureFiles | Should -Contain $file
        $state.SessionResult.Count | Should -Be 0
        $script:ErrorLogs | Should -Not -BeNullOrEmpty
        $script:ErrorLogs[0] | Should -Match 'probe'
        $script:ErrorLogs[0] | Should -Match 'could not be probed'
        $script:ErrorLogs[0] | Should -Not -Match 'expected s,'
    }

    It 'accepte un mismatch en warning et installe le temporaire lorsque AllowIntegrityMismatch est vrai' {
        $file = Join-Path $TestDrive 'mismatch-allow.mp4'
        Set-Content -LiteralPath $file -Value 'source-original'

        Mock -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity {
            [pscustomobject]@{
                Status              = 'mismatch'
                Method              = 'timestamp-span'
                Reason              = 'span-mismatch'
                StreamType          = 'audio'
                SourceRelativeIndex = 2
                OutputRelativeIndex = 1
                Expected            = 100.0
                Actual              = 90.0
                Diff                = 10.0
                Tolerance           = 0.128
            }
        }

        $state = Invoke-ReencodeFileForIntegrity `
            -Filename $file `
            -Config (New-ReencodeFileTestConfig -AllowIntegrityMismatch $true) `
            -TempPath $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity -Times 1
        $state.IntegrityFailureFiles | Should -HaveCount 0
        $state.IntegrityWarningFiles | Should -Contain $file
        $state.IntegrityWarningMessages | Should -HaveCount 1
        $state.SessionResult.Count | Should -Be 1
        $script:ErrorLogs | Should -BeNullOrEmpty
        $script:WarningLogs | Should -HaveCount 1
        $state.IntegrityWarningMessages[0] | Should -BeExactly $script:WarningLogs[0]
        $state.IntegrityWarningMessages[0] | Should -BeLike '* — accepted because -AllowIntegrityMismatch is set'
        $script:WarningLogs[0] | Should -Match 'mismatch-allow'
        $script:WarningLogs[0] | Should -Match 'timestamp-span'
        $script:WarningLogs[0] | Should -Match '100'
        $script:WarningLogs[0] | Should -Match '90'
        $script:WarningLogs[0] | Should -Match 'AllowIntegrityMismatch'
        Should -Invoke -ModuleName Tetram.Media.Remux Write-InfoWarning -Times 1 -ParameterFilter {
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

        Mock -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity {
            [pscustomobject]@{
                Status              = 'unknown'
                Method              = 'timestamp-span'
                Reason              = 'no-end-pts'
                StreamType          = 'audio'
                SourceRelativeIndex = 0
                OutputRelativeIndex = 1
                Expected            = $null
                Actual              = $null
                Diff                = $null
            }
        }

        $state = Invoke-ReencodeFileForIntegrity -Filename $file -Config (New-ReencodeFileTestConfig) -TempPath $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity -Times 1
        $state.IntegrityFailureFiles | Should -HaveCount 0
        $state.IntegrityWarningFiles | Should -Contain $file
        $state.SessionResult.Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $TestDrive 'unknown-duration.mkv') -PathType Leaf | Should -BeTrue
        $script:ErrorLogs | Should -HaveCount 1
        $state.IntegrityWarningMessages | Should -HaveCount 1
        $state.IntegrityWarningMessages[0] | Should -BeExactly $script:ErrorLogs[0]
        $script:ErrorLogs[0] | Should -Match 'inconclusive'
        $script:ErrorLogs[0] | Should -Match 'timestamp-span'
        $script:ErrorLogs[0] | Should -Not -Match 'comparable duration'
    }

    It 'n''exécute pas le contrôle d''intégrité en NoTranscode' {
        $file = Join-Path $TestDrive 'notranscode-drop.mkv'
        Set-Content -LiteralPath $file -Value 'source-original'

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @(
                    (New-HevcStream)
                    (New-AacStream)
                    @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'jpn' } }
                )
            }
        }
        Mock -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity {
            throw 'Test-EncodedFileIntegrity ne doit pas être appelé en NoTranscode'
        }

        $state = Invoke-ReencodeFileForIntegrity `
            -Filename $file `
            -Config (New-ReencodeFileTestConfig -NoTranscode $true) `
            -TempPath $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity -Times 0
        $state.IntegrityFailureFiles | Should -HaveCount 0
        $state.IntegrityWarningFiles | Should -HaveCount 0
        $state.IntegrityWarningMessages | Should -HaveCount 0
        $state.SessionResult.Count | Should -Be 1
        Get-Content -LiteralPath $file -Raw | Should -Match 'encoded-temp'
    }

    It 'transmet les mappings A/V dans l''ordre des -map ffmpeg, sans subtitles' {
        $file = Join-Path $TestDrive 'maps-kept.mkv'
        Set-Content -LiteralPath $file -Value 'source-original'

        $audioKept0 = [pscustomobject]@{
            _index               = 0
            __copy               = $true
            __process            = $false
            __recode             = $false
            codec_name           = 'aac'
            channels             = 2
            channel_layout       = 'stereo'
            bit_rate             = '192000'
            __targetAudioCodec   = $null
            __targetAudioBitrate = $null
            __targetAudioFilter  = $null
        }
        $audioDropped1 = [pscustomobject]@{
            _index               = 1
            __copy               = $false
            __process            = $false
            __recode             = $false
            codec_name           = 'aac'
            channels             = 2
            channel_layout       = 'stereo'
            bit_rate             = '192000'
            __targetAudioCodec   = $null
            __targetAudioBitrate = $null
            __targetAudioFilter  = $null
        }
        $audioKept2 = [pscustomobject]@{
            _index               = 2
            __copy               = $true
            __process            = $false
            __recode             = $false
            codec_name           = 'aac'
            channels             = 2
            channel_layout       = 'stereo'
            bit_rate             = '192000'
            __targetAudioCodec   = $null
            __targetAudioBitrate = $null
            __targetAudioFilter  = $null
        }
        $script:AudioTracksForMaps = @($audioKept0, $audioDropped1, $audioKept2)
        $script:CapturedFfmpegArgs = $null

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson {
            @{
                format  = @{ duration = '10.0' }
                streams = @(
                    (New-HevcStream)
                    (New-AacStream)
                    (New-AacStream)
                    (New-AacStream)
                    @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fr' } }
                    @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'jpn' } }
                    @{ codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'en' } }
                )
            }
        }
        Mock -ModuleName Tetram.Media.Remux Select-AudioStreams { $script:AudioTracksForMaps }
        Mock -ModuleName Tetram.Media.Remux Invoke-FFmpeg {
            param($OutputFile, $DynamicArgs)
            $script:CapturedFfmpegArgs = @($DynamicArgs)
            if ($OutputFile)
            {
                Set-Content -LiteralPath $OutputFile -Value 'encoded-temp'
            }
            return $true
        }
        Mock -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity {
            [pscustomobject]@{
                Status = 'ok'
                Method = 'complete'
            }
        }

        $null = Invoke-ReencodeFileForIntegrity -Filename $file -Config (New-ReencodeFileTestConfig) -TempPath $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Remux Test-EncodedFileIntegrity -Times 1 -ParameterFilter {
            $maps = @($StreamMaps)
            $maps.Count -eq 3 -and
            $maps[0].StreamType -eq 'video' -and $maps[0].SourceRelativeIndex -eq 0 -and $maps[0].OutputRelativeIndex -eq 0 -and
            $maps[1].StreamType -eq 'audio' -and $maps[1].SourceRelativeIndex -eq 0 -and $maps[1].OutputRelativeIndex -eq 0 -and
            $maps[2].StreamType -eq 'audio' -and $maps[2].SourceRelativeIndex -eq 2 -and $maps[2].OutputRelativeIndex -eq 1 -and
            @($maps | Where-Object { $_.StreamType -eq 'subtitle' }).Count -eq 0
        }

        $mapArgs = for ($i = 0; $i -lt $script:CapturedFfmpegArgs.Count; $i++) {
            if ($script:CapturedFfmpegArgs[$i] -eq '-map') {
                $script:CapturedFfmpegArgs[$i + 1]
            }
        }
        $avMaps = @($mapArgs | Where-Object { $_ -match '^0:[va]:' })
        $avMaps | Should -Be @('0:v:0', '0:a:0', '0:a:2')
    }
}
