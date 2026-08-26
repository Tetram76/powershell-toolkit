---
document type: cmdlet
external help file: Tetram.Media.Translation-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Translation
ms.date: 08/26/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-FrenchSubtitle
---

# ConvertTo-FrenchSubtitle

## SYNOPSIS

Produit un fichier de sous-titres français à partir d'un sous-titre source et d'une transcription Whisper, via Gemini.

## SYNTAX

### __AllParameterSets

```
ConvertTo-FrenchSubtitle -SubtitlePath <string> -TranscriptPath <string> [-OutputPath <string>]
 [-Model <string>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Importer `.\Tetram.Media.Translation` (PowerShell 7+). La commande envoie à Gemini le fichier de sous-titres source et une transcription Whisper de la piste japonaise.

Si la réponse Gemini est acceptée (candidat présent, `finishReason` STOP, texte non vide), elle est conservée telle quelle dans un fichier `.raw` dérivé de la sortie (`episode.fr.ass` → `episode.fr.raw.ass`). Aucun `.raw` n'est créé si Gemini n'a pas de candidat, si `finishReason` n'est pas STOP, ou si le texte est vide. Le fichier final n'est écrit que si la reconstruction technique depuis la source est sûre. Un candidat accepté peut donc être conservé même lorsque le fichier final ne peut pas être reconstruit (warning, pas d'exception de fusion).

Sans `-OutputPath`, le fichier final est écrit à côté de la source, avec le suffixe `.fr` avant l'extension (`episode.ass` → `episode.fr.ass`). Si le fichier final ou le `.raw` correspondant existe déjà, la commande échoue sans écraser et sans appeler Gemini.

Prérequis : variable d'environnement `GEMINI_API_KEY`. Modèle par défaut : `gemini-3.6-flash`.

Aucun objet n'est émis dans le pipeline. Le chemin du fichier produit est affiché sur la console.

## EXAMPLES

### Example 1: Traduire un couple sous-titre + transcription

Le fichier traduit est écrit à côté de la source, avec le suffixe `.fr`.

```powershell
ConvertTo-FrenchSubtitle -SubtitlePath 'D:\Media\episode.ass' -TranscriptPath 'D:\Media\episode.ja.txt'
```

### Example 2: Choisir le fichier de sortie

Échoue si `D:\Media\episode.fr.ass` existe déjà.

```powershell
ConvertTo-FrenchSubtitle -SubtitlePath 'D:\Media\episode.ass' -TranscriptPath 'D:\Media\episode.ja.txt' -OutputPath 'D:\Media\episode.fr.ass'
```

### Example 3: Choisir le modèle Gemini

```powershell
ConvertTo-FrenchSubtitle -SubtitlePath 'D:\Media\episode.ass' -TranscriptPath 'D:\Media\episode.ja.txt' -Model 'gemini-3.6-flash'
```

## PARAMETERS

### -Model

Identifiant du modèle Gemini. Défaut : `gemini-3.6-flash`.

```yaml
Type: System.String
DefaultValue: gemini-3.6-flash
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

Chemin du fichier traduit. S'il est omis : même dossier que `-SubtitlePath`, basename + `.fr` + extension source. Échoue si le fichier existe déjà.

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

### -SubtitlePath

Fichier de sous-titres source. Doit exister et être un fichier.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TranscriptPath

Fichier de transcription Whisper. Doit exister et être un fichier.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
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

Prérequis : PowerShell 7+ et `GEMINI_API_KEY`. Les chemins `-SubtitlePath` et `-TranscriptPath` sont littéraux (pas de jokers). La commande lève une exception si la clé est absente, si la sortie ou le `.raw` existe déjà, ou si la réponse Gemini est inutilisable (aucun candidat, `finishReason` autre que STOP, texte vide) : dans ces cas aucun `.raw` n'est écrit. Un échec de reconstruction technique conserve le `.raw` et émet un warning.

## RELATED LINKS

- [Get-MediaTranscript]()
