# Résolution dynamique FFmpeg — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Découvrir automatiquement sous `RecodeVideo/ffmpeg-*` la build FFmpeg la plus récente dont `ffmpeg -version` est parsable et `≥` la version mini du manifeste, avec message d’erreur actionnable et affichage propre aux points d’entrée.

**Architecture:** Helper privé `Resolve-FFToolsDefaultBase` (cache session + root injectable pour tests) ; `Get-FFmpegPath` / `Get-FfprobePath` gardent override → base locale → PATH → throw ; `Invoke-ReencodeMedia` / `Test-MediaSimilarity` catch → `Write-ErrorLog` → return. Les paramètres `-FFMPEGPath` / `-FFPROBEPath` de Reencode deviennent optionnels (sinon le `ValidateScript` File.Exists court-circuite toujours la découverte).

**Tech Stack:** PowerShell 7+, Pester 5, modules `Tetram.Media.FFmpeg`, `Tetram.Media.Reencode`, `Tetram.Media.Similarity`.

**Spec:** `docs/superpowers/specs/2026-08-13-ffmpeg-dynamic-resolution-design.md`

## Global Constraints

- Version uniquement via sortie `ffmpeg -version` (jamais via le nom de dossier).
- Candidats = dossiers `ffmpeg-*` sous le root de recherche (défaut : `<repo>/RecodeVideo`).
- Binaire sans version parsable → exclu.
- Version mini = `PrivateData.FFToolsMinVersion` du manifeste = `9.0.1`.
- Cache une fois par session module (sentinel séparé pour « déjà résolu » vs « pas encore »).
- Pas de validation hash/signature ; pas de téléchargement.
- Commits fréquents (un par tâche, après tests verts) — règles Superpowers / `writing-plans`.
- Finalisation obligatoire : push PR + babysit Codex (`babysit-protocol` / `codex-mr-review`) — Task 5.
- CI = `ubuntu-latest` : stubs = scripts shell exécutables nommés `ffmpeg` / `ffprobe` (pas `.exe`).

---

## File map

| Fichier | Rôle |
|---|---|
| `Utils/Tetram.Media.FFmpeg.psd1` | `FFToolsMinVersion = '9.0.1'` |
| `Utils/Tetram.Media.FFmpeg.psm1` | Résolution dynamique + message throw |
| `tests/Utils/Tetram.Media.FFmpeg.Tests.ps1` | Remplacer le stub ; fixtures temp |
| `Tetram.Media.Reencode.psm1` | Paths optionnels + catch résolution |
| `Tetram.Media.Similarity.psm1` | Catch sur `Test-MediaSimilarity` |

---

### Task 1: Manifeste — version minimale

**Files:**
- Modify: `Utils/Tetram.Media.FFmpeg.psd1`
- Test: `tests/Utils/Tetram.Media.FFmpeg.Tests.ps1` (créé/étendu ici pour le cas manifeste)

**Interfaces:**
- Produces: `PrivateData.FFToolsMinVersion` = `'9.0.1'` (string)

- [ ] **Step 1: Écrire le test manifeste qui échoue**

Remplacer le contenu de `tests/Utils/Tetram.Media.FFmpeg.Tests.ps1` par :

```powershell
BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'Utils/Tetram.Media.FFmpeg.psd1'
}

Describe 'Tetram.Media.FFmpeg manifest' {
    It 'déclare FFToolsMinVersion = 9.0.1 dans PrivateData' {
        $data = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
        $data.PrivateData.FFToolsMinVersion | Should -Be '9.0.1'
    }
}
```

- [ ] **Step 2: Exécuter le test — doit échouer**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Utils/Tetram.Media.FFmpeg.Tests.ps1' -Output Detailed"`  
Expected: FAIL — `FFToolsMinVersion` absent / `$null`

- [ ] **Step 3: Ajouter la clé au manifeste**

Dans `Utils/Tetram.Media.FFmpeg.psd1`, remplacer le bloc `PrivateData` par :

```powershell
    PrivateData = @{
        FFToolsMinVersion = '9.0.1'
        PSData = @{
            Tags = @(
                'ffmpeg',
                'media',
                'hash',
                'ps7'
            )
        }
    }
```

- [ ] **Step 4: Rejouer le test — doit passer**

Run: idem Step 2  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Utils/Tetram.Media.FFmpeg.psd1 tests/Utils/Tetram.Media.FFmpeg.Tests.ps1
git commit -m "$(cat <<'EOF'
feat(ffmpeg): déclarer FFToolsMinVersion 9.0.1 dans le manifeste

EOF
)"
```

---

### Task 2: Résolution dynamique + getters (TDD)

**Files:**
- Modify: `Utils/Tetram.Media.FFmpeg.psm1`
- Modify: `tests/Utils/Tetram.Media.FFmpeg.Tests.ps1`

**Interfaces:**
- Consumes: `PrivateData.FFToolsMinVersion`
- Produces (privés, accessibles via `InModuleScope 'Tetram.Media.FFmpeg'`) :
  - `$script:FFToolsSearchRoot` — `[string]`, défaut `Join-Path (Split-Path -Parent $PSScriptRoot) 'RecodeVideo'`
  - `$script:FFToolsDefaultBase` — `[string]` ou `$null`
  - `$script:FFToolsBaseResolved` — `[bool]`, défaut `$false`
  - `Resolve-FFToolsDefaultBase` → `[string]` ou `$null`
  - `Get-FFToolsMinVersion` → `[version]`
  - `Get-FFmpegVersionFromBinary -LiteralPath <string>` → `[version]` ou `$null`
- Produces (publics, inchangés en signature) :
  - `Get-FFmpegPath [[string]$OverridePath]` → `[string]` ou throw
  - `Get-FfprobePath [[string]$OverridePath]` → `[string]` ou throw

- [ ] **Step 1: Helper de fixtures de test + tests qui échouent**

Ajouter à `tests/Utils/Tetram.Media.FFmpeg.Tests.ps1` (après le Describe manifeste) :

```powershell
BeforeAll {
    Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.FFmpeg' -Force -ErrorAction SilentlyContinue
}

function script:New-FakeFFBuild {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FolderName,
        [string]$VersionText, # $null = script qui n'imprime pas de version
        [switch]$OmitBinary
    )
    $bin = Join-Path $Root $FolderName 'bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    if ($OmitBinary) { return }
    $ffmpegName = if ($IsWindows) { 'ffmpeg.exe' } else { 'ffmpeg' }
    $ffprobeName = if ($IsWindows) { 'ffprobe.exe' } else { 'ffprobe' }
    $ffmpegPath = Join-Path $bin $ffmpegName
    $ffprobePath = Join-Path $bin $ffprobeName
    if ($IsWindows) {
        # Stubs .cmd invoqués via cmd ; on crée des .bat renommés ne marchent pas comme .exe.
        # Sur Windows local : utiliser un shim .exe via PowerShell scriptblock injection —
        # la CI est Linux ; pour Windows, les tests s'appuient sur $script:FFToolsVersionReader.
        Set-Content -LiteralPath $ffmpegPath -Value '' -Encoding Byte
        Set-Content -LiteralPath $ffprobePath -Value '' -Encoding Byte
    }
    else {
        $body = if ($VersionText) {
            "#!/bin/sh`necho 'ffmpeg version $VersionText-full_build-www.gyan.dev Copyright (c) 2000-2026'`n"
        }
        else {
            "#!/bin/sh`necho 'not a version line'`n"
        }
        Set-Content -LiteralPath $ffmpegPath -Value $body -NoNewline
        Set-Content -LiteralPath $ffprobePath -Value $body -NoNewline
        & chmod +x $ffmpegPath $ffprobePath
    }
}

Describe 'Resolve-FFToolsDefaultBase' {
    BeforeEach {
        $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ("fftools-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        InModuleScope 'Tetram.Media.FFmpeg' {
            $script:FFToolsSearchRoot = $TestRoot
            $script:FFToolsDefaultBase = $null
            $script:FFToolsBaseResolved = $false
            $script:FFToolsVersionReader = $null
        }
    }
    AfterEach {
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'sélectionne la plus haute version >= min' {
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-8.0.1-full_build' -VersionText '8.0.1'
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-9.0.1-full_build' -VersionText '9.0.1'
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-9.1.0-full_build' -VersionText '9.1.0'
        if ($IsWindows) {
            InModuleScope 'Tetram.Media.FFmpeg' {
                $script:FFToolsVersionReader = {
                    param($LiteralPath)
                    if ($LiteralPath -match '9\.1\.0') { return [version]'9.1.0' }
                    if ($LiteralPath -match '9\.0\.1') { return [version]'9.0.1' }
                    if ($LiteralPath -match '8\.0\.1') { return [version]'8.0.1' }
                    return $null
                }
            }
        }
        $base = InModuleScope 'Tetram.Media.FFmpeg' { Resolve-FFToolsDefaultBase }
        $base | Should -Match 'ffmpeg-9\.1\.0-full_build[\\/]bin$'
    }

    It 'ignore une version < min' {
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-8.0.1-full_build' -VersionText '8.0.1'
        if ($IsWindows) {
            InModuleScope 'Tetram.Media.FFmpeg' {
                $script:FFToolsVersionReader = { param($LiteralPath) [version]'8.0.1' }
            }
        }
        $base = InModuleScope 'Tetram.Media.FFmpeg' { Resolve-FFToolsDefaultBase }
        $base | Should -BeNullOrEmpty
    }

    It 'ignore un binaire sans version parsable' {
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-bogus-full_build' -VersionText $null
        if ($IsWindows) {
            InModuleScope 'Tetram.Media.FFmpeg' {
                $script:FFToolsVersionReader = { param($LiteralPath) $null }
            }
        }
        $base = InModuleScope 'Tetram.Media.FFmpeg' { Resolve-FFToolsDefaultBase }
        $base | Should -BeNullOrEmpty
    }

    It 'Get-FFmpegPath et Get-FfprobePath partagent le même bin' {
        New-FakeFFBuild -Root $script:TestRoot -FolderName 'ffmpeg-9.0.1-full_build' -VersionText '9.0.1'
        if ($IsWindows) {
            InModuleScope 'Tetram.Media.FFmpeg' {
                $script:FFToolsVersionReader = { param($LiteralPath) [version]'9.0.1' }
            }
        }
        InModuleScope 'Tetram.Media.FFmpeg' {
            $ff = Get-FFmpegPath
            $fp = Get-FfprobePath
            [IO.Path]::GetDirectoryName($ff) | Should -Be ([IO.Path]::GetDirectoryName($fp))
        }
    }

    It 'Get-FFmpegPath -OverridePath retourne override sans scan' {
        $fake = Join-Path $script:TestRoot 'custom-ffmpeg'
        Set-Content -LiteralPath $fake -Value 'x'
        InModuleScope 'Tetram.Media.FFmpeg' -Parameters @{ Fake = $fake } {
            param($Fake)
            Get-FFmpegPath -OverridePath $Fake | Should -Be $Fake
            $script:FFToolsBaseResolved | Should -BeFalse
        }
    }

    It 'throw un message actionnable si rien trouvé' {
        Mock -ModuleName Tetram.Media.FFmpeg Get-Command { $null } -ParameterFilter { $Name -eq 'ffmpeg' }
        InModuleScope 'Tetram.Media.FFmpeg' {
            $script:FFToolsSearchRoot = Join-Path ([IO.Path]::GetTempPath()) ('empty-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:FFToolsSearchRoot -Force | Out-Null
            $script:FFToolsBaseResolved = $false
            $script:FFToolsDefaultBase = $null
            { Get-FFmpegPath } | Should -Throw -ExpectedMessage '*9.0.1*'
            { Get-FFmpegPath } | Should -Throw -ExpectedMessage '*RecodeVideo*'
        }
    }
}
```

Si `InModuleScope -Parameters` n’est pas supporté par la version Pester du repo, utiliser une variable `$script:FakeOverride` lue depuis `InModuleScope`.

- [ ] **Step 2: Exécuter les tests — doivent échouer**

Run: `pwsh -NoProfile -File build/Invoke-Tests.ps1`  
(ou Pester ciblé sur ce fichier)  
Expected: FAIL — `Resolve-FFToolsDefaultBase` introuvable / ancien chemin figé

- [ ] **Step 3: Implémenter `Utils/Tetram.Media.FFmpeg.psm1`**

Remplacer le début du module (jusqu’à la fin de `Get-FfprobePath`) par la logique suivante (garder `Invoke-FFmpeg` et `Get-MediaFastHash` inchangés sauf message throw de `Invoke-FFmpeg` qui doit appeler `Get-FFmpegPath` comme aujourd’hui) :

```powershell
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
    $min = Get-FFToolsMinVersion
    $bestVer = $null
    $bestBin = $null

    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'ffmpeg-*' } |
        ForEach-Object {
            $candidate = Join-Path $_.FullName 'bin' $exeName
            if (-not (Test-Path -LiteralPath $candidate)) { return }
            $ver = Get-FFmpegVersionFromBinary -LiteralPath $candidate
            if ($null -eq $ver) { return }
            if ($ver -lt $min) { return }
            if ($null -eq $bestVer -or $ver -gt $bestVer)
            {
                $bestVer = $ver
                $bestBin = Split-Path -Parent $candidate
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
    return "$ToolName introuvable : placez une build officielle >= $min sous '$root\ffmpeg-<version>-...\bin\', ou fournissez -OverridePath / PATH."
}

function Get-FFmpegPath
{
    param([string]$OverridePath)

    if (-not [string]::IsNullOrWhiteSpace($OverridePath) -and (Test-Path -LiteralPath $OverridePath))
    {
        return $OverridePath
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

    if (-not [string]::IsNullOrWhiteSpace($OverridePath) -and (Test-Path -LiteralPath $OverridePath))
    {
        return $OverridePath
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
```

Notes d’implémentation :
- Dans le `ForEach-Object`, utiliser `return` pour passer au suivant (équivalent `continue` en scriptblock pipeline).
- `Join-Path` à 3 arguments nécessite PS7 (OK).
- Ne **pas** exporter les helpers privés.

- [ ] **Step 4: Rejouer les tests FFmpeg**

Run: `pwsh -NoProfile -File build/Invoke-Tests.ps1`  
Expected: tous les tests `Tetram.Media.FFmpeg*` PASS (les autres suites inchangées PASS)

- [ ] **Step 5: Commit**

```bash
git add Utils/Tetram.Media.FFmpeg.psm1 tests/Utils/Tetram.Media.FFmpeg.Tests.ps1
git commit -m "$(cat <<'EOF'
feat(ffmpeg): résoudre dynamiquement la build RecodeVideo la plus récente

EOF
)"
```

---

### Task 3: `Invoke-ReencodeMedia` — paths optionnels + catch propre

**Files:**
- Modify: `Tetram.Media.Reencode.psm1` (paramètres ~749–786 et résolution)

**Interfaces:**
- Consumes: `Get-FFmpegPath`, `Get-FfprobePath`, `Write-ErrorLog`
- Produces: résolution échouée → `Write-ErrorLog` + `return` (pas de rethrow)

- [ ] **Step 1: Assouplir les paramètres outils**

Sur `-FFMPEGPath` et `-FFPROBEPath` :
- Retirer `ValidateScript({ [System.IO.File]::Exists($_) } …)` (il empêche la découverte RecodeVideo).
- Défaut = `''` (chaîne vide), plus de `Join-Path $FFToolsBase …`.
- Garder `-FFToolsBase` pour compatibilité d’appel, mais il ne sert plus à construire les chemins outils (peut rester documenté comme obsolète pour les outils, sans suppression dans ce plan).

Exemple :

```powershell
        [string] $FFMPEGPath = '',

        ...
        [string] $FFPROBEPath = '',
```

- [ ] **Step 2: Catch autour de la résolution**

Remplacer le bloc :

```powershell
    $resolvedFFmpegPath = Get-FFmpegPath -OverridePath $FFMPEGPath
    $resolvedFFprobePath = Get-FfprobePath -OverridePath $FFPROBEPath
```

par :

```powershell
    try
    {
        $resolvedFFmpegPath = Get-FFmpegPath -OverridePath $FFMPEGPath
        $resolvedFFprobePath = Get-FfprobePath -OverridePath $FFPROBEPath
    }
    catch
    {
        Write-ErrorLog $_.Exception.Message
        return
    }
```

- [ ] **Step 3: Vérifier manuellement le message (smoke)**

Run (depuis la racine repo, sans stub PATH ffmpeg si possible) :

```powershell
Import-Module .\Tetram.Media.Reencode.psd1 -Force
# Forcer l’échec : pointer temporairement le search root vide via InModuleScope si besoin,
# ou renommer RecodeVideo le temps du test local.
Invoke-ReencodeMedia -Path . -CheckOnly
```

Expected: une ligne `Error: …` via `Write-ErrorLog` contenant `9.0.1` et `RecodeVideo`, **pas** de stack trace non gérée ; la fonction revient.

Si RecodeVideo local a déjà 9.0.1, valider plutôt le happy path : `Get-FFmpegPath` (via module FFmpeg) pointe vers `ffmpeg-9.0.1-full_build\bin`.

- [ ] **Step 4: Suite Pester complète**

Run: `pwsh -NoProfile -File build/Invoke-Tests.ps1`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Reencode.psm1
git commit -m "$(cat <<'EOF'
fix(reencode): paths FFmpeg optionnels et erreur de résolution propre

EOF
)"
```

---

### Task 4: `Test-MediaSimilarity` — catch propre

**Files:**
- Modify: `Tetram.Media.Similarity.psm1` (`Test-MediaSimilarity`)

**Interfaces:**
- Consumes: `Get-FFmpegPath` / `Invoke-FFmpeg` (indirect), `Write-ErrorLog`
- Produces: échec résolution → `Write-ErrorLog` + return sans rethrow

- [ ] **Step 1: Envelopper le `process` / appels FFmpeg**

Dans `Test-MediaSimilarity`, envelopper le corps de `process` (et éventuellement le premier usage FFmpeg) :

```powershell
    process {
        try
        {
            $files = Get-ChildItem -Path (Resolve-Path $Path) -Include $InputMasks -Recurse:$Recurse | Where-Object { -not $_.PSIsContainer }
            $registry = @(Sync-SignatureRegistry -Files $files)

            if ($UpdateOnly -or $registry.Count -lt 2)
            {
                $results = @(); return
            }
            $results = @(Invoke-SimilarityAnalysis -Registry $registry -Threshold $ConfidenceThreshold)
        }
        catch
        {
            Write-ErrorLog $_.Exception.Message
            $results = @()
            return
        }
    }
```

S’assurer que `Tetram.Media.Similarity` a bien accès à `Write-ErrorLog` (via NestedModules / import existant de `Tetram.Common` — vérifier `Tetram.Media.Similarity.psd1` et ajouter NestedModules `.\Utils\Tetram.Common` + `.\Utils\Tetram.Media.FFmpeg` si manquants).

- [ ] **Step 2: Lire et aligner le manifeste Similarity si besoin**

Fichier : `Tetram.Media.Similarity.psd1`  
Si `NestedModules` n’inclut pas Common/FFmpeg, les ajouter comme dans Reencode.

- [ ] **Step 3: Suite Pester**

Run: `pwsh -NoProfile -File build/Invoke-Tests.ps1`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Tetram.Media.Similarity.psm1 Tetram.Media.Similarity.psd1
git commit -m "$(cat <<'EOF'
fix(similarity): afficher proprement l'absence de FFmpeg utilisable

EOF
)"
```

(Si le `.psd1` n’a pas changé, l’omettre du `git add`.)

---

### Task 5: Finalisation — PR + babysit Codex

**Prérequis :** tasks 1–4 terminées, suite Pester verte, branche à jour.

**Règles à appliquer :**
- Template PR GitHub (`github-pr-template.mdc`) — titre Conventional Commits, test plan en **commentaire séparé**
- `babysit-protocol.mdc` + `codex-mr-review.mdc` : un commentaire non résolu à la fois, contre-analyse, décision utilisateur, puis GitHub (réponse + resolve + 👍/👎) ; un seul `git push` en fin de tour de corrections
- Ne pas poser 👍 à la place de Codex sur la description ; attendre `+1` de `chatgpt-codex-connector[bot]`
- **Ne jamais merger la PR** (`gh pr merge`, squash, auto-merge, etc.) — le merge reste **exclusivement** le rôle de l’utilisateur

**Note :** le menu multi-options de `finishing-a-development-branch` est **court-circuité** — la finalisation est fixée à « Push + PR + babysit Codex ».

- [ ] **Step 1: Vérifier les tests une dernière fois**

Run: `pwsh -NoProfile -File build/Invoke-Tests.ps1`  
Expected: PASS

- [ ] **Step 2: Inclure docs spec/plan si pas encore commités**

```bash
git add docs/superpowers/specs/2026-08-13-ffmpeg-dynamic-resolution-design.md \
        docs/superpowers/plans/2026-08-13-ffmpeg-dynamic-resolution.md
git status
# Si des changements restent : commit dédié
git commit -m "$(cat <<'EOF'
docs: spec et plan résolution dynamique FFmpeg

EOF
)"
```

(Sauter le commit s’il n’y a rien à ajouter.)

- [ ] **Step 3: Pousser la branche et créer la PR**

```bash
git push -u origin HEAD
gh pr create --title "feat(ffmpeg): résolution dynamique de la build RecodeVideo" --body "$(cat <<'EOF'
## Description

Remplace le chemin FFmpeg figé par une découverte automatique de la build la plus récente sous RecodeVideo (version via ffmpeg -version, seuil mini 9.0.1 dans le manifeste). Les points d'entrée Reencode/Similarity affichent une erreur propre via Write-ErrorLog.

## Portée

- Fonctionnalités impactées : Tetram.Media.FFmpeg, Invoke-ReencodeMedia, Test-MediaSimilarity
- Comportements modifiés : sélection dynamique ; chemins -FFMPEGPath/-FFPROBEPath optionnels ; throw actionnable si aucune build utilisable ni PATH
- Points d'attention pour la revue : injection de test FFToolsSearchRoot / FFToolsVersionReader ; pas de validation hash

EOF
)"
```

- [ ] **Step 4: Commentaire test plan (séparé)**

Publier un commentaire PR avec le test plan (cases cochables : Pester local, smoke résolution, CI).

- [ ] **Step 5: Babysit Codex**

1. Attendre la réaction 👀 (`eyes`) sur la description (~jusqu’à ~1 min).
2. Attendre la conclusion Codex (👍/`+1` sans points, ou liste de points).
3. Si points : traiter **un fil non résolu à la fois** selon babysit (analyse → verdict → décision user → action GitHub) ; push unique en fin de tour ; résoudre le fil conclusion ; boucler jusqu’à validation Codex.

- [ ] **Step 6: Rapport final**

Communiquer l’URL de la PR, l’état Codex (👍 ou points restants), et l’état CI.  
**Stop** : ne pas merger ; indiquer que la PR est prête (ou non) pour merge manuel par l’utilisateur.

---

## Self-review (plan vs spec)

| Exigence spec | Task |
|---|---|
| Scan `ffmpeg-*`, version via `-version` only | Task 2 |
| Exclure non parsable / `<` min | Task 2 |
| Min version dans `.psd1` PrivateData | Task 1 |
| Cache session | Task 2 (`FFToolsBaseResolved`) |
| Même bin ffmpeg/ffprobe | Task 2 |
| throw message actionnable | Task 2 |
| Catch + Write-ErrorLog aux entrées | Tasks 3–4 |
| Tests fixtures / injection root | Task 2 (`FFToolsSearchRoot`, `FFToolsVersionReader`) |
| Hors scope hash/web | Respecté (rien ajouté) |
| Fix ValidateScript qui bloquait la découverte | Task 3 (nécessaire pour honorer la spec côté Reencode) |
| Commit par tâche | Steps Commit des tasks 1–4 |
| Finalisation PR + babysit Codex | Task 5 |
