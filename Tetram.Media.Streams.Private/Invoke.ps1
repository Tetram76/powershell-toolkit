Set-StrictMode -Version 3.0

function Get-StreamsUniqueTempPath {
    param(
        [Parameter(Mandatory)][string] $FinalPath,
        [switch] $KeepExtension
    )
    if ($KeepExtension) {
        # FFmpeg déduit le muxer de la dernière extension ; `.srt.tmp` n'en a pas. Le merge MKV utilise `-f matroska` à la place.
        $dir = Split-Path -Parent $FinalPath
        if (-not $dir) { $dir = '.' }
        $ext = [IO.Path]::GetExtension($FinalPath)
        $stem = [IO.Path]::GetFileNameWithoutExtension($FinalPath)
        $temp = Join-Path $dir ($stem + '.tmp' + $ext)
        $n = 2
        while (Test-Path -LiteralPath $temp) {
            $temp = Join-Path $dir ($stem + ".tmp$n" + $ext)
            $n++
        }
        return $temp
    }
    $temp = $FinalPath + '.tmp'
    $n = 2
    while (Test-Path -LiteralPath $temp) {
        $temp = $FinalPath + ".tmp$n"
        $n++
    }
    return $temp
}

function Invoke-StreamsFFmpeg {
    param(
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)][string] $Exe,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $TargetLabel
    )
    Show-CommandLine $Exe $Arguments -NoPathDetectionParameters 'metadata*', 'disposition*', 'map*'
    if ($Cmdlet.ShouldProcess($TargetLabel, "ffmpeg on $TargetLabel")) {
        $code = Invoke-FFmpeg -ExePath $Exe -Arguments $Arguments
        return ($code -eq 0)
    }
    Write-InfoLog -Color Magenta "[WhatIf] Would run ffmpeg on $TargetLabel"
    return $true
}

function Get-SplitExtractArguments {
    param([pscustomobject] $Descriptor, [string] $MkvPath, [string] $OutPath)
    return @('-hide_banner', '-i', $MkvPath, '-map', "0:$($Descriptor.StreamIndex)", '-c', 'copy', '-y', $OutPath)
}
