#Requires -Version 5.1
[CmdletBinding()]
param(
    [string] $Path = "./tests",

    [switch] $Coverage,

    [string[]] $ExcludeTag = @('Integration'),

    [string[]] $CodeCoveragePath = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$config = New-PesterConfiguration

$config.Run.Path = $Path
$config.Run.Exit = $true

$config.Output.Verbosity = "Detailed"
$config.Output.CIFormat = "GithubActions"

if ($ExcludeTag.Count -gt 0) {
    $config.Filter.ExcludeTag = $ExcludeTag
}

$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = "TestResults.xml"
$config.TestResult.OutputFormat = "JUnitXml"

if ($Coverage) {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    [string[]] $pathsForCoverage =
        if ($CodeCoveragePath.Count -gt 0) {
            @($CodeCoveragePath | Where-Object { Test-Path -LiteralPath $_ })
        }
        else {
            $moduleDirs = @(
                Get-ChildItem -LiteralPath $repoRoot -Directory |
                    Where-Object {
                        Test-Path -LiteralPath (Join-Path $_.FullName "$($_.Name).psd1") -PathType Leaf
                    }
            )
            $coveragePaths = [System.Collections.Generic.List[string]]::new()
            foreach ($dir in $moduleDirs) {
                Get-ChildItem -LiteralPath $dir.FullName -Filter *.psm1 -File |
                    ForEach-Object { [void]$coveragePaths.Add($_.FullName) }
                $privateDir = Join-Path $dir.FullName 'Private'
                if (Test-Path -LiteralPath $privateDir -PathType Container) {
                    [void]$coveragePaths.Add($privateDir)
                }
            }
            @($coveragePaths | Where-Object { Test-Path -LiteralPath $_ })
        }

    $config.CodeCoverage.Enabled = [bool]$pathsForCoverage.Count
    if ($pathsForCoverage.Count -gt 0) {
        $config.CodeCoverage.Path = $pathsForCoverage
        $config.CodeCoverage.OutputPath = "coverage.xml"
        $config.CodeCoverage.OutputFormat = "JaCoCo"
    }
}

Invoke-Pester -Configuration $config
