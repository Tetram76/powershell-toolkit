Set-StrictMode -Version 3.0

$PrivateRoot = Join-Path $PSScriptRoot 'Tetram.Media.Streams.Private'
. (Join-Path $PrivateRoot 'Naming.ps1')
. (Join-Path $PrivateRoot 'CodecMap.ps1')
. (Join-Path $PrivateRoot 'Descriptors.ps1')
. (Join-Path $PrivateRoot 'Matching.ps1')
. (Join-Path $PrivateRoot 'Invoke.ps1')

function Split-MediaStream {
    <#
.EXTERNALHELP Tetram.Media.Streams-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $LiteralPath,
        [ValidateSet('Video', 'Audio', 'Subtitle', 'Attachment', 'Chapter')]
        [string[]] $StreamType,
        [string[]] $Language,
        [switch] $Force
    )
    try { $ffmpeg = Get-FFmpegPath; $ffprobe = Get-FfprobePath }
    catch { Write-ErrorLog $_.Exception.Message; return }

    if (-not (Test-StreamsMkvPath -LiteralPath $LiteralPath)) {
        Write-ErrorLog "Not a .mkv file: '$LiteralPath'"
        return
    }

    $probe = Get-StreamsProbeHashtable -Ffprobe $ffprobe -LiteralPath $LiteralPath
    if ($null -eq $probe) {
        Write-ErrorLog "Can't get media info for '$LiteralPath'"
        return
    }

    foreach ($u in @(Get-UnmappedStreamDescriptors -Probe $probe)) {
        $cn = [string](Get-ProbeProperty $u 'codec_name')
        Write-ErrorLog "Unmapped codec '$cn' in '$LiteralPath' — skipped"
    }

    $all = @(Get-MediaStreamDescriptors -Probe $probe)
    $sel = @(Select-MediaStreamDescriptors -Descriptors $all -StreamType $StreamType -Language $Language)
    if ($sel.Count -eq 0) {
        Write-InfoLog "No stream to extract from '$LiteralPath'"
        return
    }

    $dir = Split-Path -Parent (Resolve-Path -LiteralPath $LiteralPath)
    $base = [IO.Path]::GetFileNameWithoutExtension($LiteralPath)
    foreach ($d in $sel) {
        $name = ConvertTo-StreamFileName -Basename $base -Descriptor $d
        $out = Join-Path $dir $name
        if ((Test-Path -LiteralPath $out -PathType Leaf) -and -not $WhatIfPreference) {
            if (-not $Force -and -not $PSCmdlet.ShouldContinue($out, 'Overwrite sidecar')) {
                Write-InfoLog "Skip existing sidecar '$out'"
                continue
            }
        }
        $ffmpegArgs = Get-SplitExtractArguments -Descriptor $d -MkvPath $LiteralPath -OutPath $out
        $ok = Invoke-StreamsFFmpeg -Cmdlet $PSCmdlet -Exe $ffmpeg -Arguments $ffmpegArgs -TargetLabel $out
        if (-not $ok) {
            Write-ErrorLog "ffmpeg failed extracting '$out'"
        }
    }
}

function Merge-MediaStream {
    <#
.EXTERNALHELP Tetram.Media.Streams-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $LiteralPath,
        [string] $Destination,
        [switch] $RemoveSidecars,
        [switch] $Force
    )
    try { $ffmpeg = Get-FFmpegPath; $ffprobe = Get-FfprobePath }
    catch { Write-ErrorLog $_.Exception.Message; return }

    if (-not (Test-StreamsMkvPath -LiteralPath $LiteralPath)) {
        Write-ErrorLog "Not a .mkv file: '$LiteralPath'"
        return
    }

    $src = [IO.Path]::GetFullPath($LiteralPath)
    if ($Destination) {
        if ([IO.Path]::GetExtension($Destination) -ine '.mkv') {
            Write-ErrorLog "Destination must be a .mkv path: '$Destination'"
            return
        }
        $dest = [IO.Path]::GetFullPath($Destination)
    }
    else { $dest = $src }

    $probe = Get-StreamsProbeHashtable -Ffprobe $ffprobe -LiteralPath $src
    if ($null -eq $probe) {
        Write-ErrorLog "Can't get media info for '$src'"
        return
    }

    $dir = Split-Path -Parent $src
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $sides = @(Get-SidecarFiles -Directory $dir -Basename $base -ExcludePath @($src, $dest))
    if ($sides.Count -eq 0) {
        Write-ErrorLog "No sidecar files found for '$base'"
        return
    }

    $desc = @(Get-MediaStreamDescriptors -Probe $probe)
    $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars $sides

    if ((Test-Path -LiteralPath $dest -PathType Leaf) -and -not $WhatIfPreference) {
        if (-not $Force -and -not $PSCmdlet.ShouldContinue($dest, 'Overwrite MKV')) {
            Write-InfoLog "Skip existing '$dest'"
            return
        }
    }

    $temp = $dest + '.tmp'
    $n = 2
    while (Test-Path -LiteralPath $temp) {
        $temp = $dest + ".tmp$n"
        $n++
    }

    $ffmpegArgs = Build-MergeFFmpegArgs -MkvPath $src -Actions $act -OutputPath $temp
    $ok = Invoke-StreamsFFmpeg -Cmdlet $PSCmdlet -Exe $ffmpeg -Arguments $ffmpegArgs -TargetLabel $dest
    if ($WhatIfPreference) { return }
    if (-not $ok) {
        Write-ErrorLog "ffmpeg failed muxing '$dest'"
        if (Test-Path -LiteralPath $temp) {
            if ($PSCmdlet.ShouldProcess($temp, 'Cleanup temp')) { Remove-Item -LiteralPath $temp -Force }
        }
        return
    }
    if ($PSCmdlet.ShouldProcess($dest, "Move temp over '$dest'")) {
        Move-Item -LiteralPath $temp -Destination $dest -Force
    }
    if ($RemoveSidecars) {
        $toRemove = @($act.Replaces | ForEach-Object { $_.Sidecar.FullName }) + @($act.Adds | ForEach-Object { $_.FullName })
        foreach ($p in $toRemove) {
            if (-not $p) { continue }
            if ($PSCmdlet.ShouldProcess($p, 'Remove sidecar')) {
                try { Remove-Item -LiteralPath $p -ErrorAction Stop }
                catch { Write-ErrorLog "Unable to delete sidecar '$p': $($_.Exception.Message)" }
            }
        }
    }
}

Export-ModuleMember -Function Split-MediaStream, Merge-MediaStream
