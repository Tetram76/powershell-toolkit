#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $OutputFolder,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputFolder) {
    $OutputFolder = Join-Path $repoRoot 'docs\help'
}

function Install-PlatyPSIfMissing {
    if (Get-Module -ListAvailable -Name Microsoft.PowerShell.PlatyPS) {
        return
    }

    Write-Verbose 'Microsoft.PowerShell.PlatyPS absent : installation CurrentUser.'
    if (Get-Command -Name Install-PSResource -ErrorAction SilentlyContinue) {
        Install-PSResource -Name Microsoft.PowerShell.PlatyPS -Scope CurrentUser -TrustRepository
        return
    }

    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null
    Install-Module -Name Microsoft.PowerShell.PlatyPS -Scope CurrentUser -Force -SkipPublisherCheck
}

Install-PlatyPSIfMissing
Import-Module Microsoft.PowerShell.PlatyPS -Force

$manifests = @(
    Get-ChildItem -LiteralPath $repoRoot -Filter '*.psd1' -File |
        Sort-Object Name
)
if ($manifests.Count -eq 0) {
    throw "Aucun manifeste .psd1 à la racine de $repoRoot."
}

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

# UTF-8 sans BOM : les aides commentées du dépôt sont en français.
$utf8 = [System.Text.UTF8Encoding]::new($false)

foreach ($manifest in $manifests) {
    Write-Verbose "Génération de l'aide markdown pour $($manifest.BaseName)."
    $module = Import-Module -Name $manifest.FullName -Force -PassThru
    $splat = @{
        ModuleInfo = $module
        OutputFolder = $OutputFolder
        WithModulePage = $true
        HelpVersion = $module.Version
        Locale = 'fr-FR'
        Encoding = $utf8
    }
    if ($Force) {
        $splat.Force = $true
    }

    # PlatyPS 1.0.3 lit defaultValue sur des paramètres sans valeur par défaut ;
    # StrictMode Latest fait échouer cet accès.
    Set-StrictMode -Off
    try {
        New-MarkdownCommandHelp @splat
    }
    finally {
        Set-StrictMode -Version Latest
    }
}
