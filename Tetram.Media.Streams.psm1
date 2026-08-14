Set-StrictMode -Version 3.0

$PrivateRoot = Join-Path $PSScriptRoot 'Tetram.Media.Streams.Private'
. (Join-Path $PrivateRoot 'Naming.ps1')
. (Join-Path $PrivateRoot 'CodecMap.ps1')
. (Join-Path $PrivateRoot 'Descriptors.ps1')
. (Join-Path $PrivateRoot 'Matching.ps1')
. (Join-Path $PrivateRoot 'Invoke.ps1')

function Test-StreamsUnmappedAvCodec {
    param($Probe, [string] $SourcePath)
    $unmapped = @(Get-UnmappedStreamDescriptors -Probe $Probe)
    if ($unmapped.Count -eq 0) { return $false }
    foreach ($u in $unmapped) {
        $cn = [string](Get-ProbeProperty $u 'codec_name')
        Write-ErrorLog "Unmapped codec '$cn' in '$SourcePath'"
    }
    return $true
}

function Split-MediaStream {
    <#
.EXTERNALHELP Tetram.Media.Streams-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $LiteralPath,
        [ValidateSet('Video', 'Audio', 'Subtitle')]
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

    $src = Resolve-StreamsExistingPath -LiteralPath $LiteralPath
    if (-not $src) {
        Write-ErrorLog "Not a .mkv file: '$LiteralPath'"
        return
    }

    $probe = Get-StreamsProbeHashtable -Ffprobe $ffprobe -LiteralPath $src
    if ($null -eq $probe) {
        Write-ErrorLog "Can't get media info for '$src'"
        return
    }

    if (Test-StreamsUnmappedAvCodec -Probe $probe -SourcePath $src) { return }

    $all = @(Get-MediaStreamDescriptors -Probe $probe)
    $sel = @(Select-MediaStreamDescriptors -Descriptors $all -StreamType $StreamType -Language $Language)
    if ($sel.Count -eq 0) {
        Write-InfoLog "No stream to extract from '$src'"
        return
    }

    $dir = Split-Path -Parent $src
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    foreach ($d in $sel) {
        $name = ConvertTo-StreamFileName -Basename $base -Descriptor $d
        $out = Join-Path $dir $name
        if (Test-Path -LiteralPath $out) {
            if (-not (Test-Path -LiteralPath $out -PathType Leaf)) {
                # Move-Item vers un dossier range le fichier dedans : pas de sidecar mergeable.
                Write-ErrorLog "Sidecar path is not a file: '$out'"
                continue
            }
            if (-not $WhatIfPreference) {
                if (-not $Force -and -not $PSCmdlet.ShouldContinue($out, 'Overwrite sidecar')) {
                    Write-InfoLog "Skip existing sidecar '$out'"
                    continue
                }
            }
        }
        # -y sur le sidecar tronquerait un fichier déjà bon si FFmpeg échoue ensuite.
        $temp = Get-StreamsUniqueTempPath -FinalPath $out
        $ffmpegArgs = Get-SplitExtractArguments -Descriptor $d -MkvPath $src -OutPath $temp
        try {
            try {
                $ok = Invoke-StreamsFFmpeg -Cmdlet $PSCmdlet -Exe $ffmpeg -Arguments $ffmpegArgs -TargetLabel $out
            }
            catch {
                Write-ErrorLog $_.Exception.Message
                continue
            }
            if (-not $ok) {
                Write-ErrorLog "ffmpeg failed extracting '$out'"
                continue
            }
            if ($PSCmdlet.ShouldProcess($out, "Move temp over '$out'")) {
                if (-not (Test-Path -LiteralPath $temp -PathType Leaf)) {
                    Write-ErrorLog "Temp file missing after extract: '$temp'"
                    continue
                }
                try {
                    Move-Item -LiteralPath $temp -Destination $out -Force -ErrorAction Stop
                }
                catch {
                    Write-ErrorLog $_.Exception.Message
                }
            }
        }
        finally {
            Remove-StreamsTempIfPresent -Cmdlet $PSCmdlet -TempPath $temp
        }
    }
}

function Merge-MediaSubtitle {
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

    $src = Resolve-StreamsExistingPath -LiteralPath $LiteralPath
    if (-not $src) {
        Write-ErrorLog "Not a .mkv file: '$LiteralPath'"
        return
    }
    if ($Destination) {
        if ([IO.Path]::GetExtension($Destination) -ine '.mkv') {
            Write-ErrorLog "Destination must be a .mkv path: '$Destination'"
            return
        }
        $dest = Resolve-StreamsOutputPath -LiteralPath $Destination
        if (-not $dest) {
            Write-ErrorLog "Destination must be a .mkv path: '$Destination'"
            return
        }
    }
    else { $dest = $src }

    $probe = Get-StreamsProbeHashtable -Ffprobe $ffprobe -LiteralPath $src
    if ($null -eq $probe) {
        Write-ErrorLog "Can't get media info for '$src'"
        return
    }

    $dir = Split-Path -Parent $src
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $sides = @(Get-SidecarFiles -Directory $dir -Basename $base -ExcludePath @($src, $dest) -ExistingPath $src)
    if ($sides.Count -eq 0) {
        Write-ErrorLog "No sidecar files found for '$base'"
        return
    }

    $desc = @(Get-MediaStreamDescriptors -Probe $probe)
    $desc = @(Add-UnmappedKeepDescriptors -Descriptors $desc -Probe $probe)
    $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars $sides

    if ((Test-Path -LiteralPath $dest -PathType Leaf) -and -not $WhatIfPreference) {
        if (-not $Force -and -not $PSCmdlet.ShouldContinue($dest, 'Overwrite MKV')) {
            Write-InfoLog "Skip existing '$dest'"
            return
        }
    }

    $temp = Get-StreamsUniqueTempPath -FinalPath $dest
    try {
        $ffmpegArgs = Build-MergeFFmpegArgs -MkvPath $src -Actions $act -OutputPath $temp
        try {
            $ok = Invoke-StreamsFFmpeg -Cmdlet $PSCmdlet -Exe $ffmpeg -Arguments $ffmpegArgs -TargetLabel $dest
        }
        catch {
            Write-ErrorLog $_.Exception.Message
            return
        }
        if (-not $ok) {
            Write-ErrorLog "ffmpeg failed muxing '$dest'"
            return
        }
        $moveSucceeded = $false
        if ($PSCmdlet.ShouldProcess($dest, "Move temp over '$dest'")) {
            if (-not (Test-Path -LiteralPath $temp -PathType Leaf)) {
                Write-ErrorLog "Temp file missing after mux: '$temp'"
                return
            }
            try {
                Move-Item -LiteralPath $temp -Destination $dest -Force -ErrorAction Stop
                $moveSucceeded = $true
            }
            catch {
                Write-ErrorLog $_.Exception.Message
                return
            }
        }
        elseif (-not $WhatIfPreference) {
            return
        }
        if ($RemoveSidecars -and ($WhatIfPreference -or $moveSucceeded)) {
            $toRemove = @($act.Replaces | ForEach-Object { $_.Sidecar.FullName }) + @($act.Adds | ForEach-Object { $_.FullName })
            foreach ($p in $toRemove) {
                if (-not $p) { continue }
                # FullName issu de Get-ChildItem : uniquement le fichier réellement muxé, casse du FS respectée.
                if ($PSCmdlet.ShouldProcess($p, 'Remove sidecar')) {
                    try { Remove-Item -LiteralPath $p -ErrorAction Stop }
                    catch { Write-ErrorLog "Unable to delete sidecar '$p': $($_.Exception.Message)" }
                }
            }
        }
    }
    finally {
        Remove-StreamsTempIfPresent -Cmdlet $PSCmdlet -TempPath $temp
    }
}

Export-ModuleMember -Function Split-MediaStream, Merge-MediaSubtitle
