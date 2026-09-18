# Étendre la suite autour du SUD Probe.ps1 (ffprobe/JSON métadonnées + span packets).
#
# RepoRoot (trois `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Mkv') ; InModuleScope 'Tetram.Media.Mkv' { … }
# Mocks : -ModuleName Tetram.Media.Remux (Probe.ps1 est dot-sourcé dans ce nested ; un mock sur le parent Mkv n'intercepte pas Get-FFprobeJson).

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootProbe = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootProbe 'Tetram.Media.Mkv') -Force -ErrorAction Stop

    function script:New-ProbeStream {
        param(
            [Parameter(Mandatory)] [string] $CodecType,
            [Parameter(Mandatory)] [int] $Index,
            [string] $TimeBase = '1/1000',
            [string] $CodecName,
            [string] $Duration,
            [string] $DurationTag
        )

        $stream = @{
            codec_type = $CodecType
            index      = $Index
            time_base  = $TimeBase
        }
        if ($PSBoundParameters.ContainsKey('CodecName')) {
            $stream['codec_name'] = $CodecName
        }
        if ($PSBoundParameters.ContainsKey('Duration')) {
            $stream['duration'] = $Duration
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

    function script:New-SpanEntry {
        param(
            [Parameter(Mandatory)] [int] $StreamIndex,
            [decimal] $DurationSeconds,
            [switch] $Unmeasurable,
            [string] $Reason = 'no-packets'
        )

        if ($Unmeasurable) {
            return [pscustomobject]@{
                StreamIndex      = $StreamIndex
                Measurable       = $false
                DurationSeconds  = $null
                MinPts           = $null
                MaxEnd           = $null
                PacketCount      = 0
                Reason           = $Reason
            }
        }

        [pscustomobject]@{
            StreamIndex      = $StreamIndex
            Measurable       = $true
            DurationSeconds  = $DurationSeconds
            MinPts           = $null
            MaxEnd           = $null
            PacketCount      = 1
            Reason           = $null
        }
    }

    function script:New-SpanScan {
        param(
            [switch] $Failed,
            [object[]] $Entries = @()
        )

        $spans = [System.Collections.Generic.Dictionary[int, object]]::new()
        foreach ($entry in @($Entries)) {
            $spans[[int]$entry.StreamIndex] = $entry
        }

        [pscustomobject]@{
            ScanFailed = [bool]$Failed
            Reason     = $(if ($Failed) { 'ffprobe-failed' } else { $null })
            Spans      = $spans
        }
    }

    function script:Invoke-ReadPacketSpanMap {
        param(
            [Parameter(Mandatory)] [hashtable] $Probe,
            [Parameter(Mandatory)] [int[]] $StreamIndices,
            [Parameter(Mandatory)] [string] $Text
        )

        $bound = @{
            Probe          = $Probe
            StreamIndices  = $StreamIndices
            Text           = $Text
        }
        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param($Probe, $StreamIndices, $Text)
            $reader = [System.IO.StringReader]::new($Text)
            try {
                Read-FFprobePacketSpanMap -Probe $Probe -StreamIndices $StreamIndices -Reader $reader
            }
            finally {
                $reader.Dispose()
            }
        }
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
            SourceProbe                 = $SourceProbe
            SourceFile                  = $script:SourceFile
            TempFile                    = $script:TempFile
            KeptSourceVideoIndices      = $KeptSourceVideoIndices
            KeptSourceAudioIndices      = $KeptSourceAudioIndices
        }
        if ($PSBoundParameters.ContainsKey('KeptSourceSubtitleIndices')) {
            $bound['KeptSourceSubtitleIndices'] = $KeptSourceSubtitleIndices
        }

        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param(
                $SourceProbe,
                $SourceFile,
                $TempFile,
                $KeptSourceVideoIndices,
                $KeptSourceAudioIndices,
                $KeptSourceSubtitleIndices
            )

            $integrityParams = @{
                FFPROBE                    = 'ffprobe'
                SourceProbe                = $SourceProbe
                SourceFile                 = $SourceFile
                TempFile                   = $TempFile
                KeptSourceVideoIndices     = $KeptSourceVideoIndices
                KeptSourceAudioIndices     = $KeptSourceAudioIndices
            }
            if ($PSBoundParameters.ContainsKey('KeptSourceSubtitleIndices')) {
                $integrityParams['KeptSourceSubtitleIndices'] = $KeptSourceSubtitleIndices
            }

            Test-EncodedFileIntegrity @integrityParams
        }
    }
}

Describe 'ConvertFrom-FFprobeCompactPacketLine' {
    It 'parse les champs indépendamment de leur ordre' {
        $bound = @{
            LineA = 'stream_index=2|pts=100|duration=40'
            LineB = 'duration=40|stream_index=2|pts=100'
        }
        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param($LineA, $LineB)
            $a = ConvertFrom-FFprobeCompactPacketLine -Line $LineA
            $b = ConvertFrom-FFprobeCompactPacketLine -Line $LineB
            $a.stream_index | Should -Be $b.stream_index
            $a.pts | Should -Be $b.pts
            $a.duration | Should -Be $b.duration
            $a.stream_index | Should -Be '2'
            $a.pts | Should -Be '100'
            $a.duration | Should -Be '40'
        }
    }
}

Describe 'Read-FFprobePacketSpanMap — formule' {
    BeforeAll {
        $script:SpanProbe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
    }

    It 'calcule max(pts+duration)-min(pts) = 23s, pas la somme des durations' {
        $text = @(
            'stream_index=0|pts=10000|duration=2000'
            'stream_index=0|pts=30000|duration=3000'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $script:SpanProbe -StreamIndices @(0) -Text $text
        $span = $map.Spans[0]
        $span.Measurable | Should -BeTrue
        $span.MinPts | Should -Be 10000
        $span.MaxEnd | Should -Be 33000
        $span.DurationSeconds | Should -Be 23
        $span.DurationSeconds | Should -Not -Be 5
    }

    It 'utilise min/max même si l''ordre PTS n''est pas monotone' {
        $text = @(
            'stream_index=0|pts=200|duration=40'
            'stream_index=0|pts=100|duration=40'
            'stream_index=0|pts=300|duration=40'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $script:SpanProbe -StreamIndices @(0) -Text $text
        $span = $map.Spans[0]
        $span.MinPts | Should -Be 100
        $span.MaxEnd | Should -Be 340
        $span.DurationSeconds | Should -Be ([decimal]'0.24')
    }

    It 'convertit 9000000 ticks en 100s avec time_base 1/90000' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/90000')
        )
        $text = 'stream_index=0|pts=0|duration=9000000'

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].Measurable | Should -BeTrue
        $map.Spans[0].DurationSeconds | Should -Be 100
    }

    It 'donne 100s pour 1/1000 (100000 ticks) et pour 1/90000 (9000000 ticks)' {
        $sourceProbe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $outputProbe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/90000')
        )

        $sourceMap = Invoke-ReadPacketSpanMap -Probe $sourceProbe -StreamIndices @(0) -Text 'stream_index=0|pts=0|duration=100000'
        $outputMap = Invoke-ReadPacketSpanMap -Probe $outputProbe -StreamIndices @(0) -Text 'stream_index=0|pts=0|duration=9000000'

        $sourceMap.Spans[0].DurationSeconds | Should -Be 100
        $outputMap.Spans[0].DurationSeconds | Should -Be 100
        $sourceMap.Spans[0].DurationSeconds | Should -Be $outputMap.Spans[0].DurationSeconds
    }

    It 'calcule le span d''un sous-titre commençant après zéro (1421200 - 6500 ms)' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=6500|duration=2000'
            'stream_index=0|pts=1418200|duration=3000'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].MinPts | Should -Be 6500
        $map.Spans[0].MaxEnd | Should -Be 1421200
        $map.Spans[0].DurationSeconds | Should -Be ([decimal]'1414.7')
    }

    It 'prend la fin de timeline au max(pts+duration), pas au max(pts)' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=5000'
            'stream_index=0|pts=2000|duration=1000'
            'stream_index=0|pts=1000|duration=1000'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $span = $map.Spans[0]
        $span.Measurable | Should -BeTrue
        $span.MinPts | Should -Be 0
        $span.MaxEnd | Should -Be 5000
        $span.DurationSeconds | Should -Be 5
    }

    It 'mesure un PGS par max(pts) alors que duration est toujours N/A' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -TimeBase '1/1000' -CodecName 'hdmv_pgs_subtitle')
        )
        $text = @(
            'stream_index=0|pts=6500|duration=N/A'
            'stream_index=0|pts=1418200|duration=N/A'
            'stream_index=0|pts=20000|duration=0'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $span = $map.Spans[0]
        $span.Measurable | Should -BeTrue
        $span.MinPts | Should -Be 6500
        $span.MaxEnd | Should -Be 1418200
        $span.DurationSeconds | Should -Be ([decimal]'1411.7')
    }
}

Describe 'Read-FFprobePacketSpanMap — agrégation multi-flux' {
    It 'isole min/max par stream_index et ignore un flux non demandé' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'subtitle' -Index 2 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=1|pts=5000|duration=1000'
            'stream_index=2|pts=9000|duration=1000'
            'stream_index=0|pts=2000|duration=1000'
            'stream_index=1|pts=8000|duration=1000'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $text
        $map.Spans.ContainsKey(0) | Should -BeTrue
        $map.Spans.ContainsKey(1) | Should -BeTrue
        $map.Spans.ContainsKey(2) | Should -BeFalse
        $map.Spans[0].MinPts | Should -Be 0
        $map.Spans[0].MaxEnd | Should -Be 3000
        $map.Spans[0].DurationSeconds | Should -Be 3
        $map.Spans[1].MinPts | Should -Be 5000
        $map.Spans[1].MaxEnd | Should -Be 9000
        $map.Spans[1].DurationSeconds | Should -Be 9
    }
}

Describe 'Read-FFprobePacketSpanMap — origine fichier' {
    It 'ancre chaque flux à min(pts) global, pas au min du flux : un sub qui commence à 6.5s garde ce délai' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'subtitle' -Index 1 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1420000'
            'stream_index=1|pts=6500|duration=2000'
            'stream_index=1|pts=1418200|duration=3000'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $text
        $map.Spans[0].DurationSeconds | Should -Be 1420
        $map.Spans[1].MinPts | Should -Be 6500
        $map.Spans[1].MaxEnd | Should -Be 1421200
        $map.Spans[1].DurationSeconds | Should -Be ([decimal]'1421.2')
        $map.Spans[1].DurationSeconds | Should -Not -Be ([decimal]'1414.7')
    }

    It 'neutralise un décalage global identique via fileOrigin' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'subtitle' -Index 1 -TimeBase '1/1000')
        )
        $base = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=2000|duration=1000'
        ) -join [Environment]::NewLine
        $shifted = @(
            'stream_index=0|pts=1000|duration=10000'
            'stream_index=1|pts=3000|duration=1000'
        ) -join [Environment]::NewLine

        $a = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $base
        $b = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $shifted
        $a.Spans[0].DurationSeconds | Should -Be $b.Spans[0].DurationSeconds
        $a.Spans[1].DurationSeconds | Should -Be $b.Spans[1].DurationSeconds
        $a.Spans[0].DurationSeconds | Should -Be 10
        $a.Spans[1].DurationSeconds | Should -Be 3
    }

    It 'détecte un décalage propre à une piste' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'subtitle' -Index 1 -TimeBase '1/1000')
        )
        $source = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=2000|duration=1000'
        ) -join [Environment]::NewLine
        $shiftedSub = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=3000|duration=1000'
        ) -join [Environment]::NewLine

        $a = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $source
        $b = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $shiftedSub
        $a.Spans[0].DurationSeconds | Should -Be $b.Spans[0].DurationSeconds
        $b.Spans[1].DurationSeconds | Should -Be 4
        $a.Spans[1].DurationSeconds | Should -Be 3
    }

    It 'mesure un PGS par max(pts)-fileOrigin quand une vidéo ancre l''origine à 0' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'subtitle' -Index 1 -TimeBase '1/1000' -CodecName 'hdmv_pgs_subtitle')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1420000'
            'stream_index=1|pts=6500|duration=N/A'
            'stream_index=1|pts=1418200|duration=N/A'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $text
        $map.Spans[1].Measurable | Should -BeTrue
        $map.Spans[1].DurationSeconds | Should -Be ([decimal]'1418.2')
    }

    It 'convertit les pts vers une origine commune malgré des time_base distinctes' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/90000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=9000000'
            'stream_index=1|pts=5000|duration=1000'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $text
        $map.Spans[0].DurationSeconds | Should -Be 100
        $map.Spans[1].DurationSeconds | Should -Be 6
    }
}

Describe 'Read-FFprobePacketSpanMap — packets non exploitables' {
    It 'infère end=pts[suivant] si duration inconnue et qu''un Block suit en ordre d''affichage' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=500|duration=0'
            'stream_index=0|pts=800|duration=N/A'
            'stream_index=0|pts=2000|duration=1000'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $span = $map.Spans[0]
        $span.Measurable | Should -BeTrue
        $span.MinPts | Should -Be 0
        $span.MaxEnd | Should -Be 3000
        $span.DurationSeconds | Should -Be 3
    }

    It 'rend le flux non mesurable seulement si le dernier packet en ordre d''affichage a duration inconnue' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=1000|duration=0'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].Measurable | Should -BeFalse
        $map.Spans[0].Reason | Should -Be 'duration-unknown'
    }

    It 'rend le flux non mesurable si duration inconnue est sur le dernier pts, même hors dernier packet muxé' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=3000|duration=N/A'
            'stream_index=0|pts=1000|duration=1000'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].Measurable | Should -BeFalse
        $map.Spans[0].Reason | Should -Be 'duration-unknown'
    }

    It 'au même pts, seul le dernier Block en ordre d''arrivée exige une duration' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -TimeBase '1/1000')
        )
        $okLast = @(
            'stream_index=0|pts=1000|duration=0'
            'stream_index=0|pts=1000|duration=500'
        ) -join [Environment]::NewLine
        $badLast = @(
            'stream_index=0|pts=1000|duration=500'
            'stream_index=0|pts=1000|duration=0'
        ) -join [Environment]::NewLine

        $ok = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $okLast
        $ok.Spans[0].Measurable | Should -BeTrue
        $ok.Spans[0].MaxEnd | Should -Be 1500
        $ok.Spans[0].DurationSeconds | Should -Be ([decimal]'0.5')

        $bad = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $badLast
        $bad.Spans[0].Measurable | Should -BeFalse
        $bad.Spans[0].Reason | Should -Be 'duration-unknown'
    }

    It 'rend le flux non mesurable si pts est N/A' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = 'stream_index=0|pts=N/A|duration=1000'

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].Measurable | Should -BeFalse
    }

    It 'rend le flux non mesurable si time_base est absente ou invalide' {
        $probe = New-MediaProbe -Streams @(
            @{ codec_type = 'video'; index = 0; time_base = 'oops' }
        )
        $text = 'stream_index=0|pts=0|duration=1000'

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].Measurable | Should -BeFalse
    }

    It 'rend le flux non mesurable si time_base est absente' {
        $probe = New-MediaProbe -Streams @(
            @{ codec_type = 'video'; index = 0 }
        )
        $text = 'stream_index=0|pts=0|duration=1000'

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].Measurable | Should -BeFalse
        $map.Spans[0].Reason | Should -Be 'time_base-invalid'
    }
}

Describe 'Test-EncodedFileIntegrity — packet-span' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        $script:TempProbe = @{ format = @{}; streams = @() }
        $script:SourceSpanScan = New-SpanScan
        $script:TempSpanScan = New-SpanScan

        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Remux Get-FFprobePacketSpanMap {
            if ($File -eq $script:SourceFile) {
                return $script:SourceSpanScan
            }
            return $script:TempSpanScan
        }
        Mock -ModuleName Tetram.Media.Remux Write-ErrorLog {}
    }

    It 'ignore stream.duration et le tag DURATION quand les spans packets sont identiques' {
        $source = New-MediaProbe -FormatDuration 10 -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -Duration '10' -DurationTag '00:00:10.000000000')
        )
        $temp = New-MediaProbe -FormatDuration 99 -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -Duration '99' -DurationTag '00:01:39.000000000')
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'packet-span'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 100
    }

    It 'accepte un sous-titre commençant après zéro malgré des tags DURATION divergents' {
        $source = New-MediaProbe -FormatDuration 1421.2 -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'subtitle' -Index 1 -Duration '1421.2' -DurationTag '00:23:41.200000000')
        )
        $temp = New-MediaProbe -FormatDuration 1414.7 -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'subtitle' -Index 1 -Duration '1414.7' -DurationTag '00:23:34.700000000')
        )
        $spanSeconds = [decimal]1414.7
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 1421.2)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds $spanSeconds)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 1421.2)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds $spanSeconds)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceSubtitleIndices @(0)

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'packet-span'
    }

    It 'compare via time_base distinctes une fois converties en secondes' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/90000')
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'ok'
    }

    It 'mismatch si la sortie est plus courte hors tolérance (98.9s vs 100s)' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds ([decimal]'98.9'))
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-span'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be ([decimal]'98.9')
    }

    It 'mismatch si la sortie est plus longue hors tolérance (101.1s vs 100s)' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds ([decimal]'101.1'))
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be ([decimal]'101.1')
    }

    It 'accepte la limite exacte de tolérance (diff == 1s)' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 99)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'ok'
        $result.Diff | Should -Be 1
    }

    It 'applique la même méthode packet-span à la vidéo, l''audio et les sous-titres' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'audio' -Index 1)
            (New-ProbeStream -CodecType 'subtitle' -Index 2)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'audio' -Index 1)
            (New-ProbeStream -CodecType 'subtitle' -Index 2)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 2 -DurationSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 2 -DurationSeconds 100)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0) `
            -KeptSourceSubtitleIndices @(0)

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'packet-span'
    }

    It 'mappe source a:2 -> output a:1 après suppression d''une piste' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'audio' -Index 1)
            (New-ProbeStream -CodecType 'audio' -Index 2)
            (New-ProbeStream -CodecType 'audio' -Index 3)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'audio' -Index 1)
            (New-ProbeStream -CodecType 'audio' -Index 2)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 3 -DurationSeconds 80)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 2 -DurationSeconds 40)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0, 2)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-span'
        $result.StreamType | Should -Be 'audio'
        $result.SourceRelativeIndex | Should -Be 2
        $result.OutputRelativeIndex | Should -Be 1
        $result.Expected | Should -Be 80
        $result.Actual | Should -Be 40
    }

    It 'mappe source s:2 -> output s:1 après suppression d''une piste' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'subtitle' -Index 1)
            (New-ProbeStream -CodecType 'subtitle' -Index 2)
            (New-ProbeStream -CodecType 'subtitle' -Index 3)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'subtitle' -Index 1)
            (New-ProbeStream -CodecType 'subtitle' -Index 2)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 3 -DurationSeconds 80)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 2 -DurationSeconds 40)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceSubtitleIndices @(0, 2)

        $result.Status | Should -Be 'mismatch'
        $result.StreamType | Should -Be 'subtitle'
        $result.SourceRelativeIndex | Should -Be 2
        $result.OutputRelativeIndex | Should -Be 1
        $result.Expected | Should -Be 80
        $result.Actual | Should -Be 40
    }

    It 'mismatch si un flux conservé est absent de la sortie' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'audio' -Index 1)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.StreamType | Should -Be 'audio'
        $result.Actual | Should -BeNullOrEmpty
        $result.Reason | Should -Be 'output-stream-missing'
    }

    It 'ne laisse pas un flux source unknown masquer un mismatch ultérieur' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'audio' -Index 1)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'audio' -Index 1)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -Unmeasurable)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds 90)
        )

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.StreamType | Should -Be 'audio'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 90
    }

    It 'mismatch si la sortie n''est plus mesurable alors que la source l''est' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -Unmeasurable)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-span'
        $result.Expected | Should -Be 100
        $result.Actual | Should -BeNullOrEmpty
        $result.Reason | Should -Be 'no-packets'
    }

    It 'unknown si le scan packet-level source échoue' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Failed
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'unknown'
        $result.Reason | Should -Be 'ffprobe-failed'
    }

    It 'mismatch si le scan packet-level sortie échoue' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Failed

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-probe'
        $result.Reason | Should -Be 'ffprobe-failed'
    }

    It 'n''appelle le scan packet-level qu''une fois par fichier malgré plusieurs types de flux' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'video' -Index 1)
            (New-ProbeStream -CodecType 'audio' -Index 2)
            (New-ProbeStream -CodecType 'audio' -Index 3)
            (New-ProbeStream -CodecType 'subtitle' -Index 4)
            (New-ProbeStream -CodecType 'subtitle' -Index 5)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
            (New-ProbeStream -CodecType 'video' -Index 1)
            (New-ProbeStream -CodecType 'audio' -Index 2)
            (New-ProbeStream -CodecType 'audio' -Index 3)
            (New-ProbeStream -CodecType 'subtitle' -Index 4)
            (New-ProbeStream -CodecType 'subtitle' -Index 5)
        )
        $entries = @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 1 -DurationSeconds 80)
            (New-SpanEntry -StreamIndex 2 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 3 -DurationSeconds 100)
            (New-SpanEntry -StreamIndex 4 -DurationSeconds 90)
            (New-SpanEntry -StreamIndex 5 -DurationSeconds 90)
        )
        $script:SourceSpanScan = New-SpanScan -Entries $entries
        $script:TempSpanScan = New-SpanScan -Entries $entries

        $result = Invoke-IntegrityCheck `
            -SourceProbe $source `
            -TempProbe $temp `
            -KeptSourceVideoIndices @(0, 1) `
            -KeptSourceAudioIndices @(0, 1) `
            -KeptSourceSubtitleIndices @(0, 1)

        $result.Status | Should -Be 'ok'
        Should -Invoke -ModuleName Tetram.Media.Remux Get-FFprobePacketSpanMap -Times 2
        Should -Invoke -ModuleName Tetram.Media.Remux Get-FFprobePacketSpanMap -Times 1 -ParameterFilter {
            $File -eq $script:SourceFile
        }
        Should -Invoke -ModuleName Tetram.Media.Remux Get-FFprobePacketSpanMap -Times 1 -ParameterFilter {
            $File -eq $script:TempFile
        }
    }

    It 'mismatch probe si la sortie ne peut pas être sondée en metadata' {
        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson { $null }
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'probe'
    }

    It 'ne conclut pas ok s''il n''y a aucun flux temporel conservé' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -Duration '100')
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -Duration '100')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'unknown'
    }
}

Describe 'Get-FFprobePacketSpanMap — contrat scanner' {
    It 'expose les arguments ffprobe packet-span sans -show_data ni -select_streams' {
        InModuleScope 'Tetram.Media.Mkv' {
            $args = Get-FFprobePacketSpanArgumentList -File 'C:\media\film.mkv'
            $args | Should -Be @(
                '-v', 'error',
                '-show_packets',
                '-show_entries', 'packet=stream_index,pts,duration',
                '-of', 'compact=p=0:nk=0',
                'C:\media\film.mkv'
            )
        }
    }

    It 'jette un scan partiel lorsque le code de sortie ffprobe est non nul' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = 'stream_index=0|pts=0|duration=1000'
        $validMap = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $validMap.ScanFailed | Should -BeFalse

        $bound = @{ Map = $validMap }
        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param($Map)
            Mock -ModuleName Tetram.Media.Remux Write-ErrorLog {}
            $failed = Select-FFprobePacketSpanScanResult -Map $Map -ExitCode 1 -StdErr 'ffprobe: Invalid data'
            $failed.ScanFailed | Should -BeTrue
            $failed.Reason | Should -Be 'ffprobe-failed'
            $failed.Spans.Count | Should -Be 0
            Should -Invoke -ModuleName Tetram.Media.Remux Write-ErrorLog -Times 1 -ParameterFilter { $Text -eq 'ffprobe: Invalid data' }
        }
    }

    It 'conserve le scan lorsque le code de sortie est 0' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $validMap = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text 'stream_index=0|pts=0|duration=1000'
        $bound = @{ Map = $validMap }
        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param($Map)
            $kept = Select-FFprobePacketSpanScanResult -Map $Map -ExitCode 0 -StdErr ''
            $kept.ScanFailed | Should -BeFalse
            $kept.Spans[0].DurationSeconds | Should -Be 1
        }
    }

    It 'ne lance pas ffprobe quand aucun indice n''est demandé' {
        $probe = New-MediaProbe -Streams @()
        $bound = @{ Probe = $probe }
        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param($Probe)
            $map = Get-FFprobePacketSpanMap -FFPROBE 'this-must-not-start.exe' -File 'whatever.mkv' -Probe $Probe -StreamIndices @()
            $map.ScanFailed | Should -BeFalse
            $map.Spans.Count | Should -Be 0
        }
    }

    It 'échoue si le fichier est absent' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $missing = Join-Path $TestDrive 'missing-media.mkv'
        $bound = @{ Probe = $probe; File = $missing }
        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param($Probe, $File)
            $map = Get-FFprobePacketSpanMap -FFPROBE 'ffprobe' -File $File -Probe $Probe -StreamIndices @(0)
            $map.ScanFailed | Should -BeTrue
            $map.Reason | Should -Be 'ffprobe-failed'
        }
    }
}
