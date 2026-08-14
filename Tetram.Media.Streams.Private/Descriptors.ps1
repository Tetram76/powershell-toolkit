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

function Get-MediaStreamDescriptors {
    param([Parameter(Mandatory)][hashtable] $Probe)
    $list = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($st in @($Probe['streams'])) {
        $codecType = [string](Get-ProbeProperty $st 'codec_type')
        $codecName = [string](Get-ProbeProperty $st 'codec_name')
        $index = ConvertTo-IntOrNull (Get-ProbeProperty $st 'index')
        $tags = Get-ProbeProperty $st 'tags'
        $disp = Get-ProbeProperty $st 'disposition'
        $attached = ((Get-ProbeProperty $disp 'attached_pic') -eq 1)
        if ($codecType -eq 'attachment') {
            $fn = [string](Get-ProbeProperty $tags 'filename')
            $ext = [IO.Path]::GetExtension($fn)
            if (-not $ext) { $ext = '.bin' }
            $base = [IO.Path]::GetFileNameWithoutExtension($fn)
            $d = New-StreamDescriptorObject -Class 'Attachment' -Extension $ext.ToLowerInvariant() `
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

function Get-UnmappedStreamDescriptors {
    param([Parameter(Mandatory)][hashtable] $Probe)
    $out = @()
    foreach ($st in @($Probe['streams'])) {
        $codecType = [string](Get-ProbeProperty $st 'codec_type')
        if ($codecType -eq 'attachment') { continue }
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
    if (@($StreamType).Count -gt 0) {
        $sel = @($sel | Where-Object {
            $c = $_.Class
            $ok = $false
            foreach ($t in $StreamType) {
                if ($t -eq 'Video' -and $c -in @('Video', 'Cover')) { $ok = $true }
                elseif ($t -eq 'Attachment' -and $c -eq 'Attachment') { $ok = $true }
                elseif ($t -eq 'Chapter' -and $c -eq 'Chapter') { $ok = $true }
                elseif ($t -eq $c) { $ok = $true }
            }
            $ok
        })
    }
    if (@($Language).Count -gt 0) {
        $sel = @($sel | Where-Object {
            if ($_.Class -in @('Attachment', 'Chapter')) { return $true }
            foreach ($l in $Language) {
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
