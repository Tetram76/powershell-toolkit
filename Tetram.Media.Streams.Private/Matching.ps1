Set-StrictMode -Version 3.0

function Get-SidecarFiles {
    param(
        [Parameter(Mandatory)][string] $Directory,
        [Parameter(Mandatory)][string] $Basename,
        [string[]] $ExcludePath = @()
    )
    $exclude = @()
    foreach ($p in @($ExcludePath)) {
        if ($p) { $exclude += [IO.Path]::GetFullPath($p) }
    }
    $out = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue)) {
        $full = [IO.Path]::GetFullPath($f.FullName)
        if ($exclude -contains $full) { continue }
        $parsed = ConvertFrom-StreamFileName -Basename $Basename -FileName $f.Name
        if ($null -eq $parsed) { continue }
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
        if ($item.Class -in @('Attachment', 'Chapter')) { continue }
        if ($inputIndex.ContainsKey($item.FullName)) { continue }
        [void]$a.Add('-i'); [void]$a.Add($item.FullName)
        $inputIndex[$item.FullName] = $n
        $n++
    }
    # @($null).Count is 1 when Where-Object matches nothing; absent chapters must not become an -i input
    $chapterHits = $Actions.Adds | Where-Object { $_.Class -eq 'Chapter' }
    $chapter = @()
    if ($null -ne $chapterHits) { $chapter = @($chapterHits) }
    foreach ($r in @($Actions.Replaces)) {
        if ($r.Mkv.Class -eq 'Chapter') { $chapter = @($r.Sidecar); break }
    }
    $chapterInput = $null
    if ($chapter.Count -gt 0 -and $null -ne $chapter[0] -and $chapter[0].FullName) {
        [void]$a.Add('-i'); [void]$a.Add($chapter[0].FullName)
        $chapterInput = $n
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
            $r = $null
            if ($null -ne $mkv.StreamIndex) { $r = $replaceByIndex[[int]$mkv.StreamIndex] }
            if ($r) {
                [void]$a.Add('-attach'); [void]$a.Add($r.Sidecar.FullName)
                $ti = $outIdx['t']
                $fn = $r.Sidecar.AttachmentName
                if (-not $fn) { $fn = $r.Sidecar.AttachmentNameSanitized + $r.Sidecar.Extension }
                [void]$a.Add("-metadata:s:t:${ti}"); [void]$a.Add("filename=$fn")
                $outIdx['t']++
            }
            else {
                [void]$a.Add('-map'); [void]$a.Add("0:$($mkv.StreamIndex)")
                $outIdx['t']++
            }
            continue
        }
        $letter = Get-MapSpecLetter $mkv.Class
        $r = $null
        if ($null -ne $mkv.StreamIndex) { $r = $replaceByIndex[[int]$mkv.StreamIndex] }
        if ($r) {
            $in = $inputIndex[$r.Sidecar.FullName]
            [void]$a.Add('-map'); [void]$a.Add("${in}:0")
            $oi = $outIdx[$letter]
            $lang = if ($r.Sidecar.Language) { $r.Sidecar.Language } else { 'und' }
            [void]$a.Add("-metadata:s:${letter}:${oi}"); [void]$a.Add("language=$lang")
            [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add((Get-FfmpegDispositionValue $r.Sidecar.Flags))
            if ($mkv.Class -eq 'Cover') {
                [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add('attached_pic')
            }
            $outIdx[$letter]++
        }
        else {
            [void]$a.Add('-map'); [void]$a.Add("0:$($mkv.StreamIndex)")
            $outIdx[$letter]++
        }
    }
    foreach ($add in @($Actions.Adds)) {
        if ($add.Class -eq 'Chapter') { continue }
        if ($add.Class -eq 'Attachment') {
            [void]$a.Add('-attach'); [void]$a.Add($add.FullName)
            $ti = $outIdx['t']
            $fn = $add.AttachmentNameSanitized + $add.Extension
            [void]$a.Add("-metadata:s:t:${ti}"); [void]$a.Add("filename=$fn")
            $outIdx['t']++
            continue
        }
        $letter = Get-MapSpecLetter $add.Class
        $in = $inputIndex[$add.FullName]
        [void]$a.Add('-map'); [void]$a.Add("${in}:0")
        $oi = $outIdx[$letter]
        $lang = if ($add.Language) { $add.Language } else { 'und' }
        [void]$a.Add("-metadata:s:${letter}:${oi}"); [void]$a.Add("language=$lang")
        [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add((Get-FfmpegDispositionValue $add.Flags))
        if ($add.Class -eq 'Cover') {
            [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add('attached_pic')
        }
        $outIdx[$letter]++
    }
    if ($null -ne $chapterInput) {
        [void]$a.Add('-map_chapters'); [void]$a.Add([string]$chapterInput)
    }
    [void]$a.Add($OutputPath)
    return @($a)
}
