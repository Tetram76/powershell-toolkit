Set-StrictMode -Version 3.0

@(
    'Tetram.Common'
    'Tetram.Media.FFmpeg'
) | ForEach-Object {
    Import-Module -Name (Join-Path $PSScriptRoot '..' $_) -Force
}

$PrivateRoot = Join-Path $PSScriptRoot 'Private'
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

function Get-MediaStream {
    <#
.EXTERNALHELP Tetram.Media.Streams-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string] $MediaFile,
        [ValidateSet('Video', 'Audio', 'Subtitle')]
        [string[]] $StreamType,
        [string[]] $Language,
        [switch] $Force
    )
    begin {
        $ffmpegAvailable = $true
        try { $ffmpeg = Get-FFmpegPath; $ffprobe = Get-FfprobePath }
        catch { Write-ErrorLog $_.Exception.Message; $ffmpegAvailable = $false }
    }
    process {
        if (-not $ffmpegAvailable) { return }

        if (-not (Test-StreamsMkvPath -LiteralPath $MediaFile)) {
            Write-ErrorLog "Not a .mkv file: '$MediaFile'"
            return
        }

        $src = Resolve-StreamsExistingPath -LiteralPath $MediaFile
        if (-not $src) {
            Write-ErrorLog "Not a .mkv file: '$MediaFile'"
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
                    # Move-Item vers un dossier range le fichier dedans : pas de fichier de flux mergeable.
                    Write-ErrorLog "Stream file path is not a file: '$out'"
                    continue
                }
                if (-not $WhatIfPreference) {
                    if (-not $Force -and -not $PSCmdlet.ShouldContinue($out, 'Overwrite stream file')) {
                        Write-InfoLog "Skip existing stream file '$out'"
                        continue
                    }
                }
            }
            # -y sur le fichier de flux tronquerait un fichier déjà bon si FFmpeg échoue ensuite.
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
                if ($null -eq $ok) { continue }
                if (-not $ok) {
                    Write-ErrorLog "ffmpeg failed extracting '$out'"
                    continue
                }
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
            finally {
                Remove-StreamsTempIfPresent -TempPath $temp
            }
        }
    }
}

function Merge-MediaSubtitle {
    <#
.EXTERNALHELP Tetram.Media.Streams-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string] $MediaFile,
        [Parameter(Mandatory, Position = 1)]
        [Alias('LiteralPath')]
        [string] $Path,
        [Parameter(Mandatory, ParameterSetName = 'Add')]
        [switch] $Add,
        [Parameter(Mandatory, ParameterSetName = 'Update')]
        [switch] $Update,
        [switch] $Force
    )
    begin {
        $ffmpegAvailable = $true
        try { $ffmpeg = Get-FFmpegPath; $ffprobe = Get-FfprobePath }
        catch { Write-ErrorLog $_.Exception.Message; $ffmpegAvailable = $false }
    }
    process {
        if (-not $ffmpegAvailable) { return }

        if (-not (Test-StreamsMkvPath -LiteralPath $MediaFile)) {
            Write-ErrorLog "Not a .mkv file: '$MediaFile'"
            return
        }

        $src = Resolve-StreamsExistingPath -LiteralPath $MediaFile
        if (-not $src) {
            Write-ErrorLog "Not a .mkv file: '$MediaFile'"
            return
        }

        $streamFileFull = Resolve-StreamsExistingPath -LiteralPath $Path
        if (-not $streamFileFull -or -not (Test-Path -LiteralPath $streamFileFull -PathType Leaf)) {
            Write-ErrorLog "Subtitle path not found: '$Path'"
            return
        }
        $base = [IO.Path]::GetFileNameWithoutExtension($src)
        $streamFile = ConvertFrom-StreamFileName -Basename $base -FileName ([IO.Path]::GetFileName($streamFileFull))
        if ($null -eq $streamFile -or $streamFile.Class -ne 'Subtitle') {
            Write-ErrorLog "Not a subtitle stream file for basename '$base': '$Path'"
            return
        }
        $streamFile | Add-Member -NotePropertyName FullName -NotePropertyValue $streamFileFull -Force

        $probe = Get-StreamsProbeHashtable -Ffprobe $ffprobe -LiteralPath $src
        if ($null -eq $probe) {
            Write-ErrorLog "Can't get media info for '$src'"
            return
        }

        $desc = @(Get-MediaStreamDescriptors -Probe $probe)
        $desc = @(Add-UnmappedKeepDescriptors -Descriptors $desc -Probe $probe)
        $act = Resolve-MergeActions -MkvDescriptors $desc -StreamFiles @($streamFile)

        if ($Add -and $act.Replaces.Count -gt 0) {
            Write-ErrorLog "A matching subtitle track already exists; use -Update instead of -Add: '$Path'"
            return
        }
        if ($Update -and $act.Adds.Count -gt 0) {
            Write-ErrorLog "No matching subtitle track to update; use -Add instead of -Update: '$Path'"
            return
        }

        if ((Test-Path -LiteralPath $src -PathType Leaf) -and -not $WhatIfPreference) {
            if (-not $Force -and -not $PSCmdlet.ShouldContinue($src, 'Overwrite MKV')) {
                Write-InfoLog "Skip existing '$src'"
                return
            }
        }

        $temp = Get-StreamsUniqueTempPath -FinalPath $src
        try {
            $ffmpegArgs = Build-MergeFFmpegArgs -MkvPath $src -Actions $act -OutputPath $temp
            try {
                $ok = Invoke-StreamsFFmpeg -Cmdlet $PSCmdlet -Exe $ffmpeg -Arguments $ffmpegArgs -TargetLabel $src
            }
            catch {
                Write-ErrorLog $_.Exception.Message
                return
            }
            if ($null -eq $ok) { return }
            if (-not $ok) {
                Write-ErrorLog "ffmpeg failed muxing '$src'"
                return
            }
            if (-not (Test-Path -LiteralPath $temp -PathType Leaf)) {
                Write-ErrorLog "Temp file missing after mux: '$temp'"
                return
            }
            try {
                Move-Item -LiteralPath $temp -Destination $src -Force -ErrorAction Stop
            }
            catch {
                Write-ErrorLog $_.Exception.Message
                return
            }
        }
        finally {
            Remove-StreamsTempIfPresent -TempPath $temp
        }
    }
}

Export-ModuleMember -Function Get-MediaStream, Merge-MediaSubtitle
