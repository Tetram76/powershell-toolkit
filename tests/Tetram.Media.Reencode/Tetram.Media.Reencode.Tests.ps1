# Étendre la suite autour du module SUD Tetram.Media.Reencode (Exports / comportement public après chargement réel du .psm1).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Sanity : Test-ModuleManifest (Join-Path $RepoRoot 'Tetram.Media.Reencode' 'Tetram.Media.Reencode.psd1') avant Import-Module sur ce chemin avec -Force
# Nouvelle couverture : un Describe par commande FunctionsToExport (ou famille logique), It minimaux puis mocks sur Utils/ffmpeg si nécessaires

Describe 'Invoke-ReencodeMedia - surface publique' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $script:RepoRootReencodeApi = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module -Name (Join-Path $script:RepoRootReencodeApi 'Tetram.Media.Reencode') -Force -ErrorAction Stop

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
        Remove-Module -Name 'Tetram.Media.Reencode' -Force -ErrorAction SilentlyContinue
    }

    It 'expose les six ParameterSets cibles, ReencodeFromPath par défaut' {
        $meta = Get-Command Invoke-ReencodeMedia
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
        $meta = Get-Command Invoke-ReencodeMedia
        Get-ParameterSetNames $meta 'NoTranscode' | Should -Be @('NoTranscodeFromFile', 'NoTranscodeFromPath')
        $meta.Parameters['NoTranscode'].ParameterSets['NoTranscodeFromPath'].IsMandatory | Should -BeTrue
        $meta.Parameters['NoTranscode'].ParameterSets['NoTranscodeFromFile'].IsMandatory | Should -BeTrue
    }

    It 'place -CheckOnly uniquement sur les ParameterSets Check*, en obligatoire' {
        $meta = Get-Command Invoke-ReencodeMedia
        Get-ParameterSetNames $meta 'CheckOnly' | Should -Be @('CheckFromFile', 'CheckFromPath')
        $meta.Parameters['CheckOnly'].ParameterSets['CheckFromPath'].IsMandatory | Should -BeTrue
        $meta.Parameters['CheckOnly'].ParameterSets['CheckFromFile'].IsMandatory | Should -BeTrue
    }

    It 'réserve les paramètres de transformation aux ParameterSets Reencode*' {
        $meta = Get-Command Invoke-ReencodeMedia
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
        $meta = Get-Command Invoke-ReencodeMedia
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
        $meta = Get-Command Invoke-ReencodeMedia
        $expected = @('NoTranscodeFromFile', 'NoTranscodeFromPath', 'ReencodeFromFile', 'ReencodeFromPath')
        Get-ParameterSetNames $meta 'ClearStreamsTitle' | Should -Be $expected
        Get-ParameterSetNames $meta 'SubTitlesToKeep' | Should -Be $expected
    }

    It 'rend les paramètres transverses de scan et d''outils disponibles sur les six ParameterSets' {
        $meta = Get-Command Invoke-ReencodeMedia
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
        $meta = Get-Command Invoke-ReencodeMedia
        Get-ParameterSetNames $meta 'AllowIntegrityMismatch' | Should -Be @(
            'ReencodeFromFile'
            'ReencodeFromPath'
        )
        $meta.Parameters['AllowIntegrityMismatch'].ParameterSets['ReencodeFromPath'].IsMandatory | Should -BeFalse
        $meta.Parameters['AllowIntegrityMismatch'].ParameterSets['ReencodeFromFile'].IsMandatory | Should -BeFalse
    }
}

Describe 'Invoke-ReencodeMedia - résolution FFmpeg au démarrage' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $script:RepoRootReencode = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module -Name (Join-Path $script:RepoRootReencode 'Tetram.Media.Reencode') -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module -Name 'Tetram.Media.Reencode' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName Tetram.Media.Reencode Get-FFmpegPath { throw "FFmpeg introuvable (test)" }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It "log une erreur via Write-ErrorLog et ne lève pas d'exception quand FFmpeg est introuvable" {
        { Invoke-ReencodeMedia -Path $TestDrive -CheckOnly } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Reencode Write-ErrorLog -Times 1
    }
}

Describe 'Invoke-ReencodeMedia - configuration et récapitulatif' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $script:RepoRootReencodeConfig = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module -Name (Join-Path $script:RepoRootReencodeConfig 'Tetram.Media.Reencode') -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module -Name 'Tetram.Media.Reencode' -Force -ErrorAction SilentlyContinue
    }

    It 'propage -AllowIntegrityMismatch dans la configuration transmise à l''orchestration' {
        $script:capturedConfig = $null
        Mock -ModuleName Tetram.Media.Reencode Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Reencode Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Reencode Invoke-PathList {
            param($Paths, $State, $Config, $Cmdlet)
            $script:capturedConfig = $Config
        }
        Mock -ModuleName Tetram.Media.Reencode Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Reencode Write-InfoWarning {}

        Invoke-ReencodeMedia -Path $TestDrive -AllowIntegrityMismatch

        $script:capturedConfig | Should -Not -BeNullOrEmpty
        $script:capturedConfig.AllowIntegrityMismatch | Should -BeTrue
    }

    It 'propage AllowIntegrityMismatch à false par défaut' {
        $script:capturedConfig = $null
        Mock -ModuleName Tetram.Media.Reencode Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Reencode Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Reencode Invoke-PathList {
            param($Paths, $State, $Config, $Cmdlet)
            $script:capturedConfig = $Config
        }
        Mock -ModuleName Tetram.Media.Reencode Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Reencode Write-InfoWarning {}

        Invoke-ReencodeMedia -Path $TestDrive

        $script:capturedConfig.AllowIntegrityMismatch | Should -BeFalse
    }

    It 'présente les warnings d''intégrité sans les limiter aux durées invérifiables' {
        Mock -ModuleName Tetram.Media.Reencode Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Reencode Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Reencode Invoke-PathList {
            param($Paths, $State, $Config, $Cmdlet)
            [void]$State.IntegrityWarningFiles.Add('accepted.mkv')
        }
        Mock -ModuleName Tetram.Media.Reencode Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Reencode Write-InfoWarning {}

        Invoke-ReencodeMedia -Path $TestDrive

        Should -Invoke -ModuleName Tetram.Media.Reencode Write-InfoWarning -Times 1 -ParameterFilter {
            $Force -and
            $Text -eq '1 file(s) accepted with integrity warning:'
        }
        Should -Invoke -ModuleName Tetram.Media.Reencode Write-InfoWarning -Times 1 -ParameterFilter {
            $Force -and $Text -eq '  - accepted.mkv'
        }
        Should -Invoke -ModuleName Tetram.Media.Reencode Write-InfoWarning -Times 0 -ParameterFilter {
            $Text -like '*unverifiable*'
        }
    }
}
