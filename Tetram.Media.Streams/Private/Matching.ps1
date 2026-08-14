Set-StrictMode -Version 3.0

function Resolve-MergeActions {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][pscustomobject[]] $MkvDescriptors,
        [Parameter(Mandatory)][AllowEmptyCollection()][pscustomobject[]] $StreamFiles
    )
    $used = @{}
    $replaces = @()
    $keeps = @()
    foreach ($mkv in @($MkvDescriptors)) {
        if ($mkv.Class -notin @('Video', 'Audio', 'Subtitle')) {
            $keeps += $mkv
            continue
        }
        $hit = @($StreamFiles | Where-Object {
            $_.CollisionKey -eq $mkv.CollisionKey -and [int]$_.CollisionIndex -eq [int]$mkv.CollisionIndex
        }) | Select-Object -First 1
        if ($hit) {
            $replaces += [pscustomobject]@{ Mkv = $mkv; StreamFile = $hit }
            $used[$hit.FullName] = $true
        }
        else { $keeps += $mkv }
    }
    $classOrder = @{ Video = 0; Cover = 1; Audio = 2; Subtitle = 3; Attachment = 4; Chapter = 5 }
    $adds = @($StreamFiles | Where-Object { -not $used.ContainsKey($_.FullName) } |
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
    foreach ($r in @($Actions.Replaces)) { $sideForInput += $r.StreamFile }
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
            $in = $inputIndex[$r.StreamFile.FullName]
            [void]$a.Add('-map'); [void]$a.Add("${in}:0")
            $oi = $outIdx[$letter]
            $lang = if ($r.StreamFile.Language) { $r.StreamFile.Language } else { 'und' }
            [void]$a.Add("-metadata:s:${letter}:${oi}"); [void]$a.Add("language=$lang")
            [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add((Get-FfmpegDispositionValue $r.StreamFile.Flags))
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
    # Muxer explicite : le nom du temporaire (GUID.mkv) ne doit pas être la seule source de vérité.
    [void]$a.Add('-f'); [void]$a.Add('matroska')
    [void]$a.Add($OutputPath)
    return @($a)
}
