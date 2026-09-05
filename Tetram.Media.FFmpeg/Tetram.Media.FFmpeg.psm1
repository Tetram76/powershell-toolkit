Set-StrictMode -Version 3.0

$script:FFToolsSearchRoot = Join-Path $PSScriptRoot 'ffmpeg'
$script:FFToolsDefaultBase = $null
$script:FFToolsBaseResolved = $false
$script:FFToolsMinVersionCache = $null
$script:FFToolsRejectedMapCache = $null
$script:FFToolsRejectedHighest = $null
# Hook tests : scriptblock (string $LiteralPath) -> [version]| $null
$script:FFToolsVersionReader = $null

function Get-FFToolsMinVersion
{
    if ($null -eq $script:FFToolsMinVersionCache)
    {
        $raw = $MyInvocation.MyCommand.Module.PrivateData.FFToolsMinVersion
        if ([string]::IsNullOrWhiteSpace($raw))
        {
            $raw = '8.0.0'
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

function ConvertTo-FFToolsVersionKey
{
    param([Parameter(Mandatory)][version]$Version)

    $build = if ($Version.Build -lt 0) { 0 } else { $Version.Build }
    return '{0}.{1}.{2}' -f $Version.Major, $Version.Minor, $build
}

function Get-FFToolsRejectedMap
{
    if ($null -eq $script:FFToolsRejectedMapCache)
    {
        $raw = $MyInvocation.MyCommand.Module.PrivateData.FFToolsRejectedVersions
        if (-not ($raw -is [System.Collections.IDictionary]))
        {
            $raw = @{
                '9.0.0' = 'bug de parallélisation qui peut corrompre le fichier final'
                '9.0.1' = 'bug de parallélisation qui peut corrompre le fichier final'
            }
        }
        $map = @{}
        foreach ($item in $raw.GetEnumerator())
        {
            $reason = [string]$item.Value
            if ([string]::IsNullOrWhiteSpace($item.Key) -or [string]::IsNullOrWhiteSpace($reason)) { continue }
            try
            {
                $map[(ConvertTo-FFToolsVersionKey -Version ([version]$item.Key))] = $reason
            }
            catch
            {
                # Entrée manifeste non parsable en [version] : ignorer plutôt que d'abandonner le scan.
            }
        }
        $script:FFToolsRejectedMapCache = $map
    }
    return $script:FFToolsRejectedMapCache
}

function Get-FFToolsRejectedReason
{
    param([Parameter(Mandatory)][version]$Version)

    $map = Get-FFToolsRejectedMap
    $key = ConvertTo-FFToolsVersionKey -Version $Version
    if ($map.ContainsKey($key))
    {
        return $map[$key]
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
    $script:FFToolsRejectedHighest = $null

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
    $highestFound = $null
    $highestFoundReason = $null

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
            $rejectReason = Get-FFToolsRejectedReason -Version $ver
            if ($null -eq $highestFound -or $ver -gt $highestFound)
            {
                $highestFound = $ver
                $highestFoundReason = $rejectReason
            }
            if ($ver -lt $min) { return }
            # Rejet métier distinct du seuil mini : ces builds (ex. 9.0.0/9.0.1) sont inutilisables.
            if ($rejectReason) { return }
            if ($null -eq $bestVer -or $ver -gt $bestVer)
            {
                $bestVer = $ver
                $bestBin = $binDir
            }
        }

    if ($null -eq $bestBin -and $highestFoundReason)
    {
        $script:FFToolsRejectedHighest = @{
            Version = $highestFound
            Reason  = $highestFoundReason
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
    $hint = "placez une build officielle >= $min sous 'Tetram.Media.FFmpeg\ffmpeg\ffmpeg-<version>-...\bin\' (racine recherchée : '$root'), ou fournissez -OverridePath / PATH."
    if ($script:FFToolsRejectedHighest)
    {
        $ver = $script:FFToolsRejectedHighest.Version
        $reason = $script:FFToolsRejectedHighest.Reason
        return "$ToolName introuvable : la version $ver trouvée est explicitement rejetée ($reason). $hint"
    }
    return "$ToolName introuvable : $hint"
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
        throw "OverridePath inexistant ou invalide : '$OverridePath'"
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

    # -CommandType Application : une fonction/alias de même nom dans la session primerait sinon sur
    # l'exécutable du PATH, avec une Source vide ou trompeuse.
    $fromPath = Get-Command ffmpeg -CommandType Application -ErrorAction SilentlyContinue
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
        throw "OverridePath inexistant ou invalide : '$OverridePath'"
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

    # -CommandType Application : une fonction/alias de même nom dans la session primerait sinon sur
    # l'exécutable du PATH, avec une Source vide ou trompeuse.
    $fromPath = Get-Command ffprobe -CommandType Application -ErrorAction SilentlyContinue
    if ($fromPath)
    {
        return $fromPath.Source
    }

    throw (Get-FFToolMissingMessage -ToolName 'FFprobe')
}

function Invoke-FFmpeg
{
    param(
        [Parameter(Mandatory)] [string[]]$Arguments,
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

    # & + splat : conserve les frontières d'args (chemins avec espaces).
    # Start-Process -ArgumentList joint un string[] en une seule chaîne.
    if ($CaptureOutput)
    {
        return & $exe @Arguments 2>&1
    }

    Write-Verbose "Execution: $exe $($Arguments -join ' ')"
    # Écarter stdout du success stream pour ne renvoyer que le code de sortie
    # (contrat historique Start-Process → ExitCode). stderr reste visible.
    & $exe @Arguments > $null
    return $LASTEXITCODE
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
