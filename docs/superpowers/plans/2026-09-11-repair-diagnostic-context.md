# Repair — contexte média des diagnostics — plan d’implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Chaque diagnostic Repair relatif à un média s’affiche avec un en-tête source uniforme, produit uniquement par `Write-RepairDiagnostic`, sans changer les règles publiques de poursuite/remplacement.

**Architecture:** Helpers silencieux (throw ou résultat structuré). `Invoke-MkvRepairFile` orchestre le fichier, affiche, retourne `Outcome` sans throw. `Invoke-MkvRepair` applique `-ContinueOnError` et la terminaison. Tout dans `Tetram.Media.Repair.psm1`.

**Tech Stack:** PowerShell 7.6+, Pester 5, TestDrive, PlatyPS (`tools/New-HelpMaml.ps1`).

**Spec :** `docs/superpowers/specs/2026-09-11-repair-diagnostic-context-design.md`

## Global Constraints

- ⚠️ **Ne pas committer ni pousser** : aucune commande `git commit`, `git push` ou création de PR tant que l’utilisateur n’a pas explicitement validé les modifications.
- Pas de worktree isolé : travailler dans `d:\GIT\Scripts`.
- Périmètre : Repair uniquement (les deux commandes publiques et ce qu’elles déclenchent).
- Exports publics inchangés : `Get-MkvInterleaveRepairCommand`, `Invoke-MkvRepair`.
- `Show-CommandLine` reste commenté.
- Une fonction n’attache que les données de sa responsabilité introuvables ailleurs. **Pas de `SourcePath` dans `Exception.Data`.**
- Helpers : aucun `Write-Warning` / `Write-Error`.
- Une seule fonction finale d’affichage : `Write-RepairDiagnostic`.
- TDD : test qui échoue d’abord, puis code minimal.
- Commentaires : pourquoi, jamais le quoi.
- Réponses / docs utilisateur en français.
- Ne pas modifier `ErrorActionPreference` global.
- Invariants métier publics du spec (code 0/1/>=2, ForceReplace, ContinueOnError seulement sur `Failed`) : non négociables.

---

## File Structure

| Chemin | Responsabilité |
| --- | --- |
| `Tetram.Media.Reencode/Tetram.Media.Repair.psm1` | Unique fichier de code : helpers silencieux, affichage, builder privé, RepairFile, façades |
| `tests/Tetram.Media.Reencode/Tetram.Media.Repair.Tests.ps1` | Suite Repair (adapter captures + Outcome + header) |
| `docs/help/Tetram.Media.Reencode/Invoke-MkvRepair.md` | Aide : format des blocs |
| `docs/help/Tetram.Media.Reencode/Get-MkvInterleaveRepairCommand.md` | Aide : format des blocs |
| `Tetram.Media.Reencode/fr-FR/Tetram.Media.Reencode-Help.xml` | MAML régénéré, pas édité à la main |
| `Tetram.Media.Reencode/Tetram.Media.Reencode.psd1` | `3.5.1` + release notes |

---

### Task 1: Formateur et émetteur unique

**Files:**
- Modify: `Tetram.Media.Reencode/Tetram.Media.Repair.psm1` (après les helpers d’en-tête de fichier)
- Test: `tests/Tetram.Media.Reencode/Tetram.Media.Repair.Tests.ps1`

**Interfaces:**
- Consumes: rien
- Produces:

```powershell
function Format-RepairSourceHeader {
    param([AllowNull()][string] $SourcePath)
    # retourne "Fichier source '$SourcePath'" ou $null si pas de média
}

function Write-RepairDiagnostic {
    param(
        [string] $SourcePath,
        [Parameter(Mandatory)] [object[]] $Diagnostics
        # chaque item : Severity = 'Warning'|'Error' ; Message = string (peut être multiligne)
        # ErrorRecord optionnel pour préserver l’incident métier lors de la copie de présentation
    )
    # 1. header au Write-xxx du max de sévérité (omis si SourcePath vide)
    # 2. pour chaque diagnostic, pour chaque ligne : Write-Warning ou Write-Error -ErrorAction Continue
}
```

- [x] **Step 1: Tests formateur + émetteur**

Ajouter un `Describe 'Format-RepairSourceHeader'` et `Describe 'Write-RepairDiagnostic'` en `InModuleScope 'Tetram.Media.Repair'` :

- header exact `Fichier source 'V:\Séries\Une série\episode.mkv'`
- UNC, apostrophe, crochets, espaces : littéral
- `\\?\C:\Media\film.mkv` **n’est pas** la responsabilité du formateur (RepairFile lui passe déjà le chemin logique) : le formateur n’appelle pas le disque
- sans média : `Format-RepairSourceHeader` → `$null` ; `Write-RepairDiagnostic` n’émet pas de header
- warning isolé : 2 appels Warning (header + ligne)
- message 2 lignes : 1 header + 2 lignes, même Write-xxx
- bloc mixte Warning/Error/Warning : header Error, puis W/E/W (4 appels)
- original ErrorRecord non muté
- `-WarningAction SilentlyContinue` masque header et corps warning ensemble

- [x] **Step 2: Exécuter les tests, constater l’échec** (fonctions absentes)

```powershell
pwsh -NoProfile -File ./tools/Invoke-Tests.ps1 -Path ./tests/Tetram.Media.Reencode/Tetram.Media.Repair.Tests.ps1
```

- [x] **Step 3: Implémenter formateur + `Write-RepairDiagnostic`**

Découper les messages sur `[\r\n]+`, ignorer les lignes vides issues du split, pas de `-join` vers une seule émission. Header Error : `Write-Error -ErrorAction Continue`. Ne pas lire `ContinueOnError` / `ForceReplaceOnWarning`.

- [x] **Step 4: Revérifier les nouveaux tests au vert** (la suite existante peut encore passer : ces fonctions ne sont pas encore branchées)

---

### Task 2: Métadonnées d’exception (sans SourcePath)

**Files:**
- Modify: `Tetram.Media.Reencode/Tetram.Media.Repair.psm1`
- Test: `tests/Tetram.Media.Reencode/Tetram.Media.Repair.Tests.ps1`

**Interfaces:**
- Consumes: Task 1
- Produces: constantes de clés + `Add-RepairExceptionData` / `Get-RepairExceptionData`

```powershell
$script:RepairExceptionKeyDiagnostics = 'Tetram.Media.Repair.Diagnostics'
$script:RepairExceptionKeyTempPath    = 'Tetram.Media.Repair.TempPath'
$script:RepairExceptionKeySeverity    = 'Tetram.Media.Repair.Severity'
$script:RepairExceptionKeyBlocked     = 'Tetram.Media.Repair.OperationBlocked'

function Add-RepairExceptionData {
    param(
        [Parameter(Mandatory)] [System.Exception] $Exception,
        [object[]] $Diagnostics,
        [string] $TempPath,
        [string] $Severity,
        [bool] $OperationBlocked
    )
    # n’écrit une clé que si fournie et absente (pas d’écrasement)
}

function Get-RepairExceptionData {
    param([Parameter(Mandatory)] [System.Exception] $Exception)
    # parcourt Exception puis InnerException ; retourne hashtable des clés trouvées
}
```

- [x] Tests : même exception/message ; Data ajouté ; données étrangères intactes ; aucune sortie ; InnerException ; pas de clé SourcePath
- [x] Implémenter
- [x] Tests au vert

---

### Task 3: Lecteurs silencieux JSON / log

**Files:**
- Modify: `Tetram.Media.Reencode/Tetram.Media.Repair.psm1` (`Write-MkvMergeIdentificationDiagnostics`, `Write-MkvMergeCapturedDiagnostics` → lecteurs `Get-*` retournant diagnostics + counts)
- Test: adapter / ajouter dans `Tetram.Media.Repair.Tests.ps1`

**Interfaces:**
- Consumes: `Get-MkvMergeJsonDiagnosticMessageList`, `New-MkvMergeDiagnosticCounts`
- Produces:

```powershell
function Get-MkvMergeIdentificationDiagnostics {
    param([Parameter(Mandatory)] [object] $Info)
    # { Items = @( { Severity; Message } ); WarningCount; ErrorCount }
}

function Get-MkvMergeCapturedDiagnostics {
    param([string] $LogPath)
    # même forme ; ordre Warning:/Error: conservé ; fichier absent → counts 0
}
```

Supprimer tout `Write-Warning` / `Write-Error` de ces fonctions. Les anciens noms `Write-*` disparaissent (mettre à jour les mocks éventuels).

- [x] Tests InModuleScope : JSON warnings puis errors ; log mixte ; fallback vide ; counts natifs = nombre de diagnostics, pas de lignes d’en-tête
- [x] Ces tests ne doivent **aucune** WarningRecord/ErrorRecord
- [x] Implémenter
- [x] Vert

---

### Task 4: `Get-MkvMergeInfo` silencieux

**Files:**
- Modify: `Tetram.Media.Repair.psm1` (`Get-MkvMergeInfo`)
- Test: `Describe 'Get-MkvMergeInfo'` (aujourd’hui il capture des Write-*)

**Interfaces:**
- Consumes: Task 3, Task 2
- Produces: info hashtable/object en code 0/1 ; throw en ≥ 2 avec `Diagnostics` dans `Data` (JSON, log, ou brut)

Message métier **sans** chemin obligatoire : `mkvmerge -J a échoué avec le code $exitCode.` (le header viendra de RepairFile / façade). Adapter `Assert-MkvMergeJFailedException` : ne plus matcher `$Path` dans le message.

Politique 0/1 : ne pas attacher/rejouer les warnings JSON d’identification.

Fallback brut : si rien de classifié et raw non vide → un diagnostic Error = `raw.TrimEnd()`.

- [x] Tests : 0/1 sans records Warning/Error ; ≥ 2 throw + Data.Diagnostics ; JSON invalide 0 vs ≥ 2 ; log ; fallback ; temp file nettoyé
- [x] Implémenter
- [x] Vert — les tests d’identification via **commandes publiques** qui attendent encore l’affichage casseront : les réparer dans Task 5–7, pas en affaiblissant les asserts métier

---

### Task 5: Builder privé + façade publique

**Files:**
- Modify: extraire le corps actuel de `Get-MkvInterleaveRepairCommand` vers `New-MkvInterleaveRepairCommand` (mêmes paramètres métier, **aucun** `[CmdletBinding]` d’affichage)
- `Get-MkvInterleaveRepairCommand` : appelle le privé ; catch → `Write-RepairDiagnostic` avec le chemin logique déjà calculé (ou l’argument reçu) puis terminaison (`$PSCmdlet.ThrowTerminatingError` / rethrow après affichage, sans rejeu)

`ConvertTo-MkvDate` : message inchangé avec la valeur invalide ; pas de chemin.

Validations (sortie identique, conteneur, pistes, A/V) : throw **sans** chemin dans le texte (le header le porte). Adapter les `Should -Throw '*Aucune piste*'` : le motif reste valide (corps). Ajouter des tests d’affichage sur la **façade** : première ligne de flux = header avec chemin complet.

`Invoke-MkvRepairFile` appellera le privé à la Task 7 ; jusqu’à Task 6 il peut encore appeler la façade — **dès Task 5**, basculer RepairFile vers le privé pour ne pas double-afficher. Si RepairFile n’est pas encore prêt à catch, laisser un throw brut du privé (affichage = Task 7). Donc : Task 5 = extraire + façade ; RepairFile pointe déjà le privé (erreurs builder encore non wrappées d’en-tête en mode RepairFile jusqu’à Task 7). Les tests publics `Get-MkvInterleaveRepairCommand` voient le header.

- [x] Tests façade : header puis message ; deux fichiers homonymes → bon chemin ; pipeline du résultat builder sans header
- [x] Tests privé InModuleScope : throw brut, zéro Write-*
- [x] Mocks `Get-MkvMergeInfo` existants : inchangés si le privé reste dans le même module
- [x] Implémenter
- [x] Vert sur les tests builder ; RepairFile peut encore échouer sans header — acceptable jusqu’à Task 7

---

### Task 6: Remux silencieux

**Files:**
- Modify: extraire de `Invoke-MkvRepairFile` l’invocation `mkvmerge` (stdout masqué, `--quiet`, log) vers p.ex. `Invoke-MkvMergeRemux`

**Interfaces:**

```powershell
function Invoke-MkvMergeRemux {
    param($Executable, $Arguments, $LogPath)
    # & $Executable … > $null
    # Diagnostics = Get-MkvMergeCapturedDiagnostics
    # throw si lancement impossible, Diagnostics attachés si déjà lus
    [pscustomobject]@{
        ExitCode    = $LASTEXITCODE
        Diagnostics = $items
        WarningCount = …
        ErrorCount   = …
    }
}
```

Aucun `Write-*`. Aucune décision `ForceReplaceOnWarning`.

- [x] Test : code 0/1/2, ordre natif, stdout non fuité, log lu ; zéro WarningRecord depuis le helper
- [x] Implémenter
- [x] Vert

---

### Task 7: Orchestrateur `Invoke-MkvRepairFile`

**Files:**
- Modify: `Invoke-MkvRepairFile`
- Test: `Invoke-RepairFileUnderTest` + `Describe 'Invoke-MkvRepairFile'` + ForceReplace

**Comportement:**

1. Normalisation / `Get-Item` / timestamps **dans** un try (aujourd’hui hors try) : échec → `Write-RepairDiagnostic` + `Outcome = Failed`.
2. Builder privé, remux, wait, move, timestamps.
3. Code 1 : afficher les diagnostics natifs (un bloc) ; si pas Force ou `ErrorCount -gt 0` : warning synthétique « source non remplacée » (même bloc ou bloc suivant **même média**, header une fois par appel d’affichage — regrouper natifs + synthèse dans **un** appel `Write-RepairDiagnostic` pour un seul header) ; `WarningKept`.
4. Force + code 1 sans Error : warning synthétique de poursuite, puis remplacement ; `Success`.
5. Code ≥ 2 : diagnostics natifs + message d’échec (détail temporaire si pertinent) ; `Failed`.
6. Sortie absente / timeout / move : `Failed`, source identifiée, temporaire dans le détail.
7. Erreur **après** move : ne pas dire que la source n’a pas été remplacée.
8. `finally` : nettoyage log + temporaire si non remplacé.
9. **Pas de throw.**
10. `-PassThru` : remplir `PassThru`, ne rien écrire dans le pipeline succès.

Adapter `Invoke-RepairFileUnderTest` pour stocker `Outcome` / `ErrorRecord` / `PassThru`. Les tests qui attendaient un throw de RepairFile passent par `Outcome = Failed` + capture Warning/Error.

- [x] Tests : Outcome, header présent, ForceReplace, code 1+Error non remplacé et lot non concerné ici, timestamps, WhatIf n’est pas dans RepairFile
- [x] Implémenter
- [x] Vert

---

### Task 8: `Invoke-MkvRepair` lot et `-Path`

**Files:**
- Modify: `Invoke-MkvRepair`
- Test: `Describe 'Invoke-MkvRepair'`

**Comportement:**

- ShouldProcess Target = `Format-RepairSourceHeader` (chemin logique si déjà connu, sinon argument). Action inchangée.
- Progress `CurrentOperation` = même libellé ; `-Completed` sans média.
- Émettre `result.PassThru` si `-PassThru` et `Success`.
- `Failed` + ParameterSet File → `ThrowTerminatingError(ErrorRecord)` sans réaffichage.
- `Failed` + Folder + ContinueOnError → `continue` (déjà affiché ; **ne pas** `Write-Error` une seconde fois).
- `Failed` + Folder sans ContinueOnError → break puis `ThrowTerminatingError`.
- `WarningKept` : toujours le fichier suivant.
- Dossier introuvable : throw sans header.

- [x] Tests Path terminant (header une fois, corps complet, ErrorRecord original) ; Folder ± ContinueOnError ; deux homonymes ; pipeline PassThru propre ; WhatIf/Confirm ; WarningAction Stop
- [x] Implémenter
- [x] Vert

---

### Task 9: Filet du brief §9 et régression Reencode

**Files:**
- Test: `Tetram.Media.Repair.Tests.ps1` (trous restants : JSON identification via façade, fallback, préparation timestamps, UNC/long path Windows)

- [x] Checklist brief §9 : chaque ligne a un test, sinon l’ajouter
- [x] `pwsh -NoProfile -File ./tools/Invoke-Tests.ps1 -Path ./tests/Tetram.Media.Reencode/Tetram.Media.Repair.Tests.ps1`
- [x] `pwsh -NoProfile -File ./tools/Invoke-Tests.ps1 -Path ./tests/Tetram.Media.Reencode`
- [x] Analyzer du module si `tools/Invoke-Analyzer.ps1` est la gate habituelle

---

### Task 10: Documentation, MAML, manifeste

**Files:**
- `docs/help/Tetram.Media.Reencode/Invoke-MkvRepair.md`
- `docs/help/Tetram.Media.Reencode/Get-MkvInterleaveRepairCommand.md`
- `Tetram.Media.Reencode/Tetram.Media.Reencode.psd1` → `3.5.1` + note
- Régénérer : `pwsh -NoProfile -File ./tools/New-HelpMaml.ps1`
- Ne conserver que le XML Reencode si d’autres modules bougent sans raison

Décrire l’en-tête `Fichier source '…'` et le bloc. Ne pas changer les règles code 0/1/`-ContinueOnError`/`-ForceReplaceOnWarning`.

- [x] Diff MAML relu
- [x] `Test-ModuleManifest` + exports inchangés

---

### Task 11: Revue indépendante (après le code, avant tout commit)

Sous-agent lecture seule, contrat `.cursor/rules/subagent-contract.mdc` + brief §11 + `post-plan-review.mdc`. Corriger les causes des défauts bloquants, rejouer les tests concernés.

Une fois le code validé par l’utilisateur : committer (hors de ce plan).
