# Tetram.Common.psm1 — PowerShell 7+
Set-StrictMode -Version 3.0

<#
.SYNOPSIS
    Fonctions d’aide pour la journalisation colorée (PowerShell 7+).
.DESCRIPTION
    Fournit des fonctions Write-Log*, conformes aux conventions PowerShell.
    - Write-Log        : affiche un message avec couleur.
    - Write-ErrorLog   : journalise les erreurs (en rouge).
    - Write-InfoLog    : journalise les infos (en bleu).
    - Write-DebugLog   : journalise les messages de debug (en gris).
.NOTES
    Ces fonctions n’écrivent pas dans le pipeline (affichage console uniquement).
    Cross-platform, aucun avertissement de verbe non approuvé.
#>

function Write-Log
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][System.ConsoleColor] $Color
    )

    Write-Host -ForegroundColor $Color "$( Get-Date -Format 'G' ): $Text"
}

function Write-ErrorLog
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text
    )

    Write-Log -Color Red "Error: $Text"
}

function Write-InfoLog
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [System.ConsoleColor] $Color = 'Blue',
        [switch] $Force
    )

    if ($Force -or $PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue')
    {
        Write-Log -Color $Color $Text
    }
}

function Write-DebugLog
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text
    )

    if ($PSBoundParameters.ContainsKey('Debug') -or $DebugPreference -eq 'Continue')
    {
        Write-Log -Color DarkGray $Text
    }
}

function Format-FileSize
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][long] $Size
    )

    if ($Size -lt 0)
    {
        return "-$( Format-FileSize -Size (-$Size) )"
    }
    if ($Size -gt 1PB)
    {
        return "{0:0.00} PB" -f ($Size/1PB)
    }
    if ($Size -gt 1TB)
    {
        return "{0:0.00} TB" -f ($Size/1TB)
    }
    if ($Size -gt 1GB)
    {
        return "{0:0.00} GB" -f ($Size/1GB)
    }
    if ($Size -gt 1MB)
    {
        return "{0:0.00} MB" -f ($Size/1MB)
    }
    if ($Size -gt 1KB)
    {
        return "{0:0.00} kB" -f ($Size/1KB)
    }
    return "{0:0.00} B" -f $Size
}

function Format-Duration
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TimeSpan] $TimeSpan
    )

    if (-not $TimeSpan)
    {
        return ""
    }
    if ($TimeSpan.Days -eq 0)
    {
        return $TimeSpan.ToString("h':'mm':'ss")
    }
    return $TimeSpan.ToString("d'.'hh':'mm':'ss")
}

function Test-IsLikelyPath
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$InputString,

        [Parameter(Mandatory = $false)]
        [int]$MaxExtensionLength = 5
    )

    if ( [string]::IsNullOrWhiteSpace($InputString))
    {
        return $false
    }
    $trimmed = $InputString.Trim()

    # 1. URLs
    if ($trimmed -match '^[a-zA-Z][a-zA-Z0-9+\-.]*://')
    {
        if ( [System.Uri]::IsWellFormedUriString($trimmed, [System.UriKind]::Absolute))
        {
            return $true
        }
    }

    # 2. Indicateurs forts (Tilde, ., .., Variables d'env)
    if ($trimmed -match '^~[/\\]' -or $trimmed -eq '.' -or $trimmed -eq '..' -or
            $trimmed -match '%[^%]+%' -or $trimmed -match '^\$[a-zA-Z_][a-zA-Z0-9_]*[/\\]')
    {
        return $true
    }

    # 3. Validation des caractères (Sécurité Windows)
    $InvalidChars = [System.IO.Path]::GetInvalidPathChars() | Where-Object { $_ -notin @(':', '\', '/') }
    if ($trimmed.IndexOfAny($InvalidChars) -ge 0)
    {
        return $false
    }

    # 4. Analyse des séparateurs (Dossiers ou Chemins complexes)
    if ($trimmed -match '[\\/]')
    {
        # Si contient un slash et n'a pas de caractères interdits, c'est un chemin
        return $true
    }

    # 5. Nom de fichier seul (Sans aucun slash)
    # Doit avoir une extension alphanumérique de longueur X
    if ($trimmed -match '\.(?<extension>[a-zA-Z0-9]+)$')
    {
        if ($trimmed -match '^\d+\.\d+$')
        {
            return $false
        } # Exclure nombres
        if ($Matches['extension'].Length -le $MaxExtensionLength)
        {
            return $true
        }
    }

    return $false
}

function Show-CommandLine
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Exe,

        [Parameter()]
        [string[]] $Arguments = @(),

        [int] $Indent = 4,

        [ConsoleColor] $ExeColor = 'Yellow',
        [ConsoleColor] $ParamColor = 'DarkGray',
        [ConsoleColor] $FileColor = 'Cyan',

    # - Wildcards : 'c:*', 'metadata*', 'map*', etc.
    # - Regex via préfixe 're:' : 're:^(metadata|map)(:|$)'
        [Parameter()]
        [string[]] $NoPathDetectionParameters = @(),

        [switch] $PassThru
    )

    function Should-SkipPathDetection
    {
        param([string] $ParamToken)

        if (-not $NoPathDetectionParameters -or $NoPathDetectionParameters.Count -eq 0)
        {
            return $false
        }

        $name = ($ParamToken -replace '^-', '')

        foreach ($pattern in $NoPathDetectionParameters)
        {
            if ( [string]::IsNullOrWhiteSpace($pattern))
            {
                continue
            }

            if ($pattern -like 're:*')
            {
                $rx = $pattern.Substring(3)
                if ($name -match $rx)
                {
                    return $true
                }
                continue
            }
            else
            {
                if ($name -like $pattern)
                {
                    return $true
                }
            }
        }

        return $false
    }

    $indentStr = ' ' * $Indent
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add($Exe)

    $i = 0
    while ($i -lt $Arguments.Count)
    {
        $arg = $Arguments[$i]

        $hasValue = $false
        $val = $null
        if ($i + 1 -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch '^-')
        {
            $hasValue = $true
            $val = $Arguments[$i + 1]
        }

        if ($arg -like '-*')
        {
            if ($hasValue)
            {
                $lines.Add("$indentStr$arg $val")
                $i += 2
                continue
            }
            else
            {
                $lines.Add("$indentStr$arg")
                $i++
                continue
            }
        }
        else
        {
            $lines.Add("$indentStr$arg")
            $i++
            continue
        }
    }

    if ($PassThru)
    {
        return $lines
    }

    Write-Host $lines[0] -ForegroundColor $ExeColor
    foreach ($line in $lines.GetRange(1, $lines.Count - 1))
    {
        if ($line -match "^\s*(-\S+)\s+(.+)$")
        {
            $k = $Matches[1]; $v = $Matches[2]
            $vColor = ((-not (Should-SkipPathDetection $k) -and (Test-IsLikelyPath $v)) ? $FileColor: $ParamColor)
            Write-Host ($indentStr + $k + ' ') -ForegroundColor $ParamColor -NoNewline
            Write-Host $v -ForegroundColor $vColor
        }
        else
        {
            $color = ($line.TrimStart() -notlike '-*' -and (Test-IsLikelyPath ($line.Trim()))) ? $FileColor : $ParamColor
            Write-Host $line -ForegroundColor $color
        }
    }
}

function Show-Colors()
{
    $colors = [Enum]::GetValues([ConsoleColor])
    $max = ($colors | foreach { "$_ ".Length } | Measure-Object -Maximum).Maximum
    foreach ($color in $colors)
    {
        Write-Host (" {0,2} {1,$max} " -f [int]$color, $color) -NoNewline
        Write-Host "$color" -Foreground $color
    }
}

Export-ModuleMember -Function `
	Show-Colors,
Write-Log, Write-ErrorLog, Write-InfoLog, Write-DebugLog,
Format-FileSize, Format-Duration,
Show-CommandLine
