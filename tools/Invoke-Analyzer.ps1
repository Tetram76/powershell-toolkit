#Requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'AdditionalPaths')]
param(
    [Parameter(ParameterSetName = 'AdditionalPaths')]
    [string[]] $AdditionalPaths = @(
        '.\tools'
        '.\tests'
    ),

    # Cible un fichier (ou dossier) en particulier ; exclusif avec -AdditionalPaths
    # (pas de scan des dossiers de modules dans ce cas).
    [Parameter(Mandatory, ParameterSetName = 'Path')]
    [string] $Path,

    [string] $Settings,

    # Phase 1 dépôt existant : ParseError + Error. Passer aussi 'Warning' quand le dépôt est stabilisé.
    [string[]] $Severity = @('ParseError', 'Error')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Settings) {
    # [string] non renseigné vaut '' (pas $null) : ??= ne s'applique pas ici.
    $Settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
}

if (-not (Test-Path -LiteralPath $Settings)) {
    throw "Fichier de paramètres introuvable : $Settings"
}

Push-Location $repoRoot
try {
    # Severités évaluées : celles du fichier de paramètres. Le gate bloquant = paramètre $Severity (phase 1 typique : ParseError, Error).
    $analyzerParams = @{
        Settings = $Settings
    }

    $results = [System.Collections.ArrayList]::new()
    $scanPaths = [System.Collections.Generic.List[string]]::new()

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "Chemin introuvable : $Path"
        }
        [void]$scanPaths.Add((Resolve-Path -LiteralPath $Path).Path)
    }
    else {
        foreach ($item in @($AdditionalPaths)) {
            if (Test-Path -LiteralPath $item) {
                [void]$scanPaths.Add((Resolve-Path -LiteralPath $item).Path)
            }
        }

        $moduleDirs = foreach ($dir in @(Get-ChildItem -LiteralPath $repoRoot -Directory)) {
            if (Test-Path -LiteralPath (Join-Path $dir.FullName "$($dir.Name).psd1") -PathType Leaf) {
                $dir
            }
        }
        foreach ($dir in @($moduleDirs)) {
            $moduleFiles = foreach ($file in @(Get-ChildItem -LiteralPath $dir.FullName -File)) {
                if ($file.Extension -in @('.psm1', '.psd1', '.ps1')) {
                    $file
                }
            }
            $privateDir = Join-Path $dir.FullName 'Private'
            if (Test-Path -LiteralPath $privateDir -PathType Container) {
                $moduleFiles = @($moduleFiles) + @(Get-ChildItem -LiteralPath $privateDir -Filter '*.ps1' -File -Recurse)
            }
            foreach ($f in @($moduleFiles)) {
                [void]$scanPaths.Add($f.FullName)
            }
        }
    }

    foreach ($scan in @($scanPaths)) {
        $isContainer = (Get-Item -LiteralPath $scan).PSIsContainer
        # PSScriptAnalyzer émet parfois CommandNotFound (Get-Command) en interne ;
        # -ErrorAction Continue évite que $ErrorActionPreference = 'Stop' transforme
        # ça en échec du script avant la gate $Severity.
        $chunk = Invoke-ScriptAnalyzer -Path $scan -Recurse:$isContainer -ErrorAction Continue @analyzerParams
        if ($chunk) {
            [void]$results.AddRange(@($chunk))
        }
    }

    $failures = @($results | Where-Object { $_.Severity -in $Severity })

    if ($failures.Count -gt 0) {
        $failures |
            Sort-Object ScriptName, Line, Column |
            Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize

        throw "PSScriptAnalyzer a signalé $($failures.Count) problème(s) (severités : $($Severity -join ', '))."
    }
}
finally {
    Pop-Location
}
