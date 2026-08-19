Set-StrictMode -Version 3.0

function Get-ProbeProperty {
    param($Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        return $null
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function ConvertTo-IntOrNull {
    param($Value)
    if ($null -eq $Value) { return $null }
    $n = 0
    if ([int]::TryParse([string]$Value, [ref]$n)) { return $n }
    return $null
}

function Get-StreamLanguage {
    param($Tags)
    $raw = [string](Get-ProbeProperty $Tags 'language')
    if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
    $low = $raw.ToLowerInvariant()
    if ($low -in @('und', 'unk')) { return '' }
    return $raw
}

function Get-StreamFlags {
    param($Disposition, [string] $Class)
    if ($Class -in @('Cover', 'Attachment', 'Chapter')) { return @() }
    $flags = @()
    foreach ($row in $script:StreamsDispositionFlags) {
        $v = Get-ProbeProperty $Disposition ([string]$row.ProbeName)
        if ("$v" -eq '1') { $flags += [string]$row.FileToken }
    }
    return $flags
}

function ConvertTo-SanitizedAttachmentName {
    param([string] $Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $invalid = [IO.Path]::GetInvalidFileNameChars() + [char]'.'
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalid -contains $ch) { [void]$sb.Append('_') }
        else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function Resolve-StreamCollisionIndex {
    param([pscustomobject[]] $Descriptors)
    $groups = $Descriptors | Group-Object -Property CollisionKey
    foreach ($g in $groups) {
        $i = 1
        foreach ($d in @($g.Group)) {
            $d.CollisionIndex = $i
            $i++
        }
    }
}

function Get-ProbeStreamList {
    param([hashtable] $Probe)
    # @($h['streams']) vaut 1 élément $null si la clé manque — une itération fantôme, pas « aucun flux ».
    $raw = Get-ProbeProperty $Probe 'streams'
    if ($null -eq $raw) { return @() }
    return @($raw | Where-Object { $null -ne $_ })
}

function Get-MediaStreamDescriptors {
    param([Parameter(Mandatory)][hashtable] $Probe)
    $list = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($st in (Get-ProbeStreamList -Probe $Probe)) {
        $codecType = [string](Get-ProbeProperty $st 'codec_type')
        $codecName = [string](Get-ProbeProperty $st 'codec_name')
        $index = ConvertTo-IntOrNull (Get-ProbeProperty $st 'index')
        $tags = Get-ProbeProperty $st 'tags'
        $disp = Get-ProbeProperty $st 'disposition'
        $attached = ((Get-ProbeProperty $disp 'attached_pic') -eq 1)
        if ($codecType -eq 'attachment') {
            $fn = [string](Get-ProbeProperty $tags 'filename')
            $ext = [IO.Path]::GetExtension($fn).ToLowerInvariant()
            # .jpg/.xml etc. ne sont pas dans l'allowlist Attachment : le parse les prendrait pour Cover ou les ignorerait.
            if (-not $ext -or $script:StreamsExtClass[$ext] -ne 'Attachment') { $ext = '.bin' }
            $base = [IO.Path]::GetFileNameWithoutExtension($fn)
            $d = New-StreamDescriptorObject -Class 'Attachment' -Extension $ext `
                -AttachmentName $fn -AttachmentNameSanitized (ConvertTo-SanitizedAttachmentName $base) `
                -StreamIndex $index -Codec $codecName -MimeType ([string](Get-ProbeProperty $tags 'mimetype'))
            $list.Add($d)
            continue
        }
        $mapped = Get-ElementaryExtension -CodecName $codecName -CodecType $codecType -AttachedPic $attached
        if ($null -eq $mapped) { continue }
        $d = New-StreamDescriptorObject -Class $mapped.Class -Language (Get-StreamLanguage $tags) `
            -Flags (Get-StreamFlags $disp $mapped.Class) -Extension $mapped.Extension `
            -StreamIndex $index -Codec $codecName
        $list.Add($d)
    }
    # @($null).Count is 1 in PowerShell; absent chapters must not synthesize a Chapter descriptor
    $chapters = $Probe['chapters']
    if ($null -ne $chapters -and @($chapters).Count -gt 0) {
        $list.Add((New-StreamDescriptorObject -Class 'Chapter' -Extension '.ffmeta'))
    }
    $arr = @($list)
    foreach ($d in $arr) { $d.CollisionKey = Get-StreamCollisionKey $d }
    Resolve-StreamCollisionIndex -Descriptors $arr
    return $arr
}

function Add-UnmappedKeepDescriptors {
    param(
        [AllowEmptyCollection()][pscustomobject[]] $Descriptors,
        [Parameter(Mandatory)][hashtable] $Probe
    )
    $keeps = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($st in (Get-ProbeStreamList -Probe $Probe)) {
        $codecType = [string](Get-ProbeProperty $st 'codec_type')
        # A/V/S hors table : keep au mux (copie MKV). Attachment déjà décrit. Data = keep-only.
        if ($codecType -eq 'attachment') { continue }
        $index = ConvertTo-IntOrNull (Get-ProbeProperty $st 'index')
        if ($null -eq $index) { continue }
        $codec = [string](Get-ProbeProperty $st 'codec_name')
        if ($codecType -in @('video', 'audio', 'subtitle')) {
            $disp = Get-ProbeProperty $st 'disposition'
            $attached = ((Get-ProbeProperty $disp 'attached_pic') -eq 1)
            if ($null -ne (Get-ElementaryExtension -CodecName $codec -CodecType $codecType -AttachedPic $attached)) {
                continue
            }
            $class = switch ($codecType) {
                'video' { 'Video' }
                'audio' { 'Audio' }
                default { 'Subtitle' }
            }
            $keeps.Add((New-StreamDescriptorObject -Class $class -StreamIndex $index -Codec $codec -Extension ''))
            continue
        }
        $keeps.Add((New-StreamDescriptorObject -Class 'Data' -StreamIndex $index -Codec $codec -Extension ''))
    }
    $mapped = @($Descriptors | Where-Object { $null -ne $_ -and $_.Class -ne 'Chapter' })
    $chapters = @($Descriptors | Where-Object { $null -ne $_ -and $_.Class -eq 'Chapter' })
    $combined = @($mapped + @($keeps) | Sort-Object -Property StreamIndex)
    return @($combined) + @($chapters)
}

function Get-UnmappedStreamDescriptors {
    param([Parameter(Mandatory)][hashtable] $Probe)
    $out = @()
    foreach ($st in (Get-ProbeStreamList -Probe $Probe)) {
        $codecType = [string](Get-ProbeProperty $st 'codec_type')
        if ($codecType -notin @('video', 'audio', 'subtitle')) { continue }
        $codecName = [string](Get-ProbeProperty $st 'codec_name')
        $disp = Get-ProbeProperty $st 'disposition'
        $attached = ((Get-ProbeProperty $disp 'attached_pic') -eq 1)
        if ($null -eq (Get-ElementaryExtension -CodecName $codecName -CodecType $codecType -AttachedPic $attached)) {
            $out += $st
        }
    }
    return $out
}

function Select-MediaStreamDescriptors {
    param(
        [pscustomobject[]] $Descriptors,
        [string[]] $StreamType,
        [string[]] $Language
    )
    $sel = @($Descriptors)
    $types = @($StreamType | Where-Object { $null -ne $_ -and "$_" -ne '' })
    if ($types.Count -eq 0) {
        $types = @('Video', 'Audio', 'Subtitle')
    }
    $sel = @($sel | Where-Object { $types -contains $_.Class })
    $langs = @($Language | Where-Object { $null -ne $_ -and "$_" -ne '' })
    if ($langs.Count -gt 0) {
        $sel = @($sel | Where-Object {
            foreach ($l in $langs) {
                if ($_.Language -and ($_.Language -ieq $l)) { return $true }
            }
            return $false
        })
    }
    return $sel
}

function Test-StreamsMkvPath {
    param([string] $LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return $false }
    return ([IO.Path]::GetExtension($LiteralPath) -ieq '.mkv')
}

function Resolve-StreamsExistingPath {
    param([string] $LiteralPath)
    try {
        # GetFullPath laisse `~` littéral ; le provider PowerShell le développe.
        # -ErrorAction SilentlyContinue : un chemin absent est un cas nominal pour l'appelant (retourne
        # $null), pas une erreur à afficher — sans ça, Resolve-Path écrit une erreur non terminante sur
        # la console (visible même quand ce cas est traité normalement plus haut), indépendamment du
        # catch ci-dessous qui ne couvre que les erreurs réellement terminantes.
        return (Resolve-Path -LiteralPath $LiteralPath -ErrorAction SilentlyContinue).Path
    }
    catch {
        return $null
    }
}

function Get-StreamsProbeHashtable {
    param(
        [Parameter(Mandatory)][string] $Ffprobe,
        [Parameter(Mandatory)][string] $LiteralPath
    )
    try {
        $raw = & $Ffprobe $LiteralPath -v quiet -show_format -show_streams -show_chapters -of json 2>$null | Out-String
        if (-not $raw) { return $null }
        return ConvertFrom-Json -InputObject $raw -AsHashtable
    }
    catch { return $null }
}
