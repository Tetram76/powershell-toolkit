Set-StrictMode -Version 3.0

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
    if ($Descriptor.Class -eq 'Chapter') {
        return @('-hide_banner', '-i', $MkvPath, '-f', 'ffmetadata', '-map_chapters', '0', '-y', $OutPath)
    }
    # .ttf/.otf n'ont pas de muxer : -map -c copy échoue ; dump_attachment écrit le binaire brut.
    if ($Descriptor.Class -eq 'Attachment') {
        return @('-hide_banner', "-dump_attachment:$($Descriptor.StreamIndex)", $OutPath, '-i', $MkvPath, '-y')
    }
    return @('-hide_banner', '-i', $MkvPath, '-map', "0:$($Descriptor.StreamIndex)", '-c', 'copy', '-y', $OutPath)
}
