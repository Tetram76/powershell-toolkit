# Étendre la suite autour du SUD Probe.ps1 (ffprobe/JSON métadonnées).
#
# RepoRoot (trois `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode') ; InModuleScope 'Tetram.Media.Reencode' { … }
# ffprobe/ffmpeg : éviter dépendance à l’installation hôte — mocker la fonction qui lance la commande et faire retourner du JSON représentatif (succès / erreurs / fichier absent).

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootProbe = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootProbe 'Tetram.Media.Reencode') -Force -ErrorAction Stop

    function script:New-ProbeStream {
        param(
            [Parameter(Mandatory)] [string] $CodecType,
            [double] $Duration,
            [string] $DurationTag
        )

        $stream = @{ codec_type = $CodecType }
        if ($PSBoundParameters.ContainsKey('Duration')) {
            $stream['duration'] = [string]$Duration
        }
        if ($PSBoundParameters.ContainsKey('DurationTag')) {
            $stream['tags'] = @{ DURATION = $DurationTag }
        }
        $stream
    }

    function script:New-MediaProbe {
        param(
            [double] $FormatDuration,
            [object[]] $Streams = @()
        )

        $probe = @{
            streams = @($Streams)
        }
        if ($PSBoundParameters.ContainsKey('FormatDuration')) {
            $probe['format'] = @{ duration = [string]$FormatDuration }
        }
        else {
            $probe['format'] = @{}
        }
        $probe
    }

    function script:Invoke-IntegrityCheck {
        param(
            [Parameter(Mandatory)] [hashtable] $SourceProbe,
            [Parameter(Mandatory)] [hashtable] $TempProbe,
            [int[]] $KeptSourceVideoIndices = @(),
            [int[]] $KeptSourceAudioIndices = @(),
            [int[]] $KeptSourceSubtitleIndices
        )

        $script:TempProbe = $TempProbe

        $bound = @{
            SourceProbe              = $SourceProbe
            SourceFile               = $script:SourceFile
            TempFile                 = $script:TempFile
            KeptSourceVideoIndices   = $KeptSourceVideoIndices
            KeptSourceAudioIndices   = $KeptSourceAudioIndices
        }
        if ($PSBoundParameters.ContainsKey('KeptSourceSubtitleIndices')) {
            $bound['KeptSourceSubtitleIndices'] = $KeptSourceSubtitleIndices
        }

        InModuleScope 'Tetram.Media.Reencode' -Parameters $bound {
            param(
                $SourceProbe,
                $SourceFile,
                $TempFile,
                $KeptSourceVideoIndices,
                $KeptSourceAudioIndices,
                $KeptSourceSubtitleIndices
            )

            $integrityParams = @{
                FFPROBE                  = 'ffprobe'
                SourceProbe              = $SourceProbe
                SourceFile               = $SourceFile
                TempFile                 = $TempFile
                KeptSourceVideoIndices   = $KeptSourceVideoIndices
                KeptSourceAudioIndices   = $KeptSourceAudioIndices
            }
            if ($PSBoundParameters.ContainsKey('KeptSourceSubtitleIndices')) {
                $integrityParams['KeptSourceSubtitleIndices'] = $KeptSourceSubtitleIndices
            }

            Test-EncodedFileIntegrity @integrityParams
        }
    }
}

Describe 'Test-EncodedFileIntegrity — format.duration' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        $script:TempProbe = @{ format = @{}; streams = @() }

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Reencode Get-DurationFromPacketCount { $null }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It 'A1 — mismatch global format sans poursuivre vers un ok flux' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 90 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'format'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 90
        $result.Diff | Should -Be 10
    }

    It 'A2 — format identique mais un stream hors tolérance reste mismatch' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 90)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'stream'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 90
        $result.Diff | Should -Be 10
    }

    It 'A3 — format dans la tolérance, stream hors tolérance' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )
        # diff format 0.4s < max(1s, 0.5%) donc le garde global ne tranche pas
        $temp = New-MediaProbe -FormatDuration 99.6 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 90)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'stream'
    }

    It 'A4 — format indisponible mais streams valides => ok' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'ok'
    }
}

Describe 'Test-EncodedFileIntegrity — plusieurs vidéos' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        $script:TempProbe = @{ format = @{}; streams = @() }

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Reencode Get-DurationFromPacketCount { $null }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It 'B1 — toutes les vidéos conservées dans la tolérance => ok' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'video' -Duration 80)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'video' -Duration 80)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0, 1)

        $result.Status | Should -Be 'ok'
    }

    It 'B2 — première vidéo correcte, deuxième tronquée => mismatch' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'video' -Duration 80)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'video' -Duration 40)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0, 1)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'stream'
        $result.Expected | Should -Be 80
        $result.Actual | Should -Be 40
        $result.Diff | Should -Be 40
    }

    It 'B3 — compare source v:2 à output v:1, jamais à un leurre v:2' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'video' -Duration 50)
            (New-ProbeStream -CodecType 'video' -Duration 80)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'video' -Duration 40)
            (New-ProbeStream -CodecType 'video' -Duration 80)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0, 2)

        $result.Status | Should -Be 'mismatch'
        $result.Expected | Should -Be 80
        $result.Actual | Should -Be 40
    }
}

Describe 'Test-EncodedFileIntegrity — plusieurs audios' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        $script:TempProbe = @{ format = @{}; streams = @() }

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Reencode Get-DurationFromPacketCount { $null }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It 'C1 — tous les audios conservés dans la tolérance => ok' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0, 1)

        $result.Status | Should -Be 'ok'
    }

    It 'C2 — audio secondaire tronqué malgré vidéo et premier audio corrects' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 90)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0, 1)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'stream'
        $result.StreamType | Should -Be 'audio'
        $result.SourceRelativeIndex | Should -Be 1
        $result.OutputRelativeIndex | Should -Be 1
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 90
    }

    It 'C3 — mapping audio après suppression a:1, leurre a:2 ignoré' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 50)
            (New-ProbeStream -CodecType 'audio' -Duration 80)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 40)
            (New-ProbeStream -CodecType 'audio' -Duration 80)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0, 2)

        $result.Status | Should -Be 'mismatch'
        $result.StreamType | Should -Be 'audio'
        $result.SourceRelativeIndex | Should -Be 2
        $result.OutputRelativeIndex | Should -Be 1
        $result.Expected | Should -Be 80
        $result.Actual | Should -Be 40
    }
}

Describe 'Test-EncodedFileIntegrity — sous-titres' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        $script:TempProbe = @{ format = @{}; streams = @() }

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Reencode Get-DurationFromPacketCount { $null }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It 'D1 — subtitle conservé comparable et dans la tolérance => ok' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 98)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 98)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0) `
            -KeptSourceSubtitleIndices @(0)

        $result.Status | Should -Be 'ok'
    }

    It 'D2 — subtitle conservé hors tolérance malgré vidéo/audio corrects' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 90)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0) `
            -KeptSourceSubtitleIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'stream'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 90
    }

    It 'D3 — subtitle volontairement supprimé n''influence pas le résultat' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 20)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 100)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0) `
            -KeptSourceSubtitleIndices @(0)

        $result.Status | Should -Be 'ok'
    }

    It 'D4 — mapping subtitles après suppression s:1, leurre s:2 ignoré' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 50)
            (New-ProbeStream -CodecType 'subtitle' -Duration 80)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 100)
            (New-ProbeStream -CodecType 'subtitle' -Duration 40)
            (New-ProbeStream -CodecType 'subtitle' -Duration 80)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceSubtitleIndices @(0, 2)

        $result.Status | Should -Be 'mismatch'
        $result.Expected | Should -Be 80
        $result.Actual | Should -Be 40
    }
}

Describe 'Test-EncodedFileIntegrity — méthodes d''extraction' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        $script:TempProbe = @{ format = @{}; streams = @() }

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Reencode Get-DurationFromPacketCount { $null }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It 'E1 — utilise stream.duration quand les deux côtés l''ont' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100 -DurationTag '00:01:10.0000000')
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100 -DurationTag '00:01:10.0000000')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'stream'
    }

    It 'E2 — fallback tag DURATION quand stream.duration est absent des deux côtés' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -DurationTag '00:01:40.0000000')
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -DurationTag '00:01:40.0000000')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'tag'
    }

    It 'E3 — fallback count_packets vidéo avec les indices source/output remappés' {
        $script:PacketCountCalls = [System.Collections.Generic.List[hashtable]]::new()
        Mock -ModuleName Tetram.Media.Reencode Get-DurationFromPacketCount {
            param([string] $File, [int] $StreamIndex)
            [void]$script:PacketCountCalls.Add(@{ File = $File; StreamIndex = $StreamIndex })
            if ($File -eq $script:SourceFile -and $StreamIndex -eq 0) { return 100.0 }
            if ($File -eq $script:TempFile -and $StreamIndex -eq 0) { return 100.0 }
            if ($File -eq $script:SourceFile -and $StreamIndex -eq 2) { return 80.0 }
            if ($File -eq $script:TempFile -and $StreamIndex -eq 1) { return 80.0 }
            return $null
        }

        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video')
            (New-ProbeStream -CodecType 'video')
            (New-ProbeStream -CodecType 'video')
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video')
            (New-ProbeStream -CodecType 'video')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0, 2)

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'count'
        $script:PacketCountCalls.StreamIndex | Should -Contain 2
        $script:PacketCountCalls.StreamIndex | Should -Contain 1
        $script:PacketCountCalls | Where-Object { $_.File -eq $script:SourceFile -and $_.StreamIndex -eq 2 } | Should -Not -BeNullOrEmpty
        $script:PacketCountCalls | Where-Object { $_.File -eq $script:TempFile -and $_.StreamIndex -eq 1 } | Should -Not -BeNullOrEmpty
        $script:PacketCountCalls | Where-Object { $_.File -eq $script:TempFile -and $_.StreamIndex -eq 2 } | Should -BeNullOrEmpty
    }
}

Describe 'Test-EncodedFileIntegrity — tolérance' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        $script:TempProbe = @{ format = @{}; streams = @() }

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Reencode Get-DurationFromPacketCount { $null }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It 'F1 — différence inférieure à la tolérance => ok' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 99.5)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'ok'
    }

    It 'F2 — différence exactement égale à la tolérance => ok (comparaison -gt)' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 99)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'ok'
    }

    It 'F3 — différence juste supérieure à la tolérance => mismatch' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 98.9)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Diff | Should -BeGreaterThan 1
    }
}

Describe 'Test-EncodedFileIntegrity — unknown vs mismatch' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        $script:TempProbe = @{ format = @{}; streams = @() }

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Reencode Get-DurationFromPacketCount { $null }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It 'G1 — échec de probe du fichier réencodé => mismatch, jamais unknown' {
        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson { $null }

        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe @{ format = @{}; streams = @() } -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'probe'
        $result.Status | Should -Not -Be 'unknown'
        $result.Expected | Should -BeNullOrEmpty
        $result.Actual | Should -BeNullOrEmpty
        $result.Diff | Should -BeNullOrEmpty
    }

    It 'G2 — un stream non comparable, aucun mismatch => unknown' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video')
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video')
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'unknown'
    }

    It 'G3 — stream non comparable puis stream mismatch => mismatch, pas unknown' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video')
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video')
            (New-ProbeStream -CodecType 'audio' -Duration 90)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'stream'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 90
    }
}

Describe 'Test-EncodedFileIntegrity — asymétrie de conteneur et fail-safe' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        $script:TempProbe = @{ format = @{}; streams = @() }

        Mock -ModuleName Tetram.Media.Reencode Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Reencode Get-DurationFromPacketCount { $null }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It 'rapproche stream.duration source et tag DURATION sortie du même flux (mp4 vs mkv)' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -DurationTag '00:01:40.0000000')
            (New-ProbeStream -CodecType 'audio' -DurationTag '00:01:40.0000000')
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'ok'
    }

    It 'détecte un mismatch quand le tag de sortie du même flux est hors tolérance' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -DurationTag '00:01:30.0000000')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 90
    }

    It 'ne conclut pas ok sur le seul format.duration si aucun index conservé n''est transmis' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 10)
            (New-ProbeStream -CodecType 'audio' -Duration 10)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'unknown'
    }

    It 'retourne unknown quand aucune comparaison de flux n''est possible' {
        $source = New-MediaProbe
        $temp = New-MediaProbe

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'unknown'
    }

    It 'mismatch si un flux conservé est absent de la sortie' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0, 1)

        $result.Status | Should -Be 'mismatch'
    }

    It 'mismatch si la durée de sortie du flux est nulle' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 0)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Actual | Should -Be 0
    }

    It 'ignore les attachments même s''ils portent une durée' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'attachment' -Duration 1)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
            (New-ProbeStream -CodecType 'attachment' -Duration 999)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'ok'
    }
}
