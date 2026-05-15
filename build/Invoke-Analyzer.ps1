#Requires -Version 5.1
[CmdletBinding()]
param(
    [string[]] $Path = @(
        '.\build',
        '.\tests',
        '.\Utils',
        '.\Tetram.Media.Reencode.Private'
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
    foreach ($item in $Path) {
        if (Test-Path -LiteralPath $item) {
            $chunk = Invoke-ScriptAnalyzer -Path $item -Recurse @analyzerParams
            if ($chunk) {
                [void]$results.AddRange(@($chunk))
            }
        }
    }

    $rootPsFiles = Get-ChildItem -LiteralPath $repoRoot -File |
        Where-Object {
            $_.Extension -in @('.psm1', '.psd1')
        }

    foreach ($f in $rootPsFiles) {
        $chunk = Invoke-ScriptAnalyzer -Path $f.FullName @analyzerParams
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
