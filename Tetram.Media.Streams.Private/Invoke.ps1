Set-StrictMode -Version 3.0

function Get-StreamsUniqueTempPath {
    param(
        [Parameter(Mandatory)][string] $FinalPath
    )
    # Comme Reencode : TEMP + GUID + extension réelle — FFmpeg déduit le muxer, Merge ne prend pas le fichier pour un sidecar.
    $ext = [IO.Path]::GetExtension($FinalPath)
    $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + $ext)
    if (Test-Path -LiteralPath $temp -PathType Leaf) {
        Remove-Item -LiteralPath $temp -Force -Confirm:$false -WhatIf:$false
    }
    return $temp
}

function Remove-StreamsTempIfPresent {
    param(
        [string] $TempPath
    )
    # GUID interne TEMP : pas un ShouldProcess utilisateur (No to All sur le publish laisserait le fichier).
    if (-not $TempPath) { return }
    if (-not (Test-Path -LiteralPath $TempPath)) { return }
    Remove-Item -LiteralPath $TempPath -Force -Confirm:$false -WhatIf:$false -ErrorAction SilentlyContinue
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
