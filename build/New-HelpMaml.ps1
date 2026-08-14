#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $MarkdownRoot,

    [string] $OutputFolder,

    [string] $Locale = 'fr-FR',

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $MarkdownRoot) {
    $MarkdownRoot = Join-Path $repoRoot 'docs\help'
}
if (-not $OutputFolder) {
    # Get-Help cherche <dossier-du-psd1>\<culture>\*-Help.xml ; les modules racine partagent donc ce dossier.
    $OutputFolder = Join-Path $repoRoot $Locale
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

if (-not (Test-Path -LiteralPath $MarkdownRoot)) {
    throw "Dossier markdown introuvable : $MarkdownRoot. Lancer d'abord build\New-HelpMarkdown.ps1."
}

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

$utf8 = [System.Text.UTF8Encoding]::new($false)
$exported = @()

foreach ($manifest in $manifests) {
    $moduleHelpDir = Join-Path $MarkdownRoot $manifest.BaseName
    if (-not (Test-Path -LiteralPath $moduleHelpDir)) {
        Write-Warning "Pas de markdown pour $($manifest.BaseName) dans $moduleHelpDir — ignoré."
        continue
    }

    Write-Verbose "Export MAML $($manifest.BaseName) -> $OutputFolder"

    # PlatyPS 1.0.3 : accès à des propriétés optionnelles sous StrictMode Latest.
    Set-StrictMode -Off
    try {
        $measured = Measure-PlatyPSMarkdown -Path (Join-Path $moduleHelpDir '*.md')
        $commandFiles = @($measured | Where-Object { $_.Filetype -match 'CommandHelp' })
        if ($commandFiles.Count -eq 0) {
            Write-Warning "Aucun fichier CommandHelp dans $moduleHelpDir — ignoré."
            continue
        }

        $splat = @{
            OutputFolder = $OutputFolder
            Encoding = $utf8
        }
        if ($Force) {
            $splat.Force = $true
        }

        $commandFiles |
            Import-MarkdownCommandHelp -Path { $_.FilePath } |
            Export-MamlCommandHelp @splat |
            ForEach-Object { $exported += $_ }
    }
    finally {
        Set-StrictMode -Version Latest
    }
}

if ($exported.Count -eq 0) {
    throw "Aucun fichier MAML généré depuis $MarkdownRoot."
}

# PlatyPS écrit <culture>\<Module>\<Module>-Help.xml ; Get-Help n'ouvre que
# <dossier-du-psd1>\<culture>\<Module>-Help.xml.
$xmlFiles = @(
    Get-ChildItem -LiteralPath $OutputFolder -Recurse -Filter '*-Help.xml' -File
)
foreach ($xml in $xmlFiles) {
    $dest = Join-Path $OutputFolder $xml.Name
    if ($xml.FullName -ne $dest) {
        Move-Item -LiteralPath $xml.FullName -Destination $dest -Force
        $subdir = Split-Path -Parent $xml.FullName
        $leftovers = @(Get-ChildItem -LiteralPath $subdir -Force)
        if ($subdir -ne $OutputFolder -and $leftovers.Count -eq 0) {
            Remove-Item -LiteralPath $subdir -Force
        }
    }
}

. (Join-Path $PSScriptRoot 'Repair-MamlExampleCode.ps1')
$writerSettings = [System.Xml.XmlWriterSettings]::new()
$writerSettings.Encoding = $utf8
$writerSettings.Indent = $true
Get-ChildItem -LiteralPath $OutputFolder -Filter '*-Help.xml' -File | ForEach-Object {
    $doc = [xml](Get-Content -LiteralPath $_.FullName -Raw)
    Repair-MamlExampleCode -Document $doc
    $writer = [System.Xml.XmlWriter]::Create($_.FullName, $writerSettings)
    try {
        $doc.Save($writer)
    }
    finally {
        $writer.Dispose()
    }
}

Get-ChildItem -LiteralPath $OutputFolder -Filter '*-Help.xml' -File
