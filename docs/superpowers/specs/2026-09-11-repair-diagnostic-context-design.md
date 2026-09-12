# Design — Repair : contexte média et responsabilité unique

Date : 2026-09-11  
Module : `Tetram.Media.Reencode` / nested `Tetram.Media.Repair`  
Commandes publiques : `Get-MkvInterleaveRepairCommand`, `Invoke-MkvRepair`  
Base : commit `624363f` (`feat(reencode): ajouter -ForceReplaceOnWarning`)  
Brief : `.cursor/prompts/brief-cursor-repair-erreurs-fichier (1).md`

## Objectif

Tout diagnostic isolé ou bloc relatif à un média identifie le chemin source logique complet, via un en-tête uniforme émis **avant** le contenu, par **une seule** fonction finale d’affichage.

`Invoke-MkvRepairFile` orchestre le fichier (décisions de remplacement/abandon, affichage, interception). `Invoke-MkvRepair` orchestre le lot (ShouldProcess, progression, `-ContinueOnError`, terminaison `-Path`). Les helpers métier restent silencieux.

## Décisions validées

| Sujet | Choix |
| --- | --- |
| Fichiers | Tout reste dans `Tetram.Media.Repair.psm1` |
| Orchestrateur fichier | `Invoke-MkvRepairFile` : travail, affichage, catch, **ne throw pas** |
| Orchestrateur lot | `Invoke-MkvRepair` : appel unique ou boucle ; applique `-ContinueOnError` ; termine en `-Path` |
| Remontée interne | Contrat mixte : exception si pas de résultat ; objet structuré si remux achevé |
| `SourcePath` | Paramètre d’affichage fourni par RepairFile / façade publique. **Absent** de `Exception.Data`. Les helpers ne le posent pas |
| Données d’exception | Une fonction n’attache que ce qui est de sa responsabilité **et** introuvable ailleurs (`Diagnostics`, `TempPath`, `Severity`, `OperationBlocked`) |
| Affichage | **Une** fonction privée `Write-RepairDiagnostic` : elle calcule elle-même le niveau du header |
| Formateur | `Format-RepairSourceHeader` retourne uniquement le texte, sans console ni disque |
| Builder | Métier dans `New-MkvInterleaveRepairCommand` (privé). Façade publique + RepairFile l’appellent |
| Exports | Inchangés |
| `Show-CommandLine` | Reste commenté |
| Docs | Ajuster Markdown + régénérer le MAML si le rendu change |
| Version | `3.5.1` (présentation ; pas de nouvelle règle de poursuite/remplacement) |

## Hors scope

- Autres commandes de `Tetram.Media.Reencode` (`Invoke-ReencodeMedia`, Probe, Streams, etc.).
- Réactivation de `Show-CommandLine`.
- Nouveaux messages Host / Information / Verbose « pour remplir des catégories ».
- Changement des règles publiques `-ContinueOnError` / `-ForceReplaceOnWarning`.

## Couches

```text
Get-MkvInterleaveRepairCommand          Invoke-MkvRepair
  façade : catch → Write-RepairDiagnostic     ShouldProcess / Progress
  puis terminaison                            unwrap PassThru
       │                                      ContinueOnError / ThrowTerminatingError
       ▼                                              │
New-MkvInterleaveRepairCommand              Invoke-MkvRepairFile
  (silencieux, throw métier)                  orchestrateur fichier
       │                                      Outcome + PassThru + ErrorRecord
       ▼                                              │
Get-MkvMergeInfo / lecteurs / remux / wait / move / ConvertTo-MkvDate
  silencieux : throw ou objet { ExitCode, Diagnostics, … }

Write-RepairDiagnostic  ←  seul émetteur Warning/Error Repair
Format-RepairSourceHeader  ←  texte uniquement
```

### Helpers (interdits : Write-Warning, Write-Error, header, décision de lot/fichier)

- `Get-MkvMergeJsonDiagnosticMessageList`, nouveau lecteur JSON → diagnostics bruts ordonnés.
- Lecteur de log (remplace l’écriture de `Write-MkvMergeCapturedDiagnostics`) → diagnostics bruts + compteurs natifs.
- `Get-MkvMergeInfo` : identification ; code ≥ 2 → throw avec `Diagnostics` attachés ; code 0/1 → objet info, **sans** rejouer les warnings JSON.
- `New-MkvInterleaveRepairCommand` : tout le métier actuel du builder.
- Helper remux : stdout masqué, `--quiet`, log capturé ; retour `{ SourcePath n’y figure pas, OutputPath, ExitCode, Diagnostics }`.
- `Wait-FileReady`, `Move-ItemWithRetry`, `ConvertTo-MkvDate` : throw opérationnel (valeur invalide conservée pour la date).
- `Add-RepairExceptionData` / `Get-RepairExceptionData` : clés centralisées, parcours `InnerException`, pas d’affichage, pas d’accès disque, **pas de SourcePath**.

### `Invoke-MkvRepairFile`

1. Normalise le chemin (échec de normalisation : garder l’argument reçu pour l’affichage).
2. Appelle le builder privé, le remux, les validations, wait/move/timestamps.
3. Applique `-ForceReplaceOnWarning` (code 1 remplaçable seulement si `ErrorCount` natif = 0).
4. Catch : n’écrit rien dans le catch ; appelle `Write-RepairDiagnostic` avec le chemin qu’il connaît et les diagnostics de l’exception / du résultat.
5. Retourne toujours :

```powershell
[pscustomobject]@{
    Outcome    = 'Success' | 'WarningKept' | 'Failed'
    PassThru   = $fileInfoOuNull
    ErrorRecord = $errorRecordMetierOuNull
}
```

- `Success` : source remplacée (code 0, ou code 1 forcé sans Error natif).
- `WarningKept` : code 1, source conservée (y compris code 1 + Error natif, même avec le switch). Le lot **continue toujours**.
- `Failed` : erreur réelle, déjà affichée. `ErrorRecord` = incident métier original, non modifié.

Aucune émission pipeline depuis RepairFile (même `-PassThru` : l’objet est dans `PassThru` du résultat interne).

### `Invoke-MkvRepair`

- `-Path` : après ShouldProcess, appelle RepairFile ; si `PassThru` et `Success`, émet l’objet ; si `Failed`, `$PSCmdlet.ThrowTerminatingError($result.ErrorRecord)` **sans réafficher**.
- `-Folder` : matérialisation, filtre lecture seule, progression, ShouldProcess par fichier. `Failed` + `-ContinueOnError` → fichier suivant (déjà affiché). `Failed` sans le switch → arrêt de boucle puis la même terminaison sans réaffichage. `WarningKept` ne consulte pas `-ContinueOnError`.
- Erreur globale sans média (dossier absent, binding) : pas d’en-tête fictif.
- `Write-Progress -Completed` : pas de média. `CurrentOperation` : même libellé d’en-tête. ShouldProcess `Target` : `Fichier source '…'` ; action inchangée.

L’affichage **ne lit pas** `ContinueOnError` ni `ForceReplaceOnWarning`.

## Présentation

Forme unique :

```text
Fichier source 'V:\Séries\Une série\episode.mkv'
Aucune piste trouvée dans le fichier.
```

Règles :

1. Toujours le même en-tête avant le contenu. Pas de suffixe / préfixe / pied alternatif.
2. Un bloc = un média, contigu, émis entièrement par `Write-RepairDiagnostic`.
3. Chemin logique absolu, sans `\\?\` / `\\?\UNC\`. Préserver UNC, accents, espaces, apostrophes, crochets.
4. Ne pas résoudre le chemin pour afficher : le fichier peut avoir disparu. Normalisation en échec → argument reçu.
5. Temporaire et log : détail du corps, jamais l’identité.
6. Pas de média → pas d’en-tête.
7. Une progression / un catch antérieur ne contextualise pas le diagnostic final.
8. Header au `Write-xxx` du **max** de sévérité du bloc ; chaque ligne garde le niveau de son diagnostic. Ordre d’origine conservé.
9. En-tête émis **séparément**, puis un `Write-xxx` par ligne (CRLF/LF, pas de CR résiduel, pas de `-join` multi-diagnostics).
10. Compteurs `WarningCount` / `ErrorCount` : diagnostics natifs, jamais le nombre d’appels Write / lignes / headers.
11. `Write-Error` de présentation : `-ErrorAction Continue` dans le parcours non terminant. Ne pas changer `ErrorActionPreference` global.
12. Objets publics (builder, PassThru) : aucun texte de journal.

`Format-RepairSourceHeader` :

```powershell
"Fichier source '$sourcePath'"
```

## Contrat d’exception

Clés (constantes de module), uniquement si la fonction **possède** l’info :

| Clé | Qui la pose | Contenu |
| --- | --- | --- |
| `Tetram.Media.Repair.Diagnostics` | Lecteur / `Get-MkvMergeInfo` / remux | Liste `{ Severity; Message }` |
| `Tetram.Media.Repair.TempPath` | Remux / wait sur le temporaire | Chemin outil du temporaire |
| `Tetram.Media.Repair.Severity` | Producteur d’un incident warning bloquant | `'Warning'` |
| `Tetram.Media.Repair.OperationBlocked` | Idem | `$true` |

Catch enrichissant : `throw` nu. Pas de `throw $_.Exception.Message`. Pas de flag « déjà affiché ». Pas d’état global, pas d’inspection de pile.

## Terminaison

1. `Write-RepairDiagnostic` émet tout le bloc (header non terminant, puis lignes).
2. RepairFile retourne `Failed` + `ErrorRecord` original.
3. `Invoke-MkvRepair` (ou la façade builder) termine avec cet `ErrorRecord` sans rejouer le bloc.
4. L’en-tête n’est pas un incident métier : il ne compte pas dans les compteurs natifs et n’interrompt pas l’émission des lignes.

La façade `Get-MkvInterleaveRepairCommand` affiche puis termine : le builder privé, lui, throw brut.

## Invariants métier publics (inchangés)

- `-Path` : erreurs terminantes restent terminantes.
- `-Folder` sans `-ContinueOnError` : arrêt après l’échec **Failed** du fichier.
- `-Folder` avec `-ContinueOnError` : erreur déjà exposée, fichier suivant.
- Remux 0 : validation, attente, remplacement, timestamps.
- Code 1 : source conservée par défaut ; remplacement forcé seulement sans diagnostic Error natif. Code 1 + Error : non remplaçable, **n’arrête pas** le lot (`WarningKept`).
- Erreur réelle : pas de remplacement. Une erreur **après** déplacement n’annonce pas « source non remplacée ».
- WhatIf / Confirm : mêmes décisions ; pas d’I/O métier pour préparer l’affichage.
- PassThru : mêmes `FileInfo` après remplacement réussi uniquement.
- Candidats, lecture seule, récursion, temporaires uniques, retries, finally, fin de progression : conservés.

## Tests

Réutiliser Pester, TestDrive, `New-MkvMergeInfo`, `New-FakeToolScript`, helpers de capture. Import public `Tetram.Media.Reencode` ; privés via `InModuleScope 'Tetram.Media.Repair'`.

Adapter :

- `Get-MkvMergeInfo` : plus d’émissions ; assert throw + `Diagnostics` dans `Data`.
- `Invoke-MkvRepairFile` : plus de throw ; assert `Outcome` ; l’affichage se capture sur RepairFile / commandes publiques.
- `Invoke-RepairFileUnderTest` : exposer `Outcome` en plus des warnings.
- `Assert-MkvMergeJFailedException` : ne plus exiger le chemin **dans le message** métier (il va dans l’en-tête au niveau façade/RepairFile).
- Mocks du builder : pointer le privé pour RepairFile ; la façade publique reste testée à part.

Couvrir le tableau du brief §9 (header, bloc mixte, terminaison, homonymes, pipeline, ForceReplace, ContinueOnError seulement sur `Failed`, validations builder, JSON/log/fallback, timestamps, chemins spéciaux, WhatIf/Progress, préférences de flux).

Commandes :

```powershell
pwsh -NoProfile -File ./tools/Invoke-Tests.ps1 -Path ./tests/Tetram.Media.Reencode/Tetram.Media.Repair.Tests.ps1
pwsh -NoProfile -File ./tools/Invoke-Tests.ps1 -Path ./tests/Tetram.Media.Reencode
```

Puis gates du dépôt et consommateurs réellement affectés. Ne pas affaiblir les tests métier.

## Documentation

- `docs/help/Tetram.Media.Reencode/Invoke-MkvRepair.md`
- `docs/help/Tetram.Media.Reencode/Get-MkvInterleaveRepairCommand.md`

Décrire le format d’en-tête et les blocs. Ne pas inventer de nouvelles règles de poursuite/remplacement.

Régénérer le MAML : `tools/New-HelpMaml.ps1`. Ne conserver que les écarts générés nécessaires (module Reencode).

Manifeste : `3.5.1` + note de publication correspondante.

## Revue finale

Sous-agent lecture seule, périmètre Repair uniquement, sans prendre le brief pour acquis. Défauts bloquants du brief §11 : fragment écrit puis rethrow ; helper qui affiche ou décide ; header hors affichage final ; politique métier dans l’affichage ; état « déjà affiché » ; diagnostics perdus/réordonnés ; régression métier ; pollution pipeline.
