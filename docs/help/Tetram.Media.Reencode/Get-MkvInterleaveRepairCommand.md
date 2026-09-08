---
document type: cmdlet
external help file: Tetram.Media.Reencode-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Reencode
ms.date: 09/08/2026
PlatyPS schema version: 2024-05-01
title: Get-MkvInterleaveRepairCommand
---

# Get-MkvInterleaveRepairCommand

## SYNOPSIS

Construit la ligne `mkvmerge` qui répare l'interleaving d'un MKV, sans remplacer le fichier.

## SYNTAX

### __AllParameterSets

```
Get-MkvInterleaveRepairCommand [-Path] <string> [-OutputPath <string>] [-MkvMerge <string>]
 [-ExtendedPathThreshold <int>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Importer `.\Tetram.Media.Reencode` (PowerShell 7.6+). `-Path` est un fichier existant, Matroska reconnu par `mkvmerge -J`. Cette commande **n'exécute pas** le remux : elle identifie le fichier (`mkvmerge -J`) puis retourne un objet décrivant l'exécutable, les arguments, la ligne PowerShell copiable et les chemins (logiques vs outils). Pour remplacer in-place, utiliser `Invoke-MkvRepair`.

Sans `-OutputPath`, la sortie est un voisin `{basename}.repaired.mkv` (le suffixe `.mkv` source, casse indifférente, est remplacé ; sinon `.repaired.mkv` est concaténé, ex. `clip.mp4.repaired.mkv`). La sortie ne peut pas être le fichier source.

Les pistes audio/vidéo sont chacune lues par un reader `mkvmerge` distinct (carrier = première piste A/V, les autres A/V en readers suivants avec `-S -B -M --no-chapters --no-global-tags`). Les pistes non A/V (sous-titres, etc.) restent rattachées au carrier. L'ordre original des pistes est restauré via `--track-order`. Les propriétés de segment présentes (UID, titre, timestamp scale, date UTC, liens previous/next) sont recopiées.

Chemins Windows longs : au-delà de `-ExtendedPathThreshold` (défaut 250), les chemins **outils** (`ToolInputPath`, `ToolOutputPath`, et `-MkvMerge` s'il est encheminé) reçoivent le préfixe `\\?\` / `\\?\UNC\`. `InputPath` / `OutputPath` restent les chemins logiques.

Échecs (exception) : fichier absent, sortie = source, conteneur non reconnu/non supporté, type autre que Matroska, aucune piste, aucune piste A/V, date Matroska illisible, `mkvmerge -J` code >= 2.

## EXAMPLES

### Example 1: Inspecter la ligne mkvmerge avant un remux

Intention : voir readers, `--track-order` et le voisin `.repaired.mkv` sans toucher au fichier. `mkvmerge -J` est quand même exécuté.

```powershell
Get-MkvInterleaveRepairCommand -Path 'D:\Media\film.mkv' | Select-Object CommandLine, OutputPath
```

### Example 2: Forcer un fichier de sortie

Intention : écrire ailleurs que le voisin par défaut. Doit être distinct du source.

```powershell
Get-MkvInterleaveRepairCommand -Path 'D:\Media\film.mkv' -OutputPath 'D:\Temp\film.repaired.mkv'
```

## PARAMETERS

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

### -MkvMerge

Chemin ou nom de `mkvmerge`. Défaut : `mkvmerge.exe` sous Windows, `mkvmerge` sinon (PATH). Un chemin encheminé est soumis au même seuil de chemin étendu.

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

### -OutputPath

Fichier MKV cible du remux. Distinct du source. Absent : voisin `{basename}.repaired.mkv`.

```yaml
Type: System.String
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

Fichier Matroska à identifier. Obligatoire, position 0.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
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

PSCustomObject : `InputPath`, `OutputPath`, `ToolInputPath`, `ToolOutputPath`, `Executable`, `Arguments`, `CommandLine`, `Tracks` (`id`, `type`, `codec`).

## NOTES

Prérequis : PowerShell 7.6+, `mkvmerge` (MKVToolNix). Identification seulement : pas de `ShouldProcess`, pas de remplacement du source.

Ne pas faire : prendre cette commande pour un remux ; pointer `-OutputPath` sur le source ; l'utiliser sur un non-Matroska.

## RELATED LINKS

- [Invoke-MkvRepair]()
- [Invoke-ReencodeMedia]()
