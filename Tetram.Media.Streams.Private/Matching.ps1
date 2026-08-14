Set-StrictMode -Version 3.0

function Get-StreamsFlippedCasePath {
    param([string] $Path)
    $dir = Split-Path -Parent $Path
    $name = Split-Path -Leaf $Path
    if (-not $name) { return $null }
    $chars = $name.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $c = $chars[$i]
        if (-not [char]::IsLetter($c)) { continue }
        $chars[$i] = if ([char]::IsUpper($c)) { [char]::ToLowerInvariant($c) } else { [char]::ToUpperInvariant($c) }
        $flipped = -join $chars
        if (-not $dir) { return $flipped }
        return (Join-Path $dir $flipped)
    }
    return $null
}

function Test-StreamsDirectoryCaseSensitive {
    param([Parameter(Mandatory)][string] $ExistingPath)
    $flipped = Get-StreamsFlippedCasePath -Path $ExistingPath
    if (-not $flipped) { return -not $IsWindows }
    if (-not (Test-Path -LiteralPath $flipped)) { return $true }
    # Get-Item.FullName = casse disque ; GetFullPath garderait la casse demandée.
    $a = (Get-Item -LiteralPath $ExistingPath).FullName
    $b = (Get-Item -LiteralPath $flipped).FullName
    return -not [string]::Equals($a, $b, [StringComparison]::Ordinal)
}

function Get-StreamsNameComparison {
    param([string] $ExistingPath)
    if ($ExistingPath -and (Test-StreamsDirectoryCaseSensitive -ExistingPath $ExistingPath)) {
        return [StringComparison]::Ordinal
    }
    return [StringComparison]::OrdinalIgnoreCase
}

function Get-SidecarFiles {
    param(
        [Parameter(Mandatory)][string] $Directory,
        [Parameter(Mandatory)][string] $Basename,
        [string[]] $ExcludePath = @(),
        [Nullable[StringComparison]] $NameComparison,
        [string] $ExistingPath
    )
    $exclude = @()
    foreach ($p in @($ExcludePath)) {
        if ($p) { $exclude += [IO.Path]::GetFullPath($p) }
    }
    $cmp = $NameComparison
    if ($null -eq $cmp) {
        $probe = $ExistingPath
        if (-not $probe) {
            foreach ($e in $exclude) {
                if ($e -and (Test-Path -LiteralPath $e -PathType Leaf)) { $probe = $e; break }
            }
        }
        $cmp = Get-StreamsNameComparison -ExistingPath $probe
    }
    else { $cmp = [StringComparison]$cmp }
    $out = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue)) {
        $full = [IO.Path]::GetFullPath($f.FullName)
        $excluded = $false
        foreach ($e in $exclude) {
            if ([string]::Equals($e, $full, $cmp)) { $excluded = $true; break }
        }
        if ($excluded) { continue }
        $parsed = ConvertFrom-StreamFileName -Basename $Basename -FileName $f.Name -Comparison $cmp
        if ($null -eq $parsed) { continue }
        if ($parsed.Class -notin @('Video', 'Audio', 'Subtitle')) { continue }
        $parsed | Add-Member -NotePropertyName FullName -NotePropertyValue $full -Force
        $out += $parsed
    }
    return $out
}

function Resolve-MergeActions {
    param(
        [Parameter(Mandatory)][pscustomobject[]] $MkvDescriptors,
        [Parameter(Mandatory)][AllowEmptyCollection()][pscustomobject[]] $Sidecars
    )
    $used = @{}
    $replaces = @()
    $keeps = @()
    foreach ($mkv in @($MkvDescriptors)) {
        if ($mkv.Class -notin @('Video', 'Audio', 'Subtitle')) {
            $keeps += $mkv
            continue
        }
        $hit = @($Sidecars | Where-Object {
            $_.CollisionKey -eq $mkv.CollisionKey -and [int]$_.CollisionIndex -eq [int]$mkv.CollisionIndex
        }) | Select-Object -First 1
        if ($hit) {
            $replaces += [pscustomobject]@{ Mkv = $mkv; Sidecar = $hit }
            $used[$hit.FullName] = $true
        }
        else { $keeps += $mkv }
    }
    $classOrder = @{ Video = 0; Cover = 1; Audio = 2; Subtitle = 3; Attachment = 4; Chapter = 5 }
    $adds = @($Sidecars | Where-Object { -not $used.ContainsKey($_.FullName) } |
            Sort-Object { $classOrder[$_.Class] }, CollisionIndex)
    return [pscustomobject]@{
        OrderedMkv = @($MkvDescriptors)
        Keeps = $keeps
        Replaces = $replaces
        Adds = $adds
    }
}

function Get-MapSpecLetter {
    param([string] $Class)
    switch ($Class) {
        'Video' { 'v' }
        'Cover' { 'v' }
        'Audio' { 'a' }
        'Subtitle' { 's' }
        default { $null }
    }
}

function Build-MergeFFmpegArgs {
    param(
        [Parameter(Mandatory)][string] $MkvPath,
        [Parameter(Mandatory)][pscustomobject] $Actions,
        [Parameter(Mandatory)][string] $OutputPath
    )
    $a = [System.Collections.Generic.List[string]]::new()
    [void]$a.Add('-hide_banner')
    [void]$a.Add('-y')
    [void]$a.Add('-i'); [void]$a.Add($MkvPath)
    $inputIndex = @{}
    $n = 1
    $sideForInput = @()
    foreach ($r in @($Actions.Replaces)) { $sideForInput += $r.Sidecar }
    $sideForInput += @($Actions.Adds)
    foreach ($item in $sideForInput) {
        if ($null -eq $item) { continue }
        if ($item.Class -notin @('Video', 'Audio', 'Subtitle')) { continue }
        if ($inputIndex.ContainsKey($item.FullName)) { continue }
        [void]$a.Add('-i'); [void]$a.Add($item.FullName)
        $inputIndex[$item.FullName] = $n
        $n++
    }
    [void]$a.Add('-c'); [void]$a.Add('copy')
    $outIdx = @{ v = 0; a = 0; s = 0; t = 0 }
    $replaceByIndex = @{}
    foreach ($r in @($Actions.Replaces)) {
        if ($null -ne $r.Mkv.StreamIndex) { $replaceByIndex[[int]$r.Mkv.StreamIndex] = $r }
    }
    foreach ($mkv in @($Actions.OrderedMkv)) {
        if ($mkv.Class -eq 'Chapter') { continue }
        if ($mkv.Class -eq 'Attachment') {
            [void]$a.Add('-map'); [void]$a.Add("0:$($mkv.StreamIndex)")
            $outIdx['t']++
            continue
        }
        $letter = Get-MapSpecLetter $mkv.Class
        $r = $null
        if ($mkv.Class -in @('Video', 'Audio', 'Subtitle') -and $null -ne $mkv.StreamIndex) {
            $r = $replaceByIndex[[int]$mkv.StreamIndex]
        }
        if ($r) {
            $in = $inputIndex[$r.Sidecar.FullName]
            [void]$a.Add('-map'); [void]$a.Add("${in}:0")
            $oi = $outIdx[$letter]
            $lang = if ($r.Sidecar.Language) { $r.Sidecar.Language } else { 'und' }
            [void]$a.Add("-metadata:s:${letter}:${oi}"); [void]$a.Add("language=$lang")
            [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add((Get-FfmpegDispositionValue $r.Sidecar.Flags))
            $outIdx[$letter]++
        }
        else {
            [void]$a.Add('-map'); [void]$a.Add("0:$($mkv.StreamIndex)")
            if ($letter) { $outIdx[$letter]++ }
        }
    }
    foreach ($add in @($Actions.Adds)) {
        if ($add.Class -notin @('Video', 'Audio', 'Subtitle')) { continue }
        $letter = Get-MapSpecLetter $add.Class
        $in = $inputIndex[$add.FullName]
        [void]$a.Add('-map'); [void]$a.Add("${in}:0")
        $oi = $outIdx[$letter]
        $lang = if ($add.Language) { $add.Language } else { 'und' }
        [void]$a.Add("-metadata:s:${letter}:${oi}"); [void]$a.Add("language=$lang")
        [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add((Get-FfmpegDispositionValue $add.Flags))
        $outIdx[$letter]++
    }
    # La cible réelle est *.tmp (spec) : sans -f, FFmpeg ne déduit pas le muxer.
    [void]$a.Add('-f'); [void]$a.Add('matroska')
    [void]$a.Add($OutputPath)
    return @($a)
}
