using namespace System
using namespace System.IO

Set-StrictMode -Version Latest

# -----------------------------------------------------------------------------
# Probe.psm1 — ffprobe + contrôle d'intégrité par span de packets
# Sous-module privé de Tetram.Media.Mkv (chargé via NestedModules).
# Ne fait pas Export-ModuleMember : les fonctions restent visibles dans le
# scope du module Tetram.Media.Mkv mais ne fuient pas vers la session utilisateur.
# -----------------------------------------------------------------------------

function Get-FFprobeJson([string] $FFPROBE, [string] $File)
{
    $ffprobeArgs = @(
        $File,
        '-v', 'quiet'
        '-show_format'
        '-show_streams'
        '-of', 'json'
    )

    $out = & $FFPROBE $ffprobeArgs | Out-String
    if (-not $?)
    {
        Write-ErrorLog "Can't get media info for '$File'"; return $null
    }
    try
    {
        return (ConvertFrom-Json -InputObject $out -AsHashtable)
    }
    catch
    {
        Write-ErrorLog "Invalid ffprobe json for '$File' — $( $_.Exception.Message )"; return $null
    }
}

function Get-ProbeStreamByRelativeIndex
{
    param(
        [hashtable] $Probe,
        [string] $CodecType,
        [int] $TypeRelativeIndex
    )
    if ($null -eq $Probe -or $TypeRelativeIndex -lt 0)
    {
        return $null
    }
    $streams = $Probe['streams']
    if ($null -eq $streams)
    {
        return $null
    }
    $relIdx = -1
    foreach ($s in @($streams))
    {
        if (-not ($s -is [hashtable]) -or $s['codec_type'] -ne $CodecType)
        {
            continue
        }
        $relIdx++
        if ($relIdx -eq $TypeRelativeIndex)
        {
            return $s
        }
    }
    return $null
}

function Get-ProbeStreamByAbsoluteIndex
{
    param(
        [hashtable] $Probe,
        [int] $StreamIndex
    )
    if ($null -eq $Probe)
    {
        return $null
    }
    $streams = $Probe['streams']
    if ($null -eq $streams)
    {
        return $null
    }
    foreach ($s in @($streams))
    {
        if (-not ($s -is [hashtable]))
        {
            continue
        }
        $raw = $s['index']
        if ($null -eq $raw)
        {
            continue
        }
        try
        {
            if ([int]$raw -eq $StreamIndex)
            {
                return $s
            }
        }
        catch
        {
        }
    }
    return $null
}

function ConvertFrom-FFprobeTimeBase
{
    param($Value)
    if ($null -eq $Value)
    {
        return $null
    }
    $text = [string]$Value
    if ($text -notmatch '^([0-9]+)/([0-9]+)$')
    {
        return $null
    }
    $numerator = [int64]$Matches[1]
    $denominator = [int64]$Matches[2]
    if ($numerator -le 0 -or $denominator -le 0)
    {
        return $null
    }
    [pscustomobject]@{
        Numerator   = $numerator
        Denominator = $denominator
    }
}

function ConvertFrom-FFprobeCompactPacketLine
{
    param([string] $Line)
    if ([string]::IsNullOrWhiteSpace($Line))
    {
        return $null
    }

    $fields = @{}
    foreach ($part in $Line.Split('|'))
    {
        $eq = $part.IndexOf('=')
        if ($eq -lt 1)
        {
            continue
        }
        $fields[$part.Substring(0, $eq)] = $part.Substring($eq + 1)
    }
    if (-not $fields.ContainsKey('stream_index'))
    {
        return $null
    }
    return $fields
}

function ConvertTo-Int64Invariant
{
    param($Value, [ref] $Result)
    if ($null -eq $Value)
    {
        return $false
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text))
    {
        return $false
    }
    try
    {
        $Result.Value = [int64]::Parse($text, [cultureinfo]::InvariantCulture)
        return $true
    }
    catch
    {
        return $false
    }
}

function New-FFprobePacketSpanScanResult
{
    param(
        [switch] $Failed,
        [string] $Reason,
        $Spans
    )
    if ($null -eq $Spans)
    {
        $Spans = [System.Collections.Generic.Dictionary[int, object]]::new()
    }
    [pscustomobject]@{
        ScanFailed = [bool]$Failed
        Reason     = $Reason
        Spans      = $Spans
    }
}

function New-FFprobePacketSpanScratch
{
    param(
        [hashtable] $Probe,
        [int[]] $StreamIndices
    )

    $scratch = [System.Collections.Generic.Dictionary[int, object]]::new()
    if ($null -eq $StreamIndices)
    {
        return $scratch
    }

    $seen = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($rawIndex in @($StreamIndices))
    {
        $index = [int]$rawIndex
        if (-not $seen.Add($index))
        {
            continue
        }

        $timeBase = $null
        $endFromPtsOnly = $false
        $stream = Get-ProbeStreamByAbsoluteIndex -Probe $Probe -StreamIndex $index
        if ($null -ne $stream)
        {
            $timeBase = ConvertFrom-FFprobeTimeBase -Value $stream['time_base']
            # PGS : ffprobe ne renseigne jamais packet.duration ; la fin de flux est max(pts).
            $endFromPtsOnly = ([string]$stream['codec_name'] -ieq 'hdmv_pgs_subtitle')
        }

        $hasValidTimeBase = ($null -ne $timeBase)
        $entry = [pscustomobject]@{
            StreamIndex          = $index
            TimeBaseNumerator    = $(if ($hasValidTimeBase) { $timeBase.Numerator } else { [int64]0 })
            TimeBaseDenominator  = $(if ($hasValidTimeBase) { $timeBase.Denominator } else { [int64]0 })
            HasValidTimeBase     = $hasValidTimeBase
            EndFromPtsOnly       = $endFromPtsOnly
            Measurable           = $hasValidTimeBase
            Reason               = $(if (-not $hasValidTimeBase) { 'time_base-invalid' } else { $null })
            HasPtsSample         = $false
            HasSample            = $false
            HasMaxPts            = $false
            LastDisplayHasDuration = $false
            MinPts               = [decimal]0
            MaxPts               = [decimal]0
            MaxEnd               = [decimal]0
            PacketCount          = 0
            DurationSeconds      = $null
        }
        $scratch[$index] = $entry
    }

    return $scratch
}

function Add-FFprobePacketSpanObservation
{
    param(
        $Scratch,
        [hashtable] $Fields
    )
    if ($null -eq $Scratch -or $null -eq $Fields)
    {
        return
    }

    $rawIndex = [int64]0
    if (-not (ConvertTo-Int64Invariant -Value $Fields['stream_index'] -Result ([ref]$rawIndex)))
    {
        return
    }
    $index = [int]$rawIndex
    if (-not $Scratch.ContainsKey($index))
    {
        return
    }

    $entry = $Scratch[$index]
    if (-not $entry.HasValidTimeBase)
    {
        return
    }

    $pts = [int64]0
    $duration = [int64]0
    if (-not (ConvertTo-Int64Invariant -Value $Fields['pts'] -Result ([ref]$pts)))
    {
        $entry.Measurable = $false
        $entry.Reason = 'pts-unavailable'
        return
    }

    $start = [decimal]$pts
    if (-not $entry.HasPtsSample)
    {
        $entry.MinPts = $start
        $entry.HasPtsSample = $true
    }
    elseif ($start -lt $entry.MinPts)
    {
        $entry.MinPts = $start
    }

    if ($entry.EndFromPtsOnly)
    {
        if (-not $entry.HasSample)
        {
            $entry.MaxEnd = $start
            $entry.HasSample = $true
        }
        elseif ($start -gt $entry.MaxEnd)
        {
            $entry.MaxEnd = $start
        }
        $entry.PacketCount++
        return
    }

    $durationKnown = (ConvertTo-Int64Invariant -Value $Fields['duration'] -Result ([ref]$duration)) -and $duration -gt 0
    # MKV : duration absente → fin = pts du Block suivant en affichage ; seul le dernier Block exige une duration.
    if (-not $entry.HasMaxPts -or $start -gt $entry.MaxPts)
    {
        $entry.MaxPts = $start
        $entry.HasMaxPts = $true
        $entry.LastDisplayHasDuration = $durationKnown
    }
    elseif ($start -eq $entry.MaxPts)
    {
        $entry.LastDisplayHasDuration = $durationKnown
    }

    if (-not $durationKnown)
    {
        $entry.PacketCount++
        return
    }

    $end = $start + [decimal]$duration
    if (-not $entry.HasSample)
    {
        $entry.MaxEnd = $end
        $entry.HasSample = $true
    }
    elseif ($end -gt $entry.MaxEnd)
    {
        $entry.MaxEnd = $end
    }
    $entry.PacketCount++
}

function ConvertTo-FFprobeTimelineSeconds
{
    param(
        [decimal] $Ticks,
        [int64] $Numerator,
        [int64] $Denominator
    )
    if ($Denominator -eq 0)
    {
        return $null
    }
    return $Ticks * [decimal]$Numerator / [decimal]$Denominator
}

function Complete-FFprobePacketSpanScratch
{
    param($Scratch)

    $spans = [System.Collections.Generic.Dictionary[int, object]]::new()
    if ($null -eq $Scratch)
    {
        return $spans
    }

    $fileOrigin = $null
    foreach ($index in @($Scratch.Keys))
    {
        $entry = $Scratch[$index]
        if (-not $entry.HasValidTimeBase -or -not $entry.HasPtsSample)
        {
            continue
        }
        $startSeconds = ConvertTo-FFprobeTimelineSeconds -Ticks $entry.MinPts -Numerator $entry.TimeBaseNumerator -Denominator $entry.TimeBaseDenominator
        if ($null -eq $startSeconds)
        {
            continue
        }
        if ($null -eq $fileOrigin -or $startSeconds -lt $fileOrigin)
        {
            $fileOrigin = $startSeconds
        }
    }

    foreach ($index in @($Scratch.Keys))
    {
        $entry = $Scratch[$index]
        if (-not $entry.HasValidTimeBase)
        {
            $entry.Measurable = $false
            $entry.Reason = 'time_base-invalid'
        }
        elseif ($entry.Reason -eq 'pts-unavailable')
        {
            $entry.Measurable = $false
        }
        elseif (-not $entry.EndFromPtsOnly -and $entry.HasPtsSample -and -not $entry.LastDisplayHasDuration)
        {
            $entry.Measurable = $false
            $entry.Reason = 'duration-unknown'
        }
        elseif (-not $entry.HasPtsSample -or -not $entry.HasSample -or $null -eq $fileOrigin)
        {
            $entry.Measurable = $false
            $entry.Reason = 'no-packets'
        }
        else
        {
            $entry.Measurable = $true
            $entry.Reason = $null
            # Origine = min(pts) de tous les flux contrôlés, pas le min du flux : un délai initial reste visible.
            $endSeconds = ConvertTo-FFprobeTimelineSeconds -Ticks $entry.MaxEnd -Numerator $entry.TimeBaseNumerator -Denominator $entry.TimeBaseDenominator
            $entry.DurationSeconds = $endSeconds - $fileOrigin
        }
        if (-not $entry.Measurable)
        {
            $entry.DurationSeconds = $null
            $entry.MinPts = $null
            $entry.MaxEnd = $null
        }
        $spans[[int]$index] = $entry
    }

    return $spans
}

function Read-FFprobePacketSpanMap
{
    param(
        [hashtable] $Probe,
        [int[]] $StreamIndices,
        [Parameter(Mandatory)] [System.IO.TextReader] $Reader
    )

    $scratch = New-FFprobePacketSpanScratch -Probe $Probe -StreamIndices $StreamIndices
    while ($null -ne ($line = $Reader.ReadLine()))
    {
        $fields = ConvertFrom-FFprobeCompactPacketLine -Line $line
        if ($null -eq $fields)
        {
            continue
        }
        Add-FFprobePacketSpanObservation -Scratch $scratch -Fields $fields
    }

    New-FFprobePacketSpanScanResult -Spans (Complete-FFprobePacketSpanScratch -Scratch $scratch)
}

function Get-FFprobePacketSpanArgumentList
{
    param([Parameter(Mandatory)] [string] $File)
    @(
        '-v', 'error',
        '-show_packets',
        '-show_entries', 'packet=stream_index,pts,duration',
        '-of', 'compact=p=0:nk=0',
        $File
    )
}

function Select-FFprobePacketSpanScanResult
{
    param(
        $Map,
        [int] $ExitCode,
        [string] $StdErr
    )
    # Un code non nul peut laisser un stdout partiel ; ne jamais valider ce résultat.
    if ($ExitCode -ne 0)
    {
        if (-not [string]::IsNullOrWhiteSpace($StdErr))
        {
            Write-ErrorLog $StdErr
        }
        return New-FFprobePacketSpanScanResult -Failed -Reason 'ffprobe-failed'
    }
    return $Map
}

function Get-FFprobePacketSpanMap
{
    param(
        [Parameter(Mandatory)] [string] $FFPROBE,
        [Parameter(Mandatory)] [string] $File,
        [Parameter(Mandatory)] [hashtable] $Probe,
        [int[]] $StreamIndices
    )

    if ($null -eq $StreamIndices -or @($StreamIndices).Count -eq 0)
    {
        return New-FFprobePacketSpanScanResult -Spans ([System.Collections.Generic.Dictionary[int, object]]::new())
    }

    if ([string]::IsNullOrWhiteSpace($FFPROBE) -or [string]::IsNullOrWhiteSpace($File) -or -not [File]::Exists($File))
    {
        return New-FFprobePacketSpanScanResult -Failed -Reason 'ffprobe-failed'
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FFPROBE
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($arg in (Get-FFprobePacketSpanArgumentList -File $File))
    {
        [void]$psi.ArgumentList.Add($arg)
    }

    $proc = $null
    try
    {
        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $psi
        if (-not $proc.Start())
        {
            return New-FFprobePacketSpanScanResult -Failed -Reason 'ffprobe-failed'
        }

        # stderr drain async: un buffer plein bloquerait la lecture stdout ligne à ligne.
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $map = Read-FFprobePacketSpanMap -Probe $Probe -StreamIndices $StreamIndices -Reader $proc.StandardOutput
        $proc.WaitForExit()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        return (Select-FFprobePacketSpanScanResult -Map $map -ExitCode $proc.ExitCode -StdErr $stderr)
    }
    catch
    {
        return New-FFprobePacketSpanScanResult -Failed -Reason 'ffprobe-failed'
    }
    finally
    {
        if ($null -ne $proc)
        {
            $proc.Dispose()
        }
    }
}

function Get-DurationComparison
{
    param(
        $Expected,
        $Actual,
        $TolerancePercent,
        $ToleranceSecondsMin
    )
    $expectedDec = [decimal]$Expected
    $actualDec = [decimal]$Actual
    $diff = [Math]::Abs($expectedDec - $actualDec)
    $tolerance = [Math]::Max([decimal]$ToleranceSecondsMin, $expectedDec * [decimal]$TolerancePercent / [decimal]100)
    [pscustomobject]@{
        Diff       = $diff
        IsMismatch = ($diff -gt $tolerance)
    }
}

function New-IntegrityCheckResult
{
    param(
        [string] $Status,
        [string] $Method,
        $Expected = $null,
        $Actual = $null,
        $Diff = $null,
        [string] $StreamType = $null,
        $SourceRelativeIndex = $null,
        $OutputRelativeIndex = $null,
        [string] $Reason = $null
    )
    [pscustomobject]@{
        Status               = $Status
        Method               = $Method
        Expected             = $Expected
        Actual               = $Actual
        Diff                 = $Diff
        StreamType           = $StreamType
        SourceRelativeIndex  = $SourceRelativeIndex
        OutputRelativeIndex  = $OutputRelativeIndex
        Reason               = $Reason
    }
}

function Get-IntegrityStreamMapLabel
{
    param(
        [string] $StreamType,
        $SourceRelativeIndex,
        $OutputRelativeIndex
    )
    if ([string]::IsNullOrWhiteSpace($StreamType) -or $null -eq $SourceRelativeIndex -or $null -eq $OutputRelativeIndex)
    {
        return $null
    }
    $letter = switch ($StreamType)
    {
        'video' { 'v' }
        'audio' { 'a' }
        'subtitle' { 's' }
        default { $null }
    }
    if ($null -eq $letter)
    {
        return $null
    }
    return ('source 0:{0}:{1} -> output 0:{0}:{2}' -f $letter, [int]$SourceRelativeIndex, [int]$OutputRelativeIndex)
}

function ConvertTo-StreamAbsoluteIndex
{
    param($Stream)
    if ($null -eq $Stream)
    {
        return $null
    }
    $raw = $Stream['index']
    if ($null -eq $raw)
    {
        return $null
    }
    try
    {
        return [int]$raw
    }
    catch
    {
        return $null
    }
}

function Get-KeptIntegrityStreamPairs
{
    param(
        [hashtable] $SourceProbe,
        [hashtable] $TempProbe,
        [int[]] $KeptSourceVideoIndices,
        [int[]] $KeptSourceAudioIndices,
        [int[]] $KeptSourceSubtitleIndices
    )

    $pairs = [System.Collections.Generic.List[object]]::new()
    foreach ($codecType in @('video', 'audio', 'subtitle'))
    {
        $kept = [System.Collections.Generic.List[int]]::new()
        $keptIndices = switch ($codecType)
        {
            'video' { $KeptSourceVideoIndices }
            'audio' { $KeptSourceAudioIndices }
            'subtitle' { $KeptSourceSubtitleIndices }
        }
        if ($null -ne $keptIndices)
        {
            foreach ($idx in $keptIndices)
            {
                $kept.Add([int]$idx)
            }
        }

        for ($outputRelativeIndex = 0; $outputRelativeIndex -lt $kept.Count; $outputRelativeIndex++)
        {
            $sourceRelativeIndex = [int]$kept[$outputRelativeIndex]
            $sourceStream = Get-ProbeStreamByRelativeIndex -Probe $SourceProbe -CodecType $codecType -TypeRelativeIndex $sourceRelativeIndex
            $outputStream = Get-ProbeStreamByRelativeIndex -Probe $TempProbe -CodecType $codecType -TypeRelativeIndex $outputRelativeIndex
            if ($null -eq $outputStream)
            {
                return [pscustomobject]@{
                    Missing = (New-IntegrityCheckResult -Status 'mismatch' -Method 'packet-span' `
                            -StreamType $codecType -SourceRelativeIndex $sourceRelativeIndex -OutputRelativeIndex $outputRelativeIndex `
                            -Reason 'output-stream-missing')
                    Pairs   = $pairs
                }
            }

            $pairs.Add([pscustomobject]@{
                    CodecType            = $codecType
                    SourceRelativeIndex  = $sourceRelativeIndex
                    OutputRelativeIndex  = $outputRelativeIndex
                    SourceAbsoluteIndex  = (ConvertTo-StreamAbsoluteIndex -Stream $sourceStream)
                    OutputAbsoluteIndex  = (ConvertTo-StreamAbsoluteIndex -Stream $outputStream)
                })
        }
    }

    [pscustomobject]@{
        Missing = $null
        Pairs   = $pairs
    }
}

function Get-PacketSpanEntry
{
    param(
        $Spans,
        $Index
    )
    if ($null -eq $Spans -or $null -eq $Index)
    {
        return $null
    }
    $key = [int]$Index
    if (-not $Spans.ContainsKey($key))
    {
        return $null
    }
    return $Spans[$key]
}

function Find-KeptStreamDurationMismatch
{
    param(
        $Pairs,
        $SourceSpans,
        $OutputSpans,
        $TolerancePercent,
        $ToleranceSecondsMin,
        [ref] $HadUnknownStream,
        [ref] $LastOk
    )

    foreach ($pair in @($Pairs))
    {
        $sourceSpan = Get-PacketSpanEntry -Spans $SourceSpans -Index $pair.SourceAbsoluteIndex
        if ($null -eq $sourceSpan -or -not $sourceSpan.Measurable)
        {
            $HadUnknownStream.Value = $true
            continue
        }

        $outputSpan = Get-PacketSpanEntry -Spans $OutputSpans -Index $pair.OutputAbsoluteIndex
        if ($null -eq $outputSpan -or -not $outputSpan.Measurable)
        {
            $reason = 'packet-timeline-unavailable'
            if ($null -ne $outputSpan -and -not [string]::IsNullOrWhiteSpace([string]$outputSpan.Reason))
            {
                $reason = [string]$outputSpan.Reason
            }
            return New-IntegrityCheckResult -Status 'mismatch' -Method 'packet-span' -Expected $sourceSpan.DurationSeconds -Actual $null `
                -StreamType $pair.CodecType -SourceRelativeIndex $pair.SourceRelativeIndex -OutputRelativeIndex $pair.OutputRelativeIndex `
                -Reason $reason
        }

        $streamCmp = Get-DurationComparison `
            -Expected $sourceSpan.DurationSeconds `
            -Actual $outputSpan.DurationSeconds `
            -TolerancePercent $TolerancePercent `
            -ToleranceSecondsMin $ToleranceSecondsMin
        if ($streamCmp.IsMismatch)
        {
            return New-IntegrityCheckResult -Status 'mismatch' -Method 'packet-span' `
                -Expected $sourceSpan.DurationSeconds -Actual $outputSpan.DurationSeconds -Diff $streamCmp.Diff `
                -StreamType $pair.CodecType -SourceRelativeIndex $pair.SourceRelativeIndex -OutputRelativeIndex $pair.OutputRelativeIndex
        }
        $LastOk.Value = New-IntegrityCheckResult -Status 'ok' -Method 'packet-span' `
            -Expected $sourceSpan.DurationSeconds -Actual $outputSpan.DurationSeconds -Diff $streamCmp.Diff `
            -StreamType $pair.CodecType -SourceRelativeIndex $pair.SourceRelativeIndex -OutputRelativeIndex $pair.OutputRelativeIndex
    }

    return $null
}

function Test-EncodedFileIntegrity
{
    param(
        [Parameter(Mandatory)] [string] $FFPROBE,
        [Parameter(Mandatory)] [hashtable] $SourceProbe,
        [Parameter(Mandatory)] [string] $SourceFile,
        [Parameter(Mandatory)] [string] $TempFile,
        [double] $TolerancePercent = 0.5,
        [double] $ToleranceSecondsMin = 1.0,
        [int[]] $KeptSourceVideoIndices = $null,
        [int[]] $KeptSourceAudioIndices = $null,
        [int[]] $KeptSourceSubtitleIndices = $null
    )

    $tempProbe = Get-FFprobeJson -FFPROBE $FFPROBE -File $TempFile
    if ($null -eq $tempProbe)
    {
        return New-IntegrityCheckResult -Status 'mismatch' -Method 'probe'
    }

    $built = Get-KeptIntegrityStreamPairs `
        -SourceProbe $SourceProbe `
        -TempProbe $tempProbe `
        -KeptSourceVideoIndices $KeptSourceVideoIndices `
        -KeptSourceAudioIndices $KeptSourceAudioIndices `
        -KeptSourceSubtitleIndices $KeptSourceSubtitleIndices
    if ($null -ne $built.Missing)
    {
        return $built.Missing
    }

    $pairs = @($built.Pairs)
    if ($pairs.Count -eq 0)
    {
        return New-IntegrityCheckResult -Status 'unknown' -Method 'unknown'
    }

    $sourceIndices = [System.Collections.Generic.List[int]]::new()
    $outputIndices = [System.Collections.Generic.List[int]]::new()
    $sourceSeen = [System.Collections.Generic.HashSet[int]]::new()
    $outputSeen = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($pair in $pairs)
    {
        if ($null -ne $pair.SourceAbsoluteIndex -and $sourceSeen.Add([int]$pair.SourceAbsoluteIndex))
        {
            $sourceIndices.Add([int]$pair.SourceAbsoluteIndex)
        }
        if ($null -ne $pair.OutputAbsoluteIndex -and $outputSeen.Add([int]$pair.OutputAbsoluteIndex))
        {
            $outputIndices.Add([int]$pair.OutputAbsoluteIndex)
        }
    }

    $sourceMap = Get-FFprobePacketSpanMap -FFPROBE $FFPROBE -File $SourceFile -Probe $SourceProbe -StreamIndices $sourceIndices.ToArray()
    if ($sourceMap.ScanFailed)
    {
        return New-IntegrityCheckResult -Status 'unknown' -Method 'unknown' -Reason 'ffprobe-failed'
    }

    $outputMap = Get-FFprobePacketSpanMap -FFPROBE $FFPROBE -File $TempFile -Probe $tempProbe -StreamIndices $outputIndices.ToArray()
    if ($outputMap.ScanFailed)
    {
        return New-IntegrityCheckResult -Status 'mismatch' -Method 'packet-probe' -Reason 'ffprobe-failed'
    }

    $hadUnknownStream = $false
    $lastOk = $null
    $mismatch = Find-KeptStreamDurationMismatch `
        -Pairs $pairs `
        -SourceSpans $sourceMap.Spans `
        -OutputSpans $outputMap.Spans `
        -TolerancePercent $TolerancePercent `
        -ToleranceSecondsMin $ToleranceSecondsMin `
        -HadUnknownStream ([ref]$hadUnknownStream) `
        -LastOk ([ref]$lastOk)
    if ($null -ne $mismatch)
    {
        return $mismatch
    }

    if ($hadUnknownStream)
    {
        return New-IntegrityCheckResult -Status 'unknown' -Method 'unknown'
    }

    if ($null -ne $lastOk)
    {
        return $lastOk
    }

    return New-IntegrityCheckResult -Status 'unknown' -Method 'unknown'
}
