Set-StrictMode -Version 3.0

function Get-ElementaryExtension {
    param(
        [Parameter(Mandatory)][string] $CodecName,
        [Parameter(Mandatory)][string] $CodecType,
        [bool] $AttachedPic = $false
    )
    $c = $CodecName.ToLowerInvariant()
    $t = $CodecType.ToLowerInvariant()
    if ($AttachedPic -and $c -eq 'mjpeg') { return [pscustomobject]@{ Class = 'Cover'; Extension = '.jpg' } }
    if ($AttachedPic -and $c -eq 'png') { return [pscustomobject]@{ Class = 'Cover'; Extension = '.png' } }
    $map = @{
        'h264' = @{ Class = 'Video'; Extension = '.h264' }
        'avc' = @{ Class = 'Video'; Extension = '.h264' }
        'hevc' = @{ Class = 'Video'; Extension = '.hevc' }
        'h265' = @{ Class = 'Video'; Extension = '.hevc' }
        'av1' = @{ Class = 'Video'; Extension = '.ivf' }
        'vp8' = @{ Class = 'Video'; Extension = '.ivf' }
        'vp9' = @{ Class = 'Video'; Extension = '.ivf' }
        'mpeg2video' = @{ Class = 'Video'; Extension = '.m2v' }
        'vc1' = @{ Class = 'Video'; Extension = '.vc1' }
        'aac' = @{ Class = 'Audio'; Extension = '.aac' }
        'ac3' = @{ Class = 'Audio'; Extension = '.ac3' }
        'eac3' = @{ Class = 'Audio'; Extension = '.eac3' }
        'dts' = @{ Class = 'Audio'; Extension = '.dts' }
        'dca' = @{ Class = 'Audio'; Extension = '.dts' }
        'truehd' = @{ Class = 'Audio'; Extension = '.thd' }
        'flac' = @{ Class = 'Audio'; Extension = '.flac' }
        'opus' = @{ Class = 'Audio'; Extension = '.opus' }
        'mp3' = @{ Class = 'Audio'; Extension = '.mp3' }
        'mp2' = @{ Class = 'Audio'; Extension = '.mp2' }
        'vorbis' = @{ Class = 'Audio'; Extension = '.ogg' }
        'subrip' = @{ Class = 'Subtitle'; Extension = '.srt' }
        'ass' = @{ Class = 'Subtitle'; Extension = '.ass' }
        'ssa' = @{ Class = 'Subtitle'; Extension = '.ssa' }
        'webvtt' = @{ Class = 'Subtitle'; Extension = '.vtt' }
        'hdmv_pgs_subtitle' = @{ Class = 'Subtitle'; Extension = '.sup' }
    }
    if ($c.StartsWith('pcm_')) { return [pscustomobject]@{ Class = 'Audio'; Extension = '.wav' } }
    if ($map.ContainsKey($c)) {
        return [pscustomobject]@{ Class = [string]$map[$c].Class; Extension = [string]$map[$c].Extension }
    }
    return $null
}
