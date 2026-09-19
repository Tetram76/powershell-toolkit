using namespace System
using namespace System.IO
using namespace System.Globalization
using namespace System.Collections.Generic

Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# Probe.ps1 — ffprobe + contrôle d'intégrité post-réencodage (PTS / offsets / interleave)
# Sous-module privé de Tetram.Media.Mkv (dot-sourcé par Tetram.Media.Remux.psm1).
# -----------------------------------------------------------------------------

# Les profils temporels utilisent des fenêtres multi-stream bornées. -select_streams
# est exclu de ce chemin parce que ffprobe peut alors démuxer beaucoup plus de données
# avant que le stream sélectionné fasse progresser l'intervalle.
# 5 s est une politique de projet, pas une norme FFmpeg/Matroska.
$script:IntegrityInitialWindowSeconds = 5.0
$script:IntegrityStartHintWindowSeconds = 5.0
$script:IntegrityTailLookbackSeconds = 10.0
$script:IntegrityTailLookaheadSeconds = 5.0
$script:IntegrityTailGuardSeconds = 10.0

# Politique de projet : largeur de RECHERCHE autour d'un anchor d'interleave
# (calée sur cluster_time_limit=5000). Ce n'est PAS une tolérance de contemporanéité :
# un packet n'entre dans PhysicalSpread que s'il est à <= 2×cadence de l'anchor.
$script:IntegrityAnchorWindowSeconds = 5.0

# Politique de projet : un budget Cluster FFmpeg seekable (cluster_size_limit = 5 MiB).
# La limite d'entrelacement = 2 × ce budget + plus gros packet candidat, pour absorber
# une frontière de Cluster. Ce n'est ni une règle Matroska ni une garantie lecteur.
$script:IntegrityClusterBudgetBytes = 5L * 1024L * 1024L

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

function ConvertTo-IntegrityFiniteDouble
{
    param($Value)

    if ($null -eq $Value)
    {
        return $null
    }

    if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal] -or
        $Value -is [int] -or $Value -is [long] -or $Value -is [byte] -or $Value -is [uint32] -or $Value -is [uint64])
    {
        $d = [double]$Value
        if ([double]::IsFinite($d))
        {
            return $d
        }
        return $null
    }

    $ds = [string]$Value
    if ([string]::IsNullOrWhiteSpace($ds) -or $ds.Trim() -eq 'N/A')
    {
        return $null
    }

    try
    {
        $d = [double]::Parse($ds.Trim(), [cultureinfo]::InvariantCulture)
        if ([double]::IsFinite($d))
        {
            return $d
        }
    }
    catch
    {
    }

    return $null
}

function ConvertTo-IntegrityNonNegativeInt64
{
    param($Value)

    if ($null -eq $Value)
    {
        return $null
    }

    if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal])
    {
        $d = [double]$Value
        if (-not [double]::IsFinite($d) -or $d -lt 0)
        {
            return $null
        }
        return [long]$d
    }

    if ($Value -is [int] -or $Value -is [long] -or $Value -is [byte] -or $Value -is [uint32] -or $Value -is [uint64])
    {
        $n = [long]$Value
        if ($n -lt 0)
        {
            return $null
        }
        return $n
    }

    $ds = [string]$Value
    if ([string]::IsNullOrWhiteSpace($ds) -or $ds.Trim() -eq 'N/A')
    {
        return $null
    }

    try
    {
        $n = [long]::Parse($ds.Trim(), [cultureinfo]::InvariantCulture)
        if ($n -ge 0)
        {
            return $n
        }
    }
    catch
    {
    }

    return $null
}

function ConvertTo-IntegrityPacket
{
    param($Packet)

    $pts = $null
    $pos = $null
    $size = $null
    $streamIndex = $null

    if ($null -ne $Packet)
    {
        if ($Packet -is [hashtable])
        {
            $pts = ConvertTo-IntegrityFiniteDouble -Value $Packet['pts_time']
            $pos = ConvertTo-IntegrityNonNegativeInt64 -Value $Packet['pos']
            $size = ConvertTo-IntegrityNonNegativeInt64 -Value $Packet['size']
            $streamIndex = ConvertTo-IntegrityNonNegativeInt64 -Value $Packet['stream_index']
        }
        elseif ($Packet.PSObject.Properties['PtsTime'])
        {
            # Déjà converti (mocks unitaires) : ne pas relire duration même si elle est présente.
            $pts = ConvertTo-IntegrityFiniteDouble -Value $Packet.PtsTime
            $pos = ConvertTo-IntegrityNonNegativeInt64 -Value $Packet.Pos
            $size = ConvertTo-IntegrityNonNegativeInt64 -Value $Packet.Size
            if ($Packet.PSObject.Properties['StreamIndex'])
            {
                $streamIndex = ConvertTo-IntegrityNonNegativeInt64 -Value $Packet.StreamIndex
            }
        }
        else
        {
            $pts = ConvertTo-IntegrityFiniteDouble -Value ($Packet.pts_time)
            $pos = ConvertTo-IntegrityNonNegativeInt64 -Value ($Packet.pos)
            $size = ConvertTo-IntegrityNonNegativeInt64 -Value ($Packet.size)
            $streamIndex = ConvertTo-IntegrityNonNegativeInt64 -Value ($Packet.stream_index)
        }
    }

    [pscustomobject]@{
        PtsTime     = $pts
        Pos         = $pos
        Size        = $size
        StreamIndex = $streamIndex
    }
}

function ConvertTo-IntegrityInvariantNumberString
{
    param([double] $Value)

    # G15 peut émettre 1E-06 ; av_parse_time de ffprobe refuse la notation scientifique.
    $text = $Value.ToString('0.###############', [cultureinfo]::InvariantCulture)
    if ($text.Contains('.'))
    {
        $text = $text.TrimEnd('0').TrimEnd('.')
    }
    if ([string]::IsNullOrEmpty($text) -or $text -eq '-' -or $text -eq '-0')
    {
        return '0'
    }
    return $text
}

function ConvertTo-IntegrityPacketArray
{
    param($Packets)

    # `return @()` se déroule en $null : le caller ne peut plus distinguer
    # « ffprobe a échoué » de « JSON valide sans packet ».
    if ($null -eq $Packets)
    {
        return ,([object[]]@())
    }

    return ,([object[]]@($Packets))
}


function Get-IntegrityClosedReadInterval
{
    param(
        [double] $Start,
        [double] $End
    )

    return '{0}%{1}' -f `
        (ConvertTo-IntegrityInvariantNumberString -Value $Start), `
        (ConvertTo-IntegrityInvariantNumberString -Value $End)
}

function Get-IntegrityStartReadInterval
{
    return '%+{0}' -f (ConvertTo-IntegrityInvariantNumberString -Value $script:IntegrityInitialWindowSeconds)
}

function Get-IntegrityStartHintWindowInterval
{
    param([double] $Hint)

    $windowStart = [math]::Max(0.0, [double]$Hint - $script:IntegrityStartHintWindowSeconds)
    $windowEnd = [double]$Hint + $script:IntegrityStartHintWindowSeconds
    return Get-IntegrityClosedReadInterval -Start $windowStart -End $windowEnd
}

function Get-IntegrityPacketsInPtsRange
{
    param(
        $Packets,
        [double] $Start,
        [double] $End,
        [switch] $ExclusiveStart
    )

    if ($null -eq $Packets)
    {
        return $null
    }

    $selected = @()
    foreach ($packet in @($Packets))
    {
        if ($null -eq $packet -or $null -eq $packet.PtsTime)
        {
            continue
        }
        $pts = [double]$packet.PtsTime
        $afterStart = if ($ExclusiveStart) { $pts -gt $Start } else { $pts -ge $Start }
        if ($afterStart -and $pts -le $End)
        {
            $selected += $packet
        }
    }

    return ConvertTo-IntegrityPacketArray -Packets $selected
}

function Get-IntegrityTailReadInterval
{
    param([double] $Hint)

    # 0%(H+5) reste une fenêtre fermée. L'intervalle interdit est START% (EOF).
    if (-not [double]::IsFinite($Hint) -or $Hint -le 0)
    {
        return $null
    }

    $tailStart = [math]::Max(0.0, [double]$Hint - $script:IntegrityTailLookbackSeconds)
    $tailEnd = [double]$Hint + $script:IntegrityTailLookaheadSeconds
    if ($tailEnd -le $tailStart)
    {
        return $null
    }

    return Get-IntegrityClosedReadInterval -Start $tailStart -End $tailEnd
}

function Get-IntegrityTailGuardInterval
{
    param([double] $Hint)

    $guardStart = [double]$Hint + $script:IntegrityTailLookaheadSeconds
    $guardEnd = $guardStart + $script:IntegrityTailGuardSeconds
    return Get-IntegrityClosedReadInterval -Start $guardStart -End $guardEnd
}

function Get-IntegrityAnchorSearchWindow
{
    param([double] $Anchor)

    # Seek ffprobe refuse un temps négatif ; le filtre PTS, lui, doit
    # conserver un packet historique à pts ≈ -0.005 autour de l'anchor 0.
    $ptsStart = [double]$Anchor - $script:IntegrityAnchorWindowSeconds
    $ptsEnd = [double]$Anchor + $script:IntegrityAnchorWindowSeconds
    $seekStart = [math]::Max(0.0, $ptsStart)
    return [pscustomobject]@{
        PtsStart        = $ptsStart
        PtsEnd          = $ptsEnd
        ReadIntervals   = Get-IntegrityClosedReadInterval -Start $seekStart -End $ptsEnd
    }
}

function Get-IntegrityPacketWindow
{
    param(
        [Parameter(Mandatory)] [string] $FFPROBE,
        [Parameter(Mandatory)] [string] $File,
        [Parameter(Mandatory)] [string] $ReadIntervals
    )

    $ffprobeArgs = @(
        '-v', 'error'
        '-read_intervals', $ReadIntervals
        '-show_packets'
        '-show_entries', 'packet=stream_index,pts_time,pos,size'
        '-of', 'json'
        $File
    )

    $out = & $FFPROBE $ffprobeArgs 2>$null | Out-String
    if (-not $?)
    {
        return $null
    }

    try
    {
        $json = ConvertFrom-Json -InputObject $out -AsHashtable
    }
    catch
    {
        return $null
    }

    if ($null -eq $json)
    {
        return $null
    }

    $rawPackets = $json['packets']
    if ($null -eq $rawPackets)
    {
        return ConvertTo-IntegrityPacketArray -Packets @()
    }

    $packets = @()
    foreach ($raw in @($rawPackets))
    {
        $packets += ConvertTo-IntegrityPacket -Packet $raw
    }
    return ConvertTo-IntegrityPacketArray -Packets $packets
}

function Get-IntegrityTargetedInterleavePackets
{
    param(
        [Parameter(Mandatory)] [string] $FFPROBE,
        [Parameter(Mandatory)] [string] $File,
        [Parameter(Mandatory)] [string] $StreamSpecifier,
        [Parameter(Mandatory)] [string] $ReadIntervals
    )

    # Exception intentionnelle :
    # -select_streams peut provoquer une lecture physique supérieure à la largeur
    # apparente de la fenêtre si le stream est physiquement retardé.
    # Ce comportement est utile ici pour révéler précisément un mauvais interleave.
    # Ne pas réutiliser ce helper pour les profils temporels.
    $ffprobeArgs = @(
        '-v', 'error'
        '-select_streams', $StreamSpecifier
        '-read_intervals', $ReadIntervals
        '-show_packets'
        '-show_entries', 'packet=stream_index,pts_time,pos,size'
        '-of', 'json'
        $File
    )

    $out = & $FFPROBE $ffprobeArgs 2>$null | Out-String
    if (-not $?)
    {
        return $null
    }

    try
    {
        $json = ConvertFrom-Json -InputObject $out -AsHashtable
    }
    catch
    {
        return $null
    }

    if ($null -eq $json)
    {
        return $null
    }

    $rawPackets = $json['packets']
    if ($null -eq $rawPackets)
    {
        return ConvertTo-IntegrityPacketArray -Packets @()
    }

    $packets = @()
    foreach ($raw in @($rawPackets))
    {
        $packets += ConvertTo-IntegrityPacket -Packet $raw
    }
    return ConvertTo-IntegrityPacketArray -Packets $packets
}

function Get-CachedIntegrityPacketWindow
{
    param(
        $Cache,
        [Parameter(Mandatory)] [string] $FFPROBE,
        [Parameter(Mandatory)] [string] $File,
        [Parameter(Mandatory)] [string] $ReadIntervals
    )

    $key = '{0}|{1}' -f $File, $ReadIntervals
    if ($null -ne $Cache -and $Cache.ContainsKey($key))
    {
        $cached = $Cache[$key]
        if ($null -eq $cached)
        {
            return $null
        }
        return ConvertTo-IntegrityPacketArray -Packets $cached
    }

    $sample = Get-IntegrityPacketWindow `
        -FFPROBE $FFPROBE `
        -File $File `
        -ReadIntervals $ReadIntervals

    if ($null -ne $Cache)
    {
        $Cache[$key] = $sample
    }

    if ($null -eq $sample)
    {
        return $null
    }

    return ConvertTo-IntegrityPacketArray -Packets $sample
}

function Get-IntegrityPacketsForAbsoluteStream
{
    param(
        $Packets,
        [int] $AbsoluteStreamIndex
    )

    if ($null -eq $Packets)
    {
        return $null
    }

    $selected = @()
    foreach ($packet in @($Packets))
    {
        if ($null -eq $packet -or $null -eq $packet.StreamIndex)
        {
            continue
        }

        if ([int]$packet.StreamIndex -eq $AbsoluteStreamIndex)
        {
            $selected += $packet
        }
    }

    return ConvertTo-IntegrityPacketArray -Packets $selected
}

function Get-ProbeStreamAbsoluteIndex
{
    param([hashtable] $Stream)

    if ($null -eq $Stream)
    {
        return $null
    }

    return ConvertTo-IntegrityNonNegativeInt64 -Value $Stream['index']
}

function ConvertTo-IntegrityPositiveDuration
{
    param($Value)

    $duration = ConvertTo-IntegrityFiniteDouble -Value $Value
    if ($null -eq $duration -or $duration -le 0)
    {
        return $null
    }

    return $duration
}

function Get-IntegrityMinPts
{
    param($Packets)

    $minPts = $null
    foreach ($packet in @($Packets))
    {
        if ($null -eq $packet -or $null -eq $packet.PtsTime)
        {
            continue
        }
        if ($null -eq $minPts -or [double]$packet.PtsTime -lt [double]$minPts)
        {
            $minPts = [double]$packet.PtsTime
        }
    }

    return $minPts
}

function Get-IntegrityMaxPts
{
    param($Packets)

    $maxPts = $null
    foreach ($packet in @($Packets))
    {
        if ($null -eq $packet -or $null -eq $packet.PtsTime)
        {
            continue
        }
        if ($null -eq $maxPts -or [double]$packet.PtsTime -gt [double]$maxPts)
        {
            $maxPts = [double]$packet.PtsTime
        }
    }

    return $maxPts
}

function Get-IntegrityStartSeekHint
{
    param(
        [hashtable] $Probe,
        [hashtable] $Stream
    )

    if ($null -ne $Stream)
    {
        $streamStart = ConvertTo-IntegrityFiniteDouble -Value $Stream['start_time']
        if ($null -ne $streamStart)
        {
            return $streamStart
        }
    }

    if ($null -eq $Probe)
    {
        return $null
    }

    $fmt = $Probe['format']
    if (-not ($fmt -is [hashtable]))
    {
        return $null
    }

    $formatStart = ConvertTo-IntegrityFiniteDouble -Value $fmt['start_time']
    if ($null -eq $formatStart)
    {
        return $null
    }

    # format.start_time au début du fichier ne localise pas une piste tardive.
    $windowStart = [math]::Max(0.0, [double]$formatStart - $script:IntegrityStartHintWindowSeconds)
    if ($windowStart -le 0)
    {
        return $null
    }

    return $formatStart
}

function Get-IntegrityMedianPositivePtsDelta
{
    param($Packets)

    $pts = @()
    $seen = [HashSet[double]]::new()
    foreach ($packet in @($Packets))
    {
        if ($null -eq $packet -or $null -eq $packet.PtsTime)
        {
            continue
        }
        $value = [double]$packet.PtsTime
        if ($seen.Add($value))
        {
            $pts += $value
        }
    }

    if ($pts.Count -lt 2)
    {
        return $null
    }

    $sortedPts = @($pts | Sort-Object)
    $deltas = @()
    for ($i = 1; $i -lt $sortedPts.Count; $i++)
    {
        $delta = [double]$sortedPts[$i] - [double]$sortedPts[$i - 1]
        if ($delta -gt 0)
        {
            $deltas += $delta
        }
    }

    if ($deltas.Count -eq 0)
    {
        return $null
    }

    $sortedDeltas = @($deltas | Sort-Object)
    $n = $sortedDeltas.Count
    if (($n % 2) -eq 1)
    {
        return [double]$sortedDeltas[($n - 1) / 2]
    }

    return (([double]$sortedDeltas[$n / 2 - 1] + [double]$sortedDeltas[$n / 2]) / 2.0)
}

function Get-IntegrityTailSeekHint
{
    param(
        [hashtable] $Probe,
        [hashtable] $Stream
    )

    $streamStart = $null
    $streamDuration = $null
    if ($null -ne $Stream)
    {
        $streamStart = ConvertTo-IntegrityFiniteDouble -Value $Stream['start_time']
        $streamDuration = ConvertTo-IntegrityPositiveDuration -Value $Stream['duration']
    }

    $formatStart = $null
    $formatDuration = $null
    if ($null -ne $Probe)
    {
        $fmt = $Probe['format']
        if ($fmt -is [hashtable])
        {
            $formatStart = ConvertTo-IntegrityFiniteDouble -Value $fmt['start_time']
            $formatDuration = ConvertTo-IntegrityPositiveDuration -Value $fmt['duration']
        }
    }

    $candidates = @()
    if ($null -ne $streamStart -and $null -ne $streamDuration)
    {
        $candidates += ($streamStart + $streamDuration)
    }
    if ($null -ne $formatStart -and $null -ne $formatDuration)
    {
        $candidates += ($formatStart + $formatDuration)
    }
    if ($null -ne $streamDuration)
    {
        $candidates += $streamDuration
    }
    if ($null -ne $formatDuration)
    {
        $candidates += $formatDuration
    }

    foreach ($candidate in $candidates)
    {
        $hint = ConvertTo-IntegrityFiniteDouble -Value $candidate
        if ($null -ne $hint -and $hint -gt 0)
        {
            return $hint
        }
    }

    return $null
}

function New-IntegrityTemporalProfile
{
    param(
        $FirstPtsTime = $null,
        $LastPtsTime = $null,
        $SpanSeconds = $null,
        $StartCadence = $null,
        $EndCadence = $null,
        $Cadence = $null,
        $StartPackets = @(),
        $TailPackets = @(),
        $AbsoluteStreamIndex = $null,
        [bool] $IsUsable = $false,
        [string] $UnknownReason = $null
    )

    [pscustomobject]@{
        FirstPtsTime         = $FirstPtsTime
        LastPtsTime          = $LastPtsTime
        SpanSeconds          = $SpanSeconds
        StartCadence         = $StartCadence
        EndCadence           = $EndCadence
        Cadence              = $Cadence
        StartPackets         = @($StartPackets)
        TailPackets          = @($TailPackets)
        AbsoluteStreamIndex  = $AbsoluteStreamIndex
        IsUsable             = $IsUsable
        UnknownReason        = $UnknownReason
    }
}

function Get-IntegrityTemporalProfile
{
    param(
        [Parameter(Mandatory)] [string] $FFPROBE,
        [Parameter(Mandatory)] [string] $File,
        [hashtable] $Probe,
        [hashtable] $Stream,
        $WindowCache
    )

    $streamIndex = Get-ProbeStreamAbsoluteIndex -Stream $Stream
    $initial = Get-CachedIntegrityPacketWindow `
        -Cache $WindowCache `
        -FFPROBE $FFPROBE `
        -File $File `
        -ReadIntervals (Get-IntegrityStartReadInterval)

    if ($null -eq $initial)
    {
        return New-IntegrityTemporalProfile `
            -AbsoluteStreamIndex $streamIndex `
            -UnknownReason 'no-start-pts'
    }

    $startPackets = if ($null -eq $streamIndex)
    {
        ConvertTo-IntegrityPacketArray -Packets $initial
    }
    else
    {
        Get-IntegrityPacketsForAbsoluteStream -Packets $initial -AbsoluteStreamIndex ([int]$streamIndex)
    }

    $firstPts = Get-IntegrityMinPts -Packets $startPackets
    if ($null -eq $firstPts)
    {
        $startHint = Get-IntegrityStartSeekHint -Probe $Probe -Stream $Stream
        if ($null -eq $startHint)
        {
            return New-IntegrityTemporalProfile `
                -StartPackets $startPackets `
                -AbsoluteStreamIndex $streamIndex `
                -UnknownReason 'no-start-seek-hint'
        }

        $hintWindow = Get-CachedIntegrityPacketWindow `
            -Cache $WindowCache `
            -FFPROBE $FFPROBE `
            -File $File `
            -ReadIntervals (Get-IntegrityStartHintWindowInterval -Hint $startHint)

        if ($null -eq $hintWindow)
        {
            return New-IntegrityTemporalProfile `
                -AbsoluteStreamIndex $streamIndex `
                -UnknownReason 'no-start-pts'
        }

        $startPackets = if ($null -eq $streamIndex)
        {
            ConvertTo-IntegrityPacketArray -Packets $hintWindow
        }
        else
        {
            Get-IntegrityPacketsForAbsoluteStream -Packets $hintWindow -AbsoluteStreamIndex ([int]$streamIndex)
        }

        $hintWindowStart = [math]::Max(0.0, [double]$startHint - $script:IntegrityStartHintWindowSeconds)
        $hintWindowEnd = [double]$startHint + $script:IntegrityStartHintWindowSeconds
        $startPackets = Get-IntegrityPacketsInPtsRange `
            -Packets $startPackets `
            -Start $hintWindowStart `
            -End $hintWindowEnd

        $firstPts = Get-IntegrityMinPts -Packets $startPackets
        if ($null -eq $firstPts)
        {
            return New-IntegrityTemporalProfile `
                -StartPackets $startPackets `
                -AbsoluteStreamIndex $streamIndex `
                -UnknownReason 'no-start-packet-near-hint'
        }
    }

    $startCadence = Get-IntegrityMedianPositivePtsDelta -Packets $startPackets
    $hint = Get-IntegrityTailSeekHint -Probe $Probe -Stream $Stream
    $tailStart = $null
    $tailEnd = $null
    $tailInterval = $null
    if ($null -ne $hint)
    {
        $tailStart = [math]::Max(0.0, [double]$hint - $script:IntegrityTailLookbackSeconds)
        $tailEnd = [double]$hint + $script:IntegrityTailLookaheadSeconds
        $tailInterval = Get-IntegrityTailReadInterval -Hint $hint
    }
    if ($null -eq $tailInterval)
    {
        return New-IntegrityTemporalProfile `
            -FirstPtsTime $firstPts `
            -StartCadence $startCadence `
            -StartPackets $startPackets `
            -AbsoluteStreamIndex $streamIndex `
            -UnknownReason 'no-tail-seek-hint'
    }

    $fileTailPackets = Get-CachedIntegrityPacketWindow `
        -Cache $WindowCache `
        -FFPROBE $FFPROBE `
        -File $File `
        -ReadIntervals $tailInterval

    if ($null -eq $fileTailPackets)
    {
        return New-IntegrityTemporalProfile `
            -FirstPtsTime $firstPts `
            -StartCadence $startCadence `
            -StartPackets $startPackets `
            -AbsoluteStreamIndex $streamIndex `
            -UnknownReason 'tail-probe-failed'
    }

    $tailPackets = if ($null -eq $streamIndex)
    {
        ConvertTo-IntegrityPacketArray -Packets $fileTailPackets
    }
    else
    {
        Get-IntegrityPacketsForAbsoluteStream -Packets $fileTailPackets -AbsoluteStreamIndex ([int]$streamIndex)
    }

    $tailPackets = Get-IntegrityPacketsInPtsRange -Packets $tailPackets -Start $tailStart -End $tailEnd
    $lastPts = Get-IntegrityMaxPts -Packets $tailPackets
    if ($null -eq $lastPts)
    {
        return New-IntegrityTemporalProfile `
            -FirstPtsTime $firstPts `
            -StartCadence $startCadence `
            -StartPackets $startPackets `
            -TailPackets $tailPackets `
            -AbsoluteStreamIndex $streamIndex `
            -UnknownReason 'no-end-packet-near-hint'
    }

    $endCadence = Get-IntegrityMedianPositivePtsDelta -Packets $tailPackets
    $guardStart = [double]$hint + $script:IntegrityTailLookaheadSeconds
    $guardEnd = $guardStart + $script:IntegrityTailGuardSeconds
    $guardWindow = Get-CachedIntegrityPacketWindow `
        -Cache $WindowCache `
        -FFPROBE $FFPROBE `
        -File $File `
        -ReadIntervals (Get-IntegrityTailGuardInterval -Hint $hint)

    if ($null -eq $guardWindow)
    {
        return New-IntegrityTemporalProfile `
            -FirstPtsTime $firstPts `
            -LastPtsTime $lastPts `
            -StartCadence $startCadence `
            -EndCadence $endCadence `
            -StartPackets $startPackets `
            -TailPackets $tailPackets `
            -AbsoluteStreamIndex $streamIndex `
            -UnknownReason 'tail-probe-failed'
    }

    $guardPackets = if ($null -eq $streamIndex)
    {
        ConvertTo-IntegrityPacketArray -Packets $guardWindow
    }
    else
    {
        Get-IntegrityPacketsForAbsoluteStream -Packets $guardWindow -AbsoluteStreamIndex ([int]$streamIndex)
    }

    # ExclusiveStart : un packet pile à H+5 appartient déjà à la fenêtre tail.
    $guardPackets = Get-IntegrityPacketsInPtsRange `
        -Packets $guardPackets `
        -Start $guardStart `
        -End $guardEnd `
        -ExclusiveStart

    if (@($guardPackets).Count -gt 0)
    {
        return New-IntegrityTemporalProfile `
            -FirstPtsTime $firstPts `
            -LastPtsTime $lastPts `
            -StartCadence $startCadence `
            -EndCadence $endCadence `
            -StartPackets $startPackets `
            -TailPackets $tailPackets `
            -AbsoluteStreamIndex $streamIndex `
            -UnknownReason 'tail-hint-underestimates-stream'
    }

    if ($lastPts -lt $firstPts)
    {
        return New-IntegrityTemporalProfile `
            -FirstPtsTime $firstPts `
            -LastPtsTime $lastPts `
            -StartCadence $startCadence `
            -EndCadence $endCadence `
            -StartPackets $startPackets `
            -TailPackets $tailPackets `
            -AbsoluteStreamIndex $streamIndex `
            -UnknownReason 'no-end-pts'
    }

    if ($null -eq $startCadence -or $startCadence -le 0)
    {
        return New-IntegrityTemporalProfile `
            -FirstPtsTime $firstPts `
            -LastPtsTime $lastPts `
            -SpanSeconds ($lastPts - $firstPts) `
            -StartCadence $startCadence `
            -EndCadence $endCadence `
            -StartPackets $startPackets `
            -TailPackets $tailPackets `
            -AbsoluteStreamIndex $streamIndex `
            -UnknownReason 'no-start-cadence'
    }

    if ($null -eq $endCadence -or $endCadence -le 0)
    {
        return New-IntegrityTemporalProfile `
            -FirstPtsTime $firstPts `
            -LastPtsTime $lastPts `
            -SpanSeconds ($lastPts - $firstPts) `
            -StartCadence $startCadence `
            -EndCadence $endCadence `
            -Cadence $startCadence `
            -StartPackets $startPackets `
            -TailPackets $tailPackets `
            -AbsoluteStreamIndex $streamIndex `
            -UnknownReason 'no-end-cadence'
    }

    $cadence = [math]::Max([double]$startCadence, [double]$endCadence)
    $span = $lastPts - $firstPts
    return New-IntegrityTemporalProfile `
        -FirstPtsTime $firstPts `
        -LastPtsTime $lastPts `
        -SpanSeconds $span `
        -StartCadence $startCadence `
        -EndCadence $endCadence `
        -Cadence $cadence `
        -StartPackets $startPackets `
        -TailPackets $tailPackets `
        -AbsoluteStreamIndex $streamIndex `
        -IsUsable $true
}

function New-IntegrityCheckResult
{
    param(
        [string] $Status,
        [string] $Method,
        [string] $Reason = $null,
        $Expected = $null,
        $Actual = $null,
        $Diff = $null,
        $Tolerance = $null,
        [string] $StreamType = $null,
        $SourceRelativeIndex = $null,
        $OutputRelativeIndex = $null,
        $AnchorTime = $null,
        $AnchorFraction = $null,
        $PhysicalSpreadBytes = $null,
        $PhysicalLimitBytes = $null,
        [string] $ReferenceStreamType = $null,
        $ReferenceSourceRelativeIndex = $null,
        $ReferenceOutputRelativeIndex = $null,
        [string] $Side = $null
    )

    [pscustomobject]@{
        Status                        = $Status
        Method                        = $Method
        Reason                        = $Reason
        Expected                      = $Expected
        Actual                        = $Actual
        Diff                          = $Diff
        Tolerance                     = $Tolerance
        StreamType                    = $StreamType
        SourceRelativeIndex           = $SourceRelativeIndex
        OutputRelativeIndex           = $OutputRelativeIndex
        AnchorTime                    = $AnchorTime
        AnchorFraction                = $AnchorFraction
        PhysicalSpreadBytes           = $PhysicalSpreadBytes
        PhysicalLimitBytes            = $PhysicalLimitBytes
        ReferenceStreamType           = $ReferenceStreamType
        ReferenceSourceRelativeIndex  = $ReferenceSourceRelativeIndex
        ReferenceOutputRelativeIndex  = $ReferenceOutputRelativeIndex
        Side                          = $Side
    }
}

function ConvertTo-IntegrityMibLabel
{
    param([long] $Bytes)
    $mib = [double]$Bytes / (1024.0 * 1024.0)
    return ('{0} MiB' -f $mib.ToString('0.0', [cultureinfo]::InvariantCulture))
}

function Get-IntegrityResultProperty
{
    param(
        $Integrity,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -eq $Integrity -or -not $Integrity.PSObject.Properties[$Name])
    {
        return $null
    }

    return $Integrity.$Name
}

function Get-IntegrityUnknownDetail
{
    param($Integrity)

    $streamType = Get-IntegrityResultProperty -Integrity $Integrity -Name 'StreamType'
    $streamLabel = Get-IntegrityStreamMapLabel `
        -StreamType $streamType `
        -SourceRelativeIndex (Get-IntegrityResultProperty -Integrity $Integrity -Name 'SourceRelativeIndex') `
        -OutputRelativeIndex (Get-IntegrityResultProperty -Integrity $Integrity -Name 'OutputRelativeIndex')
    $reason = Get-IntegrityResultProperty -Integrity $Integrity -Name 'Reason'

    switch ($reason)
    {
        { $_ -in @('no-end-pts', 'no-end-packet-near-hint') } {
            $side = Get-IntegrityResultProperty -Integrity $Integrity -Name 'Side'
            if ([string]::IsNullOrWhiteSpace($side))
            {
                $side = 'output'
            }
            $indexName = if ($side -eq 'source') { 'SourceRelativeIndex' } else { 'OutputRelativeIndex' }
            $index = Get-IntegrityResultProperty -Integrity $Integrity -Name $indexName
            if ($null -ne $index)
            {
                $letter = if ($streamType -eq 'audio') { 'a' } else { 'v' }
                '{0} 0:{1}:{2} has no usable end PTS' -f $side, $letter, [int]$index
            }
            else
            {
                'no usable end PTS'
            }
        }
        'no-tail-seek-hint' { if ($streamLabel) { '{0} has no tail seek hint' -f $streamLabel } else { 'no tail seek hint' } }
        'tail-window-truncated' { if ($streamLabel) { '{0} tail window stopped at the duration hint' -f $streamLabel } else { 'tail window stopped at the duration hint' } }
        'tail-hint-underestimates-stream' { if ($streamLabel) { '{0} tail hint underestimates the stream' -f $streamLabel } else { 'tail hint underestimates the stream' } }
        'no-start-seek-hint' { if ($streamLabel) { '{0} has no start seek hint' -f $streamLabel } else { 'no start seek hint' } }
        'no-start-packet-near-hint' { if ($streamLabel) { '{0} has no start packet near the start hint' -f $streamLabel } else { 'no start packet near the start hint' } }
        'tail-probe-failed' { if ($streamLabel) { '{0} tail probe failed' -f $streamLabel } else { 'tail probe failed' } }
        'anchor-probe-failed' { if ($streamLabel) { '{0} anchor probe failed' -f $streamLabel } else { 'anchor probe failed' } }
        'no-start-pts' { if ($streamLabel) { '{0} has no usable start PTS' -f $streamLabel } else { 'no usable start PTS' } }
        'no-start-cadence' { if ($streamLabel) { '{0} has no start cadence' -f $streamLabel } else { 'no start cadence' } }
        'no-end-cadence' { if ($streamLabel) { '{0} has no end cadence' -f $streamLabel } else { 'no end cadence' } }
        'no-anchor-candidate' { 'no comparable A/V packets around an interleave anchor' }
        'no-anchor-cadence' { 'no usable A/V packet cadence around an interleave anchor' }
        'mapped-source-stream-missing' { if ($streamLabel) { '{0} is missing from the source probe' -f $streamLabel } else { 'mapped source stream is missing' } }
        default {
            if ($streamLabel -and $reason) { '{0} - {1}' -f $streamLabel, $reason }
            elseif ($reason) { [string]$reason }
            else { 'insufficient packet timeline data' }
        }
    }
}

function Get-IntegrityMismatchMessage
{
    param(
        [Parameter(Mandatory)] [string] $Filename,
        [Parameter(Mandatory)] $Integrity
    )

    $streamLabel = Get-IntegrityStreamMapLabel `
        -StreamType (Get-IntegrityResultProperty -Integrity $Integrity -Name 'StreamType') `
        -SourceRelativeIndex (Get-IntegrityResultProperty -Integrity $Integrity -Name 'SourceRelativeIndex') `
        -OutputRelativeIndex (Get-IntegrityResultProperty -Integrity $Integrity -Name 'OutputRelativeIndex')
    $method = Get-IntegrityResultProperty -Integrity $Integrity -Name 'Method'

    switch ($method)
    {
        'probe' {
            "Integrity mismatch for '{0}' [probe] - encoded file could not be probed" -f $Filename
        }
        'stream-missing' {
            if ($streamLabel)
            {
                "Integrity mismatch for '{0}' [stream-missing] - {1} is missing" -f $Filename, $streamLabel
            }
            else
            {
                "Integrity mismatch for '{0}' [stream-missing] - mapped output stream is missing" -f $Filename
            }
        }
        'timestamp-span' {
            "Integrity mismatch for '{0}' [timestamp-span] - {1} - span source {2:0.000}s, output {3:0.000}s, diff {4:0.000}s, tolerance {5:0.000}s" -f `
                $Filename, $streamLabel, `
                (Get-IntegrityResultProperty -Integrity $Integrity -Name 'Expected'), `
                (Get-IntegrityResultProperty -Integrity $Integrity -Name 'Actual'), `
                (Get-IntegrityResultProperty -Integrity $Integrity -Name 'Diff'), `
                (Get-IntegrityResultProperty -Integrity $Integrity -Name 'Tolerance')
        }
        'relative-offset' {
            $referenceLabel = Get-IntegrityStreamMapLabel `
                -StreamType (Get-IntegrityResultProperty -Integrity $Integrity -Name 'ReferenceStreamType') `
                -SourceRelativeIndex (Get-IntegrityResultProperty -Integrity $Integrity -Name 'ReferenceSourceRelativeIndex') `
                -OutputRelativeIndex (Get-IntegrityResultProperty -Integrity $Integrity -Name 'ReferenceOutputRelativeIndex')
            $diff = Get-IntegrityResultProperty -Integrity $Integrity -Name 'Diff'
            $tolerance = Get-IntegrityResultProperty -Integrity $Integrity -Name 'Tolerance'
            if ($streamLabel -and $referenceLabel)
            {
                "Integrity mismatch for '{0}' [relative-offset] - {1} vs reference {2} - relative start offset changed by {3:0.000}s (tolerance {4:0.000}s)" -f `
                    $Filename, $streamLabel, $referenceLabel, $diff, $tolerance
            }
            else
            {
                "Integrity mismatch for '{0}' [relative-offset] - relative start offset changed by {1:0.000}s (tolerance {2:0.000}s)" -f `
                    $Filename, $diff, $tolerance
            }
        }
        'interleave' {
            $spreadText = ConvertTo-IntegrityMibLabel -Bytes ([long](Get-IntegrityResultProperty -Integrity $Integrity -Name 'PhysicalSpreadBytes'))
            $limitText = ConvertTo-IntegrityMibLabel -Bytes ([long](Get-IntegrityResultProperty -Integrity $Integrity -Name 'PhysicalLimitBytes'))
            $percent = ''
            $anchorFraction = Get-IntegrityResultProperty -Integrity $Integrity -Name 'AnchorFraction'
            if ($null -ne $anchorFraction)
            {
                $percent = ' at {0}' -f ([double]$anchorFraction).ToString('0%', [cultureinfo]::InvariantCulture)
            }
            "Integrity mismatch for '{0}' [interleave] - A/V packet spread{1} is {2}, limit {3}" -f `
                $Filename, $percent, $spreadText, $limitText
        }
        default {
            if ($streamLabel)
            {
                "Integrity mismatch for '{0}' [{1}] - {2}" -f $Filename, $method, $streamLabel
            }
            else
            {
                "Integrity mismatch for '{0}' [{1}]" -f $Filename, $method
            }
        }
    }
}

function Get-IntegrityUnknownMessage
{
    param(
        [Parameter(Mandatory)] [string] $Filename,
        [Parameter(Mandatory)] $Integrity
    )

    $detail = Get-IntegrityUnknownDetail -Integrity $Integrity
    $method = Get-IntegrityResultProperty -Integrity $Integrity -Name 'Method'
    if ([string]::IsNullOrWhiteSpace($method))
    {
        $method = 'unknown'
    }
    "Integrity check inconclusive for '{0}' [{1}] - {2}; accepting file" -f $Filename, $method, $detail
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
        default { $null }
    }
    if ($null -eq $letter)
    {
        return $null
    }
    return ('source 0:{0}:{1} -> output 0:{0}:{2}' -f $letter, [int]$SourceRelativeIndex, [int]$OutputRelativeIndex)
}

function Get-OrderedIntegrityStreamMaps
{
    param($StreamMaps)

    $maps = @()
    if ($null -ne $StreamMaps)
    {
        foreach ($map in @($StreamMaps))
        {
            if ($null -ne $map)
            {
                $maps += $map
            }
        }
    }

    $ordered = @()
    foreach ($map in @($maps | Where-Object { $_.StreamType -eq 'video' } | Sort-Object OutputRelativeIndex))
    {
        $ordered += $map
    }
    foreach ($map in @($maps | Where-Object { $_.StreamType -eq 'audio' } | Sort-Object OutputRelativeIndex))
    {
        $ordered += $map
    }

    # `return @()` se déroule en $null : .Count lève sous StrictMode.
    return ConvertTo-IntegrityPacketArray -Packets $ordered
}

function Get-IntegrityProfileKey
{
    param($Map)
    return ('{0}:{1}' -f $Map.StreamSpecifierType, [int]$Map.OutputRelativeIndex)
}

function Get-IntegrityNearestPacket
{
    param(
        $Packets,
        [double] $Anchor
    )

    $best = $null
    $bestDist = [double]::PositiveInfinity
    foreach ($packet in @($Packets))
    {
        if ($null -eq $packet -or $null -eq $packet.PtsTime)
        {
            continue
        }
        $dist = [math]::Abs([double]$packet.PtsTime - $Anchor)
        if ($dist -lt $bestDist)
        {
            $bestDist = $dist
            $best = $packet
        }
    }

    return $best
}

function Test-IntegrityStreamActiveAtAnchor
{
    param(
        $TemporalProfile,
        [double] $Anchor
    )

    if ($null -eq $TemporalProfile -or $null -eq $TemporalProfile.FirstPtsTime -or $null -eq $TemporalProfile.LastPtsTime -or $null -eq $TemporalProfile.Cadence)
    {
        return $false
    }

    $cadence = [double]$TemporalProfile.Cadence
    return (
        $Anchor -ge ([double]$TemporalProfile.FirstPtsTime - $cadence) -and
        $Anchor -le ([double]$TemporalProfile.LastPtsTime + $cadence)
    )
}

function Get-IntegrityInterleaveCandidate
{
    param(
        $TemporalProfile,
        $Packets,
        [double] $Anchor,
        [double] $WindowStart,
        [double] $WindowEnd
    )

    if (-not (Test-IntegrityStreamActiveAtAnchor -TemporalProfile $TemporalProfile -Anchor $Anchor))
    {
        return [pscustomobject]@{ Status = 'inactive'; Packet = $null }
    }

    $packetsInWindow = Get-IntegrityPacketsInPtsRange `
        -Packets $Packets `
        -Start $WindowStart `
        -End $WindowEnd
    $candidate = Get-IntegrityNearestPacket -Packets $packetsInWindow -Anchor $Anchor
    if ($null -eq $candidate -or $null -eq $candidate.PtsTime)
    {
        return [pscustomobject]@{ Status = 'unknown'; Packet = $null }
    }

    $distance = [math]::Abs([double]$candidate.PtsTime - $Anchor)
    # Politique de projet : 2×cadence, pas une précision de timebase FFmpeg.
    if ($distance -gt (2.0 * [double]$TemporalProfile.Cadence))
    {
        return [pscustomobject]@{ Status = 'unknown'; Packet = $null }
    }

    if ($null -eq $candidate.Pos)
    {
        return [pscustomobject]@{ Status = 'unknown'; Packet = $null }
    }

    return [pscustomobject]@{ Status = 'ok'; Packet = $candidate }
}

function Get-IntegrityTargetedInterleaveCadence
{
    param(
        $TemporalProfile,
        $Packets
    )

    # La cadence locale n'est utilisable que si la tolérance de contemporanéité
    # qu'elle induit (2×cadence) reste strictement plus étroite que la demi-fenêtre
    # de recherche. Sinon tout packet trouvé dans cette fenêtre pourrait satisfaire
    # le critère de contemporanéité, ce qui reviendrait à réutiliser implicitement
    # ±IntegrityAnchorWindowSeconds comme tolérance.
    $localCadence = Get-IntegrityMedianPositivePtsDelta -Packets $Packets
    if ($null -ne $localCadence -and [double]$localCadence -gt 0 -and ((2.0 * [double]$localCadence) -lt $script:IntegrityAnchorWindowSeconds))
    {
        return [double]$localCadence
    }

    if ($null -ne $TemporalProfile)
    {
        $profileCadence = ConvertTo-IntegrityFiniteDouble -Value $TemporalProfile.Cadence
        if ($null -ne $profileCadence -and $profileCadence -gt 0)
        {
            return $profileCadence
        }

        $edgeCadences = @()
        foreach ($value in @($TemporalProfile.StartCadence, $TemporalProfile.EndCadence))
        {
            $cadence = ConvertTo-IntegrityFiniteDouble -Value $value
            if ($null -ne $cadence -and $cadence -gt 0)
            {
                $edgeCadences += $cadence
            }
        }

        if ($edgeCadences.Count -gt 0)
        {
            return [double]($edgeCadences | Measure-Object -Maximum).Maximum
        }
    }

    return $null
}

function Get-IntegrityTargetedInterleaveCandidate
{
    param(
        $TemporalProfile,
        $Packets,
        [double] $Anchor,
        [double] $WindowStart,
        [double] $WindowEnd
    )

    $packetsInWindow = Get-IntegrityPacketsInPtsRange `
        -Packets $Packets `
        -Start $WindowStart `
        -End $WindowEnd

    $candidate = Get-IntegrityNearestPacket -Packets $packetsInWindow -Anchor $Anchor
    if ($null -eq $candidate -or $null -eq $candidate.PtsTime)
    {
        return [pscustomobject]@{
            Status  = 'unknown'
            Packet  = $null
            Cadence = $null
            Reason  = 'no-anchor-candidate'
        }
    }

    $cadence = Get-IntegrityTargetedInterleaveCadence `
        -TemporalProfile $TemporalProfile `
        -Packets $packetsInWindow
    if ($null -eq $cadence)
    {
        return [pscustomobject]@{
            Status  = 'unknown'
            Packet  = $null
            Cadence = $null
            Reason  = 'no-anchor-cadence'
        }
    }

    $distance = [math]::Abs([double]$candidate.PtsTime - [double]$Anchor)
    if ($distance -gt (2.0 * $cadence))
    {
        return [pscustomobject]@{
            Status  = 'unknown'
            Packet  = $null
            Cadence = $cadence
            Reason  = 'no-anchor-candidate'
        }
    }

    if ($null -eq $candidate.Pos)
    {
        return [pscustomobject]@{
            Status  = 'unknown'
            Packet  = $null
            Cadence = $cadence
            Reason  = 'no-anchor-candidate'
        }
    }

    return [pscustomobject]@{
        Status  = 'ok'
        Packet  = $candidate
        Cadence = $cadence
        Reason  = $null
    }
}

function New-IntegrityInterleaveUnknownResult
{
    param(
        $Map,
        [string] $Reason,
        [double] $Anchor
    )

    return New-IntegrityCheckResult `
        -Status 'unknown' `
        -Method 'interleave' `
        -Reason $Reason `
        -StreamType $Map.StreamType `
        -SourceRelativeIndex $Map.SourceRelativeIndex `
        -OutputRelativeIndex $Map.OutputRelativeIndex `
        -AnchorTime $Anchor
}

function Get-IntegrityTargetedInterleaveFallback
{
    param(
        [Parameter(Mandatory)] [string] $FFPROBE,
        [Parameter(Mandatory)] [string] $File,
        $Map,
        [Parameter(Mandatory)] [string] $ReadIntervals,
        $TemporalProfile,
        [double] $Anchor,
        [double] $WindowStart,
        [double] $WindowEnd,
        [switch] $UseProfileCadence
    )

    $specifier = '{0}:{1}' -f $Map.StreamSpecifierType, [int]$Map.OutputRelativeIndex
    $targeted = Get-IntegrityTargetedInterleavePackets `
        -FFPROBE $FFPROBE `
        -File $File `
        -StreamSpecifier $specifier `
        -ReadIntervals $ReadIntervals
    if ($null -eq $targeted)
    {
        return [pscustomobject]@{
            Status = 'unknown'
            Packet = $null
            Reason = 'anchor-probe-failed'
        }
    }

    if ($UseProfileCadence)
    {
        $picked = Get-IntegrityInterleaveCandidate `
            -TemporalProfile $TemporalProfile `
            -Packets $targeted `
            -Anchor $Anchor `
            -WindowStart $WindowStart `
            -WindowEnd $WindowEnd
        if ($picked.Status -eq 'ok' -or $picked.Status -eq 'inactive')
        {
            return $picked
        }

        return [pscustomobject]@{
            Status = 'unknown'
            Packet = $null
            Reason = 'no-anchor-candidate'
        }
    }

    return Get-IntegrityTargetedInterleaveCandidate `
        -TemporalProfile $TemporalProfile `
        -Packets $targeted `
        -Anchor $Anchor `
        -WindowStart $WindowStart `
        -WindowEnd $WindowEnd
}

function Test-IntegrityOutputInterleave
{
    param(
        [Parameter(Mandatory)] [string] $FFPROBE,
        [Parameter(Mandatory)] [string] $TempFile,
        [object[]] $StreamMaps,
        [hashtable] $OutputProfiles,
        $WindowCache
    )

    $maps = Get-OrderedIntegrityStreamMaps -StreamMaps $StreamMaps
    if ($maps.Count -lt 2)
    {
        return New-IntegrityCheckResult -Status 'ok' -Method 'interleave' -Reason 'not-applicable'
    }

    $referenceMap = @($maps | Where-Object { $_.StreamType -eq 'video' } | Select-Object -First 1)
    if ($referenceMap.Count -eq 0)
    {
        $referenceMap = @($maps | Select-Object -First 1)
    }
    $referenceMap = $referenceMap[0]
    $referenceKey = Get-IntegrityProfileKey -Map $referenceMap
    $referenceProfile = $OutputProfiles[$referenceKey]
    if ($null -eq $referenceProfile -or $null -eq $referenceProfile.FirstPtsTime -or $null -eq $referenceProfile.LastPtsTime)
    {
        return New-IntegrityCheckResult -Status 'unknown' -Method 'interleave' -Reason 'no-start-pts' `
            -StreamType $referenceMap.StreamType `
            -SourceRelativeIndex $referenceMap.SourceRelativeIndex `
            -OutputRelativeIndex $referenceMap.OutputRelativeIndex
    }

    $referenceStart = [double]$referenceProfile.FirstPtsTime
    $referenceEnd = [double]$referenceProfile.LastPtsTime
    $referenceSpan = $referenceEnd - $referenceStart
    $unknownResult = $null
    # Politique de projet : sampling borné à 5 anchors, pas un parcours de tous les clusters.
    $fractions = @(0.0, 0.25, 0.50, 0.75, 1.0)

    foreach ($fraction in $fractions)
    {
        $anchor = $referenceStart + $fraction * $referenceSpan
        $search = Get-IntegrityAnchorSearchWindow -Anchor $anchor
        $commonPackets = Get-CachedIntegrityPacketWindow `
            -Cache $WindowCache `
            -FFPROBE $FFPROBE `
            -File $TempFile `
            -ReadIntervals $search.ReadIntervals

        if ($null -eq $commonPackets)
        {
            $unknownResult ??= New-IntegrityInterleaveUnknownResult `
                -Map $referenceMap `
                -Reason 'anchor-probe-failed' `
                -Anchor $anchor
            continue
        }

        $candidates = @()
        foreach ($map in $maps)
        {
            $key = Get-IntegrityProfileKey -Map $map
            $temporalProfile = $OutputProfiles[$key]
            $profileUsable = (
                $null -ne $temporalProfile -and
                $null -ne $temporalProfile.Cadence -and
                $null -ne $temporalProfile.FirstPtsTime -and
                $null -ne $temporalProfile.LastPtsTime
            )

            if (-not $profileUsable)
            {
                # Profil temporel inexploitable : sonde PAR STREAM. Un flux
                # physiquement retardé est absent de la fenêtre fichier commune.
                $picked = Get-IntegrityTargetedInterleaveFallback `
                    -FFPROBE $FFPROBE `
                    -File $TempFile `
                    -Map $map `
                    -ReadIntervals $search.ReadIntervals `
                    -TemporalProfile $temporalProfile `
                    -Anchor $anchor `
                    -WindowStart $search.PtsStart `
                    -WindowEnd $search.PtsEnd
                if ($picked.Status -ne 'ok')
                {
                    $unknownResult ??= New-IntegrityInterleaveUnknownResult `
                        -Map $map `
                        -Reason $picked.Reason `
                        -Anchor $anchor
                    continue
                }

                $candidates += $picked.Packet
                continue
            }

            if (-not (Test-IntegrityStreamActiveAtAnchor -TemporalProfile $temporalProfile -Anchor $anchor))
            {
                continue
            }

            $streamIndex = ConvertTo-IntegrityNonNegativeInt64 -Value $temporalProfile.AbsoluteStreamIndex
            $packets = if ($null -eq $streamIndex)
            {
                ConvertTo-IntegrityPacketArray -Packets @()
            }
            else
            {
                Get-IntegrityPacketsForAbsoluteStream -Packets $commonPackets -AbsoluteStreamIndex ([int]$streamIndex)
            }

            $picked = Get-IntegrityInterleaveCandidate `
                -TemporalProfile $temporalProfile `
                -Packets $packets `
                -Anchor $anchor `
                -WindowStart $search.PtsStart `
                -WindowEnd $search.PtsEnd
            if ($picked.Status -eq 'inactive')
            {
                continue
            }

            if ($picked.Status -ne 'ok')
            {
                # Le fallback ciblé peut être plus coûteux parce qu'il cherche précisément
                # un stream physiquement retardé. Son usage est limité aux anchors où la
                # sonde commune n'a pas retrouvé un stream actif.
                $picked = Get-IntegrityTargetedInterleaveFallback `
                    -FFPROBE $FFPROBE `
                    -File $TempFile `
                    -Map $map `
                    -ReadIntervals $search.ReadIntervals `
                    -TemporalProfile $temporalProfile `
                    -Anchor $anchor `
                    -WindowStart $search.PtsStart `
                    -WindowEnd $search.PtsEnd `
                    -UseProfileCadence
                if ($picked.Status -eq 'inactive')
                {
                    continue
                }
                if ($picked.Status -ne 'ok')
                {
                    $unknownResult ??= New-IntegrityInterleaveUnknownResult `
                        -Map $map `
                        -Reason $picked.Reason `
                        -Anchor $anchor
                    continue
                }
            }

            $candidates += $picked.Packet
        }

        if ($candidates.Count -lt 2)
        {
            continue
        }

        $minPos = $null
        $maxPos = $null
        $largestSize = 0L
        foreach ($packet in $candidates)
        {
            $pos = [long]$packet.Pos
            if ($null -eq $minPos -or $pos -lt $minPos)
            {
                $minPos = $pos
            }
            if ($null -eq $maxPos -or $pos -gt $maxPos)
            {
                $maxPos = $pos
            }
            if ($null -ne $packet.Size -and [long]$packet.Size -gt $largestSize)
            {
                $largestSize = [long]$packet.Size
            }
        }

        $spread = $maxPos - $minPos
        $limit = (2L * $script:IntegrityClusterBudgetBytes) + $largestSize
        if ($spread -gt $limit)
        {
            return New-IntegrityCheckResult `
                -Status 'mismatch' `
                -Method 'interleave' `
                -Reason 'interleave-spread' `
                -Diff ([double]$spread) `
                -Tolerance ([double]$limit) `
                -AnchorTime $anchor `
                -AnchorFraction $fraction `
                -PhysicalSpreadBytes $spread `
                -PhysicalLimitBytes $limit `
                -StreamType $referenceMap.StreamType `
                -SourceRelativeIndex $referenceMap.SourceRelativeIndex `
                -OutputRelativeIndex $referenceMap.OutputRelativeIndex
        }
    }

    if ($null -ne $unknownResult)
    {
        return $unknownResult
    }

    return New-IntegrityCheckResult -Status 'ok' -Method 'interleave'
}

function Get-IntegrityRelativeOffsetUnknownReason
{
    param($SourceProfile, $OutputProfile, $SourceReference, $OutputReference)

    foreach ($candidate in @($SourceProfile, $OutputProfile, $SourceReference, $OutputReference))
    {
        if ($null -eq $candidate -or $null -eq $candidate.FirstPtsTime)
        {
            return 'no-start-pts'
        }
        if ($null -eq $candidate.StartCadence -or [double]$candidate.StartCadence -le 0)
        {
            return 'no-start-cadence'
        }
    }

    return 'no-start-pts'
}

function Test-EncodedFileIntegrity
{
    param(
        [Parameter(Mandatory)] [string] $FFPROBE,
        [Parameter(Mandatory)] [hashtable] $SourceProbe,
        [Parameter(Mandatory)] [string] $SourceFile,
        [Parameter(Mandatory)] [string] $TempFile,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $StreamMaps
    )

    $tempProbe = Get-FFprobeJson -FFPROBE $FFPROBE -File $TempFile
    if ($null -eq $tempProbe)
    {
        return New-IntegrityCheckResult -Status 'mismatch' -Method 'probe' -Reason 'output-probe-failed'
    }

    $maps = Get-OrderedIntegrityStreamMaps -StreamMaps $StreamMaps
    if ($maps.Count -eq 0)
    {
        return New-IntegrityCheckResult -Status 'ok' -Method 'complete' -Reason 'not-applicable'
    }
    $unknownResult = $null
    $sourceProfiles = @{}
    $outputProfiles = @{}
    $sourceWindowCache = @{}
    $outputWindowCache = @{}

    foreach ($map in $maps)
    {
        $sourceStream = Get-ProbeStreamByRelativeIndex `
            -Probe $SourceProbe `
            -CodecType $map.StreamType `
            -TypeRelativeIndex ([int]$map.SourceRelativeIndex)

        $outputStream = Get-ProbeStreamByRelativeIndex `
            -Probe $tempProbe `
            -CodecType $map.StreamType `
            -TypeRelativeIndex ([int]$map.OutputRelativeIndex)

        if ($null -eq $outputStream)
        {
            return New-IntegrityCheckResult `
                -Status 'mismatch' `
                -Method 'stream-missing' `
                -Reason 'mapped-output-stream-missing' `
                -StreamType $map.StreamType `
                -SourceRelativeIndex $map.SourceRelativeIndex `
                -OutputRelativeIndex $map.OutputRelativeIndex
        }

        $key = Get-IntegrityProfileKey -Map $map
        $outputProfile = Get-IntegrityTemporalProfile `
            -FFPROBE $FFPROBE `
            -File $TempFile `
            -Probe $tempProbe `
            -Stream $outputStream `
            -WindowCache $outputWindowCache
        $outputProfiles[$key] = $outputProfile

        if ($null -eq $sourceStream)
        {
            $unknownResult ??= New-IntegrityCheckResult `
                -Status 'unknown' `
                -Method 'timestamp-span' `
                -Reason 'mapped-source-stream-missing' `
                -StreamType $map.StreamType `
                -SourceRelativeIndex $map.SourceRelativeIndex `
                -OutputRelativeIndex $map.OutputRelativeIndex
            continue
        }

        $sourceProfile = Get-IntegrityTemporalProfile `
            -FFPROBE $FFPROBE `
            -File $SourceFile `
            -Probe $SourceProbe `
            -Stream $sourceStream `
            -WindowCache $sourceWindowCache
        $sourceProfiles[$key] = $sourceProfile

        if (-not $sourceProfile.IsUsable -or -not $outputProfile.IsUsable)
        {
            $side = if (-not $outputProfile.IsUsable) { 'output' } else { 'source' }
            $reason = if ($side -eq 'output') { $outputProfile.UnknownReason } else { $sourceProfile.UnknownReason }
            $unknownResult ??= New-IntegrityCheckResult `
                -Status 'unknown' `
                -Method 'timestamp-span' `
                -Reason $reason `
                -StreamType $map.StreamType `
                -SourceRelativeIndex $map.SourceRelativeIndex `
                -OutputRelativeIndex $map.OutputRelativeIndex `
                -Side $side
            continue
        }

        $diff = [math]::Abs([double]$sourceProfile.SpanSeconds - [double]$outputProfile.SpanSeconds)
        # Politique de projet : 2×(Qs+Qo) pour absorber une granularité différente
        # source/sortie. Ce n'est pas un pourcentage de durée.
        $tolerance = 2.0 * ([double]$sourceProfile.Cadence + [double]$outputProfile.Cadence)
        if ($diff -gt $tolerance)
        {
            return New-IntegrityCheckResult `
                -Status 'mismatch' `
                -Method 'timestamp-span' `
                -Reason 'span-mismatch' `
                -Expected $sourceProfile.SpanSeconds `
                -Actual $outputProfile.SpanSeconds `
                -Diff $diff `
                -Tolerance $tolerance `
                -StreamType $map.StreamType `
                -SourceRelativeIndex $map.SourceRelativeIndex `
                -OutputRelativeIndex $map.OutputRelativeIndex
        }
    }

    $referenceMap = @($maps | Where-Object { $_.StreamType -eq 'video' } | Select-Object -First 1)
    if ($referenceMap.Count -eq 0)
    {
        $referenceMap = @($maps | Select-Object -First 1)
    }

    if ($referenceMap.Count -gt 0)
    {
        $referenceMap = $referenceMap[0]
        $referenceKey = Get-IntegrityProfileKey -Map $referenceMap
        foreach ($map in $maps)
        {
            if ($map -eq $referenceMap)
            {
                continue
            }

            $key = Get-IntegrityProfileKey -Map $map
            $sourceProfile = $sourceProfiles[$key]
            $outputProfile = $outputProfiles[$key]
            $sourceReference = $sourceProfiles[$referenceKey]
            $outputReference = $outputProfiles[$referenceKey]

            $canCompare = (
                $null -ne $sourceProfile -and $null -ne $outputProfile -and
                $null -ne $sourceReference -and $null -ne $outputReference -and
                $null -ne $sourceProfile.FirstPtsTime -and $null -ne $outputProfile.FirstPtsTime -and
                $null -ne $sourceReference.FirstPtsTime -and $null -ne $outputReference.FirstPtsTime -and
                $null -ne $sourceProfile.StartCadence -and $sourceProfile.StartCadence -gt 0 -and
                $null -ne $outputProfile.StartCadence -and $outputProfile.StartCadence -gt 0 -and
                $null -ne $sourceReference.StartCadence -and $sourceReference.StartCadence -gt 0 -and
                $null -ne $outputReference.StartCadence -and $outputReference.StartCadence -gt 0
            )

            if (-not $canCompare)
            {
                $unknownResult ??= New-IntegrityCheckResult `
                    -Status 'unknown' `
                    -Method 'relative-offset' `
                    -Reason (Get-IntegrityRelativeOffsetUnknownReason `
                        -SourceProfile $sourceProfile `
                        -OutputProfile $outputProfile `
                        -SourceReference $sourceReference `
                        -OutputReference $outputReference) `
                    -StreamType $map.StreamType `
                    -SourceRelativeIndex $map.SourceRelativeIndex `
                    -OutputRelativeIndex $map.OutputRelativeIndex `
                    -ReferenceStreamType $referenceMap.StreamType `
                    -ReferenceSourceRelativeIndex $referenceMap.SourceRelativeIndex `
                    -ReferenceOutputRelativeIndex $referenceMap.OutputRelativeIndex
                continue
            }

            $sourceOffset = [double]$sourceProfile.FirstPtsTime - [double]$sourceReference.FirstPtsTime
            $outputOffset = [double]$outputProfile.FirstPtsTime - [double]$outputReference.FirstPtsTime
            $diff = [math]::Abs($sourceOffset - $outputOffset)
            # Politique de projet : somme des quatre StartCadence (source/sortie × flux/référence).
            $tolerance = (
                [double]$sourceProfile.StartCadence +
                [double]$sourceReference.StartCadence +
                [double]$outputProfile.StartCadence +
                [double]$outputReference.StartCadence
            )

            if ($diff -gt $tolerance)
            {
                return New-IntegrityCheckResult `
                    -Status 'mismatch' `
                    -Method 'relative-offset' `
                    -Reason 'relative-offset-mismatch' `
                    -Expected $sourceOffset `
                    -Actual $outputOffset `
                    -Diff $diff `
                    -Tolerance $tolerance `
                    -StreamType $map.StreamType `
                    -SourceRelativeIndex $map.SourceRelativeIndex `
                    -OutputRelativeIndex $map.OutputRelativeIndex `
                    -ReferenceStreamType $referenceMap.StreamType `
                    -ReferenceSourceRelativeIndex $referenceMap.SourceRelativeIndex `
                    -ReferenceOutputRelativeIndex $referenceMap.OutputRelativeIndex
            }
        }
    }

    $interleave = Test-IntegrityOutputInterleave `
        -FFPROBE $FFPROBE `
        -TempFile $TempFile `
        -StreamMaps $maps `
        -OutputProfiles $outputProfiles `
        -WindowCache $outputWindowCache

    if ($interleave.Status -eq 'mismatch')
    {
        return $interleave
    }

    if ($interleave.Status -eq 'unknown')
    {
        $unknownResult ??= $interleave
    }

    if ($null -ne $unknownResult)
    {
        return $unknownResult
    }

    return New-IntegrityCheckResult -Status 'ok' -Method 'complete'
}
