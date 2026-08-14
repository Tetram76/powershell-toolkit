#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $MarkdownRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $MarkdownRoot) {
    $MarkdownRoot = Join-Path $repoRoot 'docs\help'
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

$utf8 = [System.Text.UTF8Encoding]::new($false)
$updated = 0
$skipped = 0

foreach ($manifest in $manifests) {
    $moduleHelpDir = Join-Path $MarkdownRoot $manifest.BaseName
    if (-not (Test-Path -LiteralPath $moduleHelpDir)) {
        Write-Warning "Pas de markdown pour $($manifest.BaseName) — ignoré (utiliser build\New-HelpMarkdown.ps1)."
        $skipped++
        continue
    }

    Write-Verbose "Mise à jour markdown $($manifest.BaseName) depuis le code chargé."
    $module = Import-Module -Name $manifest.FullName -Force -PassThru

    Set-StrictMode -Off
    try {
        $measured = Measure-PlatyPSMarkdown -Path (Join-Path $moduleHelpDir '*.md')
        $commandFiles = @($measured | Where-Object { $_.Filetype -match 'CommandHelp' })
        if ($commandFiles.Count -eq 0) {
            Write-Warning "Aucun fichier CommandHelp dans $moduleHelpDir — ignoré."
            $skipped++
            continue
        }

        # Git versionne docs/help : les .bak PlatyPS seraient du bruit dans le dépôt.
        $commandFiles |
            Update-MarkdownCommandHelp -Path { $_.FilePath } -NoBackup

        $documented = @(
            $commandFiles |
                ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.FilePath) }
        )
        $missing = @(
            $module.ExportedCommands.Keys |
                Where-Object { $_ -notin $documented }
        )
        if ($missing.Count -gt 0) {
            Write-Verbose "Nouvelles commandes sans markdown : $($missing -join ', ')."
            $newSplat = @{
                CommandInfo = @(Get-Command -Name $missing -Module $module.Name)
                OutputFolder = $MarkdownRoot
                HelpVersion = $module.Version
                Locale = 'fr-FR'
                Encoding = $utf8
            }
            New-MarkdownCommandHelp @newSplat
        }

        $modulePage = Join-Path $moduleHelpDir "$($manifest.BaseName).md"
        if (Test-Path -LiteralPath $modulePage) {
            $measuredAfter = Measure-PlatyPSMarkdown -Path (Join-Path $moduleHelpDir '*.md')
            $commandFilesAfter = @($measuredAfter | Where-Object { $_.Filetype -match 'CommandHelp' })
            # -Force : Update-MarkdownModuleFile refuse d'écrire une page déjà présente.
            $commandFilesAfter |
                Import-MarkdownCommandHelp -Path { $_.FilePath } |
                Update-MarkdownModuleFile -Path $modulePage -NoBackup -Force -Encoding $utf8
        }

        $updated++
    }
    finally {
        Set-StrictMode -Version Latest
    }
}

if ($updated -eq 0) {
    throw "Aucun module markdown mis à jour dans $MarkdownRoot."
}

Write-Verbose "Modules mis à jour : $updated ; ignorés : $skipped."
