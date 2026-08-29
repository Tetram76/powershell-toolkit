---
document type: cmdlet
external help file: Tetram.Media.Transcript-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Transcript
ms.date: 08/28/2026
PlatyPS schema version: 2024-05-01
title: Get-MediaTranscript
---

# Get-MediaTranscript

## SYNOPSIS

Transcrit une piste audio d'un fichier média.

## SYNTAX

```
Get-MediaTranscript [-LiteralPath] <string> [-AudioTrack <int>] [-Model <string[]>]
 [-UseLanguage <string>] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

`Get-MediaTranscript` traite exactement un média et une piste audio. Chaque valeur de `-Model` déclenche une invocation distincte du moteur associé à ce modèle. Les modèles Faster-Whisper produisent un JSON Tetram à côté du média. `reazon-k2-v2` exécute deux observations VAD (Silero puis TEN) sur le même WAV temporaire et publie donc deux sidecars. L'appelant choisit un ou plusieurs modèles ; il ne choisit pas le moteur ni le VAD. Les artefacts natifs temporaires sont le JSON Faster-Whisper et le WAV préparé pour Sherpa-ONNX : ils sont écrits sous le répertoire temporaire système, lus, normalisés, puis supprimés. Le stdout Sherpa (lignes `start -- end: text`) est capturé, pas écrit sur disque. `-LiteralPath` doit désigner un fichier unique existant : un masque ou un dossier est refusé par l'orchestrateur. Un fichier-liste existant (`.lst`, `.m3u`, …) est transmis au backend : Faster-Whisper / Purfview le refuse. Les caractères spéciaux PowerShell font partie du nom. La commande n'émet rien dans le pipeline.

Le fichier durable Faster-Whisper/Kotoba suit `<media-base>.track <trackid>.<langue>.<model>.json` (piste puis langue). Exemple : `Episode.track 2.ja.large-v3.json`. Pour Reazon : `Episode.track 1.ja.reazon-k2-v2.silero.json` et `Episode.track 1.ja.reazon-k2-v2.ten.json`. Dans le JSON, `model` reste `reazon-k2-v2` ; `vad` vaut `silero` ou `ten`. Les formats de présentation (SRT, VTT, etc.) seront produits plus tard par une autre commande à partir de ce JSON.

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

### Example 8: Enchaîner plusieurs modèles

```powershell
Get-MediaTranscript -LiteralPath 'D:\Videos\Episode.mkv' -Model large-v3, kotoba-v2 -UseLanguage ja
```

Produit `Episode.track 1.ja.large-v3.json` puis `Episode.track 1.ja.kotoba-v2.json`, chacune via sa propre invocation.

### Example 9: Mélanger Faster-Whisper et Sherpa-ONNX

```powershell
Get-MediaTranscript -LiteralPath 'D:\Videos\Episode.mkv' -Model large-v3, reazon-k2-v2 -UseLanguage ja
```

Faster-Whisper produit `Episode.track 1.ja.large-v3.json`. Reazon produit `Episode.track 1.ja.reazon-k2-v2.silero.json` et `Episode.track 1.ja.reazon-k2-v2.ten.json` (`model` = `reazon-k2-v2`, `vad` distinct).

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

La ligne de commande s'affiche ; une confirmation est demandée avant d'exécuter le binaire du moteur (il tourne si on confirme).

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

Chemin littéral d'un fichier média unique existant. Les caractères spéciaux PowerShell (`*`, `?`, `[`) font partie du nom ; ils ne sont pas interprétés comme un masque. Un masque ou un dossier est refusé par l'orchestrateur. Un fichier-liste existant est transmis au backend (Purfview le refuse).

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

Modèle de transcription, défaut `large-v2`. Plusieurs valeurs : une invocation par modèle, éventuellement sur des moteurs différents. `large-v2`, `large-v3`, `large-v3-turbo` et `kotoba-v2` passent par Faster-Whisper / Purfview et produisent un sidecar chacun. `reazon-k2-v2` est un modèle japonais provisoire exécuté localement via Sherpa-ONNX ; une valeur produit deux sidecars (Silero et TEN) distingués par `vad`, sans nouveau paramètre public. Il sert à valider le routage, pas un choix ASR définitif. Les poids Sherpa sont attendus dans `SherpaOnnx/models/<nom>/` (pour `reazon-k2-v2` : `SherpaOnnx/models/reazon-k2-v2/`). Les binaires et poids doivent déjà être présents localement : la commande ne télécharge rien. `kotoba-v2` doit être installé séparément dans la distribution Purfview. `-UseLanguage ja` est accepté pour `reazon-k2-v2` sans forcer une langue : le moteur n'expose pas de paramètre de langue. Une autre langue est refusée par le backend Sherpa.

```yaml
Type: System.String[]
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
- reazon-k2-v2
HelpMessage: ''
```

### -UseLanguage

Code ISO de la langue. Absent, Faster-Whisper la détecte ; pour `reazon-k2-v2` le japonais est fourni par le modèle.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

Une invocation traite un seul fichier média et une seule piste audio (`-AudioTrack`, défaut 1) ; `-Model` accepte plusieurs valeurs ; Faster-Whisper/Kotoba produisent un sidecar par modèle, `reazon-k2-v2` en produit deux (`.silero` / `.ten`) à partir d'un WAV temporaire commun ; les distributions Purfview et Sherpa-ONNX se posent respectivement dans `Purfview-Whisper-Faster` et `SherpaOnnx`, dossiers non versionnés hors README ; jamais de téléchargement automatique ; jamais de traduction ; la seule sortie durable est le JSON Tetram ; une réexécution réécrit ces sidecars ; la commande n'accepte pas d'entrée pipeline.

## RELATED LINKS
