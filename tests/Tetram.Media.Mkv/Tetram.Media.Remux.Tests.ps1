# Étendre la suite autour du module SUD Tetram.Media.Mkv (Exports / comportement public après chargement réel du .psm1).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Manifeste : Tetram.Media.Mkv.Tests.ps1
# Repair.psm1 : Tetram.Media.Repair.Tests.ps1
# Mocks : -ModuleName Tetram.Media.Remux — Invoke-MkvRemux s'exécute dans ce nested ; un mock sur le parent Mkv n'intercepte pas Get-FFmpegPath / Invoke-PathList.

Describe 'Invoke-MkvRemux - surface publique' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $script:RepoRootReencodeApi = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module -Name (Join-Path $script:RepoRootReencodeApi 'Tetram.Media.Mkv') -Force -ErrorAction Stop

        function script:Get-ParameterSetNames {
            param(
                [Parameter(Mandatory)]
                [System.Management.Automation.CommandInfo] $Command,
                [Parameter(Mandatory)]
                [string] $ParameterName
            )

            $param = $Command.Parameters[$ParameterName]
            if ($null -eq $param)
            {
                return @()
            }

            @($param.ParameterSets.Keys |
                    Where-Object { $_ -ne '__AllParameterSets' } |
                    Sort-Object)
        }
    }

    AfterAll {
        Remove-Module -Name 'Tetram.Media.Mkv' -Force -ErrorAction SilentlyContinue
    }

    It 'expose les six ParameterSets cibles, ReencodeFromPath par défaut' {
        $meta = Get-Command Invoke-MkvRemux
        $meta.DefaultParameterSet | Should -Be 'ReencodeFromPath'
        @($meta.ParameterSets | Select-Object -ExpandProperty Name | Sort-Object) | Should -Be @(
            'CheckFromFile'
            'CheckFromPath'
            'NoTranscodeFromFile'
            'NoTranscodeFromPath'
            'ReencodeFromFile'
            'ReencodeFromPath'
        )
    }

    It 'place -NoTranscode uniquement sur les ParameterSets NoTranscode*, en obligatoire' {
        $meta = Get-Command Invoke-MkvRemux
        Get-ParameterSetNames $meta 'NoTranscode' | Should -Be @('NoTranscodeFromFile', 'NoTranscodeFromPath')
        $meta.Parameters['NoTranscode'].ParameterSets['NoTranscodeFromPath'].IsMandatory | Should -BeTrue
        $meta.Parameters['NoTranscode'].ParameterSets['NoTranscodeFromFile'].IsMandatory | Should -BeTrue
    }

    It 'place -CheckOnly uniquement sur les ParameterSets Check*, en obligatoire' {
        $meta = Get-Command Invoke-MkvRemux
        Get-ParameterSetNames $meta 'CheckOnly' | Should -Be @('CheckFromFile', 'CheckFromPath')
        $meta.Parameters['CheckOnly'].ParameterSets['CheckFromPath'].IsMandatory | Should -BeTrue
        $meta.Parameters['CheckOnly'].ParameterSets['CheckFromFile'].IsMandatory | Should -BeTrue
    }

    It 'réserve les paramètres de transformation aux ParameterSets Reencode*' {
        $meta = Get-Command Invoke-MkvRemux
        $reencodeSets = @('ReencodeFromFile', 'ReencodeFromPath')
        foreach ($name in @(
                'VideoCodec'
                'ForceRecodeVideo'
                'AllowVideoCodecUpgrade'
                'Quality'
                'Upscale'
                'UpscaleWidth'
                'UpscaleFit'
                'Deinterlace'
                'AllowSubTitlesConversion'
            ))
        {
            Get-ParameterSetNames $meta $name | Should -Be $reencodeSets -Because $name
        }
    }

    It 'rend Path disponible sur les ParameterSets *FromPath et ListFile/UpdateList sur *FromFile' {
        $meta = Get-Command Invoke-MkvRemux
        Get-ParameterSetNames $meta 'Path' | Should -Be @('CheckFromPath', 'NoTranscodeFromPath', 'ReencodeFromPath')
        Get-ParameterSetNames $meta 'ListFile' | Should -Be @('CheckFromFile', 'NoTranscodeFromFile', 'ReencodeFromFile')
        Get-ParameterSetNames $meta 'UpdateList' | Should -Be @('CheckFromFile', 'NoTranscodeFromFile', 'ReencodeFromFile')
        # Recurse reste sur les *FromPath ; parmi les *FromFile, seulement NoTranscodeFromFile
        # (héritage du jeu RewriteFromFile, le seul File set qui l'exposait).
        Get-ParameterSetNames $meta 'Recurse' | Should -Be @(
            'CheckFromPath'
            'NoTranscodeFromFile'
            'NoTranscodeFromPath'
            'ReencodeFromPath'
        )
    }

    It 'rend ClearStreamsTitle et SubTitlesToKeep disponibles en réencodage et en NoTranscode' {
        $meta = Get-Command Invoke-MkvRemux
        $expected = @('NoTranscodeFromFile', 'NoTranscodeFromPath', 'ReencodeFromFile', 'ReencodeFromPath')
        Get-ParameterSetNames $meta 'ClearStreamsTitle' | Should -Be $expected
        Get-ParameterSetNames $meta 'SubTitlesToKeep' | Should -Be $expected
    }

    It 'rend les paramètres transverses de scan et d''outils disponibles sur les six ParameterSets' {
        $meta = Get-Command Invoke-MkvRemux
        $allSets = @(
            'CheckFromFile'
            'CheckFromPath'
            'NoTranscodeFromFile'
            'NoTranscodeFromPath'
            'ReencodeFromFile'
            'ReencodeFromPath'
        )
        foreach ($name in @(
                'Sort'
                'ScanReadOnlyDirectory'
                'InputMasks'
                'TempPath'
                'FFToolsBase'
                'FFMPEGPath'
                'FFPROBEPath'
            ))
        {
            Get-ParameterSetNames $meta $name | Should -Be $allSets -Because $name
        }
    }

    It 'place -AllowIntegrityMismatch uniquement sur les ParameterSets Reencode*' {
        $meta = Get-Command Invoke-MkvRemux
        Get-ParameterSetNames $meta 'AllowIntegrityMismatch' | Should -Be @(
            'ReencodeFromFile'
            'ReencodeFromPath'
        )
        $meta.Parameters['AllowIntegrityMismatch'].ParameterSets['ReencodeFromPath'].IsMandatory | Should -BeFalse
        $meta.Parameters['AllowIntegrityMismatch'].ParameterSets['ReencodeFromFile'].IsMandatory | Should -BeFalse
    }

    It 'place -RemoveAttachments sur les ParameterSets Reencode* et NoTranscode*, jamais Check*' {
        $meta = Get-Command Invoke-MkvRemux
        Get-ParameterSetNames $meta 'RemoveAttachments' | Should -Be @(
            'NoTranscodeFromFile'
            'NoTranscodeFromPath'
            'ReencodeFromFile'
            'ReencodeFromPath'
        )
        foreach ($set in @(
                'NoTranscodeFromFile'
                'NoTranscodeFromPath'
                'ReencodeFromFile'
                'ReencodeFromPath'
            ))
        {
            $meta.Parameters['RemoveAttachments'].ParameterSets[$set].IsMandatory | Should -BeFalse
        }
    }
}

Describe 'Invoke-MkvRemux - résolution FFmpeg au démarrage' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $script:RepoRootReencode = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module -Name (Join-Path $script:RepoRootReencode 'Tetram.Media.Mkv') -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module -Name 'Tetram.Media.Mkv' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName Tetram.Media.Remux Get-FFmpegPath { throw "FFmpeg introuvable (test)" }
        Mock -ModuleName Tetram.Media.Remux Write-ErrorLog {}
    }

    It "log une erreur via Write-ErrorLog et ne lève pas d'exception quand FFmpeg est introuvable" {
        { Invoke-MkvRemux -Path $TestDrive -CheckOnly } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Remux Write-ErrorLog -Times 1
    }
}

Describe 'Invoke-MkvRemux - configuration et récapitulatif' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $script:RepoRootReencodeConfig = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module -Name (Join-Path $script:RepoRootReencodeConfig 'Tetram.Media.Mkv') -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module -Name 'Tetram.Media.Mkv' -Force -ErrorAction SilentlyContinue
    }

    It 'propage -AllowIntegrityMismatch dans la configuration transmise à l''orchestration' {
        $script:capturedConfig = $null
        Mock -ModuleName Tetram.Media.Remux Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Remux Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Remux Invoke-PathList {
            param($Paths, $State, $Config, $Cmdlet)
            $script:capturedConfig = $Config
        }
        Mock -ModuleName Tetram.Media.Remux Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Remux Write-InfoWarning {}

        Invoke-MkvRemux -Path $TestDrive -AllowIntegrityMismatch

        $script:capturedConfig | Should -Not -BeNullOrEmpty
        $script:capturedConfig.AllowIntegrityMismatch | Should -BeTrue
    }

    It 'propage AllowIntegrityMismatch à false par défaut' {
        $script:capturedConfig = $null
        Mock -ModuleName Tetram.Media.Remux Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Remux Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Remux Invoke-PathList {
            param($Paths, $State, $Config, $Cmdlet)
            $script:capturedConfig = $Config
        }
        Mock -ModuleName Tetram.Media.Remux Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Remux Write-InfoWarning {}

        Invoke-MkvRemux -Path $TestDrive

        $script:capturedConfig.AllowIntegrityMismatch | Should -BeFalse
    }

    It 'propage -RemoveAttachments dans la configuration transmise à l''orchestration' {
        $script:capturedConfig = $null
        Mock -ModuleName Tetram.Media.Remux Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Remux Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Remux Invoke-PathList {
            param($Paths, $State, $Config, $Cmdlet)
            $script:capturedConfig = $Config
        }
        Mock -ModuleName Tetram.Media.Remux Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Remux Write-InfoWarning {}

        Invoke-MkvRemux -Path $TestDrive -RemoveAttachments

        $script:capturedConfig | Should -Not -BeNullOrEmpty
        $script:capturedConfig.RemoveAttachments | Should -BeTrue
    }

    It 'propage RemoveAttachments à false par défaut' {
        $script:capturedConfig = $null
        Mock -ModuleName Tetram.Media.Remux Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Remux Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Remux Invoke-PathList {
            param($Paths, $State, $Config, $Cmdlet)
            $script:capturedConfig = $Config
        }
        Mock -ModuleName Tetram.Media.Remux Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Remux Write-InfoWarning {}

        Invoke-MkvRemux -Path $TestDrive

        $script:capturedConfig.RemoveAttachments | Should -BeFalse
    }

    It 'présente les warnings d''intégrité sans les limiter aux durées invérifiables' {
        $message = "Integrity check inconclusive for 'accepted.mkv' [timestamp-span] - source 0:a:0 -> output 0:a:0 has no usable end PTS; accepting file"
        Mock -ModuleName Tetram.Media.Remux Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Remux Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Remux Invoke-PathList {
            param($Paths, $State, $Config, $Cmdlet)
            $State.IntegrityWarningFiles += 'accepted.mkv'
            $State.IntegrityWarningMessages += $message
        }
        Mock -ModuleName Tetram.Media.Remux Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Remux Write-InfoWarning {}

        Invoke-MkvRemux -Path $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Remux Write-InfoWarning -Times 1 -ParameterFilter {
            $Force -and
            $Text -eq '1 file(s) accepted with integrity warning:'
        }
        Should -Invoke -ModuleName Tetram.Media.Remux Write-InfoWarning -Times 1 -ParameterFilter {
            $Force -and $Text -ceq "  - $message"
        }
        Should -Invoke -ModuleName Tetram.Media.Remux Write-InfoWarning -Times 0 -ParameterFilter {
            $Text -eq '  - accepted.mkv'
        }
        Should -Invoke -ModuleName Tetram.Media.Remux Write-InfoWarning -Times 0 -ParameterFilter {
            $Text -like '*unverifiable*'
        }
    }

    Context 'récapitulatif des warnings d''intégrité acceptés' {
        BeforeEach {
            $script:summaryWarnings = [System.Collections.Generic.List[string]]::new()
            $script:injectedFiles = @()
            $script:injectedMessages = @()
            Mock -ModuleName Tetram.Media.Remux Get-FFmpegPath { 'ffmpeg' }
            Mock -ModuleName Tetram.Media.Remux Get-FfprobePath { 'ffprobe' }
            Mock -ModuleName Tetram.Media.Remux Invoke-PathList {
                param($Paths, $State, $Config, $Cmdlet)
                $State.IntegrityWarningFiles += $script:injectedFiles
                $State.IntegrityWarningMessages += $script:injectedMessages
            }
            Mock -ModuleName Tetram.Media.Remux Write-InfoLog {}
            Mock -ModuleName Tetram.Media.Remux Write-InfoWarning {
                param($Text)
                $script:summaryWarnings.Add($Text)
            }
        }

        It 'n''affiche jamais [x 1] pour un warning rencontré une seule fois' {
            $message = "Integrity mismatch for 'one.mkv' [interleave] - A/V packet spread at 50% is 14.3 MiB, limit 10.2 MiB — accepted because -AllowIntegrityMismatch is set"
            $script:injectedFiles = @('one.mkv')
            $script:injectedMessages = @($message)

            Invoke-MkvRemux -Path $TestDrive

            $expected = @(
                '1 file(s) accepted with integrity warning:'
                "  - $message"
            )
            ($script:summaryWarnings -join "`n") | Should -BeExactly ($expected -join "`n")
            @($script:summaryWarnings | Where-Object { $_ -like '*`[x 1`]*' }) | Should -HaveCount 0
        }

        It 'regroupe des messages strictement identiques en une seule ligne suffixée [x N]' {
            $message = "Integrity check inconclusive for 'same.mkv' [timestamp-span] - source 0:a:0 -> output 0:a:0 has no usable end PTS; accepting file"
            $script:injectedFiles = @('same.mkv', 'same.mkv', 'same.mkv')
            $script:injectedMessages = @($message, $message, $message)

            Invoke-MkvRemux -Path $TestDrive

            $expected = @(
                '3 file(s) accepted with integrity warning:'
                "  - $message [x 3]"
            )
            ($script:summaryWarnings -join "`n") | Should -BeExactly ($expected -join "`n")
        }

        It 'garde distincts deux warnings du même type avec des valeurs différentes' {
            $message1 = 'Non-monotonous DTS at 00:12:34.567'
            $message2 = 'Non-monotonous DTS at 00:18:42.123'
            $script:injectedFiles = @('a.mkv', 'b.mkv')
            $script:injectedMessages = @($message1, $message2)

            Invoke-MkvRemux -Path $TestDrive

            $expected = @(
                '2 file(s) accepted with integrity warning:'
                "  - $message1"
                "  - $message2"
            )
            ($script:summaryWarnings -join "`n") | Should -BeExactly ($expected -join "`n")
        }

        It 'compare le message complet de façon littérale (valeur et casse)' {
            $script:injectedFiles = @('a.mkv', 'b.mkv', 'c.mkv')
            $script:injectedMessages = @('warning value=10', 'warning value=11', 'Warning value=10')

            Invoke-MkvRemux -Path $TestDrive

            $expected = @(
                '3 file(s) accepted with integrity warning:'
                '  - warning value=10'
                '  - warning value=11'
                '  - Warning value=10'
            )
            ($script:summaryWarnings -join "`n") | Should -BeExactly ($expected -join "`n")
        }

        It 'conserve l''ordre de première apparition sans trier' {
            $script:injectedFiles = @('1.mkv', '2.mkv', '3.mkv', '4.mkv', '5.mkv')
            $script:injectedMessages = @('B warning', 'A warning', 'B warning', 'C warning', 'A warning')

            Invoke-MkvRemux -Path $TestDrive

            $expected = @(
                '5 file(s) accepted with integrity warning:'
                '  - B warning [x 2]'
                '  - A warning [x 2]'
                '  - C warning'
            )
            ($script:summaryWarnings -join "`n") | Should -BeExactly ($expected -join "`n")
        }

        It 'rend un récapitulatif mixte : warning A, puis warning B [x 2]' {
            $script:injectedFiles = @('a.mkv', 'b1.mkv', 'b2.mkv')
            $script:injectedMessages = @('warning A', 'warning B', 'warning B')

            Invoke-MkvRemux -Path $TestDrive

            $expected = @(
                '3 file(s) accepted with integrity warning:'
                '  - warning A'
                '  - warning B [x 2]'
            )
            ($script:summaryWarnings -join "`n") | Should -BeExactly ($expected -join "`n")
        }

        It 'reste silencieux sans warning d''intégrité' {
            Invoke-MkvRemux -Path $TestDrive

            $script:summaryWarnings | Should -HaveCount 0
        }
    }
}
