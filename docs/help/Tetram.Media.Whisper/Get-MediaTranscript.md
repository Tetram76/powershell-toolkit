---
document type: cmdlet
external help file: Tetram.Media.Whisper-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Whisper
ms.date: 08/28/2026
PlatyPS schema version: 2024-05-01
title: Get-MediaTranscript
---

# Get-MediaTranscript

## SYNOPSIS

Transcrit les pistes audio de fichiers médias avec faster-whisper.

## SYNTAX

### Path (Default)

```
Get-MediaTranscript [-Path] <string[]> [-Model <string>]
 [-UseLanguage <string>] [-WhisperPath <string>] [-WhatIf] [-Confirm]
```

### Mixed

```
Get-MediaTranscript -Path <string[]> -LiteralPath <string[]> [-Model <string>]
 [-UseLanguage <string>] [-WhisperPath <string>] [-WhatIf] [-Confirm]
```

### LiteralPath

```
Get-MediaTranscript -LiteralPath <string[]> [-Model <string>]
 [-UseLanguage <string>] [-WhisperPath <string>] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

`Get-MediaTranscript` produit uniquement un JSON Tetram canonique à côté du média source. Le JSON natif Faster-Whisper est un artefact temporaire : il est écrit dans un dossier unique sous le répertoire temporaire système, lu, normalisé, puis ce dossier est supprimé. Toutes les sources d'un appel sont traitées par une **seule** invocation du binaire, le chargement du modèle étant le coût dominant. La commande ne valide aucun chemin : c'est whisper qui signale une source introuvable ou sans média. La commande n'émet rien dans le pipeline.

Le fichier durable suit la convention `<media-base>.track <trackid>.<langue>.<model>.json` (piste puis langue). Exemple : `Episode.track 1.ja.large-v3.json`. Les formats de présentation (SRT, VTT, etc.) seront produits plus tard par une autre commande à partir de ce JSON.

## EXAMPLES

### Example 1: Transcrire un fichier

```powershell
Get-MediaTranscript -Model large-v3 -UseLanguage ja 'D:\Videos\Episode.mkv'
```

Produit `D:\Videos\Episode.track 1.ja.large-v3.json`.

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

### Example 7: Choisir le modèle

```powershell
Get-MediaTranscript -Path 'D:\Films\film.mkv' -Model large-v3-turbo
```

### Example 8: Forcer la langue

```powershell
Get-MediaTranscript -Path 'D:\Films\film.mkv' -UseLanguage fr
```

### Example 9: Afficher la ligne de commande sans lancer le binaire

```powershell
Get-MediaTranscript -Path 'D:\Films\film.mkv' -WhatIf
```

### Example 10: Transcrire avec kotoba-v2

```powershell
Get-MediaTranscript -Path 'D:\Films\film.mkv' -Model kotoba-v2 -UseLanguage ja
```

## PARAMETERS

### -Confirm

La ligne de commande s'affiche ; une confirmation est demandée avant d'exécuter faster-whisper-xxl (le binaire tourne si on confirme).

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

Modèle Faster-Whisper, défaut `large-v2`. `kotoba-v2` est un modèle japonais custom pour Faster-Whisper/Purfview : il doit être installé séparément dans la distribution Purfview (le module ne le télécharge pas). `Get-MediaTranscript` lui applique automatiquement les options d'inférence compatibles. `-UseLanguage ja` reste recommandé pour ce scénario.

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
- kotoba-v2
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

La ligne de commande s'affiche, le binaire ne tourne pas (dry-run).

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

Une source peut être un fichier média, un masque ou un dossier ; une source d'extension `.txt`, `.m3u`, `.m3u8` ou `.lst` est lue par le binaire comme une **liste de médias** et n'est pas transcrite ; la distribution Purfview doit être posée dans `Purfview-Whisper-Faster`, dossier non versionné ; les modèles Whisper standard sont téléchargés au premier usage (premier appel long) ; `kotoba-v2` doit déjà être présent dans cette distribution ; seul le premier flux audio est transcrit (`audioTrack` = 1) ; jamais de traduction ; la seule sortie durable est le JSON Tetram ; une réexécution réécrit ce sidecar ; la commande n'accepte pas d'entrée pipeline, un masque sur `-Path` remplaçant `Get-ChildItem | ...`.

## RELATED LINKS
