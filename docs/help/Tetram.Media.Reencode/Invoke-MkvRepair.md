---
document type: cmdlet
external help file: Tetram.Media.Reencode-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Reencode
ms.date: 09/09/2026
PlatyPS schema version: 2024-05-01
title: Invoke-MkvRepair
---

# Invoke-MkvRepair

## SYNOPSIS

Répare l'interleaving d'un MKV (ou des `*.mkv` d'un dossier) et remplace le fichier source in-place.

## SYNTAX

### File (Par défaut)

```
Invoke-MkvRepair [-Path] <string> [-MkvMerge <string>] [-ExtendedPathThreshold <int>]
 [-FileReadyTimeoutSeconds <int>] [-RetryIntervalMilliseconds <int>] [-PassThru] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### Folder

```
Invoke-MkvRepair -Folder <string> [-Recurse] [-ContinueOnError] [-MkvMerge <string>]
 [-ExtendedPathThreshold <int>] [-FileReadyTimeoutSeconds <int>] [-RetryIntervalMilliseconds <int>]
 [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Importer `.\Tetram.Media.Reencode` (PowerShell 7.6+). Remux `mkvmerge` à readers A/V séparés (même construction que `Get-MkvInterleaveRepairCommand`), puis `Move-Item` de la sortie temporaire sur le source. Ce n'est pas un réencodage : les flux conservés sont recopiés. Jeux exclusifs : `-Path` (un fichier) ou `-Folder` (scan `*.mkv`).

Effet disque :

- `-WhatIf` : pas de remux, pas de remplacement. `ConfirmImpact` Medium : pas de prompt sauf `-Confirm`.
- run réel : `mkvmerge` écrit un temporaire unique à côté du source (`{basename}.{guid}.mkv`, distinct du voisin `.repaired.mkv` du builder public), attend que le fichier soit disponible en exclusivité, puis déplace ce temporaire par-dessus le source. Après un remplacement réussi, `CreationTime` / `LastWriteTime` / `LastAccessTime` du source sont restitués (comme `Invoke-ReencodeFile`).
- code retour `mkvmerge` :
  - `0` : la sortie est validée puis remplace le source.
  - `1` : warning PowerShell (`Write-Warning`) reprenant le ou les messages `Warning:` émis par `mkvmerge`, dans l'ordre d'origine ; le source n'est pas remplacé ; le temporaire est abandonné et nettoyé. En mode `-Folder`, le fichier suivant est traité immédiatement, que `-ContinueOnError` soit présent ou non. Ce n'est pas une exception.
  - `>= 2` : warnings éventuels puis erreur(s) `mkvmerge` restitués dans l'ordre d'origine (`Write-Warning` / `Write-Error`) ; le source est conservé et le temporaire est nettoyé. L'erreur synthétique identifie toujours le fichier concerné. Sans `-ContinueOnError`, le traitement s'arrête après ce fichier. Avec `-ContinueOnError` (jeu `Folder` uniquement), l'échec reste écrit dans le flux d'erreur et le scan continue.

Mode `-Folder` : uniquement des fichiers `*.mkv` non lecture seule. La liste est **entièrement matérialisée** avant la première réparation : un temporaire créé pendant le run n'est pas ajouté à la file. Un voisin `.repaired.mkv` déjà présent n'est pas écrasé par la réparation de `{basename}.mkv` (c'est un candidat distinct). `-Recurse` descend dans les sous-dossiers. Un dossier absent lève ; un dossier sans candidat retourne sans erreur. Le mode `-Path` ne saute pas un fichier lecture seule : ce filtre n'existe que pour `-Folder`. Un warning `mkvmerge` (code `1`) n'interrompt pas le lot. Une erreur réelle (code `>= 2`, identification `-J` en échec, sortie absente, ou autre exception propre au fichier) arrête le lot par défaut ; `-ContinueOnError` expose l'erreur et passe au fichier suivant. Les erreurs qui empêchent de démarrer le lot (dossier inexistant, binding) restent terminantes. `-ContinueOnError` n'existe pas en mode `-Path`.

`-PassThru` émet le `FileInfo` du source après remplacement. Sans ce commutateur : aucun objet pipeline. Un fichier abandonné sur warning (code `1`) ou sur erreur n'émet rien. Une barre de progression s'affiche en mode dossier.

`mkvmerge` : `-MkvMerge`, défaut `mkvmerge.exe` sous Windows et `mkvmerge` sinon (PATH). Chemins longs : même seuil 250 que `Get-MkvInterleaveRepairCommand`.

## EXAMPLES

### Example 1: Simuler le remplacement d'un fichier

Intention : voir la cible `ShouldProcess` sans remux ni `Move-Item`.

```powershell
Invoke-MkvRepair -Path 'D:\Media\film.mkv' -WhatIf
```

### Example 2: Réparer un MKV in-place

Intention : remux puis écraser l'original. Un code `mkvmerge` `>= 2` conserve le source, restitue les diagnostics natifs dans l'ordre, puis lève ; un code `1` conserve aussi le source, via un warning PowerShell, sans exception.

```powershell
Invoke-MkvRepair -Path 'D:\Media\film.mkv'
```

### Example 3: Réparer tous les MKV d'un arbre

Intention : scan récursif `*.mkv`, ignore lecture seule, file figée avant le premier remux.

```powershell
Invoke-MkvRepair -Folder 'D:\Media' -Recurse
```

### Example 4: Poursuivre le scan après une erreur réelle

Intention : afficher l'échec du fichier courant (diagnostics `mkvmerge` compris), laisser ce fichier intact, et continuer avec les suivants. Sans ce commutateur, le premier véritable échec arrête le lot.

```powershell
Invoke-MkvRepair -Folder 'D:\Media' -Recurse -ContinueOnError
```

### Example 5: Récupérer le FileInfo après remplacement

Intention : enchaîner sur le fichier déjà réécrit. Sans effet sous `-WhatIf`.

```powershell
Invoke-MkvRepair -Path 'D:\Media\film.mkv' -PassThru
```

## PARAMETERS

### -Confirm

Demande confirmation avant chaque remplacement `ShouldProcess` (ConfirmImpact Medium).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ContinueOnError

En mode `-Folder` uniquement : après un échec propre à un fichier, écrit l'erreur dans le flux d'erreur, conserve le source intact, et poursuit avec le fichier suivant. Absent / faux par défaut : le premier véritable échec arrête le lot. N'a aucun effet sur un warning `mkvmerge` (code `1`), qui continue déjà. Ne remplace pas `-ErrorAction`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Folder
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ExtendedPathThreshold

Longueur à partir de laquelle les chemins outils reçoivent le préfixe Windows étendu. Défaut : 250.

```yaml
Type: System.Int32
DefaultValue: 250
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FileReadyTimeoutSeconds

Délai d'attente (secondes) pour que la sortie mkvmerge soit disponible en exclusivité, et pour les retries de `Move-Item`. Défaut : 30.

```yaml
Type: System.Int32
DefaultValue: 30
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Folder

Dossier à scanner (`*.mkv`). Exclut `-Path`. Doit exister.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Folder
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MkvMerge

Chemin ou nom de `mkvmerge`. Défaut : `mkvmerge.exe` sous Windows, `mkvmerge` sinon (PATH).

```yaml
Type: System.String
DefaultValue: mkvmerge.exe (Windows) / mkvmerge
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Émet le `FileInfo` du fichier source après un remplacement réussi. Absent sous `-WhatIf`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

Fichier Matroska à réparer et remplacer. Obligatoire en jeu File, position 0. Exclut `-Folder`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: File
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Recurse

Parcourt les sous-dossiers. Uniquement avec `-Folder`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Folder
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RetryIntervalMilliseconds

Intervalle (ms) entre tentatives d'ouverture exclusive / `Move-Item`. Défaut : 200.

```yaml
Type: System.Int32
DefaultValue: 200
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WhatIf

Pas de remux ni de remplacement du source.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

Cette commande prend en charge les paramètres communs : -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction et -WarningVariable. Pour plus d'informations, voir
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

Sans `-PassThru` : rien. Avec `-PassThru` : `System.IO.FileInfo` du source remplacé (un par fichier effectivement remplacé). Aucun objet pour un fichier abandonné sur warning `mkvmerge` (code `1`) ni pour un fichier en erreur.

## NOTES

Prérequis : PowerShell 7.6+, `mkvmerge` (MKVToolNix).

Ne pas faire : combiner `-Path` et `-Folder` ; passer `-ContinueOnError` avec `-Path` ; prendre `-Folder` pour traiter un `.mp4` ; compter sur le skip lecture seule en mode `-Path` ; prendre cette commande pour un réencodage ffmpeg (`Invoke-ReencodeMedia`) ; interpréter un warning `mkvmerge` (code `1`) comme un remplacement réussi ; interpréter `-ContinueOnError` comme un silence des erreurs.

## RELATED LINKS

- [Get-MkvInterleaveRepairCommand]()
- [Invoke-ReencodeMedia]()
