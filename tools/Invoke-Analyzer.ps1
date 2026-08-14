#Requires -Version 5.1
[CmdletBinding()]
param(
    [string[]] $AdditionalPaths = @(
        '.\tools'
        '.\tests'
    ),

    [string] $Settings,

    # Phase 1 dépôt existant : ParseError + Error. Passer aussi 'Warning' quand le dépôt est stabilisé.
    [string[]] $Severity = @('ParseError', 'Error'),

    # Si renseigné (ex. CI), écrit un SARIF à partir de la même collecte $results avant la gate.
    [string] $SarifOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Settings) {
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

    foreach ($scan in @($scanPaths)) {
        $isContainer = (Get-Item -LiteralPath $scan).PSIsContainer
        # PSScriptAnalyzer émet parfois CommandNotFound (Get-Command) en interne ;
        # Stop transformerait ça en échec du script avant la gate $Severity.
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $chunk = Invoke-ScriptAnalyzer -Path $scan -Recurse:$isContainer @analyzerParams
        }
        finally {
            $ErrorActionPreference = $previousEap
        }
        if ($chunk) {
            [void]$results.AddRange(@($chunk))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SarifOutputPath)) {
        $sarifParent = Split-Path -Parent $SarifOutputPath
        if ($sarifParent -and -not (Test-Path -LiteralPath $sarifParent)) {
            New-Item -ItemType Directory -Path $sarifParent -Force | Out-Null
        }

        $analysisResults = @($results)
        # ConvertTo-SARIF 1.0 : sous StrictMode Latest, certains accès aux DiagnosticRecord échouent.
        Set-StrictMode -Off
        try {
            Import-Module ConvertToSARIF -Force
            $analysisResults | ConvertTo-SARIF -FilePath $SarifOutputPath
        }
        finally {
            Set-StrictMode -Version Latest
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
