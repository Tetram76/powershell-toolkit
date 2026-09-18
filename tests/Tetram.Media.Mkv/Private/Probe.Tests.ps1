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
            [string] $FormatName,
            [object[]] $Streams = @()
        )

        $probe = @{
            streams = @($Streams)
        }
        $format = @{}
        if ($PSBoundParameters.ContainsKey('FormatDuration')) {
            $format['duration'] = [string]$FormatDuration
        }
        if ($PSBoundParameters.ContainsKey('FormatName')) {
            $format['format_name'] = $FormatName
        }
        $probe['format'] = $format
        $probe
    }

    function script:New-SpanEntry {
        param(
            [Parameter(Mandatory)] [int] $StreamIndex,
            [decimal] $DurationSeconds,
            [switch] $Unmeasurable,
            [string] $Reason = 'no-packets',
            [switch] $EndFromPtsOnly,
            [switch] $ExactUnavailable,
            [switch] $PtsUnavailable,
            [decimal] $ExactExtentSeconds,
            [decimal] $PtsExtentSeconds,
            [decimal] $StartSeconds = 0
        )

        $entry = [pscustomobject]@{
            StreamIndex          = $StreamIndex
            EndFromPtsOnly       = [bool]$EndFromPtsOnly
            ExactMetricAvailable = $false
            PtsMetricAvailable   = $false
            ExactExtentSeconds   = $null
            PtsExtentSeconds     = $null
            StartSeconds         = $null
            HasValidTimeBase     = $false
            HasPtsSample         = $false
            HasUnavailablePts    = $false
            Measurable           = $false
            DurationSeconds      = $null
            MinPts               = $null
            MaxPts               = $null
            MaxKnownEnd          = $null
            PacketCount          = 0
            Reason               = $Reason
        }

        if ($Unmeasurable) {
            if ($Reason -eq 'pts-unavailable') {
                $entry.HasUnavailablePts = $true
            }
            return $entry
        }

        $exactValue = $null
        if ($PSBoundParameters.ContainsKey('ExactExtentSeconds')) {
            $exactValue = $ExactExtentSeconds
        }
        elseif ($PSBoundParameters.ContainsKey('DurationSeconds')) {
            $exactValue = $DurationSeconds
        }

        $ptsValue = $null
        if ($PSBoundParameters.ContainsKey('PtsExtentSeconds')) {
            $ptsValue = $PtsExtentSeconds
        }
        elseif ($PSBoundParameters.ContainsKey('DurationSeconds')) {
            $ptsValue = $DurationSeconds
        }

        if (-not $ExactUnavailable -and $null -ne $exactValue) {
            $entry.ExactMetricAvailable = $true
            $entry.ExactExtentSeconds = $exactValue
        }
        if (-not $PtsUnavailable -and $null -ne $ptsValue) {
            $entry.PtsMetricAvailable = $true
            $entry.PtsExtentSeconds = $ptsValue
        }
        $entry.Measurable = $entry.ExactMetricAvailable -or $entry.PtsMetricAvailable
        if ($entry.ExactMetricAvailable) {
            $entry.DurationSeconds = $entry.ExactExtentSeconds
        }
        elseif ($entry.PtsMetricAvailable) {
            $entry.DurationSeconds = $entry.PtsExtentSeconds
        }
        $entry.HasValidTimeBase = $true
        $entry.HasPtsSample = $true
        $entry.HasUnavailablePts = $false
        $entry.StartSeconds = $StartSeconds
        $entry.PacketCount = 1
        $entry.Reason = $(if ($PSBoundParameters.ContainsKey('Reason')) { $Reason } else { $null })
        $entry
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
            [int[]] $KeptSourceSubtitleIndices,
            [double] $OffsetToleranceSeconds
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
        if ($PSBoundParameters.ContainsKey('OffsetToleranceSeconds')) {
            $bound['OffsetToleranceSeconds'] = $OffsetToleranceSeconds
        }

        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param(
                $SourceProbe,
                $SourceFile,
                $TempFile,
                $KeptSourceVideoIndices,
                $KeptSourceAudioIndices,
                $KeptSourceSubtitleIndices,
                $OffsetToleranceSeconds
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
            if ($PSBoundParameters.ContainsKey('OffsetToleranceSeconds')) {
                $integrityParams['OffsetToleranceSeconds'] = $OffsetToleranceSeconds
            }

            Test-EncodedFileIntegrity @integrityParams
        }
    }
}

Describe 'Test-FFprobeMatroskaFormat' {
    It 'reconnaît le démuxer FFmpeg matroska,webm' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @()
        $bound = @{ Probe = $probe }
        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param($Probe)
            Test-FFprobeMatroskaFormat -Probe $Probe | Should -BeTrue
        }
    }

    It 'refuse un format_name inconnu, absent, ou une extension .mkv' {
        $unknown = New-MediaProbe -FormatName 'mpegts' -Streams @()
        $absent = New-MediaProbe -Streams @()
        $nullProbe = $null
        $bound = @{ Unknown = $unknown; Absent = $absent; NullProbe = $nullProbe }
        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param($Unknown, $Absent, $NullProbe)
            Test-FFprobeMatroskaFormat -Probe $Unknown | Should -BeFalse
            Test-FFprobeMatroskaFormat -Probe $Absent | Should -BeFalse
            Test-FFprobeMatroskaFormat -Probe $NullProbe | Should -BeFalse
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
        $span.ExactMetricAvailable | Should -BeTrue
        $span.MinPts | Should -Be 10000
        $span.MaxKnownEnd | Should -Be 33000
        $span.ExactExtentSeconds | Should -Be 23
        $span.PtsExtentSeconds | Should -Be 20
        $span.ExactExtentSeconds | Should -Not -Be 5
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
        $span.MaxKnownEnd | Should -Be 340
        $span.ExactExtentSeconds | Should -Be ([decimal]'0.24')
    }

    It 'convertit 9000000 ticks en 100s avec time_base 1/90000' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/90000')
        )
        $text = 'stream_index=0|pts=0|duration=9000000'

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].ExactMetricAvailable | Should -BeTrue
        $map.Spans[0].ExactExtentSeconds | Should -Be 100
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

        $sourceMap.Spans[0].ExactExtentSeconds | Should -Be 100
        $outputMap.Spans[0].ExactExtentSeconds | Should -Be 100
        $sourceMap.Spans[0].ExactExtentSeconds | Should -Be $outputMap.Spans[0].ExactExtentSeconds
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
        $map.Spans[0].MaxKnownEnd | Should -Be 1421200
        $map.Spans[0].ExactExtentSeconds | Should -Be ([decimal]'1414.7')
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
        $span.ExactMetricAvailable | Should -BeTrue
        $span.MinPts | Should -Be 0
        $span.MaxKnownEnd | Should -Be 5000
        $span.ExactExtentSeconds | Should -Be 5
        $span.PtsExtentSeconds | Should -Be 2
    }

    It 'mesure un PGS par max(pts) sans dépendre de packet.duration (duration N/A)' {
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
        $span.ExactMetricAvailable | Should -BeFalse
        $span.PtsMetricAvailable | Should -BeTrue
        $span.MinPts | Should -Be 6500
        $span.MaxPts | Should -Be 1418200
        $span.PtsExtentSeconds | Should -Be ([decimal]'1411.7')
    }

    It 'mesure un PGS par max(pts) même lorsque packet.duration est positive' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -TimeBase '1/1000' -CodecName 'hdmv_pgs_subtitle')
        )
        $text = @(
            'stream_index=0|pts=6500|duration=2000'
            'stream_index=0|pts=1418200|duration=3000'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $span = $map.Spans[0]
        $span.ExactMetricAvailable | Should -BeFalse
        $span.PtsMetricAvailable | Should -BeTrue
        $span.MaxPts | Should -Be 1418200
        $span.PtsExtentSeconds | Should -Be ([decimal]'1411.7')
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
        $map.Spans[0].MaxKnownEnd | Should -Be 3000
        $map.Spans[0].ExactExtentSeconds | Should -Be 3
        $map.Spans[1].MinPts | Should -Be 5000
        $map.Spans[1].MaxKnownEnd | Should -Be 9000
        $map.Spans[1].ExactExtentSeconds | Should -Be 4
    }
}

Describe 'Read-FFprobePacketSpanMap — durée propre' {
    It 'mesure la durée du sub depuis son propre min(pts), pas depuis le début fichier' {
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
        $map.Spans[0].ExactExtentSeconds | Should -Be 1420
        $map.Spans[1].MinPts | Should -Be 6500
        $map.Spans[1].MaxKnownEnd | Should -Be 1421200
        $map.Spans[1].StartSeconds | Should -Be ([decimal]'6.5')
        $map.Spans[1].ExactExtentSeconds | Should -Be ([decimal]'1414.7')
        $map.Spans[1].ExactExtentSeconds | Should -Not -Be ([decimal]'1421.2')
    }

    It 'conserve les durées propres après une translation globale des timestamps' {
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
        $a.Spans[0].ExactExtentSeconds | Should -Be $b.Spans[0].ExactExtentSeconds
        $a.Spans[1].ExactExtentSeconds | Should -Be $b.Spans[1].ExactExtentSeconds
        $a.Spans[0].ExactExtentSeconds | Should -Be 10
        $a.Spans[1].ExactExtentSeconds | Should -Be 1
        $a.Spans[0].StartSeconds | Should -Be 0
        $b.Spans[0].StartSeconds | Should -Be 1
        $a.Spans[1].StartSeconds | Should -Be 2
        $b.Spans[1].StartSeconds | Should -Be 3
    }

    It 'ne change pas la durée propre quand seule la piste est décalée' {
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
        $a.Spans[0].ExactExtentSeconds | Should -Be $b.Spans[0].ExactExtentSeconds
        $a.Spans[1].ExactExtentSeconds | Should -Be 1
        $b.Spans[1].ExactExtentSeconds | Should -Be 1
        $a.Spans[1].StartSeconds | Should -Be 2
        $b.Spans[1].StartSeconds | Should -Be 3
    }

    It 'mesure un PGS par max(pts)-min(pts) du flux même si une vidéo commence à 0' {
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
        $map.Spans[1].PtsMetricAvailable | Should -BeTrue
        $map.Spans[1].StartSeconds | Should -Be ([decimal]'6.5')
        $map.Spans[1].PtsExtentSeconds | Should -Be ([decimal]'1411.7')
        $map.Spans[1].ExactMetricAvailable | Should -BeFalse
    }

    It 'convertit chaque flux avec sa time_base sans soustraire des ticks d''une autre piste' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/90000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=9000000'
            'stream_index=1|pts=5000|duration=1000'
        ) -join [Environment]::NewLine

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $text
        $map.Spans[0].ExactExtentSeconds | Should -Be 100
        $map.Spans[1].StartSeconds | Should -Be 5
        $map.Spans[1].ExactExtentSeconds | Should -Be 1
    }
}

Describe 'Read-FFprobePacketSpanMap — métriques exacte et PTS' {
    It 'source Matroska, durations connues : métrique exacte = max(pts+duration)-min(pts) du flux' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=10000|duration=2000'
            'stream_index=0|pts=30000|duration=3000'
        ) -join [Environment]::NewLine

        $span = (Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text).Spans[0]
        $span.ExactMetricAvailable | Should -BeTrue
        $span.PtsMetricAvailable | Should -BeTrue
        $span.ExactExtentSeconds | Should -Be 23
        $span.PtsExtentSeconds | Should -Be 20
        $span.ExactExtentSeconds | Should -Not -Be 5
    }

    It 'source Matroska : duration=0 intermédiaire conserve la métrique exacte (RFC 9559, pas next_pts hors Matroska)' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=500|duration=0'
            'stream_index=0|pts=800|duration=N/A'
            'stream_index=0|pts=2000|duration=1000'
        ) -join [Environment]::NewLine

        $span = (Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text).Spans[0]
        $span.ExactMetricAvailable | Should -BeTrue
        $span.PtsMetricAvailable | Should -BeTrue
        $span.MinPts | Should -Be 0
        $span.MaxKnownEnd | Should -Be 3000
        $span.ExactExtentSeconds | Should -Be 3
        $span.PtsExtentSeconds | Should -Be 2
    }

    It 'source Matroska : dernier Block sans durée → exact indisponible, PTS disponible' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=1000|duration=0'
        ) -join [Environment]::NewLine

        $span = (Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text).Spans[0]
        $span.ExactMetricAvailable | Should -BeFalse
        $span.PtsMetricAvailable | Should -BeTrue
        $span.PtsExtentSeconds | Should -Be 1
        $span.Reason | Should -Be 'duration-unknown'
    }

    It 'source Matroska : duration inconnue sur le max PTS, même hors dernier packet muxé → exact indisponible' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=3000|duration=N/A'
            'stream_index=0|pts=1000|duration=1000'
        ) -join [Environment]::NewLine

        $span = (Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text).Spans[0]
        $span.ExactMetricAvailable | Should -BeFalse
        $span.PtsMetricAvailable | Should -BeTrue
        $span.PtsExtentSeconds | Should -Be 3
        $span.Reason | Should -Be 'duration-unknown'
    }

    It 'source Matroska : duration inconnue au maxPTS commun rend l''exact indisponible, quel que soit l''ordre des lignes' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -TimeBase '1/1000')
        )
        $unknownThenKnown = @(
            'stream_index=0|pts=1000|duration=0'
            'stream_index=0|pts=1000|duration=500'
        ) -join [Environment]::NewLine
        $knownThenUnknown = @(
            'stream_index=0|pts=1000|duration=500'
            'stream_index=0|pts=1000|duration=0'
        ) -join [Environment]::NewLine

        foreach ($text in @($unknownThenKnown, $knownThenUnknown)) {
            $span = (Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text).Spans[0]
            $span.ExactMetricAvailable | Should -BeFalse
            $span.PtsMetricAvailable | Should -BeTrue
            $span.Reason | Should -Be 'duration-unknown'
        }
    }

    It 'source Matroska : deux durations connues au même maxPTS restent exact-mesurables' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=1000|duration=500'
            'stream_index=0|pts=1000|duration=300'
        ) -join [Environment]::NewLine

        $span = (Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text).Spans[0]
        $span.ExactMetricAvailable | Should -BeTrue
        $span.PtsMetricAvailable | Should -BeTrue
        $span.MaxKnownEnd | Should -Be 1500
        $span.ExactExtentSeconds | Should -Be ([decimal]'0.5')
        $span.Reason | Should -BeNullOrEmpty
    }

    It 'source non-Matroska, durations connues : métrique exacte disponible' {
        $probe = New-MediaProbe -FormatName 'mpegts' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=2000|duration=1000'
        ) -join [Environment]::NewLine

        $span = (Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text).Spans[0]
        $span.ExactMetricAvailable | Should -BeTrue
        $span.PtsMetricAvailable | Should -BeTrue
        $span.ExactExtentSeconds | Should -Be 3
        $span.PtsExtentSeconds | Should -Be 2
    }

    It 'source non-Matroska : duration=0 intermédiaire n''applique pas la sémantique Matroska' {
        $probe = New-MediaProbe -FormatName 'mpegts' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=500|duration=0'
            'stream_index=0|pts=2000|duration=1000'
        ) -join [Environment]::NewLine

        $span = (Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text).Spans[0]
        $span.ExactMetricAvailable | Should -BeFalse
        $span.PtsMetricAvailable | Should -BeTrue
        $span.PtsExtentSeconds | Should -Be 2
        $span.Reason | Should -Be 'duration-unknown'
    }

    It 'source non-Matroska : dernier duration=0 → fallback PTS uniquement' {
        $probe = New-MediaProbe -FormatName 'mp4' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=1000|duration=0'
        ) -join [Environment]::NewLine

        $span = (Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text).Spans[0]
        $span.ExactMetricAvailable | Should -BeFalse
        $span.PtsMetricAvailable | Should -BeTrue
        $span.PtsExtentSeconds | Should -Be 1
    }

    It 'format_name absent ou inconnu : comportement conservateur non-Matroska' {
        $text = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=500|duration=0'
            'stream_index=0|pts=2000|duration=1000'
        ) -join [Environment]::NewLine
        $streams = @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )

        foreach ($probe in @(
                (New-MediaProbe -Streams $streams),
                (New-MediaProbe -FormatName 'avi' -Streams $streams)
            )) {
            $span = (Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text).Spans[0]
            $span.ExactMetricAvailable | Should -BeFalse
            $span.PtsMetricAvailable | Should -BeTrue
            $span.PtsExtentSeconds | Should -Be 2
        }
    }
}

Describe 'Read-FFprobePacketSpanMap — packets non exploitables' {

    It 'rend le flux non mesurable si pts est N/A' {
        $probe = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $text = 'stream_index=0|pts=N/A|duration=1000'

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].ExactMetricAvailable | Should -BeFalse
        $map.Spans[0].PtsMetricAvailable | Should -BeFalse
        $map.Spans[0].Measurable | Should -BeFalse
    }

    It 'rend le flux non mesurable si time_base est absente ou invalide' {
        $probe = New-MediaProbe -Streams @(
            @{ codec_type = 'video'; index = 0; time_base = 'oops' }
        )
        $text = 'stream_index=0|pts=0|duration=1000'

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].ExactMetricAvailable | Should -BeFalse
        $map.Spans[0].PtsMetricAvailable | Should -BeFalse
        $map.Spans[0].Measurable | Should -BeFalse
    }

    It 'rend le flux non mesurable si time_base est absente' {
        $probe = New-MediaProbe -Streams @(
            @{ codec_type = 'video'; index = 0 }
        )
        $text = 'stream_index=0|pts=0|duration=1000'

        $map = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $text
        $map.Spans[0].ExactMetricAvailable | Should -BeFalse
        $map.Spans[0].PtsMetricAvailable | Should -BeFalse
        $map.Spans[0].Measurable | Should -BeFalse
        $map.Spans[0].Reason | Should -Be 'time_base-invalid'
    }
}

Describe 'Get-PacketSpanReliableStartSeconds' {
    It 'refuse un flux HasUnavailablePts même si MinPts est déjà observé' {
        $span = [pscustomobject]@{
            HasValidTimeBase      = $true
            HasPtsSample          = $true
            HasUnavailablePts     = $true
            StartSeconds          = [decimal]3
            MinPts                = 3000
            TimeBaseNumerator     = 1
            TimeBaseDenominator   = 1000
        }
        $bound = @{ Span = $span }
        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param($Span)
            Get-PacketSpanReliableStartSeconds -Span $Span | Should -BeNullOrEmpty
        }
    }

    It 'accepte un flux dont tous les PTS sont exploitables, même sans Exact' {
        $span = [pscustomobject]@{
            HasValidTimeBase     = $true
            HasPtsSample         = $true
            HasUnavailablePts    = $false
            ExactMetricAvailable = $false
            PtsMetricAvailable   = $true
            StartSeconds         = [decimal]5
        }
        $bound = @{ Span = $span }
        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param($Span)
            Get-PacketSpanReliableStartSeconds -Span $Span | Should -Be ([decimal]5)
        }
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
        $result.Method | Should -Be 'packet-end-span'
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
        $result.Method | Should -Be 'packet-end-span'
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
        $result.Method | Should -Be 'packet-end-span'
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
        $result.Method | Should -Be 'packet-end-span'
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
        $result.Method | Should -Be 'packet-end-span'
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

    It 'source Exact / sortie Exact indisponible : mismatch, pas de fallback PTS' {
        $source = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactExtentSeconds 3 -PtsExtentSeconds 2)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactUnavailable -PtsExtentSeconds 2 -Reason 'duration-unknown')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-span'
        $result.Reason | Should -Be 'duration-unknown'
        $result.Expected | Should -Be 3
        $result.Actual | Should -BeNullOrEmpty
    }

    It 'source exact indisponible / sortie exact disponible / PTS des deux côtés : PTS↔PTS' {
        $source = New-MediaProbe -FormatName 'mpegts' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactUnavailable -PtsExtentSeconds 2)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactExtentSeconds 10 -PtsExtentSeconds 2)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'packet-pts-span'
        $result.Expected | Should -Be 2
        $result.Actual | Should -Be 2
    }

    It 'source Exact 110 / sortie PTS 100 seulement : la perte de duration terminale n''est plus masquée' {
        $source = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactExtentSeconds 110 -PtsExtentSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactUnavailable -PtsExtentSeconds 100 -Reason 'duration-unknown')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-span'
        $result.Reason | Should -Be 'duration-unknown'
        $result.Expected | Should -Be 110
        $result.Actual | Should -BeNullOrEmpty
    }

    It 'cas C depuis les lignes ffprobe : source Exact / sortie dernier duration=N/A → mismatch' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=100000|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=100000|duration=N/A'
        ) -join [Environment]::NewLine

        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0)

        $script:SourceSpanScan.Spans[0].ExactMetricAvailable | Should -BeTrue
        $script:TempSpanScan.Spans[0].ExactMetricAvailable | Should -BeFalse
        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-span'
        $result.Reason | Should -Be 'duration-unknown'
        $result.Expected | Should -Be 110
        $result.Actual | Should -BeNullOrEmpty
    }

    It 'un PTS N/A audio source ne rejette pas une vidéo inchangée : unknown local, durée vidéo 10 s' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'audio' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'video' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=N/A|duration=1000'
            'stream_index=0|pts=3000|duration=1000'
            'stream_index=1|pts=5000|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=3000|duration=1000'
            'stream_index=1|pts=5000|duration=10000'
        ) -join [Environment]::NewLine

        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck `
            -SourceProbe $probe `
            -TempProbe $probe `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0)

        $script:SourceSpanScan.Spans[1].ExactExtentSeconds | Should -Be $script:TempSpanScan.Spans[1].ExactExtentSeconds
        $script:SourceSpanScan.Spans[1].ExactExtentSeconds | Should -Be 10
        $result.Status | Should -Not -Be 'mismatch'
        $result.Status | Should -Be 'unknown'
    }

    It 'un audio source sans aucun PTS n''impose pas l''origine audio de la sortie' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'audio' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'video' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=N/A|duration=1000'
            'stream_index=1|pts=5000|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=1|pts=5000|duration=10000'
        ) -join [Environment]::NewLine

        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck `
            -SourceProbe $probe `
            -TempProbe $probe `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0)

        $script:SourceSpanScan.Spans[1].ExactExtentSeconds | Should -Be $script:TempSpanScan.Spans[1].ExactExtentSeconds
        $script:SourceSpanScan.Spans[1].ExactExtentSeconds | Should -Be 10
        $result.Status | Should -Not -Be 'mismatch'
        $result.Status | Should -Be 'unknown'
    }

    It 'fallback PTS avec sortie tronquée : mismatch' {
        $source = New-MediaProbe -FormatName 'mpegts' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactUnavailable -PtsExtentSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactUnavailable -PtsExtentSeconds 90)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-pts-span'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 90
    }

    It 'fallback PTS avec sortie allongée hors tolérance : mismatch' {
        $source = New-MediaProbe -FormatName 'mpegts' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactUnavailable -PtsExtentSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactUnavailable -PtsExtentSeconds ([decimal]'101.1'))
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-pts-span'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be ([decimal]'101.1')
    }

    It 'PGS : compare packet-pts-span même si une duration exacte est disponible des deux côtés' {
        $source = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -CodecName 'hdmv_pgs_subtitle')
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -CodecName 'hdmv_pgs_subtitle')
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -EndFromPtsOnly -ExactExtentSeconds 110 -PtsExtentSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -EndFromPtsOnly -ExactExtentSeconds 110 -PtsExtentSeconds 100)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceSubtitleIndices @(0)

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'packet-pts-span'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 100
    }

    It 'PGS : compare maxPTS-fileOrigin sans dépendre de duration' {
        $source = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -CodecName 'hdmv_pgs_subtitle')
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -CodecName 'hdmv_pgs_subtitle')
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -EndFromPtsOnly -ExactUnavailable -PtsExtentSeconds ([decimal]'1411.7'))
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -EndFromPtsOnly -ExactUnavailable -PtsExtentSeconds ([decimal]'1411.7'))
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceSubtitleIndices @(0)

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'packet-pts-span'
        $result.Expected | Should -Be ([decimal]'1411.7')
        $result.Actual | Should -Be ([decimal]'1411.7')
    }

    It 'PGS tronqué : recul de maxPTS détecté' {
        $source = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -CodecName 'hdmv_pgs_subtitle')
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'subtitle' -Index 0 -CodecName 'hdmv_pgs_subtitle')
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -EndFromPtsOnly -ExactUnavailable -PtsExtentSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -EndFromPtsOnly -ExactUnavailable -PtsExtentSeconds 90)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceSubtitleIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-pts-span'
        $result.Expected | Should -Be 100
        $result.Actual | Should -Be 90
    }

    It 'PTS N/A sur un packet source : unknown' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -Unmeasurable -Reason 'pts-unavailable')
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'unknown'
    }

    It 'source PTS seulement / sortie PTS indisponible : mismatch' {
        $source = New-MediaProbe -FormatName 'mpegts' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -ExactUnavailable -PtsExtentSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -Unmeasurable -Reason 'pts-unavailable')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Expected | Should -Be 100
        $result.Actual | Should -BeNullOrEmpty
    }

    It 'PTS N/A sur la sortie alors que la source est mesurable : mismatch' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $temp = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0)
        )
        $script:SourceSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -DurationSeconds 100)
        )
        $script:TempSpanScan = New-SpanScan -Entries @(
            (New-SpanEntry -StreamIndex 0 -Unmeasurable -Reason 'pts-unavailable')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Expected | Should -Be 100
        $result.Actual | Should -BeNullOrEmpty
        $result.Reason | Should -Be 'pts-unavailable'
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

Describe 'Test-EncodedFileIntegrity — durées propres et décalages' {
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

    It 'coupe de début audio : mismatch de durée (10 s vs 7 s)' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=0|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=3000|duration=7000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-end-span'
        $result.StreamType | Should -Be 'audio'
        $result.Expected | Should -Be 10
        $result.Actual | Should -Be 7
    }

    It 'coupe de début sans perte de durée : mismatch de décalage 0 → 3 s' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=0|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=3000|duration=10000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck `
            -SourceProbe $probe `
            -TempProbe $probe `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0) `
            -OffsetToleranceSeconds 1

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-offset'
        $result.Expected | Should -Be 0
        $result.Actual | Should -Be 3
        $result.Diff | Should -Be 3
        $result.StreamType | Should -Be 'video'
        $result.OtherStreamType | Should -Be 'audio'
    }

    It 'coupe de fin : mismatch de durée' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=0|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=0|duration=7000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-end-span'
        $result.StreamType | Should -Be 'audio'
        $result.Expected | Should -Be 10
        $result.Actual | Should -Be 7
    }

    It 'déplace une piste de +5 s sur 2 h sans changer les durées : mismatch d''offset, pas la tolérance 36 s' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=7200000'
            'stream_index=1|pts=0|duration=7200000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=7200000'
            'stream_index=1|pts=5000|duration=7200000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $script:SourceSpanScan.Spans[1].ExactExtentSeconds | Should -Be 7200
        $script:TempSpanScan.Spans[1].ExactExtentSeconds | Should -Be 7200
        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-offset'
        $result.Diff | Should -Be 5
    }

    It 'accepte une translation globale qui conserve durées et décalage' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=10000|duration=10000'
            'stream_index=1|pts=13000|duration=7000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=3000|duration=7000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'ok'
    }

    It 'calcule la tolérance de durée d''une piste tardive sur sa durée propre' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'subtitle' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=1420000'
            'stream_index=1|pts=1000000|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=1420000'
            'stream_index=1|pts=1000000|duration=8500'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceSubtitleIndices @(0)

        $script:SourceSpanScan.Spans[1].StartSeconds | Should -Be 1000
        $script:SourceSpanScan.Spans[1].ExactExtentSeconds | Should -Be 10
        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-end-span'
        $result.StreamType | Should -Be 'subtitle'
        $result.Expected | Should -Be 10
        $result.Actual | Should -Be ([decimal]'8.5')
    }

    It 'un seul flux translaté reste ok sans exiger un second flux' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
        )
        $sourceText = 'stream_index=0|pts=10000|duration=10000'
        $outputText = 'stream_index=0|pts=0|duration=10000'
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0)

        $result.Status | Should -Be 'ok'
    }

    It 'compare en secondes des débuts négatifs et des time_base distinctes' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/90000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=-90000|duration=900000'
            'stream_index=1|pts=2000|duration=8000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=900000'
            'stream_index=1|pts=3000|duration=8000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $script:SourceSpanScan.Spans[0].StartSeconds | Should -Be ([decimal]-1)
        $script:TempSpanScan.Spans[1].StartSeconds | Should -Be 3
        $result.Status | Should -Be 'ok'
    }

    It 'audio source fiable devenu PTS manquant en sortie : mismatch audio, pas un écart vidéo artificiel' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=0|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=N/A|duration=10000'
            'stream_index=1|pts=0|duration=10000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.StreamType | Should -Be 'audio'
        $result.StreamType | Should -Not -Be 'video'
    }

    It 'unknown audio ne masque pas un décalage entre deux pistes fiables' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'audio' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'video' -Index 1 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'subtitle' -Index 2 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=N/A|duration=1000'
            'stream_index=0|pts=3000|duration=1000'
            'stream_index=1|pts=0|duration=10000'
            'stream_index=2|pts=2000|duration=1000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=1|pts=0|duration=10000'
            'stream_index=2|pts=5000|duration=1000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1, 2) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1, 2) -Text $outputText

        $result = Invoke-IntegrityCheck `
            -SourceProbe $probe `
            -TempProbe $probe `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0) `
            -KeptSourceSubtitleIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-offset'
    }

    It 'unknown audio ne masque pas une durée incorrecte sur une autre piste' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'audio' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'video' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=N/A|duration=1000'
            'stream_index=1|pts=0|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=1|pts=0|duration=7000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-end-span'
        $result.StreamType | Should -Be 'video'
        $result.Expected | Should -Be 10
        $result.Actual | Should -Be 7
    }

    It 'un flux sans borne exacte reste utilisable pour comparer les décalages' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=10000|duration=N/A'
            'stream_index=1|pts=0|duration=1000'
            'stream_index=1|pts=10000|duration=N/A'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=1000'
            'stream_index=0|pts=10000|duration=N/A'
            'stream_index=1|pts=3000|duration=1000'
            'stream_index=1|pts=13000|duration=N/A'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $script:SourceSpanScan.Spans[0].ExactMetricAvailable | Should -BeFalse
        $script:SourceSpanScan.Spans[0].PtsMetricAvailable | Should -BeTrue
        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-offset'
        $result.Diff | Should -Be 3
    }

    It 'applique 0,1 s par défaut : 100 ms accepté, 101 ms rejeté' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=0|duration=10000'
        ) -join [Environment]::NewLine
        $okText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=100|duration=10000'
        ) -join [Environment]::NewLine
        $badText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=101|duration=10000'
        ) -join [Environment]::NewLine

        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $okText
        $ok = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $badText
        $bad = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $ok.Status | Should -Be 'ok'
        $bad.Status | Should -Be 'mismatch'
        $bad.Method | Should -Be 'packet-offset'
        $bad.Diff | Should -Be ([decimal]'0.101')
    }

    It 'applique une tolérance d''offset explicite et conserve le signe des décalages' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=-200|duration=10000'
        ) -join [Environment]::NewLine
        $keptSign = @(
            'stream_index=0|pts=1000|duration=10000'
            'stream_index=1|pts=800|duration=10000'
        ) -join [Environment]::NewLine
        $flipped = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=200|duration=10000'
        ) -join [Environment]::NewLine
        $tight = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=75|duration=10000'
        ) -join [Environment]::NewLine

        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $keptSign
        $sameSign = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $flipped
        $flippedResult = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $zeroOffsetSource = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=0|duration=10000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $zeroOffsetSource
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $tight
        $tightResult = Invoke-IntegrityCheck `
            -SourceProbe $probe `
            -TempProbe $probe `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0) `
            -OffsetToleranceSeconds 0.05

        $sameSign.Status | Should -Be 'ok'
        $flippedResult.Status | Should -Be 'mismatch'
        $flippedResult.Method | Should -Be 'packet-offset'
        $flippedResult.Diff | Should -Be ([decimal]'0.4')
        $tightResult.Status | Should -Be 'mismatch'
        $tightResult.Method | Should -Be 'packet-offset'
    }

    It 'trois pistes : le couple éloigné de 0,15 s mismatch même si chacune reste à 0,075 s de la première' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'subtitle' -Index 2 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=0|duration=10000'
            'stream_index=2|pts=0|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=10000'
            'stream_index=1|pts=75|duration=10000'
            'stream_index=2|pts=-75|duration=10000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1, 2) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1, 2) -Text $outputText

        $result = Invoke-IntegrityCheck `
            -SourceProbe $probe `
            -TempProbe $probe `
            -KeptSourceVideoIndices @(0) `
            -KeptSourceAudioIndices @(0) `
            -KeptSourceSubtitleIndices @(0) `
            -OffsetToleranceSeconds 0.1

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-offset'
        $result.Diff | Should -Be ([decimal]'0.15')
        $result.StreamType | Should -Be 'audio'
        $result.OtherStreamType | Should -Be 'subtitle'
    }

    It 'la tolérance d''offset ne grandit pas avec la durée ni avec un décalage initial important' {
        $probe = New-MediaProbe -FormatName 'matroska,webm' -Streams @(
            (New-ProbeStream -CodecType 'video' -Index 0 -TimeBase '1/1000')
            (New-ProbeStream -CodecType 'audio' -Index 1 -TimeBase '1/1000')
        )
        $sourceText = @(
            'stream_index=0|pts=0|duration=7200000'
            'stream_index=1|pts=3600000|duration=10000'
        ) -join [Environment]::NewLine
        $outputText = @(
            'stream_index=0|pts=0|duration=7200000'
            'stream_index=1|pts=3600200|duration=10000'
        ) -join [Environment]::NewLine
        $script:SourceSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $sourceText
        $script:TempSpanScan = Invoke-ReadPacketSpanMap -Probe $probe -StreamIndices @(0, 1) -Text $outputText

        $result = Invoke-IntegrityCheck -SourceProbe $probe -TempProbe $probe -KeptSourceVideoIndices @(0) -KeptSourceAudioIndices @(0)

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'packet-offset'
        $result.Diff | Should -Be ([decimal]'0.2')
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
            $kept.Spans[0].ExactExtentSeconds | Should -Be 1
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
