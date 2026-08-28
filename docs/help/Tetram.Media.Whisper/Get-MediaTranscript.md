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

Transcrit une piste audio d'un fichier média avec faster-whisper.

## SYNTAX

```
Get-MediaTranscript [-LiteralPath] <string> [-AudioTrack <int>] [-Model <string>]
 [-UseLanguage <string>] [-WhisperPath <string>] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

`Get-MediaTranscript` traite exactement un média, une piste audio et un modèle par invocation. Elle produit uniquement un JSON Tetram canonique à côté du média. Le JSON natif Faster-Whisper est un artefact temporaire : il est écrit dans un dossier unique sous le répertoire temporaire système, lu, normalisé, puis ce dossier est supprimé. Le chemin passé à `-LiteralPath` est pris au pied de la lettre : ni masque, ni dossier à parcourir, ni fichier-liste. La commande n'émet rien dans le pipeline.

Le fichier durable suit la convention `<media-base>.track <trackid>.<langue>.<model>.json` (piste puis langue). Exemple : `Episode.track 2.ja.large-v3.json`. Les formats de présentation (SRT, VTT, etc.) seront produits plus tard par une autre commande à partir de ce JSON.

## EXAMPLES

### Example 1: Transcrire un fichier

```powershell
Get-MediaTranscript -Model large-v3 -UseLanguage ja 'D:\Videos\Episode.mkv'
```

Traite la piste audio 1 et produit `D:\Videos\Episode.track 1.ja.large-v3.json`.

### Example 2: Choisir une autre piste audio

```powershell
Get-MediaTranscript `
    -LiteralPath 'D:\Videos\Episode.mkv' `
    -AudioTrack 2 `
    -Model large-v3 `
    -UseLanguage ja
```

Produit `D:\Videos\Episode.track 2.ja.large-v3.json`.

### Example 3: Fichier dont le nom contient des crochets

```powershell
Get-MediaTranscript -LiteralPath 'D:\Films\film[1].mkv'
```

Le chemin est traité littéralement : `film[1].mkv` désigne ce fichier, pas un masque.

### Example 4: Choisir le modèle

```powershell
Get-MediaTranscript -LiteralPath 'D:\Films\film.mkv' -Model large-v3-turbo
```

### Example 5: Forcer la langue

```powershell
Get-MediaTranscript -LiteralPath 'D:\Films\film.mkv' -UseLanguage fr
```

### Example 6: Afficher la ligne de commande sans lancer le binaire

```powershell
Get-MediaTranscript -LiteralPath 'D:\Films\film.mkv' -WhatIf
```

### Example 7: Transcrire avec kotoba-v2

```powershell
Get-MediaTranscript -LiteralPath 'D:\Films\film.mkv' -Model kotoba-v2 -UseLanguage ja
```

## PARAMETERS

### -AudioTrack

Index 1-based de la piste audio à transcrire. Défaut `1`. Une invocation ne traite qu'une seule piste.

```yaml
Type: System.Int32
DefaultValue: 1
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

Chemin littéral d'un seul fichier média. Les caractères spéciaux PowerShell (`*`, `?`, `[`) font partie du nom ; ils ne sont pas interprétés comme un masque.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases:
- PSPath
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

Une invocation traite un seul fichier média et une seule piste audio (`-AudioTrack`, défaut 1) ; la distribution Purfview doit être posée dans `Purfview-Whisper-Faster`, dossier non versionné ; les modèles Whisper standard sont téléchargés au premier usage (premier appel long) ; `kotoba-v2` doit déjà être présent dans cette distribution ; jamais de traduction ; la seule sortie durable est le JSON Tetram ; une réexécution réécrit ce sidecar ; la commande n'accepte pas d'entrée pipeline.

## RELATED LINKS
