Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# Utilitaires vidéo
# -----------------------------------------------------------------------------

function Test-Is10BitVideoStream
{
    param(
        [Parameter(Mandatory)]
        $Stream
    )

    $props = $Stream.PSObject.Properties

    # 1) La source la plus fiable : pix_fmt
    $pix = $props['pix_fmt']?.Value
    if ($pix -and ([string]$pix -match '10'))
    {
        return $true
    }

    # 2) bits_per_raw_sample est parfois présent
    $bps = $props['bits_per_raw_sample']?.Value
    if ($null -ne $bps -and $bps -ne '')
    {
        if ([int]$bps -ge 10)
        {
            return $true
        }
    }

    # 3) Parfois c'est dans profile / codec_profile
    $profile = $props['profile']?.Value
    if ($profile -and ([string]$profile -match '10'))
    {
        return $true
    }

    return $false
}

function Get-SourceChromaMode
{
    param([Parameter(Mandatory)] $Stream)

    $pf = [string]$Stream.pix_fmt
    if ( [string]::IsNullOrWhiteSpace($pf))
    {
        return '420'
    } # fallback

    # Beaucoup de formats 420 apparaissent sous nv12/p010le etc.
    if ($pf -match '^(nv12|p010|p016)')
    {
        return '420'
    }

    # yuv420*, yuv422*, yuv444*
    if ($pf -match '^yuv420')
    {
        return '420'
    }
    if ($pf -match '^yuv422')
    {
        return '422'
    }
    if ($pf -match '^yuv444')
    {
        return '444'
    }

    # Cas courants RGB planar (ex: gbrp/gbrp10le) -> assimilé 444
    if ($pf -match '^gbrp')
    {
        return '444'
    }

    # fallback prudent
    return '420'
}

Export-ModuleMember -Function Test-Is10BitVideoStream, Get-SourceChromaMode
