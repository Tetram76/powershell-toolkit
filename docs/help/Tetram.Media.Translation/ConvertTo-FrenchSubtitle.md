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

Produit un fichier de sous-titres français à partir d'une source principale et de sources secondaires facultatives, via Gemini ou Ollama.

## SYNTAX

### __AllParameterSets

```
ConvertTo-FrenchSubtitle -SubtitlePath <string> [-SecondarySourcePath <string[]>] [-OutputPath <string>]
 [-Provider {Gemini | Ollama}] [-Model <string>] [-AllowModelDownload] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Importer `.\Tetram.Media.Translation` (PowerShell 7+). `-SubtitlePath` définit toujours la structure finale (cues, `cueId`, timestamps, reconstruction). Le modèle reçoit un gabarit technique `cueId`/`start`/`end` sans texte ; le texte de `-SubtitlePath` est envoyé séparément comme source linguistique structurante (`start`/`end`/`text`, sans `cueId`). `-SecondarySourcePath` accepte 0..N sources linguistiques facultatives : sous-titres SRT/ASS/SSA (JSON `start`/`end`/`text`, sans `cueId`) ou transcriptions Whisper JSON (JSON compact par segments après validation de structure minimale). Aucune source linguistique n'a de priorité fixe. Le modèle retourne une proposition JSON `{ cueId, text }`.

Le fournisseur se choisit avec `-Provider` (`Gemini` ou `Ollama`). Sans `-Provider`, Gemini est utilisé.

Si la réponse du modèle est acceptée au niveau transport, elle est conservée telle quelle dans un fichier `.raw.json` dérivé de la sortie (`episode.fr.ass` → `episode.fr.raw.json`). Aucun `.raw.json` n'est créé si le transport échoue (Gemini : aucun candidat, `finishReason` autre que STOP, texte vide ; Ollama : réponse absente, génération inachevée, contenu vide). Le fichier final est reconstruit depuis la source principale (identifiants et timestamps natifs, champs techniques ASS) en remplaçant uniquement le texte via `cueId`. Un candidat incomplet ou invalide (cue manquant, dupliqué, hors plage, JSON illisible, texte vidé) est conservé sans produire de final (warning, pas d'exception de reconstruction).

Les principales étapes longues sont journalisées : téléchargement éventuel du modèle Ollama, invocation du provider et reconstruction du sous-titre.

Sans `-OutputPath`, le fichier final est écrit à côté de la source, avec le suffixe `.fr` avant l'extension (`episode.ass` → `episode.fr.ass`). Si le fichier final ou le `.raw.json` correspondant existe déjà, la commande échoue sans écraser et sans appeler le modèle.

### Model spec (`-Model`)

`-Model` accepte un suffixe d'options terminal :

```text
<model>
<model>[thinking]
<model>[thinking=<level>]
```

Les options sont retirées du nom avant tout appel fournisseur ou téléchargement. `fast` n'existe pas aujourd'hui. `thinking=<level>` est actuellement pris en charge uniquement par Gemini. Les niveaux syntaxiques Gemini sont `minimal`, `low`, `medium` et `high` ; les niveaux réellement supportés dépendent du modèle Gemini. Ollama n'utilise `thinking` que comme booléen dans l'abstraction actuelle.

| Provider | Model spec | Comportement |
| --- | --- | --- |
| Gemini | `gemini-3.6-flash` | `thinkingLevel=low` |
| Gemini | `gemini-3.6-flash[thinking]` | `thinkingLevel=medium` |
| Gemini | `gemini-3.6-flash[thinking=high]` | `thinkingLevel=high` |
| Ollama | `qwen3.5:9b` | `think=false` |
| Ollama | `qwen3.5:9b[thinking]` | `think=true` |

Sans option, Gemini utilise `thinkingLevel=low` (défaut du projet, distinct du défaut Google du modèle).

### Gemini

Provider par défaut. Modèle par défaut : `gemini-3.6-flash`. Prérequis : variable d'environnement `GEMINI_API_KEY`.

#### Modèles Gemini intéressants à tester

Liste informative : elle ne change pas le modèle par défaut. La disponibilité, les quotas et les niveaux de thinking peuvent évoluer. Références : <https://ai.google.dev/gemini-api/docs/models>, <https://ai.google.dev/gemini-api/docs/thinking>.

##### `gemini-3.6-flash`

Modèle par défaut / baseline actuelle. Bon équilibre vitesse / qualité, structured outputs, grand contexte, thinking configurable. La documentation Google indique actuellement `minimal`, `low`, `medium`, `high`.

```powershell
-Model 'gemini-3.6-flash'
-Model 'gemini-3.6-flash[thinking]'
-Model 'gemini-3.6-flash[thinking=high]'
```

##### `gemini-3.7-flash`

Candidat à benchmarker pour privilégier la qualité / capacité, sans changer la baseline actuelle. La documentation Google actuelle annonce `low`, `medium`, `high`.

```powershell
-Model 'gemini-3.7-flash'
-Model 'gemini-3.7-flash[thinking]'
-Model 'gemini-3.7-flash[thinking=high]'
```

##### `gemini-3.5-flash`

Alternative stable à comparer si utile. Candidate de benchmark, sans affirmation de supériorité pour la traduction.

##### `gemini-3.5-flash-lite`

Potentiellement intéressante pour la latence, le coût et le haut débit sur des lots importants, à benchmarker séparément pour la qualité linguistique.

### Ollama

Ollama doit être installé et démarré. L'API attendue est `http://localhost:11434`. Modèle par défaut : `qwen3.5:9b`. `GEMINI_API_KEY` n'est pas utilisée. `-AllowModelDownload` autorise le téléchargement du modèle s'il n'est pas déjà installé.

#### Modèles Ollama intéressants à tester

Cette liste est une shortlist de benchmark, pas une validation de qualité pour le projet. La qualité japonais -> français doit être mesurée sur les épisodes de référence. Catalogue : <https://ollama.com/library>.

Les tailles indiquées correspondent approximativement au fichier modèle publié par Ollama. La RAM/VRAM réellement nécessaire dépend du modèle, de la quantification, du contexte et de l'offload CPU/GPU.

##### `qwen3.5:9b`

Modèle par défaut Ollama / premier candidat raisonnable pour une machine locale de capacité intermédiaire. Environ 6.6 GB de fichier modèle, contexte 256K, thinking disponible, forte couverture multilingue annoncée par la famille. Référence : <https://ollama.com/library/qwen3.5>.

```powershell
-Model 'qwen3.5:9b'
-Model 'qwen3.5:9b[thinking]'
```

##### `qwen3.5:27b`

Environ 17 GB, contexte 256K, thinking disponible. Candidat qualité plus lourd que 9b.

```powershell
-Model 'qwen3.5:27b'
-Model 'qwen3.5:27b[thinking]'
```

##### `qwen3.8:27b`

Environ 18 GB, contexte 256K, thinking disponible, modèle très récent. Candidat à benchmarker si le matériel le permet. Les réglages spécifiques comme `reasoning_effort` ne sont pas mappés aujourd'hui. Référence : <https://ollama.com/library/qwen3.8>.

```powershell
-Model 'qwen3.8:27b'
-Model 'qwen3.8:27b[thinking]'
```

##### `gemma3:12b`

Environ 8.1 GB, contexte 128K, plus de 140 langues annoncées. Alternative de famille différente à Qwen, intéressante pour comparer la qualité multilingue. Cette famille n'utilise pas l'option `[thinking]` dans l'abstraction actuelle. Référence : <https://ollama.com/library/gemma3>.

```powershell
-Model 'gemma3:12b'
```

##### `gemma3:27b`

Environ 17 GB, contexte 128K, plus de 140 langues annoncées. Alternative multilingue plus lourde.

```powershell
-Model 'gemma3:27b'
```

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

### Example 1: Traduire une source principale avec des sources secondaires

Le fichier traduit est écrit à côté de la source, avec le suffixe `.fr`. Gemini est utilisé. `-SecondarySourcePath` est facultatif.

```powershell
ConvertTo-FrenchSubtitle `
    -SubtitlePath 'D:\Media\episode.en.ass' `
    -SecondarySourcePath @(
        'D:\Media\episode.alt.srt',
        'D:\Media\episode.whisper-large-v3.json',
        'D:\Media\episode.other.ass'
    )
```

### Example 2: Choisir le fichier de sortie

Échoue si `D:\Media\episode.fr.ass` existe déjà.

```powershell
ConvertTo-FrenchSubtitle -SubtitlePath 'D:\Media\episode.ass' -OutputPath 'D:\Media\episode.fr.ass'
```

### Example 3: Choisir le modèle Gemini

```powershell
ConvertTo-FrenchSubtitle -SubtitlePath 'D:\Media\episode.ass' -Model 'gemini-3.6-flash'
```

### Example 3b: Activer le thinking Gemini

```powershell
ConvertTo-FrenchSubtitle -SubtitlePath 'D:\Media\episode.ass' -Model 'gemini-3.6-flash[thinking=high]'
```

### Example 4: Traduire via Ollama

Ollama doit déjà tourner sur `http://localhost:11434`. Sans `-Model`, `qwen3.5:9b` est utilisé.

```powershell
ConvertTo-FrenchSubtitle -SubtitlePath 'D:\Media\episode.ass' -Provider Ollama
```

### Example 5: Autoriser le téléchargement d'un modèle Ollama absent

Si le modèle n'est pas installé localement, la commande appelle l'API Ollama pour le télécharger, puis lance la génération.

```powershell
ConvertTo-FrenchSubtitle -SubtitlePath 'D:\Media\episode.ass' -Provider Ollama -Model llama3.2 -AllowModelDownload
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

Identifiant du modèle, éventuellement suivi d'un suffixe d'options terminal : `<model>`, `<model>[thinking]`, `<model>[thinking=<level>]`. Si le paramètre est omis : `gemini-3.6-flash` (thinking `low`) avec Gemini, `qwen3.5:9b` (`think=false`) avec `-Provider Ollama`. Les options sont retirées du nom avant l'appel fournisseur.

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

Source obligatoire. Définit la structure finale (ordre des cues, `cueId`, timestamps, reconstruction). Le texte est envoyé au modèle comme source linguistique structurante, séparément du gabarit technique. Doit exister et être un fichier.

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

### -SecondarySourcePath

0..N sources linguistiques facultatives : sous-titres SRT/ASS/SSA ou transcriptions Whisper JSON. L'ordre fourni ne représente aucune priorité linguistique.

```yaml
Type: System.String[]
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

Prérequis : PowerShell 7+. Les chemins `-SubtitlePath` et `-SecondarySourcePath` sont littéraux (pas de jokers). `-SubtitlePath` est obligatoire. `-SecondarySourcePath` accepte 0..N fichiers. La commande lève une exception si la sortie ou le `.raw.json` existe déjà, ou si la réponse du modèle est inutilisable au niveau transport : dans ces cas aucun `.raw.json` n'est écrit. Un échec de reconstruction (JSON incomplet ou invalide, contrat ASS `{...}` / `\N`) conserve le `.raw.json` et émet un warning.

Gemini : `GEMINI_API_KEY` obligatoire ; modèle par défaut `gemini-3.6-flash` ; thinking projet `low` sans option, `medium` avec `[thinking]`, niveau explicite avec `[thinking=<level>]` (`minimal`, `low`, `medium`, `high`).

Ollama : doit être installé et démarré (`winget install --id Ollama.Ollama -e`, <https://ollama.com/download/windows>, `ollama serve`). Modèle par défaut `qwen3.5:9b`. `GEMINI_API_KEY` inutile. `-AllowModelDownload` autorise le téléchargement d'un modèle absent (`ollama pull <model>` en alternative manuelle, sans le suffixe `[thinking]`). `-AllowModelDownload` est refusé avec Gemini. `[thinking]` envoie `think=true` ; sans option, `think=false` est envoyé explicitement. `[thinking=<level>]` n'est pas supporté pour Ollama.

## RELATED LINKS

- [Get-MediaTranscript]()
