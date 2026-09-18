---
document type: cmdlet
external help file: Tetram.Media.Mkv-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Mkv
ms.date: 09/05/2026
PlatyPS schema version: 2024-05-01
title: Invoke-MkvRemux
---

# Invoke-MkvRemux

## SYNOPSIS

Remplace in-place des fichiers média : réencodage HEVC/AV1 vers MKV, `-NoTranscode` (filtrage sans transcodage) ou contrôle ffmpeg (`-CheckOnly`, pas un dry-run).

## SYNTAX

### ReencodeFromPath (Par défaut)

```
Invoke-MkvRemux [[-Path] <string[]>] [-Recurse] [-Sort <string>] [-ScanReadOnlyDirectory]
 [-InputMasks <string[]>] [-VideoCodec <string>] [-ClearStreamsTitle] [-ForceRecodeVideo]
 [-AllowVideoCodecUpgrade] [-Quality <string>] [-Upscale <string>] [-UpscaleWidth <int>]
 [-UpscaleFit <string>] [-Deinterlace] [-AllowSubTitlesConversion] [-AllowIntegrityMismatch]
 [-SubTitlesToKeep <string[]>] [-RemoveAttachments] [-TempPath <string>] [-FFToolsBase <string>]
 [-FFMPEGPath <string>] [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### ReencodeFromFile

```
Invoke-MkvRemux -ListFile <string> [-UpdateList] [-Sort <string>] [-ScanReadOnlyDirectory]
 [-InputMasks <string[]>] [-VideoCodec <string>] [-ClearStreamsTitle] [-ForceRecodeVideo]
 [-AllowVideoCodecUpgrade] [-Quality <string>] [-Upscale <string>] [-UpscaleWidth <int>]
 [-UpscaleFit <string>] [-Deinterlace] [-AllowSubTitlesConversion] [-AllowIntegrityMismatch]
 [-SubTitlesToKeep <string[]>] [-RemoveAttachments] [-TempPath <string>] [-FFToolsBase <string>]
 [-FFMPEGPath <string>] [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### NoTranscodeFromPath

```
Invoke-MkvRemux [[-Path] <string[]>] -NoTranscode [-Recurse] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-ClearStreamsTitle]
 [-SubTitlesToKeep <string[]>] [-RemoveAttachments] [-TempPath <string>] [-FFToolsBase <string>]
 [-FFMPEGPath <string>] [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### NoTranscodeFromFile

```
Invoke-MkvRemux -ListFile <string> -NoTranscode [-Recurse] [-UpdateList] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-ClearStreamsTitle]
 [-SubTitlesToKeep <string[]>] [-RemoveAttachments] [-TempPath <string>] [-FFToolsBase <string>]
 [-FFMPEGPath <string>] [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### CheckFromPath

```
Invoke-MkvRemux [[-Path] <string[]>] -CheckOnly [-Recurse] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-TempPath <string>] [-FFToolsBase <string>]
 [-FFMPEGPath <string>] [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### CheckFromFile

```
Invoke-MkvRemux -ListFile <string> -CheckOnly [-UpdateList] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-TempPath <string>] [-FFToolsBase <string>]
 [-FFMPEGPath <string>] [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Point d'entrée unique du module. Importer `.\Tetram.Media.Mkv` (PowerShell 7.6+), puis appeler cette commande. Aucun objet n'est renvoyé : lire la console et, en cas d'échec, `reencode-errors.log` dans le répertoire courant.

Choisir exactement un mode (jeux de paramètres exclusifs) :

- réencodage normal (ni `-NoTranscode` ni `-CheckOnly`) : filtrage des flux indésirables (sous-titres, vignettes, et `-RemoveAttachments` si demandé) et politiques de transformation habituelles ; le conteneur final est toujours `.mkv`.
- `-NoTranscode` : même filtrage (sous-titres, vignettes, et `-RemoveAttachments` si demandé), métadonnées et attachments, mais aucun flux conservé n'est transcodé ; l'extension source est conservée. Ce n'est pas un « garder tous les flux » ni une immuabilité du fichier : des pistes peuvent être retirées, des métadonnées corrigées, et le fichier peut ne pas être réécrit s'il n'y a rien à faire.
- `-CheckOnly` : intermédiaire entre `-WhatIf` et un réencodage. Vérifie que ffmpeg peut décoder (muxer `null`) sans réencoder, remuxer ni remplacer le fichier média. Ce n'est pas un dry-run : les horodatages NFO (`premiered`) sont posés sur le fichier et éventuellement les dossiers, comme sur un run normal.

Choisir exactement une source : `-Path` (défaut `.`) ou `-ListFile` (fichier texte, une entrée par ligne). Un chemin préfixé par `+` est parcouru récursivement même sans `-Recurse`.

Effet disque :

- `-WhatIf` : pas de réécriture média, pas de timestamps NFO. N'est pas un silence disque total : une exception fichier (catch de `Invoke-ReencodeFile`) append `reencode-errors.log` dans le répertoire courant, sans `ShouldProcess`.
- `-CheckOnly` (sans `-WhatIf`) : pas de temporaire ffmpeg, pas de `Move-Item` / `Rename-Item` sur le média. Les timestamps NFO (`premiered`) sont malgré tout appliqués. Un échec ffmpeg est journalisé dans `reencode-errors.log`.
- réencodage / `-NoTranscode` : ffmpeg écrit un temporaire sous `-TempPath`, puis `Move-Item` écrase le fichier source, puis un `Rename-Item` change l'extension si besoin (réencodage vers `.mkv`). Les horodatages du fichier sont restaurés. Des dossiers voisins peuvent voir leurs dates corrigées via NFO (`premiered`). En réencodage, le fichier contrôlé en sortie est toujours un MKV ; la source peut être un autre conteneur. `-NoTranscode` conserve l'extension source mais n'exécute pas ce contrôle. Le contrôle porte sur les flux effectivement conservés par le mapping (vidéo, audio, sous-titres), jamais les pistes retirées, les pièces jointes ni les images de couverture. Deux contrôles distincts viennent du même scan packet-level, via la `time_base` de chaque flux. Durée propre : max(pts[+duration]) − min(pts) du flux lui-même — plus d'origine commune au fichier. Si la source et la sortie ont une borne exacte, comparaison `packet-end-span`. Si la source n'a pas de borne exacte mais a une étendue PTS, fallback `packet-pts-span` des deux côtés. Si la source avait une borne exacte que la sortie a perdue, mismatch (pas de rétrogradation vers PTS). La tolérance de durée est max(1 s, 0,5 % de la durée propre source). Décalages : pour chaque couple de pistes à début fiable, abs((startB − startA)_sortie − (startB − startA)_source) > 0,1 s ⇒ mismatch ; une variation exactement égale à 0,1 s est acceptée. Une translation identique de tous les timestamps est conforme : on ne compare pas le début d'une piste à son début en sortie. Un début n'est fiable pour les décalages que si tous les PTS du flux sont exploitables ; un PTS `N/A` rend ce flux `unknown` pour les relations qui l'impliquent, sans fausser les autres. Un seul flux conservé : pas d'exigence d'un second flux. Le diagnostic d'un mismatch de décalage identifie les deux pistes, les décalages attendu et observé, et l'écart. Pour la vidéo et l'audio, `packet.duration` peut déjà être synthétisée par FFmpeg (frame rate / `frame_size`) : `packet-end-span` n'est alors pas une borne lue dans le conteneur. Pour Matroska/WebM, un packet dont ffprobe imprime `duration=N/A` n'a ni `BlockDuration` ni `DefaultDuration` matérialisé ; FFmpeg n'infère pas la durée depuis le Block suivant. Ces packets intermédiaires ne peuvent pas dépasser `maxPTS`, donc `MaxKnownEnd` n'est pas sous-estimé. Hors Matroska, tout packet sans duration rend la borne exacte indisponible. Pour PGS (`hdmv_pgs_subtitle`), le contrôle de durée utilise la métrique PTS et ne dépend pas de `packet.duration`. `stream.duration`, le tag `DURATION` et `format.duration` ne servent plus de verdict. Un écart de durée au-delà de max(1 s, 0,5 %), un décalage relatif modifié au-delà de 0,1 s, un fichier de sortie que ffprobe ne peut pas sonder (métadonnées ou packets), un flux mappé absent de la sortie, ou une timeline de sortie devenue non mesurable alors que la source l'était, rejettent la sortie et conservent l'original par défaut ; avec `-AllowIntegrityMismatch`, le même mismatch (durée ou décalage) reste détecté et signalé, mais devient un avertissement non bloquant et la sortie est acceptée. Une timeline source non mesurable reste `unknown` (fichier accepté, comme auparavant). Le contrôle parcourt donc les packets de la source et de la sortie : il peut être plus coûteux en I/O sur les gros médias. `-NoTranscode` n'exécute pas ce contrôle.

Fichiers / dossiers non traités : `Plex Versions`, `.deletedByTMM`, nom contenant `-trailer.`, fichiers lecture seule, absence de durée ffprobe (sauf `-ForceRecodeVideo` / `-NoTranscode`), destination déjà existante si l'extension change, rien à faire (déjà conforme), `.mp4` avec sous-titres sans `-AllowSubTitlesConversion` en réencodage normal. `-ScanReadOnlyDirectory` ne concerne que la descente dans des répertoires lecture seule, pas les fichiers.

ffmpeg/ffprobe : `-FFMPEGPath` / `-FFPROBEPath`, sinon dossier `Tetram.Media.FFmpeg\ffmpeg\` (build ffmpeg >= 8.0.0, hors 9.0.0 et 9.0.1), sinon PATH. Ne pas utiliser `-FFToolsBase` pour pointer les binaires : le paramètre est validé mais ignoré.

Pour simuler sans toucher au média ni aux dates : `-WhatIf` (pas `-CheckOnly`). Une exception peut quand même écrire `reencode-errors.log`. `ConfirmImpact` est Medium : pas de prompt sauf `-Confirm`.

## EXAMPLES

### Example 1: Dry-run avant un réencodage récursif

Intention : voir ce qui serait fait, sans modifier le média ni les timestamps. Une exception peut quand même créer `reencode-errors.log`. Toujours préférer cet appel avant un run réel.

```powershell
Invoke-MkvRemux -Path 'D:\Media' -Recurse -WhatIf
```

### Example 2: Réencodage par défaut (HEVC, sortie .mkv)

Intention : normaliser un arbre vers MKV/HEVC qualité Medium. Les originaux sont remplacés in-place.

```powershell
Invoke-MkvRemux -Path 'D:\Media' -Recurse
```

### Example 3: Vérifier qu'ffmpeg peut décoder, sans retravailler le média

Intention : diagnostiquer des fichiers illisibles sans réencoder ni remuxer. Ce n'est pas un dry-run : les dates NFO (`premiered`) peuvent être écrites. Pour ne pas toucher au média ni aux dates : `-WhatIf`. Les échecs (ffmpeg ou exception) vont dans `reencode-errors.log`, y compris sous `-WhatIf`.

```powershell
Invoke-MkvRemux -Path 'D:\Media' -Recurse -CheckOnly
```

### Example 4: Filtrer des pistes sans transcodage

Intention : retirer sous-titres / vignettes et nettoyer les métadonnées en copiant les flux conservés. Conserve l'extension source. Ignoré si aucune opération n'est nécessaire.

```powershell
Invoke-MkvRemux -Path 'D:\Media' -Recurse -NoTranscode
```

### Example 5: File d'attente + upgrade HEVC vers AV1

Intention : traiter une liste, retirer chaque ligne après coup, réencoder les HEVC `main*` en AV1. `-ListFile` exclut `-Path`.

```powershell
Invoke-MkvRemux -ListFile 'D:\todo.txt' -UpdateList -VideoCodec AV1 -AllowVideoCodecUpgrade
```

### Example 6: Un seul sous-arbre récursif sans `-Recurse` global

Intention : récursion ciblée. Le `+` s'applique à cette entrée seulement.

```powershell
Invoke-MkvRemux -Path '+D:\Media\Shows'
```

### Example 7: Accepter explicitement un mismatch d'intégrité

Intention : continuer un réencodage malgré un mismatch déjà détecté (écart de durée packet-span, décalage relatif entre flux, probe de sortie impossible, timeline de sortie non mesurable, ou flux mappé manquant). Ce n'est pas le comportement recommandé par défaut : le contrôle s'exécute toujours, le mismatch est signalé en warning, et la sortie remplace l'original. Sans effet en `-NoTranscode` ni `-CheckOnly`.

```powershell
Invoke-MkvRemux -ListFile 'D:\todo.txt' -AllowIntegrityMismatch
```

### Example 8: Retirer toutes les pièces jointes sans transcodage

Intention : supprimer tous les flux ffprobe de type `attachment` (y compris les polices ASS) tout en copiant les autres flux conservés. Conserve l'extension source. Sans effet s'il n'y a aucun attachment et aucun autre travail.

```powershell
Invoke-MkvRemux -Path 'D:\Media' -Recurse -NoTranscode -RemoveAttachments
```

## PARAMETERS

### -AllowIntegrityMismatch

En réencodage réel uniquement. Par défaut, un mismatch d'intégrité rejette la
sortie et conserve l'original : écart de durée propre d'un flux conservé
supérieur à max(1 s, 0,5 % de sa durée source), variation du décalage relatif
entre deux flux conservés supérieure à 0,1 s, fichier de sortie que ffprobe
ne peut pas sonder (métadonnées ou packets), flux mappé manquant en sortie,
ou timeline de sortie devenue non mesurable alors que la source l'était.
La sortie contrôlée est toujours un MKV ; la source peut être un autre
conteneur. Le contrôle porte sur les flux conservés par le mapping, pas les
pistes retirées, pièces jointes ni couvertures. Durée propre :
`packet-end-span` = max(pts + duration) − min(pts) du flux si la source et
la sortie ont cette borne exacte ; `packet-pts-span` = max(pts) − min(pts)
du flux si la source n'a pas de borne exacte mais a une étendue PTS des deux
côtés ; mismatch si la source avait une borne exacte que la sortie a perdue.
Décalages : pour chaque couple à débuts fiables, abs((startB − startA)_sortie
− (startB − startA)_source) > 0,1 s ⇒ mismatch (égalité à 0,1 s acceptée).
Une translation globale des timestamps est conforme. Un PTS `N/A` rend ce
flux `unknown` pour les relations qui l'impliquent, sans fausser les autres.
Pour la vidéo et l'audio, `packet.duration` peut déjà être synthétisée par
FFmpeg (frame rate / `frame_size`) : `packet-end-span` n'est alors pas une
borne lue dans le conteneur. Pour Matroska/WebM, un packet `duration=N/A`
n'a ni `BlockDuration` ni `DefaultDuration` matérialisé ; FFmpeg n'infère
pas la durée depuis le Block suivant. Hors Matroska, tout packet sans
duration rend la borne exacte indisponible.
PGS : le contrôle de durée utilise la métrique PTS et ne dépend pas de
`packet.duration`. `stream.duration`, le tag `DURATION` et `format.duration`
ne servent plus de verdict. Avec ce commutateur, le même mismatch (durée ou
décalage) reste détecté et affiché, mais devient un avertissement non
bloquant : le fichier de sortie est accepté. Le commutateur ne désactive pas
le contrôle. Il n'existe pas en `-NoTranscode` ni en `-CheckOnly`. Le cas
« timeline source non mesurable » (`unknown`) était déjà accepté et n'est pas
la raison d'être de ce paramètre.

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
Conserve l'extension source. Avec `-RemoveAttachments`, tous les flux
`attachment` sont retirés ; sans ce commutateur, la politique actuelle de
conservation des attachments (polices ASS, etc.) reste inchangée.
Jeu de paramètres exclusif.

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

### -RemoveAttachments

Supprime de la sortie tous les flux ffprobe de type `attachment`. Cette
suppression s'applique également aux polices associées à des sous-titres ASS.
Disponible en réencodage normal et en `-NoTranscode` ; absent de `-CheckOnly`.
Sans ce commutateur, la politique de conservation actuelle des attachments
reste inchangée.

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

Cette commande prend en charge les paramètres communs : -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction et -WarningVariable. Pour plus d'informations, voir
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

Prérequis : PowerShell 7.6+, module chargé depuis son `.psd1`. ffmpeg/ffprobe >= 8.0.0 (hors 9.0.0 et 9.0.1).

Audio hors MP4 : High/Medium → EAC3 ; Low → Opus (y compris avec une vidéo finale AV1).
AV1 + AAC n'impose EAC3 qu'en High et Medium.

Ne pas faire : passer `-FFToolsBase` pour changer les binaires ; combiner `-Path` et `-ListFile` ; combiner les modes `-CheckOnly` / `-NoTranscode` ; prendre `-CheckOnly` pour un dry-run ; prendre `-WhatIf` pour « aucune écriture disque » (`reencode-errors.log` reste possible) ; attendre un code de retour par fichier (la commande continue).

Skip « No reencoding needed » / « No stream filtering needed » = déjà conforme, ce n'est pas une erreur.

`-UpdateList` réécrit `-ListFile` après chaque ligne (sous ShouldProcess).

## RELATED LINKS

- [Get-MkvInterleaveRepairCommand]()
- [Invoke-MkvRepair]()
- [Test-MediaSimilarity]()
- [Remove-EmptyDirs]()
