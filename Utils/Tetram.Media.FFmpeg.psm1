Set-StrictMode -Version 3.0

$script:FFToolsSearchRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'RecodeVideo'
$script:FFToolsDefaultBase = $null
$script:FFToolsBaseResolved = $false
$script:FFToolsMinVersionCache = $null
# Hook tests : scriptblock (string $LiteralPath) -> [version]| $null
$script:FFToolsVersionReader = $null

function Get-FFToolsMinVersion
{
    if ($null -eq $script:FFToolsMinVersionCache)
    {
        $raw = $MyInvocation.MyCommand.Module.PrivateData.FFToolsMinVersion
        if ([string]::IsNullOrWhiteSpace($raw))
        {
            $raw = '9.0.1'
        }
        $script:FFToolsMinVersionCache = [version]$raw
    }
    return $script:FFToolsMinVersionCache
}

function Get-FFmpegVersionFromBinary
{
    param([Parameter(Mandatory)][string]$LiteralPath)

    if ($script:FFToolsVersionReader)
    {
        return & $script:FFToolsVersionReader $LiteralPath
    }

    if (-not (Test-Path -LiteralPath $LiteralPath))
    {
        return $null
    }

    try
    {
        $output = & $LiteralPath -version 2>&1 | Out-String
    }
    catch
    {
        return $null
    }

    if ($output -match 'ffmpeg version (?<ver>\d+(?:\.\d+)+)')
    {
        try { return [version]$Matches['ver'] }
        catch { return $null }
    }
    return $null
}

function Resolve-FFToolsDefaultBase
{
    if ($script:FFToolsBaseResolved)
    {
        return $script:FFToolsDefaultBase
    }

    $script:FFToolsBaseResolved = $true
    $script:FFToolsDefaultBase = $null

    $root = $script:FFToolsSearchRoot
    if (-not $root -or -not (Test-Path -LiteralPath $root))
    {
        return $null
    }

    $exeName = if ($IsWindows) { 'ffmpeg.exe' } else { 'ffmpeg' }
    $probeName = if ($IsWindows) { 'ffprobe.exe' } else { 'ffprobe' }
    $min = Get-FFToolsMinVersion
    $bestVer = $null
    $bestBin = $null

    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'ffmpeg-*' } |
        ForEach-Object {
            $binDir = Join-Path $_.FullName 'bin'
            $candidate = Join-Path $binDir $exeName
            $probeCandidate = Join-Path $binDir $probeName
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { return }
            if (-not (Test-Path -LiteralPath $probeCandidate -PathType Leaf)) { return }
            $ver = Get-FFmpegVersionFromBinary -LiteralPath $candidate
            if ($null -eq $ver) { return }
            if ($ver -lt $min) { return }
            if ($null -eq $bestVer -or $ver -gt $bestVer)
            {
                $bestVer = $ver
                $bestBin = $binDir
            }
        }

    $script:FFToolsDefaultBase = $bestBin
    return $script:FFToolsDefaultBase
}

function Get-FFToolMissingMessage
{
    param([Parameter(Mandatory)][string]$ToolName)

    $min = Get-FFToolsMinVersion
    $root = $script:FFToolsSearchRoot
    return "$ToolName introuvable : placez une build officielle >= $min sous 'RecodeVideo\ffmpeg-<version>-...\bin\' (racine recherchée : '$root'), ou fournissez -OverridePath / PATH."
}

function Get-FFmpegPath
{
    param([string]$OverridePath)

    if (-not [string]::IsNullOrWhiteSpace($OverridePath))
    {
        if (Test-Path -LiteralPath $OverridePath -PathType Leaf)
        {
            return $OverridePath
        }
        if (Test-Path -LiteralPath $OverridePath)
        {
            throw "OverridePath doit être un fichier exécutable, pas un dossier : '$OverridePath'"
        }
    }

    $exeName = if ($IsWindows) { 'ffmpeg.exe' } else { 'ffmpeg' }
    $base = Resolve-FFToolsDefaultBase
    if ($base)
    {
        $defaultPath = Join-Path $base $exeName
        if (Test-Path -LiteralPath $defaultPath)
        {
            return $defaultPath
        }
    }

    $fromPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($fromPath)
    {
        return $fromPath.Source
    }

    throw (Get-FFToolMissingMessage -ToolName 'FFmpeg')
}

function Get-FfprobePath
{
    param([string]$OverridePath)

    if (-not [string]::IsNullOrWhiteSpace($OverridePath))
    {
        if (Test-Path -LiteralPath $OverridePath -PathType Leaf)
        {
            return $OverridePath
        }
        if (Test-Path -LiteralPath $OverridePath)
        {
            throw "OverridePath doit être un fichier exécutable, pas un dossier : '$OverridePath'"
        }
    }

    $exeName = if ($IsWindows) { 'ffprobe.exe' } else { 'ffprobe' }
    $base = Resolve-FFToolsDefaultBase
    if ($base)
    {
        $defaultPath = Join-Path $base $exeName
        if (Test-Path -LiteralPath $defaultPath)
        {
            return $defaultPath
        }
    }

    $fromPath = Get-Command ffprobe -ErrorAction SilentlyContinue
    if ($fromPath)
    {
        return $fromPath.Source
    }

    throw (Get-FFToolMissingMessage -ToolName 'FFprobe')
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
