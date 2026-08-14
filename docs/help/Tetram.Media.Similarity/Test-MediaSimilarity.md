---
document type: cmdlet
external help file: Tetram.Media.Similarity-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Similarity
ms.date: 08/14/2026
PlatyPS schema version: 2024-05-01
title: Test-MediaSimilarity
---

# Test-MediaSimilarity

## SYNOPSIS

Indexe des empreintes MPEG-7 (`.sig`) à côté des vidéos, puis signale les paires visuellement proches.

## SYNTAX

### __AllParameterSets

```
Test-MediaSimilarity [-Path] <string> [[-InputMasks] <string[]>] [[-ConfidenceThreshold] <int>]
 [-Recurse] [-UpdateOnly] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Importer `Tetram.Media.Similarity.psd1` (PowerShell 7+). `-Path` est obligatoire.

Deux phases :

1. Indexation : pour chaque fichier matching `-InputMasks`, calcule un hash rapide et maintient `Nom.hash.sig` dans le même dossier. Hash différent = anciennes `.sig` du même basename supprimées, nouvelle empreinte générée (ffmpeg `signature`).
2. Comparaison : paires de signatures, score FFmpeg `signature=detectmode=full`. Un match est retenu si `confidence >= -ConfidenceThreshold` (défaut 90).

`-UpdateOnly` s'arrête après la phase 1. La phase 2 exige au moins deux signatures valides.

Effet disque : crée/remplace/supprime des `.sig` à côté des médias. Ne modifie pas les vidéos. `-WhatIf` couvre création et suppression des signatures.

Résultat : objets pipeline `{ SourceFile, Matches: [{ TargetFile, Confidence }] }` seulement s'il y a au moins une paire. Sinon rien dans le pipeline (un résumé console est tout de même écrit). ffmpeg introuvable : log d'erreur, pas d'exception, rien émis.

Contraintes d'appel : `Get-ChildItem -Include` n'énumère les fichiers d'un dossier que si `-Recurse` est passé ou si `-Path` désigne déjà un contenu (ex. `D:\Media\*`). Sans cela, la commande peut ne trouver aucun fichier. Le bloc `process` écrase `$files`/`$results` : ne pas piper plusieurs chemins en attendant une fusion.

ffmpeg : `Tetram.Media.FFmpeg\ffmpeg\` (build >= 9.0.1) puis PATH. `ConfirmImpact` non élevé : `-Confirm` seulement si demandé.

## EXAMPLES

### Example 1: Comparer un arbre (cas d'usage principal)

Intention : trouver des doublons visuels. `-Recurse` est requis pour énumérer le contenu d'un dossier.

```powershell
Test-MediaSimilarity -Path 'D:\Media' -Recurse
```

Les paires s'affichent sur la console et sont renvoyées dans le pipeline.

### Example 2: Rafraîchir les empreintes sans comparer

Intention : générer/nettoyer les `.sig` seulement. Aucun objet pipeline.

```powershell
Test-MediaSimilarity -Path 'D:\Media' -Recurse -UpdateOnly
```

### Example 3: Seuil plus strict

Intention : moins de faux positifs. Score entier 0-100.

```powershell
Test-MediaSimilarity -Path 'D:\Media' -Recurse -ConfidenceThreshold 95
```

### Example 4: Dry-run des écritures `.sig`

Intention : voir quelles signatures seraient créées ou supprimées, sans toucher au disque.

```powershell
Test-MediaSimilarity -Path 'D:\Media' -Recurse -UpdateOnly -WhatIf
```

## PARAMETERS

### -ConfidenceThreshold

Score minimal (0-100, issu de `signature=detectmode=full`) pour retenir une
paire. Valeur par défaut : 90.
Score minimal (0-100, issu de `signature=detectmode=full`) pour retenir une
paire.
Valeur par défaut : 90.

```yaml
Type: System.Int32
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Confirm

Prompts you for confirmation before running the cmdlet.

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

### -InputMasks

Masques de fichiers passés à `Get-ChildItem -Include`. Valeur par défaut :
`*.mkv`, `*.mp4`, `*.avi`, `*.wmv`, `*.mov`, `*.flv`, `*.mpeg`, `*.mpg`,
`*.heic`, `*.ts`, `*.webm`.
Masques de fichiers passés à `Get-ChildItem -Include`.
Valeur par défaut :
`*.mkv`, `*.mp4`, `*.avi`, `*.wmv`, `*.mov`, `*.flv`, `*.mpeg`, `*.mpg`,
`*.heic`, `*.ts`, `*.webm`.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

Dossier (ou chemin résolu par `Resolve-Path`) contenant les fichiers à indexer.
Accepte l'entrée par pipeline. Paramètre obligatoire.
Dossier (ou chemin résolu par `Resolve-Path`) contenant les fichiers à indexer.
Accepte l'entrée par pipeline.
Paramètre obligatoire.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Recurse

Inclut les sous-dossiers. Sur un chemin dossier sans joker, `-Recurse` (ou un
`-Path` du type `D:\Media\*`) est nécessaire pour que `-InputMasks` trouve des
fichiers.
Inclut les sous-dossiers.
Sur un chemin dossier sans joker, `-Recurse` (ou un
`-Path` du type `D:\Media\*`) est nécessaire pour que `-InputMasks` trouve des
fichiers.

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

### -UpdateOnly

Génère ou rafraîchit les signatures, puis s'arrête sans comparaison.

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

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

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

### System.String

Une valeur de `-Path` (ByValue). Plusieurs objets pipeline ne sont pas fusionnés : seule la dernière itération alimente le `end`.

## OUTPUTS

### System.Object

Présent seulement s'il existe au moins une similarité. Sinon `$null` / rien (y compris `-UpdateOnly`, moins de deux `.sig`, ffmpeg absent).

Propriétés : `SourceFile` (string), `Matches` (collection de `TargetFile`, `Confidence`).

## NOTES

Prérequis : PowerShell 7+, ffmpeg >= 9.0.1. Comparaison O(n²) sur le nombre de signatures : coûteux sur de gros corpus.

Ne pas faire : attendre une exception si ffmpeg manque ; interpréter l'absence d'objets comme un échec (souvent « 0 match » ou indexation seule) ; omettre `-Recurse` sur un chemin dossier sans joker.

## RELATED LINKS

- [Invoke-ReencodeMedia]()
