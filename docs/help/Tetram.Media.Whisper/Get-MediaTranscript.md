---
document type: cmdlet
external help file: Tetram.Media.Whisper-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Whisper
ms.date: 08/15/2026
PlatyPS schema version: 2024-05-01
title: Get-MediaTranscript
---

# Get-MediaTranscript

## SYNOPSIS

Transcrit les pistes audio de fichiers médias avec faster-whisper.

## SYNTAX

### Path (Default)

```
Get-MediaTranscript [-Path] <string[]> [-Format <string[]>] [-Model <string>]
 [-UseLanguage <string>] [-WhisperPath <string>] [-WhatIf] [-Confirm]
```

### Mixed

```
Get-MediaTranscript -Path <string[]> -LiteralPath <string[]> [-Format <string[]>] [-Model <string>]
 [-UseLanguage <string>] [-WhisperPath <string>] [-WhatIf] [-Confirm]
```

### LiteralPath

```
Get-MediaTranscript -LiteralPath <string[]> [-Format <string[]>] [-Model <string>]
 [-UseLanguage <string>] [-WhisperPath <string>] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Le transcript est écrit à côté du fichier source, au(x) format(s) demandé(s), le code de langue étant ajouté au nom du fichier produit. Toutes les sources d'un appel sont traitées par une **seule** invocation du binaire, le chargement du modèle étant le coût dominant. La commande ne valide aucun chemin : c'est whisper qui signale une source introuvable ou sans média.

## EXAMPLES

### Example 1: Transcrire un fichier

```powershell
Get-MediaTranscript -Path 'D:\Films\film.mkv'
```

### Example 2: Transcrire plusieurs fichiers dans un seul appel

```powershell
Get-MediaTranscript -Path 'D:\Films\a.mkv', 'D:\Films\b.mkv'
```

### Example 3: Transmettre un masque à whisper

```powershell
Get-MediaTranscript -Path 'D:\Films\*.mkv'
```

### Example 4: Transcrire un dossier

```powershell
Get-MediaTranscript -Path 'D:\Films'
```

### Example 5: Fichier dont le nom contient des crochets

```powershell
Get-MediaTranscript -LiteralPath 'D:\Films\film[1].mkv'
```

### Example 6: Combiner un masque et un chemin littéral

```powershell
Get-MediaTranscript -Path 'D:\Films\*.mkv' -LiteralPath 'D:\Films\film[1].mkv'
```

### Example 7: Produire plusieurs formats

```powershell
Get-MediaTranscript -Path 'D:\Films\film.mkv' -Format srt, vtt
```

### Example 8: Choisir le modèle

```powershell
Get-MediaTranscript -Path 'D:\Films\film.mkv' -Model large-v3-turbo
```

### Example 9: Forcer la langue

```powershell
Get-MediaTranscript -Path 'D:\Films\film.mkv' -UseLanguage fr
```

### Example 10: Afficher la ligne de commande sans lancer le binaire

```powershell
Get-MediaTranscript -Path 'D:\Films\film.mkv' -WhatIf
```

## PARAMETERS

### -Confirm

La ligne de commande s'affiche, le binaire ne tourne pas.

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

### -Format

Formats de sortie, défaut `srt`.

```yaml
Type: System.String[]
DefaultValue: srt
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
AcceptedValues:
- json
- lrc
- txt
- text
- vtt
- srt
- tsv
- all
HelpMessage: ''
```

### -LiteralPath

Sources prises au pied de la lettre, jamais résolues, même si elles contiennent `*`.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- PSPath
ParameterSets:
- Name: Mixed
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: LiteralPath
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Model

Modèle whisper, défaut `large-v2`.

```yaml
Type: System.String
DefaultValue: large-v2
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
AcceptedValues:
- large-v2
- large-v3-turbo
- large-v3
HelpMessage: ''
```

### -Path

Sources. Les masques `*` et `?` sont transmis tels quels à whisper, qui globalise lui-même ; les entrées contenant des crochets, un échappement backtick ou un PSDrive nommé sont résolues par PowerShell au préalable. Une entrée à crochets sans correspondance ne produit aucune source.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: true
Aliases: []
ParameterSets:
- Name: Mixed
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Path
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UseLanguage

Code ISO de la langue. Absent, whisper la détecte.

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

### -WhatIf

La ligne de commande s'affiche, le binaire ne tourne pas.

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

### -WhisperPath

Chemin d'un `faster-whisper-xxl.exe` hors du dossier du module.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

Une source peut être un fichier média, un masque ou un dossier ; une source d'extension `.txt`, `.m3u`, `.m3u8` ou `.lst` est lue par le binaire comme une **liste de médias** et n'est pas transcrite ; la distribution Purfview doit être posée dans `Purfview-Whisper-Faster`, dossier non versionné ; le modèle est téléchargé au premier usage, le premier appel est donc long ; seul le premier flux audio est transcrit ; jamais de traduction ; une réexécution réécrit les transcripts existants ; la commande n'accepte pas d'entrée pipeline, un masque sur `-Path` remplaçant `Get-ChildItem | ...`.

## RELATED LINKS
