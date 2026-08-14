Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# Utilitaires audio
# -----------------------------------------------------------------------------

function Test-IsLosslessAudioCodec
{
    param([Parameter(Mandatory)] [string]$CodecName)

    switch ( $CodecName.ToLowerInvariant())
    {
        'flac'      {
            $true
        }
        'alac'      {
            $true
        }
        'truehd'    {
            $true
        }
        'wavpack'   {
            $true
        }
        'tta'       {
            $true
        }
        'ape'       {
            $true
        }
        default     {
            $false
        }
    }
}

function Get-TargetAudioCodec
{
    param(
        [Parameter(Mandatory)] [string]$FinalExtension
    )

    switch ( $FinalExtension.ToLowerInvariant())
    {
        '.mp4' {
            return 'aac'
        }
        default {
            return 'opus'
        }
    }
}

function Get-TargetAudioBitrate
{
    param(
        [Parameter(Mandatory)] [ValidateSet('opus', 'aac')] [string]$Codec,
        [Parameter(Mandatory)] [ValidateSet('High', 'Medium', 'Low')] [string]$Quality,
        [Parameter(Mandatory)] [int]$Channels
    )

    $isStereo = ($Channels -le 2)
    $is51 = ($Channels -eq 6)
    $is71 = ($Channels -ge 8)

    if ($Codec -eq 'opus')
    {
        if ($isStereo)
        {
            return @{ High = '160k'; Medium = '128k'; Low = '96k' }[$Quality]
        }
        if ($is51)
        {
            return @{ High = '384k'; Medium = '320k'; Low = '224k' }[$Quality]
        }
        if ($is71)
        {
            return @{ High = '512k'; Medium = '384k'; Low = '320k' }[$Quality]
        }
        return @{ High = '320k'; Medium = '256k'; Low = '192k' }[$Quality]
    }

    # aac
    if ($isStereo)
    {
        return @{ High = '192k'; Medium = '160k'; Low = '128k' }[$Quality]
    }
    if ($is51)
    {
        return @{ High = '448k'; Medium = '384k'; Low = '320k' }[$Quality]
    }
    if ($is71)
    {
        return @{ High = '576k'; Medium = '448k'; Low = '384k' }[$Quality]
    }
    return @{ High = '384k'; Medium = '320k'; Low = '256k' }[$Quality]
}

function ConvertTo-IntBitrate
{
    param($Value)

    if ($null -eq $Value)
    {
        return 0
    }
    try
    {
        return [int]$Value
    }
    catch
    {
        return 0
    }
}

function ConvertTo-IntBitrateK
{
    param([Parameter(Mandatory)] [string]$BitrateK) # ex "128k"

    if ($BitrateK -match '^(\d+)\s*k$')
    {
        return [int]$Matches[1] * 1000
    }
    if ($BitrateK -match '^\d+$')
    {
        return [int]$BitrateK
    } # au cas où
    return 0
}

function Test-HasBitrateGain
{
    param(
        [Parameter(Mandatory)] [string]$SourceCodec, # ex "aac"
        [Parameter(Mandatory)] [int]$SourceBitrate, # en bps (0 si inconnu)
        [Parameter(Mandatory)] [string]$TargetCodec, # "opus" ou "aac"
        [Parameter(Mandatory)] [string]$TargetBitrateLabel, # ex "128k"
        [Parameter()] [double]$MinGainRatio = 1.05          # 5% de marge
    )

    # Si on ne connait pas le bitrate source, on ne peut pas garantir un gain.
    # => règle conservative : pas de réencodage "pour gain" (sauf si source lossless, géré ailleurs).
    if ($SourceBitrate -le 0)
    {
        return $false
    }

    $targetBps = ConvertTo-IntBitrateK $TargetBitrateLabel
    if ($targetBps -le 0)
    {
        return $false
    }

    # Gain si la cible est suffisamment plus basse que la source
    return ($targetBps -lt ($SourceBitrate / $MinGainRatio))
}

Export-ModuleMember -Function Test-IsLosslessAudioCodec, Get-TargetAudioCodec, Get-TargetAudioBitrate, ConvertTo-IntBitrate, ConvertTo-IntBitrateK, Test-HasBitrateGain
