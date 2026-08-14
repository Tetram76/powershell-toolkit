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


function Get-DurationFromStreams
{
    param(
        [hashtable] $Probe,
        [int[]] $KeptSourceVideoIndices = $null,
        [int[]] $KeptSourceAudioIndices = $null
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
    $arr = @($streams)
    foreach ($prefer in @('video', 'audio'))
    {
        $kept = if ($prefer -eq 'video')
        {
            $KeptSourceVideoIndices
        }
        else
        {
            $KeptSourceAudioIndices
        }
        $relIdx = -1
        foreach ($s in $arr)
        {
            if (-not ($s -is [hashtable]))
            {
                continue
            }
            if ($s['codec_type'] -ne $prefer)
            {
                continue
            }
            $relIdx++
            if ($null -ne $kept -and -not ($kept -contains $relIdx))
            {
                continue
            }
            $d = $s['duration']
            if ($null -eq $d)
            {
                continue
            }
            $ds = [string]$d
            if ( [string]::IsNullOrWhiteSpace($ds))
            {
                continue
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
        }
    }
    return $null
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

function Get-DurationFromTags
{
    param(
        [hashtable] $Probe,
        [int[]] $KeptSourceVideoIndices = $null,
        [int[]] $KeptSourceAudioIndices = $null
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
    $arr = @($streams)
    foreach ($prefer in @('video', 'audio'))
    {
        $kept = if ($prefer -eq 'video')
        {
            $KeptSourceVideoIndices
        }
        else
        {
            $KeptSourceAudioIndices
        }
        $relIdx = -1
        foreach ($s in $arr)
        {
            if (-not ($s -is [hashtable]) -or $s['codec_type'] -ne $prefer)
            {
                continue
            }
            $relIdx++
            if ($null -ne $kept -and -not ($kept -contains $relIdx))
            {
                continue
            }
            $tags = $s['tags']
            if (-not ($tags -is [hashtable]))
            {
                continue
            }
            $dur = $null
            foreach ($key in @('DURATION', 'duration'))
            {
                if ( $tags.ContainsKey($key))
                {
                    $dur = $tags[$key]; break
                }
            }
            if ($null -ne $dur)
            {
                $parsed = ConvertTo-DurationSeconds -Tag ([string]$dur)
                if ($null -ne $parsed)
                {
                    return $parsed
                }
            }
        }
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

function Get-ComparableDurationPair
{
    param(
        [Parameter(Mandatory)] [string] $FFPROBE,
        [Parameter(Mandatory)] [hashtable] $SourceProbe,
        [Parameter(Mandatory)] [string] $SourceFile,
        [Parameter(Mandatory)] [string] $TempFile,
        [int[]] $KeptSourceVideoIndices = $null,
        [int[]] $KeptSourceAudioIndices = $null
    )

    [hashtable]$tempProbe = $null

    $s = Get-DurationFromFormat -Probe $SourceProbe
    if ($null -ne $s)
    {
        $tempProbe = Get-FFprobeJson -FFPROBE $FFPROBE -File $TempFile
        $t = Get-DurationFromFormat -Probe $tempProbe
        if ($null -ne $t)
        {
            return [pscustomobject]@{ Method = 'format'; Source = $s; Temp = $t }
        }
    }

    $s = Get-DurationFromStreams -Probe $SourceProbe -KeptSourceVideoIndices $KeptSourceVideoIndices -KeptSourceAudioIndices $KeptSourceAudioIndices
    if ($null -ne $s)
    {
        if ($null -eq $tempProbe)
        {
            $tempProbe = Get-FFprobeJson -FFPROBE $FFPROBE -File $TempFile
        }
        $t = Get-DurationFromStreams -Probe $tempProbe
        if ($null -ne $t)
        {
            return [pscustomobject]@{ Method = 'stream'; Source = $s; Temp = $t }
        }
    }

    $s = Get-DurationFromTags -Probe $SourceProbe -KeptSourceVideoIndices $KeptSourceVideoIndices -KeptSourceAudioIndices $KeptSourceAudioIndices
    if ($null -ne $s)
    {
        if ($null -eq $tempProbe)
        {
            $tempProbe = Get-FFprobeJson -FFPROBE $FFPROBE -File $TempFile
        }
        $t = Get-DurationFromTags -Probe $tempProbe
        if ($null -ne $t)
        {
            return [pscustomobject]@{ Method = 'tag'; Source = $s; Temp = $t }
        }
    }

    $srcVideoIdx = if ($null -ne $KeptSourceVideoIndices -and $KeptSourceVideoIndices.Count -gt 0)
    {
        $KeptSourceVideoIndices[0]
    }
    elseif ($null -eq $KeptSourceVideoIndices)
    {
        0
    }
    else
    {
        $null
    }

    if ($null -ne $srcVideoIdx)
    {
        $s = Get-DurationFromPacketCount -FFPROBE $FFPROBE -File $SourceFile -StreamIndex $srcVideoIdx
        if ($null -ne $s)
        {
            $t = Get-DurationFromPacketCount -FFPROBE $FFPROBE -File $TempFile -StreamIndex 0
            if ($null -ne $t)
            {
                return [pscustomobject]@{ Method = 'count'; Source = $s; Temp = $t }
            }
        }
    }

    return [pscustomobject]@{ Method = 'unknown'; Source = $null; Temp = $null }
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
        [int[]] $KeptSourceAudioIndices = $null
    )

    $pair = Get-ComparableDurationPair -FFPROBE $FFPROBE -SourceProbe $SourceProbe -SourceFile $SourceFile -TempFile $TempFile -KeptSourceVideoIndices $KeptSourceVideoIndices -KeptSourceAudioIndices $KeptSourceAudioIndices
    if ($pair.Method -eq 'unknown')
    {
        return [pscustomobject]@{
            Status = 'unknown'
            Method = 'unknown'
            Expected = $null
            Actual = $null
            Diff = $null
        }
    }

    $expected = $pair.Source
    $actual = $pair.Temp
    $tolerance = [math]::Max($ToleranceSecondsMin, $expected * $TolerancePercent / 100.0)
    $diff = [math]::Abs($expected - $actual)
    if ($diff -gt $tolerance)
    {
        return [pscustomobject]@{
            Status = 'mismatch'
            Method = $pair.Method
            Expected = $expected
            Actual = $actual
            Diff = $diff
        }
    }

    return [pscustomobject]@{
        Status = 'ok'
        Method = $pair.Method
        Expected = $expected
        Actual = $actual
        Diff = $diff
    }
}
