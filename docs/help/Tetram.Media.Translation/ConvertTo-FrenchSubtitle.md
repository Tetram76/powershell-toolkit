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

Produit un fichier de sous-titres français à partir d'un sous-titre source et d'une transcription Whisper, via Gemini ou Ollama.

## SYNTAX

### __AllParameterSets

```
ConvertTo-FrenchSubtitle -SubtitlePath <string> -TranscriptPath <string> [-OutputPath <string>]
 [-Provider {Gemini | Ollama}] [-Model <string>] [-AllowModelDownload] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Importer `.\Tetram.Media.Translation` (PowerShell 7+). La commande parse la source principale en cues canoniques (`cueId`, `start`, `end`, `text`) et envoie ce JSON au modèle, avec la transcription Whisper telle quelle. Le modèle retourne une proposition JSON `{ cueId, text }`.

Le fournisseur se choisit avec `-Provider` (`Gemini` ou `Ollama`). Sans `-Provider`, Gemini est utilisé.

Si la réponse du modèle est acceptée au niveau transport, elle est conservée telle quelle dans un fichier `.raw.json` dérivé de la sortie (`episode.fr.ass` → `episode.fr.raw.json`). Aucun `.raw.json` n'est créé si le transport échoue (Gemini : aucun candidat, `finishReason` autre que STOP, texte vide ; Ollama : réponse absente, génération inachevée, contenu vide). Le fichier final est reconstruit depuis la source principale (identifiants et timestamps natifs, champs techniques ASS) en remplaçant uniquement le texte via `cueId`. Un candidat incomplet ou invalide (cue manquant, dupliqué, hors plage, JSON illisible, texte vidé) est conservé sans produire de final (warning, pas d'exception de reconstruction).

Sans `-OutputPath`, le fichier final est écrit à côté de la source, avec le suffixe `.fr` avant l'extension (`episode.ass` → `episode.fr.ass`). Si le fichier final ou le `.raw.json` correspondant existe déjà, la commande échoue sans écraser et sans appeler le modèle.

### Gemini

Provider par défaut. Modèle par défaut : `gemini-3.6-flash`. Prérequis : variable d'environnement `GEMINI_API_KEY`.

### Ollama

Ollama doit être installé et démarré. L'API attendue est `http://localhost:11434`. `-Model` est obligatoire. `GEMINI_API_KEY` n'est pas utilisée. `-AllowModelDownload` autorise le téléchargement du modèle s'il n'est pas déjà installé.

Installation Windows :

```powershell
winget install --id Ollama.Ollama -e
```

Téléchargement officiel : <https://ollama.com/download/windows>

Téléchargement manuel d'un modèle :

```powershell
ollama pull <model>
```

Aucun objet n'est émis dans le pipeline. Le chemin du fichier produit est affiché sur la console.

## EXAMPLES

### Example 1: Traduire un couple sous-titre + transcription

Le fichier traduit est écrit à côté de la source, avec le suffixe `.fr`. Gemini est utilisé.

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

### Example 4: Traduire via Ollama

Ollama doit déjà tourner sur `http://localhost:11434`. `-Model` est obligatoire. Aucun modèle Ollama n'est choisi par défaut.

```powershell
ConvertTo-FrenchSubtitle -SubtitlePath 'D:\Media\episode.ass' -TranscriptPath 'D:\Media\episode.ja.txt' -Provider Ollama -Model llama3.2
```

### Example 5: Autoriser le téléchargement d'un modèle Ollama absent

Si le modèle n'est pas installé localement, la commande appelle l'API Ollama pour le télécharger, puis lance la génération.

```powershell
ConvertTo-FrenchSubtitle -SubtitlePath 'D:\Media\episode.ass' -TranscriptPath 'D:\Media\episode.ja.txt' -Provider Ollama -Model llama3.2 -AllowModelDownload
```

## PARAMETERS

### -AllowModelDownload

Autorise le téléchargement du modèle Ollama demandé s'il n'est pas déjà installé. Applicable uniquement avec `-Provider Ollama`. Sans ce switch, un modèle absent provoque une erreur indiquant `ollama pull <model>`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
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

### -Model

Identifiant du modèle. Avec Gemini, défaut interne `gemini-3.6-flash` si le paramètre est omis. Avec `-Provider Ollama`, le paramètre est obligatoire ; aucun modèle Ollama n'est choisi par défaut.

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

### -Provider

Fournisseur LLM. `Gemini` (défaut) ou `Ollama` (API locale `http://localhost:11434`).

```yaml
Type: System.String
DefaultValue: Gemini
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
- Gemini
- Ollama
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

Prérequis : PowerShell 7+. Les chemins `-SubtitlePath` et `-TranscriptPath` sont littéraux (pas de jokers). La commande lève une exception si la sortie ou le `.raw.json` existe déjà, ou si la réponse du modèle est inutilisable au niveau transport : dans ces cas aucun `.raw.json` n'est écrit. Un échec de reconstruction (JSON incomplet ou invalide, contrat ASS `{...}` / `\N`) conserve le `.raw.json` et émet un warning.

Gemini : `GEMINI_API_KEY` obligatoire ; modèle par défaut `gemini-3.6-flash`.

Ollama : doit être installé et démarré (`winget install --id Ollama.Ollama -e`, <https://ollama.com/download/windows>, `ollama serve`). `-Model` obligatoire. `GEMINI_API_KEY` inutile. `-AllowModelDownload` autorise le téléchargement d'un modèle absent (`ollama pull <model>` en alternative manuelle). `-AllowModelDownload` est refusé avec Gemini.

## RELATED LINKS

- [Get-MediaTranscript]()
