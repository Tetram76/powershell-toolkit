---
document type: cmdlet
external help file: Tetram.Media.Reencode-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Reencode
ms.date: 09/04/2026
PlatyPS schema version: 2024-05-01
title: Invoke-ReencodeMedia
---

# Invoke-ReencodeMedia

## SYNOPSIS

Remplace in-place des fichiers média : réencodage HEVC/AV1 vers MKV, `-NoTranscode` (filtrage sans transcodage) ou contrôle ffmpeg (`-CheckOnly`, pas un dry-run).

## SYNTAX

### ReencodeFromPath (Default)

```
Invoke-ReencodeMedia [[-Path] <string[]>] [-Recurse] [-Sort <string>] [-ScanReadOnlyDirectory]
 [-InputMasks <string[]>] [-VideoCodec <string>] [-ClearStreamsTitle] [-ForceRecodeVideo]
 [-AllowVideoCodecUpgrade] [-Quality <string>] [-Upscale <string>] [-UpscaleWidth <int>]
 [-UpscaleFit <string>] [-Deinterlace] [-AllowSubTitlesConversion] [-AllowIntegrityMismatch]
 [-SubTitlesToKeep <string[]>] [-TempPath <string>] [-FFToolsBase <string>] [-FFMPEGPath <string>]
 [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### ReencodeFromFile

```
Invoke-ReencodeMedia -ListFile <string> [-UpdateList] [-Sort <string>] [-ScanReadOnlyDirectory]
 [-InputMasks <string[]>] [-VideoCodec <string>] [-ClearStreamsTitle] [-ForceRecodeVideo]
 [-AllowVideoCodecUpgrade] [-Quality <string>] [-Upscale <string>] [-UpscaleWidth <int>]
 [-UpscaleFit <string>] [-Deinterlace] [-AllowSubTitlesConversion] [-AllowIntegrityMismatch]
 [-SubTitlesToKeep <string[]>] [-TempPath <string>] [-FFToolsBase <string>] [-FFMPEGPath <string>]
 [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### NoTranscodeFromPath

```
Invoke-ReencodeMedia [[-Path] <string[]>] -NoTranscode [-Recurse] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-ClearStreamsTitle]
 [-SubTitlesToKeep <string[]>] [-TempPath <string>] [-FFToolsBase <string>] [-FFMPEGPath <string>]
 [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### NoTranscodeFromFile

```
Invoke-ReencodeMedia -ListFile <string> -NoTranscode [-Recurse] [-UpdateList] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-ClearStreamsTitle]
 [-SubTitlesToKeep <string[]>] [-TempPath <string>] [-FFToolsBase <string>] [-FFMPEGPath <string>]
 [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### CheckFromPath

```
Invoke-ReencodeMedia [[-Path] <string[]>] -CheckOnly [-Recurse] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-TempPath <string>] [-FFToolsBase <string>]
 [-FFMPEGPath <string>] [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### CheckFromFile

```
Invoke-ReencodeMedia -ListFile <string> -CheckOnly [-UpdateList] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-TempPath <string>] [-FFToolsBase <string>]
 [-FFMPEGPath <string>] [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Point d'entrée unique du module. Importer `.\Tetram.Media.Reencode` (PowerShell 7+), puis appeler cette commande. Aucun objet n'est renvoyé : lire la console et, en cas d'échec, `reencode-errors.log` dans le répertoire courant.

Choisir exactement un mode (jeux de paramètres exclusifs) :

- réencodage normal (ni `-NoTranscode` ni `-CheckOnly`) : filtrage des flux indésirables et politiques de transformation habituelles ; le conteneur final est toujours `.mkv`.
- `-NoTranscode` : même filtrage, métadonnées et attachments, mais aucun flux conservé n'est transcodé ; l'extension source est conservée. Ce n'est pas un « garder tous les flux » ni une immuabilité du fichier : des pistes peuvent être retirées, des métadonnées corrigées, et le fichier peut ne pas être réécrit s'il n'y a rien à faire.
- `-CheckOnly` : intermédiaire entre `-WhatIf` et un réencodage. Vérifie que ffmpeg peut décoder (muxer `null`) sans réencoder, remuxer ni remplacer le fichier média. Ce n'est pas un dry-run : les horodatages NFO (`premiered`) sont posés sur le fichier et éventuellement les dossiers, comme sur un run normal.

Choisir exactement une source : `-Path` (défaut `.`) ou `-ListFile` (fichier texte, une entrée par ligne). Un chemin préfixé par `+` est parcouru récursivement même sans `-Recurse`.

Effet disque :

- `-WhatIf` : pas de réécriture média, pas de timestamps NFO. N'est pas un silence disque total : une exception fichier (catch de `Invoke-ReencodeFile`) append `reencode-errors.log` dans le répertoire courant, sans `ShouldProcess`.
- `-CheckOnly` (sans `-WhatIf`) : pas de temporaire ffmpeg, pas de `Move-Item` / `Rename-Item` sur le média. Les timestamps NFO (`premiered`) sont malgré tout appliqués. Un échec ffmpeg est journalisé dans `reencode-errors.log`.
- réencodage / `-NoTranscode` : ffmpeg écrit un temporaire sous `-TempPath`, puis `Move-Item` écrase le fichier source, puis un `Rename-Item` change l'extension si besoin (réencodage vers `.mkv`). Les horodatages du fichier sont restaurés. Des dossiers voisins peuvent voir leurs dates corrigées via NFO (`premiered`). En réencodage, un écart de durée au-delà de max(1 s, 0,5 %) rejette la sortie et conserve l'original par défaut ; avec `-AllowIntegrityMismatch`, le même écart reste détecté et signalé, mais devient un avertissement non bloquant et la sortie est acceptée. `-NoTranscode` n'exécute pas ce contrôle de durée.

Fichiers / dossiers non traités : `Plex Versions`, `.deletedByTMM`, nom contenant `-trailer.`, fichiers lecture seule, absence de durée ffprobe (sauf `-ForceRecodeVideo` / `-NoTranscode`), destination déjà existante si l'extension change, rien à faire (déjà conforme), `.mp4` avec sous-titres sans `-AllowSubTitlesConversion` en réencodage normal. `-ScanReadOnlyDirectory` ne concerne que la descente dans des répertoires lecture seule, pas les fichiers.

ffmpeg/ffprobe : `-FFMPEGPath` / `-FFPROBEPath`, sinon dossier `Tetram.Media.FFmpeg\ffmpeg\` (build ffmpeg >= 9.0.1), sinon PATH. Ne pas utiliser `-FFToolsBase` pour pointer les binaires : le paramètre est validé mais ignoré.

Pour simuler sans toucher au média ni aux dates : `-WhatIf` (pas `-CheckOnly`). Une exception peut quand même écrire `reencode-errors.log`. `ConfirmImpact` est Medium : pas de prompt sauf `-Confirm`.

## EXAMPLES

### Example 1: Dry-run avant un réencodage récursif

Intention : voir ce qui serait fait, sans modifier le média ni les timestamps. Une exception peut quand même créer `reencode-errors.log`. Toujours préférer cet appel avant un run réel.

```powershell
Invoke-ReencodeMedia -Path 'D:\Media' -Recurse -WhatIf
```

### Example 2: Réencodage par défaut (HEVC, sortie .mkv)

Intention : normaliser un arbre vers MKV/HEVC qualité Medium. Les originaux sont remplacés in-place.

```powershell
Invoke-ReencodeMedia -Path 'D:\Media' -Recurse
```

### Example 3: Vérifier qu'ffmpeg peut décoder, sans retravailler le média

Intention : diagnostiquer des fichiers illisibles sans réencoder ni remuxer. Ce n'est pas un dry-run : les dates NFO (`premiered`) peuvent être écrites. Pour ne pas toucher au média ni aux dates : `-WhatIf`. Les échecs (ffmpeg ou exception) vont dans `reencode-errors.log`, y compris sous `-WhatIf`.

```powershell
Invoke-ReencodeMedia -Path 'D:\Media' -Recurse -CheckOnly
```

### Example 4: Filtrer des pistes sans transcodage

Intention : retirer sous-titres / vignettes et nettoyer les métadonnées en copiant les flux conservés. Conserve l'extension source. Ignoré si aucune opération n'est nécessaire.

```powershell
Invoke-ReencodeMedia -Path 'D:\Media' -Recurse -NoTranscode
```

### Example 5: File d'attente + upgrade HEVC vers AV1

Intention : traiter une liste, retirer chaque ligne après coup, réencoder les HEVC `main*` en AV1. `-ListFile` exclut `-Path`.

```powershell
Invoke-ReencodeMedia -ListFile 'D:\todo.txt' -UpdateList -VideoCodec AV1 -AllowVideoCodecUpgrade
```

### Example 6: Un seul sous-arbre récursif sans `-Recurse` global

Intention : récursion ciblée. Le `+` s'applique à cette entrée seulement.

```powershell
Invoke-ReencodeMedia -Path '+D:\Media\Shows'
```

### Example 7: Accepter explicitement un écart d'intégrité de durée

Intention : continuer un réencodage malgré un mismatch de durée déjà détecté. Ce n'est pas le comportement recommandé par défaut : le contrôle s'exécute toujours, l'écart est signalé en warning, et la sortie remplace l'original. Sans effet en `-NoTranscode` ni `-CheckOnly`.

```powershell
Invoke-ReencodeMedia -ListFile 'D:\todo.txt' -AllowIntegrityMismatch
```

## PARAMETERS

### -AllowIntegrityMismatch

En réencodage réel uniquement. Par défaut, un écart de durée supérieur à la
tolérance d'intégrité (max 1 s ou 0,5 %) rejette la sortie et conserve
l'original. Avec ce commutateur, le même écart reste détecté et affiché, mais
devient un avertissement non bloquant : le fichier de sortie est accepté.
Le commutateur ne désactive pas le contrôle. Il n'existe pas en `-NoTranscode`
ni en `-CheckOnly`. Le cas « durée incomparable » (`unknown`) était déjà
accepté et n'est pas la raison d'être de ce paramètre.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -AllowSubTitlesConversion

Autorise la conversion des sous-titres vers `mov_text` lors d'une sortie `.mp4`.
Sans ce commutateur, un fichier `.mp4` qui contient des sous-titres (ou un
sidecar `.ass`) est ignoré plutôt que de perdre ou de mal convertir les pistes.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -AllowVideoCodecUpgrade

Lorsque `-VideoCodec AV1`, force le réencodage des pistes HEVC au profil `main*`
vers AV1 au lieu de les copier. Sans effet en `-CheckOnly`. Absent du mode
`-NoTranscode`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CheckOnly

Intermédiaire entre `-WhatIf` et un réencodage : décode avec ffmpeg vers le
muxer `null` pour vérifier que le fichier est lisible. Ne réencode pas, ne
remuxe pas, ne remplace pas le fichier média. Ce n'est pas un dry-run : les
horodatages NFO (`premiered`) sont quand même posés. `-WhatIf` évite média et
dates, pas le journal d'erreur. Jeu de paramètres exclusif.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: CheckFromFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromPath
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ClearStreamsTitle

Efface les titres de pistes (`title`) dans les métadonnées de flux de la sortie.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
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

Demande confirmation avant chaque action `ShouldProcess` (ConfirmImpact Medium).

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

### -Deinterlace

Applique le filtre `yadif` aux pistes vidéo conservées. Absent du mode `-NoTranscode`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FFMPEGPath

Chemin explicite vers `ffmpeg`. Sinon découverte via `Tetram.Media.FFmpeg` puis PATH.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FFPROBEPath

Chemin explicite vers `ffprobe`. Sinon découverte via `Tetram.Media.FFmpeg` puis PATH.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FFToolsBase

Validé mais ignoré pour la résolution des binaires (utiliser `-FFMPEGPath` / `-FFPROBEPath`).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ForceRecodeVideo

Force le réencodage vidéo même si le codec source est déjà HEVC `main*`, AV1 ou
VC1. Sans ce commutateur, ces pistes sont copiées (sauf upgrade AV1). Absent du
mode `-NoTranscode`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
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

Masques passés à `Get-ChildItem -Include`. Défaut : `*.mkv`, `*.mp4`, `*.avi`,
`*.wmv`, `*.mov`, `*.flv`, `*.mpeg`, `*.mpg`, `*.heic`, `*.ts`, `*.webm`.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ListFile

Fichier texte (une entrée par ligne) listant les médias à traiter. Exclut `-Path`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoTranscode

Filtrage, métadonnées et attachments sans transcoder les flux conservés.
Conserve l'extension source. Jeu de paramètres exclusif.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

Chemins fichiers ou dossiers à traiter. Défaut `.`. Préfixe `+` = récursion pour cette entrée.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromPath
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromPath
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Quality

Politique de qualité audio/vidéo (`Low` / `Medium` / `High`). Réservée au réencodage
normal (absente de `-NoTranscode` et `-CheckOnly`). Hors MP4, High et Medium ciblent
EAC3 ; Low cible Opus, y compris lorsque la vidéo finale est AV1. La contrainte
AV1 + AAC → EAC3 ne s'applique qu'en High et Medium.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Recurse

Parcourt les sous-dossiers. Sur `-ListFile`, disponible uniquement avec `-NoTranscode`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ScanReadOnlyDirectory

Autorise la descente récursive dans des répertoires marqués en lecture seule.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Sort

Ordre de traitement des fichiers découverts (`NewestFirst`, `OldestFirst`, `SmallerFirst`, `LargerFirst`).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SubTitlesToKeep

Langues de sous-titres à conserver (avec `un` / `und`). Les autres pistes sous-titres sont retirées.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TempPath

Dossier des fichiers temporaires ffmpeg.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: NoTranscodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UpdateList

Réécrit `-ListFile` après chaque ligne traitée (sous `ShouldProcess`).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: NoTranscodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CheckFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Upscale

Hauteur cible d'agrandissement (`720p` / `1080p` / `2160p` / `4320p`). Absent du mode `-NoTranscode`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UpscaleFit

Cible `LargeurxHauteur` pour la décision d'agrandissement. Absent du mode `-NoTranscode`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UpscaleWidth

Largeur cible complémentaire à `-Upscale`. Absent du mode `-NoTranscode`.

```yaml
Type: System.Int32
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -VideoCodec

Codec vidéo cible `HEVC` ou `AV1`. Absent du mode `-NoTranscode`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ReencodeFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ReencodeFromPath
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

Pas de réécriture du média ni des timestamps NFO. Une exception fichier peut
quand même append `reencode-errors.log` (hors `ShouldProcess`).

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

Prérequis : PowerShell 7+, module chargé depuis son `.psd1`. ffmpeg/ffprobe >= 9.0.1.

Audio hors MP4 : High/Medium → EAC3 ; Low → Opus (y compris avec une vidéo finale AV1).
AV1 + AAC n'impose EAC3 qu'en High et Medium.

Ne pas faire : passer `-FFToolsBase` pour changer les binaires ; combiner `-Path` et `-ListFile` ; combiner les modes `-CheckOnly` / `-NoTranscode` ; prendre `-CheckOnly` pour un dry-run ; prendre `-WhatIf` pour « aucune écriture disque » (`reencode-errors.log` reste possible) ; attendre un code de retour par fichier (la commande continue).

Skip « No reencoding needed » / « No stream filtering needed » = déjà conforme, ce n'est pas une erreur.

`-UpdateList` réécrit `-ListFile` après chaque ligne (sous ShouldProcess).

## RELATED LINKS

- [Test-MediaSimilarity]()
- [Remove-EmptyDirs]()
