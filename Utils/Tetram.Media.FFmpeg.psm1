Set-StrictMode -Version 3.0

$script:FFToolsDefaultBase = Join-Path (Split-Path -Parent $PSScriptRoot) 'RecodeVideo\ffmpeg-8.0.1-full_build\bin'

function Get-FFmpegPath
{
    param([string]$OverridePath)

    if (-not [string]::IsNullOrWhiteSpace($OverridePath) -and (Test-Path $OverridePath))
    {
        return $OverridePath
    }

    $defaultPath = Join-Path $script:FFToolsDefaultBase 'ffmpeg.exe'
    if ($script:FFToolsDefaultBase -and (Test-Path $defaultPath))
    {
        return $defaultPath
    }

    $fromPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
    return $fromPath ? $fromPath.Source : $null
}

function Get-FfprobePath
{
    param([string]$OverridePath)

    if (-not [string]::IsNullOrWhiteSpace($OverridePath) -and (Test-Path $OverridePath))
    {
        return $OverridePath
    }
    $defaultPath = Join-Path $script:FFToolsDefaultBase 'ffprobe.exe'
    if ($script:FFToolsDefaultBase -and (Test-Path $defaultPath))
    {
        return $defaultPath
    }
    $fromPath = Get-Command ffprobe -ErrorAction SilentlyContinue
    return $fromPath ? $fromPath.Source : $null
}

function Invoke-FFmpeg
{
    param(
        [Parameter(Mandatory)] [string]$Arguments,
        [string]$ExePath, # Permet d'injecter le chemin résolu par le script parent
        [switch]$CaptureOutput
    )

    $exe = if ($ExePath)
    {
        $ExePath
    }
    else
    {
        Get-FFmpegPath
    }
    if (-not $exe)
    {
        throw "FFmpeg est introuvable sur ce système."
    }

    if ($CaptureOutput)
    {
        return Start-Process -FilePath $exe -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -RedirectStandardError $null
    }
    else
    {
        Write-Verbose "Execution: $exe $Arguments"
        $proc = Start-Process -FilePath $exe -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
        return $proc.ExitCode
    }
}

function Get-MediaFastHash
{
    param([Parameter(Mandatory)][string]$Path)

    $f = [System.IO.File]::OpenRead($Path)
    $size = $f.Length
    $buffer = New-Object byte[] 307200 # 300 Ko

    try
    {
        $f.Read($buffer, 0, 102400) | Out-Null
        if ($size -gt 204800)
        {
            $f.Seek([math]::Floor($size / 2) - 51200, [System.IO.SeekOrigin]::Begin) | Out-Null
            $f.Read($buffer, 102400, 102400) | Out-Null
        }
        if ($size -gt 307200)
        {
            $f.Seek(-102400, [System.IO.SeekOrigin]::End) | Out-Null
            $f.Read($buffer, 204800, 102400) | Out-Null
        }
    }
    finally
    {
        $f.Close()
    }

    $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash($buffer)
    return "$size-$([System.BitConverter]::ToString($hash).Replace('-', '').Substring(0, 8) )"
}

Export-ModuleMember -Function Get-FFmpegPath, Get-FfprobePath, Invoke-FFmpeg, Get-MediaFastHash
