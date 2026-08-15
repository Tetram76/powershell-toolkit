# Tetram.Media.Whisper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer le module `Tetram.Media.Whisper` et sa commande `Get-MediaTranscript`, qui pilote
`faster-whisper-xxl.exe` pour produire des transcripts à côté des fichiers source.

**Architecture:** Un manifeste + un `psm1` portant la seule commande publique, et un `Private/Whisper.ps1`
dot-sourcé contenant quatre unités testables : résolution du binaire, traduction des sources, construction
des arguments, invocation. La commande ne valide aucun chemin et n'émet rien dans le pipeline : elle
construit une ligne de commande, l'affiche, la lance une seule fois pour tout le lot.

**Tech Stack:** PowerShell 7+ (Core), Pester 5, PSScriptAnalyzer, Microsoft.PowerShell.PlatyPS,
binaire Purfview Standalone Faster-Whisper r245.4.

**Spec de référence :** `docs/superpowers/specs/2026-08-15-media-whisper-design.md`

## Global Constraints

- **Pas de worktree isolé.** L'implémentation se fait directement dans le dossier de travail
`d:\GIT\Scripts`, sur la branche créée en Task 1. Si la skill d'exécution
(`superpowers:subagent-driven-development`, `superpowers:executing-plans`) réclame un worktree via
`superpowers:using-git-worktrees`, cette étape est **sautée** : l'utilisateur suit l'implémentation en
direct dans son dossier de travail.
- Cible : `PowerShellVersion = '7.0'`, `CompatiblePSEditions = @('Core')`.
- `Set-StrictMode -Version 3.0` en tête du `psm1` et de `Private/Whisper.ps1`.
- Aucun commit sur `main` : tout le travail se fait sur la branche créée en Task 1.
- Tous les affichages console passent par `Tetram.Common` : `Write-ErrorLog -Text`,
  `Write-InfoLog -Text -Force`, `Write-DebugLog -Text`, `Show-CommandLine -Exe -Arguments`.
- `Tetram.Common` est étendu par la Task 5 avec quatre utilitaires de chemin génériques. Le code qui y est
  ajouté suit le style d'accolades Allman de ce fichier ; le nouveau module suit le K&R de
  `Tetram.Media.Streams`, le plus récent du dépôt.
- Aucune exception ne remonte à l'appelant depuis `Get-MediaTranscript` : `Write-ErrorLog` puis `return`.
- Aucune validation d'existence de chemin : déléguée à whisper.
- Aucun paramètre n'accepte le pipeline.
- La sortie du binaire n'est jamais capturée ni redirigée : la barre de progression doit s'afficher
directement sur la console.
- Ordre des arguments du binaire, stable et vérifié par les tests : `<source1>` [sources…],
`--batch_recursive`, `--output_dir source`, `--output_format <formats>`, `--check_files`,
`--model <modèle>`, `--ff_track 1`, `[--language <code>]`, `--postfix`, `--print_progress`,
`--task transcribe`. Pas de préfixe `file_list=` : chaque source est un argument nu.
- `ValidateSet` de `-Format` : `json`, `lrc`, `txt`, `text`, `vtt`, `srt`, `tsv`, `all` — défaut `@('srt')`.
- `ValidateSet` de `-Model` : `large-v2` (défaut), `large-v3-turbo`, `large-v3`.
- Tests réels du binaire uniquement sous le tag Pester `Integration`, exclu du CI.
- Les tests unitaires n'appellent jamais le binaire.

---

## File Structure


| Chemin                                                      | Responsabilité                                             |
| ----------------------------------------------------------- | ---------------------------------------------------------- |
| `Tetram.Common/Tetram.Common.psm1`                          | **+** les quatre utilitaires de chemin génériques          |
| `Tetram.Common/Tetram.Common.psd1`                          | **+** leurs exports, version portée à 1.2.0                |
| `tests/Tetram.Common/Tetram.Common.Tests.ps1`               | **+** leurs tests                                          |
| `docs/help/Tetram.Common/*.md`                              | **+** leurs pages d'aide                                   |
| `Tetram.Media.Whisper/Tetram.Media.Whisper.psd1`            | Manifeste : identité, cible PS 7 Core, export unique       |
| `Tetram.Media.Whisper/Tetram.Media.Whisper.psm1`            | Commande publique `Get-MediaTranscript` + orchestration    |
| `Tetram.Media.Whisper/Private/Whisper.ps1`                  | Les quatre unités privées propres au pilotage du binaire   |
| `Tetram.Media.Whisper/Purfview-Whisper-Faster/.keep`        | Marqueur du dossier d'accueil du binaire                   |
| `Tetram.Media.Whisper/fr-FR/Tetram.Media.Whisper-Help.xml`  | MAML généré                                                |
| `docs/help/Tetram.Media.Whisper/*.md`                       | Sources PlatyPS de l'aide                                  |
| `tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1` | Manifeste, exports, binding, orchestration                 |
| `tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1`      | Unités privées, sans binaire                               |


**Trois écarts assumés par rapport à la spec, tous sans effet sur le comportement observable :**

1. La spec nomme trois helpers privés (`Get-WhisperPath`, `Get-WhisperArguments`, `Invoke-Whisper`) mais
   décrit à l'étape 2 de son flux une traduction des sources sans lui donner de nom. Ce plan la nomme
   `Resolve-WhisperSource`.
2. La spec posait que `Tetram.Common` ne serait pas modifié. Ce n'est plus vrai : les quatre conversions de
   chemin que `Resolve-WhisperSource` utilise ne connaissent rien à whisper — développement de `~`,
   absolutisation, échappement glob des crochets, détection de syntaxe PowerShell — et sont promues dans
   `Tetram.Common` sous des noms génériques et exportés. Seule la **politique** (masque transmis tel quel,
   crochets résolus, `-LiteralPath` jamais résolu) reste dans le module, parce qu'elle découle d'une
   propriété de whisper : il globalise lui-même.
3. `Invoke-Whisper` ne **retourne** pas le résultat de l'exécution : il le dépose dans une hashtable
   `-State` fournie par l'appelant. Retourner une valeur obligerait l'appelant à capturer la sortie de la
   fonction, donc celle du binaire, ce qui étoufferait la barre de progression exigée par la spec. C'est
   le schéma `-State` déjà employé par `Invoke-ReencodeMedia`.

---

### Task 1 : Branche, spec, plan et suivi git

**Files:**

- Create: `Tetram.Media.Whisper/Purfview-Whisper-Faster/.keep` (déjà présent sur disque, non suivi)
- Modify: `.gitignore`
- Commit: `docs/superpowers/specs/2026-08-15-media-whisper-design.md`, `docs/superpowers/plans/2026-08-15-media-whisper.md`

**Interfaces:**

- Consumes: rien
- Produces: la branche de travail et la règle d'ignore qui protège le dépôt des ~2 Go de la distribution
Purfview pendant tout le reste du plan.

- [ ] **Step 1: Créer la branche de travail**

```bash
git switch -c feat/media-whisper
```

- [ ] **Step 2: Constater que la distribution Purfview pollue le statut**

Run: `git status --short --untracked-files=all -- Tetram.Media.Whisper`
Expected : des milliers de lignes `??` — c'est le problème que le step suivant corrige.

- [ ] **Step 3: Ajouter la règle d'ignore**

Ajouter à la fin du bloc FFmpeg de `.gitignore` :

```
Tetram.Media.Whisper/Purfview-Whisper-Faster/*
!Tetram.Media.Whisper/Purfview-Whisper-Faster/.keep
```

- [ ] **Step 4: Vérifier que git ne voit plus qu'un seul fichier**

Run: `git status --short --untracked-files=all -- Tetram.Media.Whisper`
Expected : exactement `?? Tetram.Media.Whisper/Purfview-Whisper-Faster/.keep`

- [ ] **Step 5: Commit**

```bash
git add .gitignore Tetram.Media.Whisper/Purfview-Whisper-Faster/.keep docs/superpowers/specs/2026-08-15-media-whisper-design.md docs/superpowers/plans/2026-08-15-media-whisper.md
git commit -m "docs(whisper): spec et plan du module Tetram.Media.Whisper"
```

---

### Task 2 : Smoke test du binaire (chemins nus et crochets)

Cette tâche ne produit pas de code : elle confirme empiriquement deux points **avant** que le reste du
module ne se construise dessus. Décision déjà tranchée : **pas** de préfixe `file_list=` — les sources
sont des arguments nus (fichiers / dossiers / masques).

**Files:**

- Modify (seulement si le smoke test contredit la spec sur les crochets) :
  `docs/superpowers/specs/2026-08-15-media-whisper-design.md`,
  `docs/superpowers/plans/2026-08-15-media-whisper.md`

**Interfaces:**

- Consumes: rien
- Produces: confirmation qu'un chemin nu est accepté comme source, et que la neutralisation
  `[` → `[[]` est nécessaire (ou non). Les tâches 4, 5 et 6 s'appuient sur ce verdict.

- [ ] **Step 1: Préparer un média court**

```powershell
$work = Join-Path $env:TEMP ('whisper-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$purfview = 'D:\GIT\Scripts\Tetram.Media.Whisper\Purfview-Whisper-Faster'
$exe = Join-Path $purfview 'faster-whisper-xxl.exe'
$ffmpeg = Join-Path $purfview 'ffmpeg.exe'
& $ffmpeg -f lavfi -i 'sine=frequency=440:duration=3' -y (Join-Path $work 'sample.wav')
```

- [ ] **Step 2: Tester un chemin nu (sans `file_list=`)**

```powershell
& $exe (Join-Path $work 'sample.wav') --batch_recursive --output_dir source --output_format srt --check_files --model large-v2 --ff_track 1 --postfix --print_progress --task transcribe --beep_off
Get-ChildItem -LiteralPath $work
```

Attendu : le binaire transcrit et un `.srt` apparaît dans `$work`.
Sinon (`Error: Media files were not found.`) : **BLOCKED** — le contrat « arguments nus » est
invalide ; escalader. Rappel : le binaire sort en code `0` même en échec, lire la sortie et non
`$LASTEXITCODE`.

- [ ] **Step 3: Tester la neutralisation des crochets**

```powershell
Copy-Item (Join-Path $work 'sample.wav') (Join-Path $work 'sample[1].wav')
& $exe (Join-Path $work 'sample[[]1].wav') --batch_recursive --output_dir source --output_format srt --check_files --model large-v2 --ff_track 1 --postfix --print_progress --task transcribe --beep_off
Get-ChildItem -LiteralPath $work -Filter 'sample[[]1]*'
```

Attendu si la neutralisation est utile et correcte : un `.srt` apparaît à côté de `sample[1].wav`.

Si rien n'est produit, refaire la commande avec `sample[1].wav` non neutralisé. Si c'est cette forme-là qui
fonctionne, le binaire teste l'existence avant de globaliser : supprimer alors la neutralisation de la spec,
et retirer `ConvertTo-GlobLiteral` (Task 5, dans `Tetram.Common`), ses appels dans `Resolve-WhisperSource`
(Task 6) et ses tests.

- [ ] **Step 4: Nettoyer et commiter le verdict**

```powershell
Remove-Item -LiteralPath $work -Recurse -Force
```

Si la spec ou le plan ont été corrigés (crochets) :

```bash
git add docs/superpowers/specs/2026-08-15-media-whisper-design.md docs/superpowers/plans/2026-08-15-media-whisper.md
git commit -m "docs(whisper): aligner la spec sur le comportement réel du binaire"
```

Sinon, aucun commit : la tâche n'a rien modifié.

---

### Task 3 : Manifeste, module et squelette privé

**Files:**

- Create: `Tetram.Media.Whisper/Tetram.Media.Whisper.psd1`
- Create: `Tetram.Media.Whisper/Tetram.Media.Whisper.psm1`
- Create: `Tetram.Media.Whisper/Private/Whisper.ps1`
- Test: `tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1`

**Interfaces:**

- Consumes: rien
- Produces: `$script:WhisperRoot` (chemin du dossier `Purfview-Whisper-Faster`, lisible par les fonctions
privées), un module importable exportant `Get-MediaTranscript`, et le fichier `Private/Whisper.ps1`
dot-sourcé que les tâches 4 à 7 remplissent.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1` :

```powershell
# Étendre la suite autour du module SUD Tetram.Media.Whisper (pilote faster-whisper-xxl).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Manifeste : Tetram.Media.Whisper/Tetram.Media.Whisper.psd1 — Test-ModuleManifest puis Import-Module -Force
# Privé : mocks -ModuleName Tetram.Media.Whisper sur Get-WhisperPath / Invoke-Whisper / Write-*Log / Show-CommandLine
# Le vrai binaire n'est appelé que sous le tag Integration.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootWhisper = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRootWhisper = Join-Path $script:RepoRootWhisper 'Tetram.Media.Whisper'
    $script:ManifestWhisper = Join-Path $script:ModuleRootWhisper 'Tetram.Media.Whisper.psd1'
}

Describe 'Tetram.Media.Whisper manifest' {
    It 'passe Test-ModuleManifest' {
        { Test-ModuleManifest -Path $script:ManifestWhisper -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'Tetram.Media.Whisper exports' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
    }

    It 'exporte uniquement Get-MediaTranscript' {
        $names = @(Get-Command -Module 'Tetram.Media.Whisper' | Select-Object -ExpandProperty Name | Sort-Object)
        $names | Should -Be @('Get-MediaTranscript')
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper -Output Detailed"`
Expected : FAIL — le manifeste n'existe pas.

- [ ] **Step 3: Écrire le manifeste**

`Tetram.Media.Whisper/Tetram.Media.Whisper.psd1` :

```powershell
@{
    RootModule = 'Tetram.Media.Whisper.psm1'
    ModuleVersion = '1.0.0'
    GUID = '3f5a9c21-6d84-4b17-9e0c-2a7f8d4b6e35'
    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Transcription des pistes audio via le binaire Purfview Standalone Faster-Whisper.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    RequiredModules = @()
    RequiredAssemblies = @()
    NestedModules = @()
    FunctionsToExport = @(
        'Get-MediaTranscript'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('whisper', 'transcription', 'subtitle', 'media', 'ps7')
            ReleaseNotes = @'
- 1.0.0 : Get-MediaTranscript (pilote faster-whisper-xxl, jeux Path/LiteralPath/Mixed, WhatIf).
'@
        }
    }
}
```

- [ ] **Step 4: Écrire le module et le squelette privé**

`Tetram.Media.Whisper/Tetram.Media.Whisper.psm1` :

```powershell
Set-StrictMode -Version 3.0

Import-Module -Name (Join-Path $PSScriptRoot '..' 'Tetram.Common') -Force

# Résolu ici et pas dans Private/Whisper.ps1 : $PSScriptRoot y désignerait le sous-dossier Private.
$script:WhisperRoot = Join-Path $PSScriptRoot 'Purfview-Whisper-Faster'

# Dot-source plutôt que NestedModules : les fonctions de Tetram.Common du scope parent restent visibles.
. (Join-Path $PSScriptRoot 'Private' 'Whisper.ps1')

function Get-MediaTranscript {
    [CmdletBinding()]
    param()
}

Export-ModuleMember -Function Get-MediaTranscript
```

`Tetram.Media.Whisper/Private/Whisper.ps1` :

```powershell
Set-StrictMode -Version 3.0
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper -Output Detailed"`
Expected : PASS, 2 tests.

- [ ] **Step 6: Commit**

```bash
git add Tetram.Media.Whisper/Tetram.Media.Whisper.psd1 Tetram.Media.Whisper/Tetram.Media.Whisper.psm1 Tetram.Media.Whisper/Private/Whisper.ps1 tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1
git commit -m "feat(whisper): squelette du module et manifeste"
```

---

### Task 4 : `Get-WhisperArguments` (construction pure de la ligne de commande)

**Files:**

- Modify: `Tetram.Media.Whisper/Private/Whisper.ps1`
- Test: `tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1`

**Interfaces:**

- Consumes: rien
- Produces: `Get-WhisperArguments -Source <string[]> -Format <string[]> -Model <string> [-UseLanguage <string>]`
  → `[string[]]`. Aucune I/O. Consommée par `Get-MediaTranscript` en Task 9.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1` :

```powershell
# Étendre la suite autour des unités privées de Tetram.Media.Whisper.
#
# Tout passe par InModuleScope 'Tetram.Media.Whisper' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Aucune de ces fonctions n'appelle le binaire.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootWhisper = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootWhisper = Join-Path $script:RepoRootWhisper 'Tetram.Media.Whisper'
    Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
}

# La fonction est pure et déterministe : chaque cas assert la séquence entière plutôt qu'un fragment.
# Aucun paramètre n'est donc fourni sans être couvert, et toute régression d'ordre est vue partout.
Describe 'Get-WhisperArguments' {
    It 'produit la séquence par défaut, dans l''ordre, et sans --language' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\Films\a.mkv') -Format @('srt') -Model 'large-v2'
            $got | Should -Be @(
                'D:\Films\a.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
            )
        }
    }

    It 'passe chaque source comme argument nu, sans préfixe file_list=' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\a.mkv', 'D:\b.mkv', 'D:\c.mkv') -Format @('srt') -Model 'large-v2'
            $got | Should -Be @(
                'D:\a.mkv'
                'D:\b.mkv'
                'D:\c.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
            )
        }
    }

    It 'liste plusieurs formats derrière un seul --output_format' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\a.mkv') -Format @('srt', 'vtt') -Model 'large-v2'
            $got | Should -Be @(
                'D:\a.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt', 'vtt'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
            )
        }
    }

    It 'reprend le modèle demandé' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\a.mkv') -Format @('srt') -Model 'large-v3-turbo'
            $got | Should -Be @(
                'D:\a.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt'
                '--check_files'
                '--model', 'large-v3-turbo'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
            )
        }
    }

    It 'insère --language entre --ff_track et --postfix quand UseLanguage est fourni' {
        InModuleScope 'Tetram.Media.Whisper' {
            $got = Get-WhisperArguments -Source @('D:\a.mkv') -Format @('srt') -Model 'large-v2' -UseLanguage 'fr'
            $got | Should -Be @(
                'D:\a.mkv'
                '--batch_recursive'
                '--output_dir', 'source'
                '--output_format', 'srt'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--language', 'fr'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
            )
        }
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper/Private -Output Detailed"`
Expected : FAIL — `Get-WhisperArguments` n'est pas reconnue.

- [ ] **Step 3: Implémenter**

Ajouter à `Tetram.Media.Whisper/Private/Whisper.ps1` :

```powershell
function Get-WhisperArguments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string[]] $Source,
        [Parameter(Mandatory)] [string[]] $Format,
        [Parameter(Mandatory)] [string] $Model,
        [string] $UseLanguage
    )

    # Chaque source est un argument nu (pas de préfixe file_list=).
    $whisperArgs = @($Source)

    $whisperArgs += @(
        '--batch_recursive'
        '--output_dir', 'source'
        '--output_format'
    )
    $whisperArgs += $Format
    $whisperArgs += @(
        '--check_files'
        '--model', $Model
        '--ff_track', '1'
    )

    if (-not [string]::IsNullOrWhiteSpace($UseLanguage)) {
        $whisperArgs += @('--language', $UseLanguage)
    }

    $whisperArgs += @(
        '--postfix'
        '--print_progress'
        '--task', 'transcribe'
    )

    return $whisperArgs
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper/Private -Output Detailed"`
Expected : PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Whisper/Private/Whisper.ps1 tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1
git commit -m "feat(whisper): construction des arguments faster-whisper"
```

---

### Task 5 : Utilitaires de chemin génériques dans `Tetram.Common`

Ces quatre fonctions ne connaissent rien à whisper : elles traduisent de la syntaxe de chemin PowerShell
vers ce qu'un processus natif qui globalise lui-même sait lire. Elles sont donc exportées par
`Tetram.Common`, sous des noms sans infixe, comme `Show-CommandLine` ou `Format-FileSize`.

**Files:**

- Modify: `Tetram.Common/Tetram.Common.psm1`
- Modify: `Tetram.Common/Tetram.Common.psd1`
- Test: `tests/Tetram.Common/Tetram.Common.Tests.ps1`

**Interfaces:**

- Consumes: rien
- Produces, toutes **exportées** :
  - `Test-PowerShellSpecificPath -Path <string>` → `[bool]` — `$true` si l'entrée emploie de la syntaxe que
    seul PowerShell comprend (crochets, échappement backtick, PSDrive nommé) et doit donc être résolue
    avant d'être remise à un processus natif.
  - `ConvertTo-GlobLiteral -LiteralPath <string>` → `[string]` — échappe les crochets à la convention glob.
  - `ConvertTo-AbsolutePath -Path <string>` → `[string]` — développe `~` puis absolutise, sans exiger que
    le chemin existe.
  - `ConvertTo-AbsoluteMask -Mask <string>` → `[string]` — absolutise le préfixe sans métacaractère d'un
    masque, en conservant le masque intact.
- Toutes sont consommées par `Resolve-WhisperSource` en Task 6.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `tests/Tetram.Common/Tetram.Common.Tests.ps1` :

```powershell
Describe 'Test-PowerShellSpecificPath' {

    It 'reconnaît les crochets et l''échappement backtick' {
        Test-PowerShellSpecificPath -Path 'D:\Films\film[1].mkv' | Should -BeTrue
        Test-PowerShellSpecificPath -Path 'D:\Films\film`*.mkv' | Should -BeTrue
    }

    It 'reconnaît un PSDrive nommé' {
        Test-PowerShellSpecificPath -Path 'Temp:\a.mkv' | Should -BeTrue
    }

    It 'laisse passer un chemin, un masque, une lettre de lecteur ou un UNC' {
        Test-PowerShellSpecificPath -Path 'D:\Films\a.mkv' | Should -BeFalse
        Test-PowerShellSpecificPath -Path 'D:\Films\*.mkv' | Should -BeFalse
        Test-PowerShellSpecificPath -Path '.\a?.mkv' | Should -BeFalse
        Test-PowerShellSpecificPath -Path '\\nas\films\a.mkv' | Should -BeFalse
    }
}

Describe 'ConvertTo-GlobLiteral' {

    It 'échappe les crochets ouvrants' {
        ConvertTo-GlobLiteral -LiteralPath 'D:\Films\film[1].mkv' | Should -Be 'D:\Films\film[[]1].mkv'
    }

    It 'laisse un chemin sans crochet intact' {
        ConvertTo-GlobLiteral -LiteralPath 'D:\Films\a.mkv' | Should -Be 'D:\Films\a.mkv'
    }
}

Describe 'ConvertTo-AbsolutePath' {

    It 'absolutise relativement à l''emplacement PowerShell, sans exiger l''existence' {
        Push-Location -LiteralPath $TestDrive
        try {
            $expected = Join-Path ((Get-Location -PSProvider FileSystem).ProviderPath) 'absent.mkv'
            ConvertTo-AbsolutePath -Path 'absent.mkv' | Should -Be $expected
        }
        finally {
            Pop-Location
        }
    }

    It 'développe ~' {
        ConvertTo-AbsolutePath -Path '~/a.mkv' | Should -Be (Join-Path $HOME 'a.mkv')
    }

    It 'laisse un chemin déjà absolu inchangé' {
        ConvertTo-AbsolutePath -Path 'D:\Films\a.mkv' | Should -Be 'D:\Films\a.mkv'
    }
}

Describe 'ConvertTo-AbsoluteMask' {

    It 'absolutise le préfixe et conserve le masque de feuille' {
        Push-Location -LiteralPath $TestDrive
        try {
            $expected = Join-Path ((Get-Location -PSProvider FileSystem).ProviderPath) '*.mkv'
            ConvertTo-AbsoluteMask -Mask '.\*.mkv' | Should -Be $expected
        }
        finally {
            Pop-Location
        }
    }

    It 'absolutise un masque sans aucun séparateur' {
        Push-Location -LiteralPath $TestDrive
        try {
            $expected = Join-Path ((Get-Location -PSProvider FileSystem).ProviderPath) '*.mkv'
            ConvertTo-AbsoluteMask -Mask '*.mkv' | Should -Be $expected
        }
        finally {
            Pop-Location
        }
    }

    It 'conserve un masque de segment intermédiaire' {
        ConvertTo-AbsoluteMask -Mask 'D:\Films\*\*.mkv' | Should -Be 'D:\Films\*\*.mkv'
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Common -Output Detailed"`
Expected : FAIL — `Test-PowerShellSpecificPath` n'est pas reconnue.

- [ ] **Step 3: Implémenter**

Ajouter à `Tetram.Common/Tetram.Common.psm1`, en style Allman comme le reste du fichier, à la suite de
`Test-IsLikelyPath` :

```powershell
function Test-PowerShellSpecificPath
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    # Les classes de caractères divergent entre PowerShell et le glob des outils natifs ([!a] = négation
    # côté glob, jeu littéral côté PowerShell) : tout crochet impose une résolution PowerShell préalable.
    if ($Path.Contains('[') -or $Path.Contains('`'))
    {
        return $true
    }

    # Qualifier de plus d'une lettre = PSDrive nommé, qu'un processus natif ne sait pas interpréter.
    if ($Path -match '^(?<q>[A-Za-z][^\\/:]*):' -and $Matches['q'].Length -gt 1)
    {
        return $true
    }

    return $false
}

function ConvertTo-GlobLiteral
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $LiteralPath
    )

    return $LiteralPath -replace '\[', '[[]'
}

function ConvertTo-AbsolutePath
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $expanded = $Path
    if ($expanded -eq '~' -or $expanded.StartsWith('~/') -or $expanded.StartsWith('~\'))
    {
        $expanded = Join-Path $HOME $expanded.Substring(1).TrimStart('/', '\')
    }

    # GetFullPath et pas Resolve-Path : le chemin peut ne pas exister. La base est l'emplacement
    # PowerShell, qui ne coïncide pas forcément avec le répertoire de travail du processus — seul connu
    # des exécutables lancés depuis PowerShell.
    $base = (Get-Location -PSProvider FileSystem).ProviderPath
    return [System.IO.Path]::GetFullPath($expanded, $base)
}

function ConvertTo-AbsoluteMask
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Mask
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $prefix = @()
    $rest = @()
    $inRest = $false

    foreach ($segment in ($Mask -split '[\\/]'))
    {
        if (-not $inRest -and $segment -match '[*?]')
        {
            $inRest = $true
        }
        if ($inRest)
        {
            $rest += $segment
        }
        else
        {
            $prefix += $segment
        }
    }

    $prefixPath = $prefix -join $separator
    if ([string]::IsNullOrEmpty($prefixPath))
    {
        $prefixPath = '.'
    }

    return (@((ConvertTo-AbsolutePath -Path $prefixPath)) + $rest) -join $separator
}
```

- [ ] **Step 4: Déclarer les exports et monter la version**

Dans `Tetram.Common/Tetram.Common.psd1`, passer `ModuleVersion` à `'1.2.0'`, ajouter les quatre noms à
`FunctionsToExport` et compléter les notes de version :

```powershell
    ModuleVersion = '1.2.0'
```

```powershell
    FunctionsToExport = @(
        'Show-Colors'
        'Write-Log', 'Write-ErrorLog', 'Write-InfoLog', 'Write-DebugLog'
        'Format-FileSize', 'Format-Duration'
        'Show-CommandLine'
        'Test-PowerShellSpecificPath'
        'ConvertTo-GlobLiteral', 'ConvertTo-AbsolutePath', 'ConvertTo-AbsoluteMask'
    )
```

```powershell
            ReleaseNotes = @'
- 1.1.0 : Renommage des fonctions pour verbes approuvés.
- 1.2.0 : Utilitaires de chemin pour processus natifs (syntaxe PowerShell, glob, absolutisation).
'@
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Common -Output Detailed"`
Expected : PASS, dont les 11 nouveaux cas. Le test « Registers every FunctionsToExport from the manifest »
couvre au passage les quatre nouveaux exports.

- [ ] **Step 6: Vérifier que les autres modules ne cassent pas**

Run: `pwsh -NoProfile -File tools/Invoke-Tests.ps1`
Expected : PASS sur toute la suite du dépôt.

- [ ] **Step 7: Commit**

```bash
git add Tetram.Common/Tetram.Common.psm1 Tetram.Common/Tetram.Common.psd1 tests/Tetram.Common/Tetram.Common.Tests.ps1
git commit -m "feat(common): utilitaires de chemin pour processus natifs"
```

---

### Task 6 : `Resolve-WhisperSource` (politique de transmission des sources)

**Files:**

- Modify: `Tetram.Media.Whisper/Private/Whisper.ps1`
- Test: `tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1`

**Interfaces:**

- Consumes: `Test-PowerShellSpecificPath -Path`, `ConvertTo-GlobLiteral -LiteralPath`,
  `ConvertTo-AbsolutePath -Path`, `ConvertTo-AbsoluteMask -Mask` de `Tetram.Common` (Task 5), visibles
  depuis le module grâce à l'`Import-Module` du `psm1`
- Produces: `Resolve-WhisperSource [-Path <string[]>] [-LiteralPath <string[]>]` → `[string[]]`, consommée
  par `Get-MediaTranscript` en Task 9.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1` :

```powershell
Describe 'Resolve-WhisperSource' {
    It 'transmet un masque tel quel, sans énumérer les fichiers' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            1..3 | ForEach-Object { Set-Content -LiteralPath (Join-Path $Work "f$_.mkv") -Value 'x' }
            $got = @(Resolve-WhisperSource -Path @((Join-Path $Work '*.mkv')))
            $got.Count | Should -Be 1
            $got[0] | Should -Be (Join-Path $Work '*.mkv')
        }
    }

    It 'transmet un dossier tel quel' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'films'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $got = @(Resolve-WhisperSource -Path @($dir))
            $got | Should -Be @($dir)
        }
    }

    It 'transmet un fichier-liste tel quel, sans le lire' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $lst = Join-Path $Work 'lot.lst'
            Set-Content -LiteralPath $lst -Value 'D:\Films\a.mkv'
            $got = @(Resolve-WhisperSource -Path @($lst))
            $got | Should -Be @($lst)
        }
    }

    It 'transmet un chemin inexistant sans erreur' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $missing = Join-Path $Work 'absent.mkv'
            $got = @(Resolve-WhisperSource -Path @($missing))
            $got | Should -Be @($missing)
        }
    }

    It 'résout une entrée à crochets et neutralise les crochets du résultat' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Set-Content -LiteralPath (Join-Path $Work 'film[1].mkv') -Value 'x'
            $got = @(Resolve-WhisperSource -Path @((Join-Path $Work 'film[1].mkv')))
            $got.Count | Should -Be 1
            $got[0] | Should -Be (Join-Path $Work 'film[[]1].mkv')
        }
    }

    It 'ne produit rien pour une entrée à crochets sans correspondance' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $got = @(Resolve-WhisperSource -Path @((Join-Path $Work 'rien[9].mkv')))
            $got.Count | Should -Be 0
        }
    }

    It 'concatène -Path puis -LiteralPath' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $mask = Join-Path $Work '*.mkv'
            $literal = Join-Path $Work 'film[1].mkv'
            $got = @(Resolve-WhisperSource -Path @($mask) -LiteralPath @($literal))
            $got[0] | Should -Be $mask
            $got[1] | Should -Be (Join-Path $Work 'film[[]1].mkv')
        }
    }

    It 'ne résout jamais -LiteralPath, même avec un masque dedans' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $entry = Join-Path $Work '*.mkv'
            $got = @(Resolve-WhisperSource -LiteralPath @($entry))
            $got | Should -Be @($entry)
        }
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper/Private -Output Detailed"`
Expected : FAIL — `Resolve-WhisperSource` n'est pas reconnue.

- [ ] **Step 3: Implémenter**

Ajouter à `Tetram.Media.Whisper/Private/Whisper.ps1` :

```powershell
function Resolve-WhisperSource {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string[]] $Path,
        [string[]] $LiteralPath
    )

    $sources = @()

    foreach ($entry in @($Path)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }

        if (Test-PowerShellSpecificPath -Path $entry) {
            # Une résolution vide ne se rabat pas sur le littéral : ce serait inventer une interprétation
            # que l'appelant n'a pas demandée, et faire signaler par whisper un fichier jamais désigné.
            foreach ($resolved in @(Resolve-Path -Path $entry -ErrorAction SilentlyContinue)) {
                $sources += ConvertTo-GlobLiteral -LiteralPath $resolved.ProviderPath
            }
            continue
        }

        # Masque laissé intact : whisper globalise lui-même, et --check_files ne s'applique qu'à une
        # entrée de type masque ou dossier.
        if ($entry -match '[*?]') {
            $sources += ConvertTo-AbsoluteMask -Mask $entry
            continue
        }

        $sources += ConvertTo-GlobLiteral -LiteralPath (ConvertTo-AbsolutePath -Path $entry)
    }

    foreach ($entry in @($LiteralPath)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $sources += ConvertTo-GlobLiteral -LiteralPath (ConvertTo-AbsolutePath -Path $entry)
    }

    return $sources
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper/Private -Output Detailed"`
Expected : PASS, les 5 tests de Task 4 plus les 8 de `Resolve-WhisperSource`.

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Whisper/Private/Whisper.ps1 tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1
git commit -m "feat(whisper): politique de transmission des sources"
```

---

### Task 7 : `Get-WhisperPath` (résolution du binaire)

**Files:**

- Modify: `Tetram.Media.Whisper/Private/Whisper.ps1`
- Test: `tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1`

**Interfaces:**

- Consumes: `$script:WhisperRoot` défini par le `psm1` en Task 3
- Produces: `Get-WhisperPath [-OverridePath <string>]` → `[string]`, lève une exception si rien n'est
trouvé. Consommée par `Get-MediaTranscript` en Task 9, qui attrape l'exception.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1` :

```powershell
Describe 'Get-WhisperPath' {
    It 'retourne l''override quand c''est un fichier' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $exe = Join-Path $Work 'ailleurs.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            Get-WhisperPath -OverridePath $exe | Should -Be $exe
        }
    }

    It 'rejette un override qui est un dossier' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'dossier-exe'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            { Get-WhisperPath -OverridePath $dir } | Should -Throw '*pas un dossier*'
        }
    }

    It 'rejette un override inexistant' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            { Get-WhisperPath -OverridePath (Join-Path $Work 'absent.exe') } | Should -Throw '*inexistant*'
        }
    }

    It 'prend le binaire du dossier du module quand il existe' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $fakeRoot = Join-Path $Work 'purfview'
            New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
            $exe = Join-Path $fakeRoot 'faster-whisper-xxl.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            $saved = $script:WhisperRoot
            try {
                $script:WhisperRoot = $fakeRoot
                Get-WhisperPath | Should -Be $exe
            }
            finally {
                $script:WhisperRoot = $saved
            }
        }
    }

    It 'échoue avec un message qui indique où poser la distribution' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'faster-whisper-xxl' }
            $saved = $script:WhisperRoot
            try {
                $script:WhisperRoot = Join-Path $Work 'vide'
                { Get-WhisperPath } | Should -Throw '*Purfview*'
            }
            finally {
                $script:WhisperRoot = $saved
            }
        }
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper/Private -Output Detailed"`
Expected : FAIL — `Get-WhisperPath` n'est pas reconnue.

- [ ] **Step 3: Implémenter**

Ajouter à `Tetram.Media.Whisper/Private/Whisper.ps1` :

```powershell
function Get-WhisperPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $OverridePath
    )

    if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
        if (Test-Path -LiteralPath $OverridePath -PathType Leaf) {
            return $OverridePath
        }
        if (Test-Path -LiteralPath $OverridePath) {
            throw "WhisperPath doit désigner un exécutable, pas un dossier : '$OverridePath'"
        }
        throw "WhisperPath inexistant : '$OverridePath'"
    }

    $default = Join-Path $script:WhisperRoot 'faster-whisper-xxl.exe'
    if (Test-Path -LiteralPath $default -PathType Leaf) {
        return $default
    }

    $fromPath = Get-Command -Name 'faster-whisper-xxl' -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    throw "faster-whisper-xxl introuvable : posez la distribution Purfview dans '$script:WhisperRoot', ou fournissez -WhisperPath."
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper/Private -Output Detailed"`
Expected : PASS, 5 nouveaux tests.

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Whisper/Private/Whisper.ps1 tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1
git commit -m "feat(whisper): résolution du binaire faster-whisper-xxl"
```

---

### Task 8 : `Invoke-Whisper` (affichage, ShouldProcess, exécution)

**Files:**

- Modify: `Tetram.Media.Whisper/Private/Whisper.ps1`
- Test: `tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1`

**Interfaces:**

- Consumes: `Show-CommandLine -Exe <string> -Arguments <string[]> -NoPathDetectionParameters <string[]>`
de `Tetram.Common`
- Produces: `Invoke-Whisper -Exe <string> -Arguments <string[]> -Cmdlet <PSCmdlet> -State <hashtable>`.
N'émet rien. Écrit le code de sortie du binaire dans `$State['ExitCode']`, laissé à `$null` si
`ShouldProcess` a refusé (cas `-WhatIf`). Consommée en Task 9.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1` :

```powershell
Describe 'Invoke-Whisper' {
    It 'affiche la ligne de commande avant toute exécution' {
        InModuleScope 'Tetram.Media.Whisper' {
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $false }
            $state = @{}
            Invoke-Whisper -Exe 'binaire-absent-xyz.exe' -Arguments @('a.mkv', '--task', 'transcribe') -Cmdlet $cmdlet -State $state
            Should -Invoke Show-CommandLine -Times 1
        }
    }

    It 'laisse ExitCode à $null et n''exécute rien si ShouldProcess refuse' {
        InModuleScope 'Tetram.Media.Whisper' {
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $false }
            $state = @{}
            Invoke-Whisper -Exe 'binaire-absent-xyz.exe' -Arguments @('a.mkv') -Cmdlet $cmdlet -State $state
            $state['ExitCode'] | Should -BeNullOrEmpty
        }
    }

    It 'relève le code de sortie du binaire' {
        InModuleScope 'Tetram.Media.Whisper' {
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $true }
            $state = @{}
            Invoke-Whisper -Exe (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', 'exit 3') -Cmdlet $cmdlet -State $state
            $state['ExitCode'] | Should -Be 3
        }
    }

    It 'préserve les frontières d''arguments, y compris les chemins à espaces' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $true }
            $helper = Join-Path $Work 'ecrit-args.ps1'
            Set-Content -LiteralPath $helper -Value 'param($Destination, $Contenu) Set-Content -LiteralPath $Destination -Value $Contenu'
            $out = Join-Path $Work 'sortie avec espaces.txt'
            $state = @{}
            Invoke-Whisper -Exe (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', $helper, $out, 'ok') -Cmdlet $cmdlet -State $state
            Get-Content -LiteralPath $out | Should -Be 'ok'
        }
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper/Private -Output Detailed"`
Expected : FAIL — `Invoke-Whisper` n'est pas reconnue.

- [ ] **Step 3: Implémenter**

Ajouter à `Tetram.Media.Whisper/Private/Whisper.ps1` :

```powershell
function Invoke-Whisper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)] [hashtable] $State
    )

    # Résultat déposé dans $State et non retourné : une valeur de retour forcerait l'appelant à capturer
    # la sortie de la fonction, donc celle du binaire, et étoufferait --print_progress.
    $State['ExitCode'] = $null

    # Avant ShouldProcess : sous -WhatIf, la ligne prévue reste visible.
    Show-CommandLine -Exe $Exe -Arguments $Arguments -NoPathDetectionParameters 'output_dir', 'output_format', 'model', 'task', 'language', 'ff_track'

    if (-not $Cmdlet.ShouldProcess($Arguments[0], 'faster-whisper-xxl')) {
        return
    }

    # & + splat, sans redirection : les frontières d'arguments sont conservées et le binaire écrit
    # directement sur la console.
    & $Exe @Arguments
    $State['ExitCode'] = $LASTEXITCODE
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper/Private -Output Detailed"`
Expected : PASS, 4 nouveaux tests.

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Whisper/Private/Whisper.ps1 tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1
git commit -m "feat(whisper): invocation du binaire avec ShouldProcess"
```

---

### Task 9 : `Get-MediaTranscript` (jeux de paramètres et orchestration)

**Files:**

- Modify: `Tetram.Media.Whisper/Tetram.Media.Whisper.psm1`
- Test: `tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1`

**Interfaces:**

- Consumes: `Get-WhisperPath -OverridePath`, `Resolve-WhisperSource -Path -LiteralPath`,
`Get-WhisperArguments -Source -Format -Model -UseLanguage`,
`Invoke-Whisper -Exe -Arguments -Cmdlet -State`
- Produces: la commande publique. N'émet rien dans le pipeline.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1` :

```powershell
Describe 'Get-MediaTranscript binding' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
    }

    It 'refuse un appel sans aucune source' {
        { Get-MediaTranscript -Format srt -ErrorAction Stop } | Should -Throw
    }

    It 'refuse un format hors liste' {
        { Get-MediaTranscript -Path 'a.mkv' -Format 'docx' -ErrorAction Stop } | Should -Throw
    }

    It 'refuse un modèle hors liste' {
        { Get-MediaTranscript -Path 'a.mkv' -Model 'tiny' -ErrorAction Stop } | Should -Throw
    }

    It 'refuse une langue hors liste' {
        { Get-MediaTranscript -Path 'a.mkv' -UseLanguage 'French' -ErrorAction Stop } | Should -Throw
    }

    It 'expose trois jeux de paramètres dont Path par défaut' {
        $meta = Get-Command Get-MediaTranscript
        $meta.DefaultParameterSet | Should -Be 'Path'
        @($meta.ParameterSets | Select-Object -ExpandProperty Name | Sort-Object) | Should -Be @('LiteralPath', 'Mixed', 'Path')
    }

    It 'rend -Path positionnel dans Path et nommé dans Mixed' {
        $meta = Get-Command Get-MediaTranscript
        $inPath = ($meta.ParameterSets | Where-Object Name -EQ 'Path').Parameters | Where-Object Name -EQ 'Path'
        $inMixed = ($meta.ParameterSets | Where-Object Name -EQ 'Mixed').Parameters | Where-Object Name -EQ 'Path'
        $inPath.Position | Should -Be 0
        $inMixed.Position | Should -Be ([int]::MinValue)
    }

    It 'n''accepte aucune entrée pipeline' {
        $meta = Get-Command Get-MediaTranscript
        foreach ($parameter in $meta.Parameters.Values) {
            foreach ($attribute in @($parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })) {
                $attribute.ValueFromPipeline | Should -BeFalse
                $attribute.ValueFromPipelineByPropertyName | Should -BeFalse
            }
        }
    }
}

Describe 'Get-MediaTranscript orchestration' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { 'whisper.exe' }
        Mock -ModuleName Tetram.Media.Whisper Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Whisper Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Whisper Write-DebugLog {}
        Mock -ModuleName Tetram.Media.Whisper Show-CommandLine {}
        $script:SeenArguments = $null
    }

    It 'invoque le binaire une seule fois pour tout le lot' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -Path @('D:\a.mkv', 'D:\b.mkv')
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 1
        $script:SeenArguments[0] | Should -Be 'D:\a.mkv'
        $script:SeenArguments[1] | Should -Be 'D:\b.mkv'
    }

    It 'concatène -Path puis -LiteralPath dans le jeu Mixed' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -Path 'D:\Films\*.mkv' -LiteralPath 'D:\Films\film[1].mkv'
        $script:SeenArguments[0] | Should -Be 'D:\Films\*.mkv'
        $script:SeenArguments[1] | Should -Be 'D:\Films\film[[]1].mkv'
    }

    It 'ne lance rien et journalise si toutes les entrées résolvent à vide' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'ne doit pas tourner' }
        Get-MediaTranscript -Path (Join-Path $TestDrive 'rien[9].mkv')
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 0
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-InfoLog -Times 1
    }

    It 'ne throw pas et journalise si le binaire est introuvable' {
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { throw 'faster-whisper-xxl introuvable (test)' }
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'ne doit pas tourner' }
        { Get-MediaTranscript -Path 'D:\a.mkv' } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 0
    }

    It 'journalise un code de sortie non nul sans lever' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 1
        }
        { Get-MediaTranscript -Path 'D:\a.mkv' } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
    }

    It 'journalise une exception d''exécution sans lever' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'accès refusé' }
        { Get-MediaTranscript -Path 'D:\a.mkv' } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
    }

    It 'transmet une source inexistante sans erreur' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 0
        }
        { Get-MediaTranscript -Path (Join-Path $TestDrive 'absent.mkv') } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 0
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 1
    }

    It 'n''émet rien dans le pipeline' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 0
        }
        $out = Get-MediaTranscript -Path 'D:\a.mkv'
        $out | Should -BeNullOrEmpty
    }

    It 'sous -WhatIf, affiche la commande et ne lance pas le binaire' {
        # Invoke-Whisper n'est volontairement pas mocké : avec un exe inexistant, toute exécution réelle
        # lèverait et déclencherait Write-ErrorLog.
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { 'X:\binaire-absent-xyz.exe' }
        Get-MediaTranscript -Path 'D:\a.mkv' -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Whisper Show-CommandLine -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 0
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper -Output Detailed"`
Expected : FAIL — `Get-MediaTranscript` n'a pas encore de paramètres.

- [ ] **Step 3: Implémenter**

Remplacer la fonction stub de `Tetram.Media.Whisper/Tetram.Media.Whisper.psm1` par :

```powershell
function Get-MediaTranscript {
    <#
.EXTERNALHELP Tetram.Media.Whisper-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Path')]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory, Position = 0)]
        [Parameter(ParameterSetName = 'Mixed', Mandatory)]
        [SupportsWildcards()]
        [string[]] $Path,

        [Parameter(ParameterSetName = 'LiteralPath', Mandatory)]
        [Parameter(ParameterSetName = 'Mixed', Mandatory)]
        [Alias('PSPath')]
        [string[]] $LiteralPath,

        [ValidateSet('json', 'lrc', 'txt', 'text', 'vtt', 'srt', 'tsv', 'all')]
        [string[]] $Format = @('srt'),

        [ValidateSet('large-v2', 'large-v3-turbo', 'large-v3')]
        [string] $Model = 'large-v2',

        [ValidateSet(
                'af', 'am', 'ar', 'as', 'az', 'ba', 'be', 'bg', 'bn', 'bo', 'br', 'bs', 'ca', 'cs', 'cy', 'da',
                'de', 'el', 'en', 'es', 'et', 'eu', 'fa', 'fi', 'fo', 'fr', 'gl', 'gu', 'ha', 'haw', 'he', 'hi',
                'hr', 'ht', 'hu', 'hy', 'id', 'is', 'it', 'ja', 'jw', 'ka', 'kk', 'km', 'kn', 'ko', 'la', 'lb',
                'ln', 'lo', 'lt', 'lv', 'mg', 'mi', 'mk', 'ml', 'mn', 'mr', 'ms', 'mt', 'my', 'ne', 'nl', 'nn',
                'no', 'oc', 'pa', 'pl', 'ps', 'pt', 'ro', 'ru', 'sa', 'sd', 'si', 'sk', 'sl', 'sn', 'so', 'sq',
                'sr', 'su', 'sv', 'sw', 'ta', 'te', 'tg', 'th', 'tk', 'tl', 'tr', 'tt', 'uk', 'ur', 'uz', 'vi',
                'yi', 'yo', 'yue', 'zh'
        )]
        [string] $UseLanguage,

        [string] $WhisperPath
    )

    try {
        $exe = Get-WhisperPath -OverridePath $WhisperPath
    }
    catch {
        Write-ErrorLog -Text $_.Exception.Message
        return
    }

    $sources = @(Resolve-WhisperSource -Path $Path -LiteralPath $LiteralPath)
    if ($sources.Count -eq 0) {
        # Atteignable seulement si toutes les entrées étaient des motifs résolus à vide : le binding
        # garantit au moins une source. Évite d'invoquer le binaire sans source.
        Write-InfoLog -Text 'Aucune source à transcrire.' -Force
        return
    }

    $whisperArgs = Get-WhisperArguments -Source $sources -Format $Format -Model $Model -UseLanguage $UseLanguage
    Write-DebugLog -Text ($whisperArgs -join ' ')

    $state = @{ ExitCode = $null }
    try {
        Invoke-Whisper -Exe $exe -Arguments $whisperArgs -Cmdlet $PSCmdlet -State $state
    }
    catch {
        Write-ErrorLog -Text $_.Exception.Message
        return
    }

    # ExitCode nul = ShouldProcess a refusé (WhatIf), ce n'est pas un échec. Un code non nul en est un ;
    # l'inverse n'est pas vrai, le binaire sortant en 0 même sans média trouvé.
    if ($null -ne $state['ExitCode'] -and $state['ExitCode'] -ne 0) {
        Write-ErrorLog -Text "faster-whisper-xxl a échoué (code $( $state['ExitCode'] )) sur '$( $sources[0] )'."
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper -Output Detailed"`
Expected : PASS, toute la suite du module.

- [ ] **Step 5: Vérifier l'analyseur**

Run: `pwsh -NoProfile -File tools/Invoke-Analyzer.ps1`
Expected : aucun diagnostic sur `Tetram.Media.Whisper`.

- [ ] **Step 6: Commit**

```bash
git add Tetram.Media.Whisper/Tetram.Media.Whisper.psm1 tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1
git commit -m "feat(whisper): commande Get-MediaTranscript"
```

---

### Task 10 : Aide PlatyPS et MAML

**Files:**

- Create: `docs/help/Tetram.Media.Whisper/Tetram.Media.Whisper.md`
- Create: `docs/help/Tetram.Media.Whisper/Get-MediaTranscript.md`
- Create: `Tetram.Media.Whisper/fr-FR/Tetram.Media.Whisper-Help.xml`
- Create: `docs/help/Tetram.Common/Test-PowerShellSpecificPath.md`, `ConvertTo-GlobLiteral.md`,
  `ConvertTo-AbsolutePath.md`, `ConvertTo-AbsoluteMask.md`
- Modify: `Tetram.Common/fr-FR/Tetram.Common-Help.xml` (régénéré)

**Interfaces:**

- Consumes: la commande publique de Task 9 et son commentaire `.EXTERNALHELP`, plus les quatre fonctions
  exportées par `Tetram.Common` en Task 5
- Produces: l'aide complète, condition du critère de succès « `Get-Help` exploitable, pas un stub ».

- [ ] **Step 1: Générer les squelettes markdown**

Run: `pwsh -NoProfile -File tools/New-HelpMarkdown.ps1 -Verbose`
Expected : création de `docs/help/Tetram.Media.Whisper/` avec la page module et `Get-MediaTranscript.md`,
et des quatre nouvelles pages sous `docs/help/Tetram.Common/`.

- [ ] **Step 2: Rédiger le fond en français**

Compléter `docs/help/Tetram.Media.Whisper/Get-MediaTranscript.md` avec exactement ce contenu :

- **Synopsis** : « Transcrit les pistes audio de fichiers médias avec faster-whisper. »
- **Description** : le transcript est écrit à côté du fichier source, au(x) format(s) demandé(s), le code
de langue étant ajouté au nom du fichier produit. Toutes les sources d'un appel sont traitées par une
**seule** invocation du binaire, le chargement du modèle étant le coût dominant. La commande ne valide
aucun chemin : c'est whisper qui signale une source introuvable ou sans média.
- **Paramètres** :
  - `-Path` : sources. Les masques `*` et `?` sont transmis tels quels à whisper, qui globalise lui-même ;
  les entrées contenant des crochets, un échappement backtick ou un PSDrive nommé sont résolues par
  PowerShell au préalable. Une entrée à crochets sans correspondance ne produit aucune source.
  - `-LiteralPath` : sources prises au pied de la lettre, jamais résolues, même si elles contiennent `*`.
  - `-Format` : formats de sortie, défaut `srt`.
  - `-Model` : modèle whisper, défaut `large-v2`.
  - `-UseLanguage` : code ISO de la langue. Absent, whisper la détecte.
  - `-WhisperPath` : chemin d'un `faster-whisper-xxl.exe` hors du dossier du module.
  - `-WhatIf` / `-Confirm` : la ligne de commande s'affiche, le binaire ne tourne pas.
- **Exemples**, un par bloc :

```powershell
Get-MediaTranscript -Path 'D:\Films\film.mkv'
Get-MediaTranscript -Path 'D:\Films\a.mkv', 'D:\Films\b.mkv'
Get-MediaTranscript -Path 'D:\Films\*.mkv'
Get-MediaTranscript -Path 'D:\Films'
Get-MediaTranscript -LiteralPath 'D:\Films\film[1].mkv'
Get-MediaTranscript -Path 'D:\Films\*.mkv' -LiteralPath 'D:\Films\film[1].mkv'
Get-MediaTranscript -Path 'D:\Films\film.mkv' -Format srt, vtt
Get-MediaTranscript -Path 'D:\Films\film.mkv' -Model large-v3-turbo
Get-MediaTranscript -Path 'D:\Films\film.mkv' -UseLanguage fr
Get-MediaTranscript -Path 'D:\Films\film.mkv' -WhatIf
```

- **Notes** : une source peut être un fichier média, un masque ou un dossier ; une source d'extension
`.txt`, `.m3u`, `.m3u8` ou `.lst` est lue par le binaire comme une **liste de médias** et n'est pas
transcrite ; la distribution Purfview doit être posée dans `Purfview-Whisper-Faster`, dossier non
versionné ; le modèle est téléchargé au premier usage, le premier appel est donc long ; seul le premier
flux audio est transcrit ; jamais de traduction ; une réexécution réécrit les transcripts existants ;
la commande n'accepte pas d'entrée pipeline, un masque sur `-Path` remplaçant `Get-ChildItem | ...`.

- [ ] **Step 3: Rédiger les quatre pages de `Tetram.Common`**

Ces fonctions étant désormais exportées, leur aide fait partie de la surface publique du module commun.
Contenu attendu, une page par fonction :

- `Test-PowerShellSpecificPath` — Synopsis : « Indique si un chemin emploie de la syntaxe que seul
  PowerShell comprend. » Description : renvoie `$true` pour les crochets, l'échappement backtick et les
  PSDrive nommés, c'est-à-dire les formes qu'un processus natif ne saura pas interpréter et qu'il faut
  résoudre avant de les lui remettre. Renvoie `$false` pour une lettre de lecteur, un UNC, un chemin
  relatif et un masque `*` / `?`, que les outils natifs savent lire. Exemples :
  `Test-PowerShellSpecificPath -Path 'D:\Films\film[1].mkv'` et
  `Test-PowerShellSpecificPath -Path 'D:\Films\*.mkv'`.
- `ConvertTo-GlobLiteral` — Synopsis : « Échappe les crochets d'un chemin littéral pour un consommateur
  de glob. » Description : `[` devient `[[]`, convention glob, pour qu'un chemin réellement nommé
  `film[1].mkv` ne soit pas pris pour une classe de caractères. Exemple :
  `ConvertTo-GlobLiteral -LiteralPath 'D:\Films\film[1].mkv'`.
- `ConvertTo-AbsolutePath` — Synopsis : « Absolutise un chemin, même inexistant. » Description : développe
  `~`, puis absolutise relativement à l'emplacement PowerShell courant. Notes : contrairement à
  `Resolve-Path`, n'échoue pas sur un chemin inexistant ; la base est l'emplacement PowerShell et non le
  répertoire de travail du processus, les deux ne coïncidant pas nécessairement. Exemple :
  `ConvertTo-AbsolutePath -Path '.\film.mkv'`.
- `ConvertTo-AbsoluteMask` — Synopsis : « Absolutise le préfixe d'un masque sans toucher au masque. »
  Description : le préfixe sans métacaractère est absolutisé, les segments à partir du premier `*` ou `?`
  sont conservés tels quels, y compris un masque de segment intermédiaire. Exemples :
  `ConvertTo-AbsoluteMask -Mask '.\*.mkv'` et `ConvertTo-AbsoluteMask -Mask 'D:\Films\*\*.mkv'`.

- [ ] **Step 4: Générer le MAML**

Run: `pwsh -NoProfile -File tools/New-HelpMaml.ps1 -Force -Verbose`
Expected : `Tetram.Media.Whisper/fr-FR/Tetram.Media.Whisper-Help.xml` créé, et
`Tetram.Common/fr-FR/Tetram.Common-Help.xml` régénéré avec les quatre nouvelles fonctions.

- [ ] **Step 5: Vérifier que les deux aides se chargent**

Run: `pwsh -NoProfile -Command "Import-Module ./Tetram.Media.Whisper -Force; (Get-Help Get-MediaTranscript -Full).Examples.Example.Count"`
Expected : `10`

Run: `pwsh -NoProfile -Command "Import-Module ./Tetram.Common -Force; (Get-Help ConvertTo-AbsoluteMask -Full).Synopsis"`
Expected : le synopsis rédigé au step 3, et non un stub généré.

- [ ] **Step 6: Commit**

```bash
git add docs/help/Tetram.Media.Whisper Tetram.Media.Whisper/fr-FR docs/help/Tetram.Common Tetram.Common/fr-FR
git commit -m "docs: aide PlatyPS et MAML fr-FR (whisper + utilitaires de chemin)"
```

---

### Task 11 : Test d'intégration et validation d'ensemble

**Files:**

- Modify: `tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1`

**Interfaces:**

- Consumes: le module complet
- Produces: la preuve de bout en bout que la commande produit réellement un transcript.

- [ ] **Step 1: Écrire le test d'intégration**

Ajouter à `tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1` :

```powershell
Describe 'Get-MediaTranscript bout en bout' -Tag 'Integration' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop
        $script:PurfviewRoot = Join-Path $script:ModuleRootWhisper 'Purfview-Whisper-Faster'
        $script:RealExe = Join-Path $script:PurfviewRoot 'faster-whisper-xxl.exe'
        $script:RealFfmpeg = Join-Path $script:PurfviewRoot 'ffmpeg.exe'
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
    }

    It 'produit un .srt à côté de la source' {
        if (-not (Test-Path -LiteralPath $script:RealExe -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'distribution Purfview absente'
            return
        }

        $work = Join-Path $TestDrive 'integration'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $wav = Join-Path $work 'sample.wav'
        & $script:RealFfmpeg -f lavfi -i 'sine=frequency=440:duration=3' -y $wav 2>&1 | Out-Null

        Get-MediaTranscript -Path $wav -UseLanguage en

        @(Get-ChildItem -LiteralPath $work -Filter '*.srt').Count | Should -BeGreaterThan 0
    }
}
```

- [ ] **Step 2: Lancer le test d'intégration**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Tetram.Media.Whisper -Tag Integration -Output Detailed"`
Expected : PASS. Premier lancement long si le modèle `large-v2` n'est pas encore dans `_models`.

- [ ] **Step 3: Vérifier que le CI reste vert sans le binaire**

Run: `pwsh -NoProfile -File tools/Invoke-Tests.ps1`
Expected : PASS, le test `Integration` étant exclu par défaut.

- [ ] **Step 4: Vérifier l'analyseur sur tout le dépôt**

Run: `pwsh -NoProfile -File tools/Invoke-Analyzer.ps1`
Expected : aucun nouveau diagnostic.

- [ ] **Step 5: Vérifier que rien de la distribution n'a été ajouté par mégarde**

Run: `git status --short --untracked-files=all -- Tetram.Media.Whisper`
Expected : sortie vide.

- [ ] **Step 6: Commit**

```bash
git add tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1
git commit -m "test(whisper): transcription réelle taggée Integration"
```

---

## Couverture de la spec


| Exigence de la spec                                                                               | Tâche          |
| ------------------------------------------------------------------------------------------------- | -------------- |
| Manifeste, export unique, PS 7 Core, dot-source de `Private/`                                     | Task 3         |
| Ordre stable des arguments (chemins nus), formats, modèle, langue                                 | Task 4         |
| Conversions de chemin : `~`, absolutisation, échappement glob, syntaxe PowerShell                 | Task 5         |
| Masque transmis tel quel, spécificités PowerShell traduites, crochets neutralisés                 | Task 5, Task 6 |
| Dossier, fichier-liste et chemin inexistant transmis sans validation                              | Task 6         |
| Entrée à crochets sans correspondance : aucun élément                                             | Task 6, Task 9 |
| Résolution du binaire façon `Get-FFmpegPath`, override `-WhisperPath`                             | Task 7, Task 9 |
| `Show-CommandLine` puis `ShouldProcess`, sortie binaire non capturée                              | Task 8         |
| Trois jeux de paramètres, `-Path` positionnel hors `Mixed`, pas de pipeline                       | Task 9         |
| `ValidateSet` de `-Format`, `-Model`, `-UseLanguage`                                              | Task 9         |
| Aucune exception publique, journalisation `Tetram.Common`                                         | Task 9         |
| Aucune sortie pipeline                                                                            | Task 9         |
| `.gitignore` et `.keep`                                                                           | Task 1         |
| Aide PlatyPS complète et MAML (whisper + `Tetram.Common`)                                         | Task 10        |
| Test réel taggé `Integration`                                                                     | Task 11        |
| Smoke test préalable des chemins nus et des crochets                                              | Task 2         |


