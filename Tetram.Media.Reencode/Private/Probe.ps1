using namespace System
using namespace System.IO

Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# Probe.psm1 — ffprobe + extraction des durées + contrôle d'intégrité
# Sous-module privé de Tetram.Media.Reencode (chargé via NestedModules).
# Ne fait pas Export-ModuleMember : les fonctions restent visibles dans le
# scope du module Reencode mais ne fuient pas vers la session utilisateur.
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

function Get-DurationFromFormat
{
    param([hashtable] $Probe)
    if ($null -eq $Probe)
    {
        return $null
    }
    $fmt = $Probe['format']
    if (-not ($fmt -is [hashtable]))
    {
        return $null
    }
    $d = $fmt['duration']
    if ($null -eq $d)
    {
        return $null
    }
    $ds = [string]$d
    if ( [string]::IsNullOrWhiteSpace($ds))
    {
        return $null
    }
    try
    {
        $sec = [double]::Parse($ds, [cultureinfo]::InvariantCulture)
        if ($sec -gt 0)
        {
            return $sec
        }
    }
    catch
    {
    }
    return $null
}


function Get-ParsedDurationSeconds
{
    param($Value)
    if ($null -eq $Value)
    {
        return $null
    }
    $ds = [string]$Value
    if ([string]::IsNullOrWhiteSpace($ds))
    {
        return $null
    }
    try
    {
        $sec = [double]::Parse($ds, [cultureinfo]::InvariantCulture)
        # 0 est une durée mesurée (flux vide / tronqué), pas une métadonnée absente.
        if ($sec -ge 0)
        {
            return $sec
        }
    }
    catch
    {
    }
    return $null
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

function Get-DurationFromSpecificStream
{
    param(
        [hashtable] $Probe,
        [string] $CodecType,
        [int] $TypeRelativeIndex
    )
    $stream = Get-ProbeStreamByRelativeIndex -Probe $Probe -CodecType $CodecType -TypeRelativeIndex $TypeRelativeIndex
    if ($null -eq $stream)
    {
        return $null
    }
    return Get-ParsedDurationSeconds -Value $stream['duration']
}

function ConvertTo-DurationSeconds
{
    param([string] $Tag)
    if ( [string]::IsNullOrWhiteSpace($Tag))
    {
        return $null
    }
    $s = $Tag.Trim()
    $dot = $s.IndexOf('.')
    if ($dot -ge 0 -and ($s.Length - $dot - 1) -gt 7)
    {
        $s = $s.Substring(0, $dot + 1 + 7)
    }
    try
    {
        $ts = [TimeSpan]::Parse($s, [cultureinfo]::InvariantCulture)
        $sec = $ts.TotalSeconds
        if ($sec -ge 0)
        {
            return $sec
        }
    }
    catch
    {
    }
    return $null
}

function Get-DurationFromSpecificStreamTag
{
    param(
        [hashtable] $Probe,
        [string] $CodecType,
        [int] $TypeRelativeIndex
    )
    $stream = Get-ProbeStreamByRelativeIndex -Probe $Probe -CodecType $CodecType -TypeRelativeIndex $TypeRelativeIndex
    if ($null -eq $stream)
    {
        return $null
    }
    $tags = $stream['tags']
    if ($null -eq $tags)
    {
        return $null
    }
    # OrderedHashtable (Get-FFprobeJson) : ContainsKey('DURATION') rate la clé JSON duration.
    # Hashtable @{} des tests unitaires ne reproduit pas ce piège.
    $raw = Get-ProbeProperty $tags 'DURATION'
    if ($null -eq $raw)
    {
        return $null
    }
    return ConvertTo-DurationSeconds -Tag ([string]$raw)
}

function Get-DurationForStreamMetadata
{
    param(
        [hashtable] $Probe,
        [string] $CodecType,
        [int] $TypeRelativeIndex
    )
    $streamDuration = Get-DurationFromSpecificStream -Probe $Probe -CodecType $CodecType -TypeRelativeIndex $TypeRelativeIndex
    if ($null -ne $streamDuration)
    {
        return [pscustomobject]@{ Method = 'stream'; Duration = $streamDuration }
    }
    $tagDuration = Get-DurationFromSpecificStreamTag -Probe $Probe -CodecType $CodecType -TypeRelativeIndex $TypeRelativeIndex
    if ($null -ne $tagDuration)
    {
        return [pscustomobject]@{ Method = 'tag'; Duration = $tagDuration }
    }
    return $null
}

function Get-DurationFromPacketCount
{
    param(
        [string] $FFPROBE,
        [string] $File,
        [int] $StreamIndex = 0
    )
    if ([string]::IsNullOrWhiteSpace($File) -or -not [File]::Exists($File))
    {
        return $null
    }
    if ($StreamIndex -lt 0)
    {
        return $null
    }
    $ffprobeArgs = @(
        $File,
        '-v', 'error',
        '-select_streams', "v:$StreamIndex",
        '-count_packets',
        '-show_entries', 'stream=nb_read_packets,r_frame_rate',
        '-of', 'json'
    )
    $out = & $FFPROBE $ffprobeArgs 2> $null | Out-String
    if (-not $?)
    {
        return $null
    }
    try
    {
        $j = ConvertFrom-Json -InputObject $out -AsHashtable
    }
    catch
    {
        return $null
    }
    $streams = $j['streams']
    if ($null -eq $streams)
    {
        return $null
    }
    $st = @($streams)[0]
    if (-not ($st -is [hashtable]))
    {
        return $null
    }
    $nb = $st['nb_read_packets']
    $rfr = $st['r_frame_rate']
    if ($null -eq $nb -or $null -eq $rfr)
    {
        return $null
    }
    try
    {
        $n = [long]::Parse([string]$nb, [cultureinfo]::InvariantCulture)
    }
    catch
    {
        return $null
    }
    if ($n -le 0)
    {
        return $null
    }
    $rate = [string]$rfr
    if ($rate -match '^(\d+)/(\d+)$')
    {
        $num = [double]$Matches[1]
        $den = [double]$Matches[2]
        if ($num -le 0 -or $den -le 0)
        {
            return $null
        }
        return $n * $den / $num
    }
    try
    {
        $fps = [double]::Parse($rate, [cultureinfo]::InvariantCulture)
        if ($fps -le 0)
        {
            return $null
        }
        return $n / $fps
    }
    catch
    {
        return $null
    }
}

function Get-ComparableStreamDurationPair
{
    param(
        [hashtable] $SourceProbe,
        [hashtable] $TempProbe,
        [string] $CodecType,
        [int] $SourceRelativeIndex,
        [int] $OutputRelativeIndex,
        [string] $FFPROBE,
        [string] $SourceFile,
        [string] $TempFile
    )

    $outputStream = Get-ProbeStreamByRelativeIndex -Probe $TempProbe -CodecType $CodecType -TypeRelativeIndex $OutputRelativeIndex
    if ($null -eq $outputStream)
    {
        $sourceMeta = Get-DurationForStreamMetadata -Probe $SourceProbe -CodecType $CodecType -TypeRelativeIndex $SourceRelativeIndex
        $sourceDuration = if ($null -ne $sourceMeta) { $sourceMeta.Duration } else { $null }
        return [pscustomobject]@{ Method = 'stream'; Source = $sourceDuration; Temp = $null; OutputMissing = $true }
    }

    # stream.duration et tag DURATION du même flux mappé désignent la même grandeur ;
    # les conteneurs ne l'exposent pas par le même canal (mp4 vs mkv).
    $sourceMeta = Get-DurationForStreamMetadata -Probe $SourceProbe -CodecType $CodecType -TypeRelativeIndex $SourceRelativeIndex
    $tempMeta = Get-DurationForStreamMetadata -Probe $TempProbe -CodecType $CodecType -TypeRelativeIndex $OutputRelativeIndex
    if ($null -ne $sourceMeta -and $null -ne $tempMeta)
    {
        $method = if ($sourceMeta.Method -eq $tempMeta.Method) { $sourceMeta.Method } else { 'stream' }
        return [pscustomobject]@{ Method = $method; Source = $sourceMeta.Duration; Temp = $tempMeta.Duration; OutputMissing = $false }
    }

    if ($CodecType -eq 'video')
    {
        $sourceDuration = Get-DurationFromPacketCount -FFPROBE $FFPROBE -File $SourceFile -StreamIndex $SourceRelativeIndex
        $tempDuration = Get-DurationFromPacketCount -FFPROBE $FFPROBE -File $TempFile -StreamIndex $OutputRelativeIndex
        if ($null -ne $sourceDuration -and $null -ne $tempDuration)
        {
            return [pscustomobject]@{ Method = 'count'; Source = $sourceDuration; Temp = $tempDuration; OutputMissing = $false }
        }
    }

    return $null
}

function Get-DurationComparison
{
    param(
        [double] $Expected,
        [double] $Actual,
        [double] $TolerancePercent,
        [double] $ToleranceSecondsMin
    )
    $diff = [math]::Abs($Expected - $Actual)
    $tolerance = [math]::Max($ToleranceSecondsMin, $Expected * $TolerancePercent / 100.0)
    [pscustomobject]@{
        Diff = $diff
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
        $OutputRelativeIndex = $null
    )
    [pscustomobject]@{
        Status = $Status
        Method = $Method
        Expected = $Expected
        Actual = $Actual
        Diff = $Diff
        StreamType = $StreamType
        SourceRelativeIndex = $SourceRelativeIndex
        OutputRelativeIndex = $OutputRelativeIndex
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

function Find-KeptStreamDurationMismatch
{
    param(
        [string] $CodecType,
        [int[]] $KeptIndices,
        [hashtable] $SourceProbe,
        [hashtable] $TempProbe,
        [string] $FFPROBE,
        [string] $SourceFile,
        [string] $TempFile,
        [double] $TolerancePercent,
        [double] $ToleranceSecondsMin,
        [ref] $HadUnknownStream,
        [ref] $LastOk
    )

    # Copie vers List[int] plutôt que `$kept = if (...) { @() } else { @($KeptIndices) }` :
    # l'expression `if` déballe un tableau à un élément, et `.Count` lève sous StrictMode.
    $kept = [System.Collections.Generic.List[int]]::new()
    if ($null -ne $KeptIndices)
    {
        foreach ($idx in $KeptIndices)
        {
            $kept.Add([int]$idx)
        }
    }
    for ($outputRelativeIndex = 0; $outputRelativeIndex -lt $kept.Count; $outputRelativeIndex++)
    {
        $sourceRelativeIndex = [int]$kept[$outputRelativeIndex]
        $pair = Get-ComparableStreamDurationPair `
            -SourceProbe $SourceProbe `
            -TempProbe $TempProbe `
            -CodecType $CodecType `
            -SourceRelativeIndex $sourceRelativeIndex `
            -OutputRelativeIndex $outputRelativeIndex `
            -FFPROBE $FFPROBE `
            -SourceFile $SourceFile `
            -TempFile $TempFile
        if ($null -eq $pair)
        {
            # Un flux indéterminable ne doit pas masquer un mismatch plus loin.
            $HadUnknownStream.Value = $true
            continue
        }
        if ($pair.OutputMissing)
        {
            return New-IntegrityCheckResult -Status 'mismatch' -Method $pair.Method -Expected $pair.Source -Actual $null `
                -StreamType $CodecType -SourceRelativeIndex $sourceRelativeIndex -OutputRelativeIndex $outputRelativeIndex
        }

        $streamCmp = Get-DurationComparison `
            -Expected $pair.Source `
            -Actual $pair.Temp `
            -TolerancePercent $TolerancePercent `
            -ToleranceSecondsMin $ToleranceSecondsMin
        if ($streamCmp.IsMismatch)
        {
            return New-IntegrityCheckResult -Status 'mismatch' -Method $pair.Method -Expected $pair.Source -Actual $pair.Temp -Diff $streamCmp.Diff `
                -StreamType $CodecType -SourceRelativeIndex $sourceRelativeIndex -OutputRelativeIndex $outputRelativeIndex
        }
        $LastOk.Value = New-IntegrityCheckResult -Status 'ok' -Method $pair.Method -Expected $pair.Source -Actual $pair.Temp -Diff $streamCmp.Diff `
            -StreamType $CodecType -SourceRelativeIndex $sourceRelativeIndex -OutputRelativeIndex $outputRelativeIndex
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

    # format.duration prouve un média incorrect, jamais qu'il est complet.
    $lastOk = $null
    $sourceFormat = Get-DurationFromFormat -Probe $SourceProbe
    $tempFormat = Get-DurationFromFormat -Probe $tempProbe
    if ($null -ne $sourceFormat -and $null -ne $tempFormat)
    {
        $formatCmp = Get-DurationComparison `
            -Expected $sourceFormat `
            -Actual $tempFormat `
            -TolerancePercent $TolerancePercent `
            -ToleranceSecondsMin $ToleranceSecondsMin
        if ($formatCmp.IsMismatch)
        {
            return New-IntegrityCheckResult -Status 'mismatch' -Method 'format' -Expected $sourceFormat -Actual $tempFormat -Diff $formatCmp.Diff
        }
    }

    $hadUnknownStream = $false
    $streamTypeArgs = @{
        SourceProbe = $SourceProbe
        TempProbe = $tempProbe
        FFPROBE = $FFPROBE
        SourceFile = $SourceFile
        TempFile = $TempFile
        TolerancePercent = $TolerancePercent
        ToleranceSecondsMin = $ToleranceSecondsMin
        HadUnknownStream = [ref]$hadUnknownStream
        LastOk = [ref]$lastOk
    }
    foreach ($codecType in @('video', 'audio', 'subtitle'))
    {
        $keptIndices = switch ($codecType)
        {
            'video' { $KeptSourceVideoIndices }
            'audio' { $KeptSourceAudioIndices }
            'subtitle' { $KeptSourceSubtitleIndices }
        }
        $mismatch = Find-KeptStreamDurationMismatch @streamTypeArgs -CodecType $codecType -KeptIndices $keptIndices
        if ($null -ne $mismatch)
        {
            return $mismatch
        }
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
