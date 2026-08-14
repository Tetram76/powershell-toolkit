Set-StrictMode -Version 3.0

$script:StreamsDispositionFlags = @(
    @{ FileToken = 'default'; ProbeName = 'default'; FfmpegName = 'default' }
    @{ FileToken = 'forced'; ProbeName = 'forced'; FfmpegName = 'forced' }
    @{ FileToken = 'commentary'; ProbeName = 'comment'; FfmpegName = 'comment' }
    @{ FileToken = 'original'; ProbeName = 'original'; FfmpegName = 'original' }
    @{ FileToken = 'dub'; ProbeName = 'dub'; FfmpegName = 'dub' }
    @{ FileToken = 'hearing_impaired'; ProbeName = 'hearing_impaired'; FfmpegName = 'hearing_impaired' }
    @{ FileToken = 'visual_impaired'; ProbeName = 'visual_impaired'; FfmpegName = 'visual_impaired' }
)

$script:StreamsFlagAlias = @{
    'comment' = 'commentary'
    'comments' = 'commentary'
}

$script:StreamsContainerExtensions = @(
    '.mkv', '.mp4', '.avi', '.mov', '.webm', '.m4v', '.wmv', '.flv', '.mpeg', '.mpg', '.ts'
)

$script:StreamsExtClass = @{
    '.h264' = 'Video'; '.hevc' = 'Video'; '.ivf' = 'Video'; '.m2v' = 'Video'; '.vc1' = 'Video'
    '.aac' = 'Audio'; '.ac3' = 'Audio'; '.eac3' = 'Audio'; '.dts' = 'Audio'; '.thd' = 'Audio'
    '.flac' = 'Audio'; '.opus' = 'Audio'; '.mp3' = 'Audio'; '.mp2' = 'Audio'; '.ogg' = 'Audio'; '.wav' = 'Audio'
    '.srt' = 'Subtitle'; '.ass' = 'Subtitle'; '.ssa' = 'Subtitle'; '.vtt' = 'Subtitle'; '.sup' = 'Subtitle'
    '.jpg' = 'Cover'; '.jpeg' = 'Cover'; '.png' = 'Cover'
    '.ttf' = 'Attachment'; '.otf' = 'Attachment'; '.ttc' = 'Attachment'
    '.woff' = 'Attachment'; '.woff2' = 'Attachment'; '.bin' = 'Attachment'
    '.ffmeta' = 'Chapter'
}

function Get-StreamsOrderedFlags {
    param([string[]] $Flags)
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @($Flags)) {
        if ($f) { [void]$set.Add($f) }
    }
    $out = @()
    foreach ($row in $script:StreamsDispositionFlags) {
        if ($set.Contains([string]$row.FileToken)) { $out += [string]$row.FileToken }
    }
    return $out
}

function Get-StreamCollisionKey {
    param([Parameter(Mandatory)][pscustomobject] $Descriptor)
    $ext = ([string]$Descriptor.Extension).ToLowerInvariant()
    switch ($Descriptor.Class) {
        'Cover' { return "Cover||$ext" }
        'Attachment' { return "Attachment|$($Descriptor.AttachmentNameSanitized)|$ext" }
        'Chapter' { return 'Chapter' }
        default {
            $lang = if ($Descriptor.Language) { ([string]$Descriptor.Language).ToLowerInvariant() } else { '' }
            if ($lang -in @('und', 'unk')) { $lang = '' }
            $flags = (Get-StreamsOrderedFlags $Descriptor.Flags) -join ','
            return "$($Descriptor.Class)|$lang|$flags|$ext"
        }
    }
}

function New-StreamDescriptorObject {
    param(
        [string] $Class,
        [string] $Language = '',
        [string[]] $Flags = @(),
        [string] $Extension,
        [int] $CollisionIndex = 1,
        [string] $AttachmentNameSanitized = '',
        $StreamIndex = $null,
        [string] $Codec = '',
        [string] $AttachmentName = '',
        [string] $MimeType = ''
    )
    $d = [pscustomobject]@{
        Class = $Class
        StreamIndex = $StreamIndex
        Language = $Language
        Flags = @(Get-StreamsOrderedFlags $Flags)
        Extension = $Extension
        CollisionIndex = $CollisionIndex
        Codec = $Codec
        AttachmentName = $AttachmentName
        AttachmentNameSanitized = $AttachmentNameSanitized
        MimeType = $MimeType
        CollisionKey = ''
    }
    $d.CollisionKey = Get-StreamCollisionKey $d
    return $d
}

function ConvertTo-StreamFileName {
    param(
        [Parameter(Mandatory)][string] $Basename,
        [Parameter(Mandatory)][pscustomobject] $Descriptor
    )
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($Basename)
    switch ($Descriptor.Class) {
        'Cover' {
            $parts.Add('cover')
            if ([int]$Descriptor.CollisionIndex -ge 2) { $parts.Add([string]$Descriptor.CollisionIndex) }
        }
        'Chapter' { $parts.Add('chapters') }
        'Attachment' {
            if ($Descriptor.AttachmentNameSanitized) { $parts.Add([string]$Descriptor.AttachmentNameSanitized) }
            if ([int]$Descriptor.CollisionIndex -ge 2) { $parts.Add([string]$Descriptor.CollisionIndex) }
        }
        default {
            $lang = [string]$Descriptor.Language
            if ($lang -and $lang.ToLowerInvariant() -notin @('und', 'unk')) { $parts.Add($lang) }
            foreach ($f in Get-StreamsOrderedFlags $Descriptor.Flags) { $parts.Add($f) }
            if ([int]$Descriptor.CollisionIndex -ge 2) { $parts.Add([string]$Descriptor.CollisionIndex) }
        }
    }
    return ($parts -join '.') + $Descriptor.Extension
}

function ConvertFrom-StreamFileName {
    param(
        [Parameter(Mandatory)][string] $Basename,
        [Parameter(Mandatory)][string] $FileName
    )
    $name = [IO.Path]::GetFileName($FileName)
    $ext = [IO.Path]::GetExtension($name)
    if (-not $ext) { return $null }
    $extLower = $ext.ToLowerInvariant()
    if ($script:StreamsContainerExtensions -contains $extLower) { return $null }
    if (-not $script:StreamsExtClass.ContainsKey($extLower)) { return $null }
    $prefix = $Basename + '.'
    if ($name.Length -le $prefix.Length -or -not $name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    $stem = $name.Substring(0, $name.Length - $ext.Length)
    $rest = $stem.Substring($Basename.Length)
    if ($rest.StartsWith('.')) { $rest = $rest.Substring(1) }
    $tokens = @()
    if ($rest) { $tokens = @($rest.Split('.', [StringSplitOptions]::RemoveEmptyEntries)) }

    $classHint = $script:StreamsExtClass[$extLower]
    $hasCover = $false
    $hasChapters = $false
    $flags = @()
    $language = ''
    $collision = 1
    $attachParts = @()
    $flagLookup = @{}
    foreach ($row in $script:StreamsDispositionFlags) { $flagLookup[[string]$row.FileToken] = [string]$row.FileToken }
    foreach ($alias in $script:StreamsFlagAlias.Keys) { $flagLookup[$alias] = [string]$script:StreamsFlagAlias[$alias] }

    foreach ($tok in $tokens) {
        $low = $tok.ToLowerInvariant()
        if ($low -eq 'cover') { $hasCover = $true; continue }
        if ($low -eq 'chapters') { $hasChapters = $true; continue }
        if ($flagLookup.ContainsKey($low)) { $flags += $flagLookup[$low]; continue }
        $n = 0
        if ([int]::TryParse($tok, [ref]$n) -and $n -ge 2) { $collision = $n; continue }
        if ($low -in @('und', 'unk')) { continue }
        # Jeton langue = tag ffprobe tel quel (ISO 639 ou BCP-47 `pt-BR`) : le `.` du nom ne le casse pas.
        if ($classHint -in @('Video', 'Audio', 'Subtitle') -and $tok -match '^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$') {
            $language = $tok
            continue
        }
        $attachParts += $tok
    }

    # Seules les pièces jointes ont un nom libre ; un jeton restant n'est pas de la grammaire A/V/S/cover/chapitres.
    if ($classHint -ne 'Attachment' -and @($attachParts).Count -gt 0) {
        return $null
    }

    if ($extLower -eq '.ffmeta') {
        if (-not $hasChapters) { return $null }
        return New-StreamDescriptorObject -Class 'Chapter' -Extension '.ffmeta' -CollisionIndex 1
    }
    if ($classHint -eq 'Cover') {
        if (-not $hasCover) { return $null }
        return New-StreamDescriptorObject -Class 'Cover' -Extension $extLower -CollisionIndex $collision
    }
    if ($classHint -eq 'Attachment') {
        $san = $attachParts -join '.'
        return New-StreamDescriptorObject -Class 'Attachment' -Extension $extLower -CollisionIndex $collision -AttachmentNameSanitized $san
    }
    return New-StreamDescriptorObject -Class $classHint -Language $language -Flags $flags -Extension $extLower -CollisionIndex $collision
}

function Get-FfmpegDispositionValue {
    param([string[]] $Flags)
    $ordered = Get-StreamsOrderedFlags $Flags
    # return unwraps empty @() to $null; StrictMode then rejects .Count
    if ($null -eq $ordered -or @($ordered).Count -eq 0) { return '0' }
    $names = foreach ($tok in $ordered) {
        ($script:StreamsDispositionFlags | Where-Object { $_.FileToken -eq $tok } | Select-Object -First 1).FfmpegName
    }
    return ($names -join '+')
}
