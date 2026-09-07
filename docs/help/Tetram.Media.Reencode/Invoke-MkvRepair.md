---
document type: cmdlet
external help file: Tetram.Media.Reencode-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Reencode
ms.date: 09/08/2026
PlatyPS schema version: 2024-05-01
title: Invoke-MkvRepair
---

# Invoke-MkvRepair

## SYNOPSIS

Répare l'interleaving d'un MKV (ou des `*.mkv` d'un dossier) et remplace le fichier source in-place.

## SYNTAX

### File (Default)

```
Invoke-MkvRepair [-Path] <string> [-MkvMerge <string>] [-ExtendedPathThreshold <int>]
 [-FileReadyTimeoutSeconds <int>] [-RetryIntervalMilliseconds <int>] [-PassThru] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### Folder

```
Invoke-MkvRepair -Folder <string> [-Recurse] [-MkvMerge <string>] [-ExtendedPathThreshold <int>]
 [-FileReadyTimeoutSeconds <int>] [-RetryIntervalMilliseconds <int>] [-PassThru] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Importer `.\Tetram.Media.Reencode` (PowerShell 7+). Remux `mkvmerge` à readers A/V séparés (même construction que `Get-MkvInterleaveRepairCommand`), puis `Move-Item` de la sortie temporaire sur le source. Ce n'est pas un réencodage : les flux conservés sont recopiés. Jeux exclusifs : `-Path` (un fichier) ou `-Folder` (scan `*.mkv`).

Effet disque :

- `-WhatIf` : pas de remux, pas de remplacement. `ConfirmImpact` Medium : pas de prompt sauf `-Confirm`.
- run réel : `mkvmerge` écrit un voisin `.repaired.mkv` (ou le `-OutputPath` interne équivalent), attend que le fichier soit disponible en exclusivité, puis déplace ce temporaire par-dessus le source. Si `mkvmerge` rend un code non nul, ou si la sortie n'existe pas, le source est conservé et une exception est levée.

Mode `-Folder` : uniquement des fichiers `*.mkv` non lecture seule. La liste est **entièrement matérialisée** avant la première réparation : un `.repaired.mkv` créé pendant le run n'est pas ajouté à la file. `-Recurse` descend dans les sous-dossiers. Un dossier absent lève ; un dossier sans candidat retourne sans erreur. Le mode `-Path` ne saute pas un fichier lecture seule : ce filtre n'existe que pour `-Folder`.

`-PassThru` émet le `FileInfo` du source après remplacement. Sans ce commutateur : aucun objet pipeline. Une barre de progression s'affiche en mode dossier.

`mkvmerge` : `-MkvMerge`, défaut `mkvmerge.exe` (PATH). Chemins longs : même seuil 160 que `Get-MkvInterleaveRepairCommand`.

## EXAMPLES

### Example 1: Simuler le remplacement d'un fichier

Intention : voir la cible `ShouldProcess` sans remux ni `Move-Item`.

```powershell
Invoke-MkvRepair -Path 'D:\Media\film.mkv' -WhatIf
```

### Example 2: Réparer un MKV in-place

Intention : remux puis écraser l'original. L'échec mkvmerge conserve le source.

```powershell
Invoke-MkvRepair -Path 'D:\Media\film.mkv'
```

### Example 3: Réparer tous les MKV d'un arbre

Intention : scan récursif `*.mkv`, ignore lecture seule, file figée avant le premier remux.

```powershell
Invoke-MkvRepair -Folder 'D:\Media' -Recurse
```

### Example 4: Récupérer le FileInfo après remplacement

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

### -ExtendedPathThreshold

Longueur à partir de laquelle les chemins outils reçoivent le préfixe Windows étendu. Défaut : 160.

```yaml
Type: System.Int32
DefaultValue: 160
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

Chemin ou nom de `mkvmerge`. Défaut : `mkvmerge.exe` (PATH).

```yaml
Type: System.String
DefaultValue: mkvmerge.exe
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

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

Sans `-PassThru` : rien. Avec `-PassThru` : `System.IO.FileInfo` du source remplacé (un par fichier traité).

## NOTES

Prérequis : PowerShell 7+, `mkvmerge` (MKVToolNix).

Ne pas faire : combiner `-Path` et `-Folder` ; prendre `-Folder` pour traiter un `.mp4` ; compter sur le skip lecture seule en mode `-Path` ; prendre cette commande pour un réencodage ffmpeg (`Invoke-ReencodeMedia`).

## RELATED LINKS

- [Get-MkvInterleaveRepairCommand]()
- [Invoke-ReencodeMedia]()
