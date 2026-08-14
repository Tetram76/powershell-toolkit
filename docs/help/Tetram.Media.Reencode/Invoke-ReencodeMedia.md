---
document type: cmdlet
external help file: Tetram.Media.Reencode-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Reencode
ms.date: 08/14/2026
PlatyPS schema version: 2024-05-01
title: Invoke-ReencodeMedia
---

# Invoke-ReencodeMedia

## SYNOPSIS

Remplace in-place des fichiers média : réencodage HEVC/AV1, remux (`-Rewrite`) ou contrôle ffmpeg (`-CheckOnly`, pas un dry-run).

## SYNTAX

### SetExtensionFromPath (Default)

```
Invoke-ReencodeMedia [[-Path] <string[]>] [-Recurse] [-Sort <string>] [-ScanReadOnlyDirectory]
 [-InputMasks <string[]>] [-OutputExtension <string>] [-VideoCodec <string>] [-ClearStreamsTitle]
 [-ForceRecodeVideo] [-AllowVideoCodecUpgrade] [-Quality <string>] [-Upscale <string>]
 [-UpscaleWidth <int>] [-UpscaleFit <string>] [-Deinterlace] [-AllowSubTitlesConversion]
 [-SubTitlesToKeep <string[]>] [-TempPath <string>] [-FFToolsBase <string>] [-FFMPEGPath <string>]
 [-FFPROBEPath <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### RewriteFromPath

```
Invoke-ReencodeMedia [[-Path] <string[]>] -Rewrite [-Recurse] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-ClearStreamsTitle]
 [-SubTitlesToKeep <string[]>] [-TempPath <string>] [-FFToolsBase <string>] [-FFMPEGPath <string>]
 [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### KeepExtensionFromPath

```
Invoke-ReencodeMedia [[-Path] <string[]>] -KeepExtension [-Recurse] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-VideoCodec <string>] [-ClearStreamsTitle]
 [-ForceRecodeVideo] [-AllowVideoCodecUpgrade] [-Quality <string>] [-Upscale <string>]
 [-UpscaleWidth <int>] [-UpscaleFit <string>] [-Deinterlace] [-AllowSubTitlesConversion]
 [-SubTitlesToKeep <string[]>] [-TempPath <string>] [-FFToolsBase <string>] [-FFMPEGPath <string>]
 [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### CheckFromPath

```
Invoke-ReencodeMedia [[-Path] <string[]>] -CheckOnly [-Recurse] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-TempPath <string>] [-FFToolsBase <string>]
 [-FFMPEGPath <string>] [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### RewriteFromFile

```
Invoke-ReencodeMedia -ListFile <string> -Rewrite [-Recurse] [-UpdateList] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-ClearStreamsTitle]
 [-SubTitlesToKeep <string[]>] [-TempPath <string>] [-FFToolsBase <string>] [-FFMPEGPath <string>]
 [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### SetExtensionFromFile

```
Invoke-ReencodeMedia -ListFile <string> [-UpdateList] [-Sort <string>] [-ScanReadOnlyDirectory]
 [-InputMasks <string[]>] [-OutputExtension <string>] [-VideoCodec <string>] [-ClearStreamsTitle]
 [-ForceRecodeVideo] [-AllowVideoCodecUpgrade] [-Quality <string>] [-Upscale <string>]
 [-UpscaleWidth <int>] [-UpscaleFit <string>] [-Deinterlace] [-AllowSubTitlesConversion]
 [-SubTitlesToKeep <string[]>] [-TempPath <string>] [-FFToolsBase <string>] [-FFMPEGPath <string>]
 [-FFPROBEPath <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### KeepExtensionFromFile

```
Invoke-ReencodeMedia -ListFile <string> -KeepExtension [-UpdateList] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-VideoCodec <string>] [-ClearStreamsTitle]
 [-ForceRecodeVideo] [-AllowVideoCodecUpgrade] [-Quality <string>] [-Upscale <string>]
 [-UpscaleWidth <int>] [-UpscaleFit <string>] [-Deinterlace] [-AllowSubTitlesConversion]
 [-SubTitlesToKeep <string[]>] [-TempPath <string>] [-FFToolsBase <string>] [-FFMPEGPath <string>]
 [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

### CheckFromFile

```
Invoke-ReencodeMedia -ListFile <string> -CheckOnly [-UpdateList] [-Sort <string>]
 [-ScanReadOnlyDirectory] [-InputMasks <string[]>] [-TempPath <string>] [-FFToolsBase <string>]
 [-FFMPEGPath <string>] [-FFPROBEPath <string>] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Point d'entrée unique du module. Importer `Tetram.Media.Reencode.psd1` (PowerShell 7+), puis appeler cette commande. Aucun objet n'est renvoyé : lire la console et, en cas d'échec, `reencode-errors.log` dans le répertoire courant.

Choisir exactement un mode (jeux de paramètres exclusifs) :

- défaut (ni `-KeepExtension` ni `-Rewrite` ni `-CheckOnly`) : réencodage vers `-OutputExtension` (défaut `.mkv`), codec `-VideoCodec` (défaut HEVC / libx265), qualité `-Quality` (défaut Medium).
- `-KeepExtension` : même réencodage, mais l'extension source est conservée.
- `-Rewrite` : remux uniquement (`-c:v`/`-c:a copy`). Pas de réencodage, pas d'upscale, pas de désentrelacement. Ne s'exécute que s'il y a des pistes à retirer.
- `-CheckOnly` : intermédiaire entre `-WhatIf` et un réencodage. Vérifie que ffmpeg peut décoder (muxer `null`) sans réencoder, remuxer ni remplacer le fichier média. Ce n'est pas un dry-run : les horodatages NFO (`premiered`) sont posés sur le fichier et éventuellement les dossiers, comme sur un run normal.

Choisir exactement une source : `-Path` (défaut `.`) ou `-ListFile` (fichier texte, une entrée par ligne). Un chemin préfixé par `+` est parcouru récursivement même sans `-Recurse`.

Effet disque :

- `-WhatIf` : pas de réécriture média, pas de timestamps NFO. N'est pas un silence disque total : une exception fichier (catch de `Invoke-ReencodeFile`) append `reencode-errors.log` dans le répertoire courant, sans `ShouldProcess`.
- `-CheckOnly` (sans `-WhatIf`) : pas de temporaire ffmpeg, pas de `Move-Item` / `Rename-Item` sur le média. Les timestamps NFO (`premiered`) sont malgré tout appliqués. Un échec ffmpeg est journalisé dans `reencode-errors.log`.
- réencodage / remux : ffmpeg écrit un temporaire sous `-TempPath`, puis `Move-Item` écrase le fichier source, puis un `Rename-Item` change l'extension si besoin. Les horodatages du fichier sont restaurés. Des dossiers voisins peuvent voir leurs dates corrigées via NFO (`premiered`). Un écart de durée au-delà de max(1 s, 0,5 %) conserve l'original (le temporaire est jeté).

Fichiers / dossiers non traités : `Plex Versions`, `.deletedByTMM`, nom contenant `-trailer.`, fichiers lecture seule, absence de durée ffprobe (sauf `-ForceRecodeVideo` / `-Rewrite`), destination déjà existante si l'extension change, rien à faire (déjà conforme), `.mp4` avec sous-titres sans `-AllowSubTitlesConversion`. `-ScanReadOnlyDirectory` ne concerne que la descente dans des répertoires lecture seule, pas les fichiers.

ffmpeg/ffprobe : `-FFMPEGPath` / `-FFPROBEPath`, sinon dossier `RecodeVideo/` à la racine du dépôt (build ffmpeg >= 9.0.1), sinon PATH. Ne pas utiliser `-FFToolsBase` pour pointer les binaires : le paramètre est validé mais ignoré.

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

### Example 4: Remux pour retirer des pistes, sans réencoder

Intention : filtrer sous-titres / métadonnées en copiant vidéo et audio. Ignoré si aucun filtrage n'est nécessaire.

```powershell
Invoke-ReencodeMedia -Path 'D:\Media' -Recurse -Rewrite
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

## PARAMETERS

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
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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
vers AV1 au lieu de les copier. Sans effet en `-CheckOnly`. Ne s'applique pas
au mode `-Rewrite`.
Lorsque `-VideoCodec AV1`, force le réencodage des pistes HEVC au profil `main*`
vers AV1 au lieu de les copier.
Sans effet en `-CheckOnly`.
Ne s'applique pas
au mode `-Rewrite`.
Lorsque `-VideoCodec AV1`, force le réencodage des pistes HEVC au profil `main*`
vers AV1 au lieu de les copier.
Sans effet en `-CheckOnly`.
Ne s'applique pas
au mode `-Rewrite`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

### -Deinterlace

Applique le filtre `yadif` aux pistes vidéo conservées. Ignoré en `-Rewrite`.
Applique le filtre `yadif` aux pistes vidéo conservées.
Ignoré en `-Rewrite`.
Applique le filtre `yadif` aux pistes vidéo conservées.
Ignoré en `-Rewrite`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Chemin explicite vers l'exécutable ffmpeg. Chaîne vide : découverte automatique
(`RecodeVideo/`, puis PATH).
Chemin explicite vers l'exécutable ffmpeg.
Chaîne vide : découverte automatique
(`RecodeVideo/`, puis PATH).
Chemin explicite vers l'exécutable ffmpeg.
Chaîne vide : découverte automatique
(`RecodeVideo/`, puis PATH).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Chemin explicite vers l'exécutable ffprobe. Chaîne vide : même dossier `bin`
que ffmpeg, ou PATH.
Chemin explicite vers l'exécutable ffprobe.
Chaîne vide : même dossier `bin`
que ffmpeg, ou PATH.
Chemin explicite vers l'exécutable ffprobe.
Chaîne vide : même dossier `bin`
que ffmpeg, ou PATH.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Dossier qui doit exister (défaut : répertoire courant). Validé à l'appel, mais
non utilisé pour localiser ffmpeg/ffprobe — voir `-FFMPEGPath` et `-FFPROBEPath`.
Dossier qui doit exister (défaut : répertoire courant).
Validé à l'appel, mais
non utilisé pour localiser ffmpeg/ffprobe — voir `-FFMPEGPath` et `-FFPROBEPath`.
Dossier qui doit exister (défaut : répertoire courant).
Validé à l'appel, mais
non utilisé pour localiser ffmpeg/ffprobe — voir `-FFMPEGPath` et `-FFPROBEPath`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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
VC1. Sans ce commutateur, ces pistes sont copiées (sauf upgrade AV1). Ignoré en
`-Rewrite`.
Force le réencodage vidéo même si le codec source est déjà HEVC `main*`, AV1 ou
VC1.
Sans ce commutateur, ces pistes sont copiées (sauf upgrade AV1).
Ignoré en
`-Rewrite`.
Force le réencodage vidéo même si le codec source est déjà HEVC `main*`, AV1 ou
VC1.
Sans ce commutateur, ces pistes sont copiées (sauf upgrade AV1).
Ignoré en
`-Rewrite`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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
Masques passés à `Get-ChildItem -Include`.
Défaut : `*.mkv`, `*.mp4`, `*.avi`,
`*.wmv`, `*.mov`, `*.flv`, `*.mpeg`, `*.mpg`, `*.heic`, `*.ts`, `*.webm`.
Masques passés à `Get-ChildItem -Include`.
Défaut : `*.mkv`, `*.mp4`, `*.avi`,
`*.wmv`, `*.mov`, `*.flv`, `*.mpeg`, `*.mpg`, `*.heic`, `*.ts`, `*.webm`.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

### -KeepExtension

Conserve l'extension du fichier source au lieu d'appliquer `-OutputExtension`.
Implicite en `-Rewrite`. Jeu de paramètres exclusif.
Conserve l'extension du fichier source au lieu d'appliquer `-OutputExtension`.
Implicite en `-Rewrite`.
Jeu de paramètres exclusif.
Conserve l'extension du fichier source au lieu d'appliquer `-OutputExtension`.
Implicite en `-Rewrite`.
Jeu de paramètres exclusif.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ListFile

Fichier texte d'entrée : une ligne = un chemin. Un préfixe `+` force la
récursion pour cette ligne. Le fichier doit exister. Mutuellement exclusif avec
`-Path`.
Fichier texte d'entrée : une ligne = un chemin.
Un préfixe `+` force la
récursion pour cette ligne.
Le fichier doit exister.
Mutuellement exclusif avec
`-Path`.
Fichier texte d'entrée : une ligne = un chemin.
Un préfixe `+` force la
récursion pour cette ligne.
Le fichier doit exister.
Mutuellement exclusif avec
`-Path`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
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

### -OutputExtension

Extension de sortie, avec le point initial (ex. `.mkv`). Défaut : `.mkv`.
Uniquement dans le jeu de paramètres par défaut (pas `-KeepExtension` ni
`-Rewrite`).
Extension de sortie, avec le point initial (ex.
`.mkv`).
Défaut : `.mkv`.
Uniquement dans le jeu de paramètres par défaut (pas `-KeepExtension` ni
`-Rewrite`).
Extension de sortie, avec le point initial (ex.
`.mkv`).
Défaut : `.mkv`.
Uniquement dans le jeu de paramètres par défaut (pas `-KeepExtension` ni
`-Rewrite`).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

Dossiers ou fichiers à traiter. Défaut : `.`. Un élément préfixé par `+` est
parcouru récursivement même sans `-Recurse`. Mutuellement exclusif avec
`-ListFile`.
Dossiers ou fichiers à traiter.
Défaut : `.`.
Un élément préfixé par `+` est
parcouru récursivement même sans `-Recurse`.
Mutuellement exclusif avec
`-ListFile`.
Dossiers ou fichiers à traiter.
Défaut : `.`.
Un élément préfixé par `+` est
parcouru récursivement même sans `-Recurse`.
Mutuellement exclusif avec
`-ListFile`.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromPath
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Cible de qualité `Low`, `Medium` (défaut) ou `High`. Pilote CRF/preset vidéo
(libx265 ou libsvtav1) et le seuil de réencodage audio (bitrate, codecs
lossless). Ignoré en `-Rewrite` et `-CheckOnly`.
Cible de qualité `Low`, `Medium` (défaut) ou `High`.
Pilote CRF/preset vidéo
(libx265 ou libsvtav1) et le seuil de réencodage audio (bitrate, codecs
lossless).
Ignoré en `-Rewrite` et `-CheckOnly`.
Cible de qualité `Low`, `Medium` (défaut) ou `High`.
Pilote CRF/preset vidéo
(libx265 ou libsvtav1) et le seuil de réencodage audio (bitrate, codecs
lossless).
Ignoré en `-Rewrite` et `-CheckOnly`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Parcourt les sous-dossiers. Peut être combiné avec le préfixe `+` sur un chemin
individuel. Les dossiers `Plex Versions` et `.deletedByTMM` restent exclus.
Parcourt les sous-dossiers.
Peut être combiné avec le préfixe `+` sur un chemin
individuel.
Les dossiers `Plex Versions` et `.deletedByTMM` restent exclus.
Parcourt les sous-dossiers.
Peut être combiné avec le préfixe `+` sur un chemin
individuel.
Les dossiers `Plex Versions` et `.deletedByTMM` restent exclus.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

### -Rewrite

Remux sans réencodage : copie vidéo/audio, filtre les sous-titres, nettoie les
métadonnées. Conserve l'extension source. Jeu de paramètres exclusif.
Remux sans réencodage : copie vidéo/audio, filtre les sous-titres, nettoie les
métadonnées.
Conserve l'extension source.
Jeu de paramètres exclusif.
Remux sans réencodage : copie vidéo/audio, filtre les sous-titres, nettoie les
métadonnées.
Conserve l'extension source.
Jeu de paramètres exclusif.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ScanReadOnlyDirectory

Autorise la descente récursive dans des répertoires marqués en lecture seule.
Les fichiers en lecture seule ne sont jamais traités.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Ordre de traitement : `NewestFirst`, `OldestFirst`, `SmallerFirst`,
`LargerFirst`. Absent : tri par nom.
Ordre de traitement : `NewestFirst`, `OldestFirst`, `SmallerFirst`,
`LargerFirst`.
Absent : tri par nom.
Ordre de traitement : `NewestFirst`, `OldestFirst`, `SmallerFirst`,
`LargerFirst`.
Absent : tri par nom.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Langues de sous-titres à conserver (codes `tags.language`). Les pistes sans
langue, `un` et `und` sont toujours gardées. Défaut : `fr`, `fre`, `fr-FR`,
`en`, `eng`, `en-US`, `en-GB`.
Langues de sous-titres à conserver (codes `tags.language`).
Les pistes sans
langue, `un` et `und` sont toujours gardées.
Défaut : `fr`, `fre`, `fr-FR`,
`en`, `eng`, `en-US`, `en-GB`.
Langues de sous-titres à conserver (codes `tags.language`).
Les pistes sans
langue, `un` et `und` sont toujours gardées.
Défaut : `fr`, `fre`, `fr-FR`,
`en`, `eng`, `en-US`, `en-GB`.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Dossier temporaire de travail. Doit exister. Défaut : `$env:TEMP`, sinon
`$env:TMPDIR`, `$env:TMP`, sinon `[IO.Path]::GetTempPath()`.
Dossier temporaire de travail.
Doit exister.
Défaut : `$env:TEMP`, sinon
`$env:TMPDIR`, `$env:TMP`, sinon `[IO.Path]::GetTempPath()`.
Dossier temporaire de travail.
Doit exister.
Défaut : `$env:TEMP`, sinon
`$env:TMPDIR`, `$env:TMP`, sinon `[IO.Path]::GetTempPath()`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: RewriteFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Après traitement d'une ligne de `-ListFile`, retire cette ligne du fichier
(sous `-WhatIf`/`-Confirm`). Uniquement avec `-ListFile`.
Après traitement d'une ligne de `-ListFile`, retire cette ligne du fichier
(sous `-WhatIf`/`-Confirm`).
Uniquement avec `-ListFile`.
Après traitement d'une ligne de `-ListFile`, retire cette ligne du fichier
(sous `-WhatIf`/`-Confirm`).
Uniquement avec `-ListFile`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RewriteFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
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

Hauteur cible `720p`, `1080p`, `2160p` ou `4320p`. N'agrandit que si la source
est plus petite (ou, à hauteur égale, si `-UpscaleWidth` diffère). Combinable
avec `-UpscaleWidth`. Ignoré en `-Rewrite`.
Hauteur cible `720p`, `1080p`, `2160p` ou `4320p`.
N'agrandit que si la source
est plus petite (ou, à hauteur égale, si `-UpscaleWidth` diffère).
Combinable
avec `-UpscaleWidth`.
Ignoré en `-Rewrite`.
Hauteur cible `720p`, `1080p`, `2160p` ou `4320p`.
N'agrandit que si la source
est plus petite (ou, à hauteur égale, si `-UpscaleWidth` diffère).
Combinable
avec `-UpscaleWidth`.
Ignoré en `-Rewrite`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Boîte `LARGEURxHAUTEUR` (ex. `1920x1080`). Scale Lanczos avec
`force_original_aspect_ratio=decrease`. Si présent, remplace `-Upscale` /
`-UpscaleWidth` pour la décision d'agrandissement. Ignoré en `-Rewrite`.
Boîte `LARGEURxHAUTEUR` (ex.
`1920x1080`).
Scale Lanczos avec
`force_original_aspect_ratio=decrease`.
Si présent, remplace `-Upscale` /
`-UpscaleWidth` pour la décision d'agrandissement.
Ignoré en `-Rewrite`.
Boîte `LARGEURxHAUTEUR` (ex.
`1920x1080`).
Scale Lanczos avec
`force_original_aspect_ratio=decrease`.
Si présent, remplace `-Upscale` /
`-UpscaleWidth` pour la décision d'agrandissement.
Ignoré en `-Rewrite`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Largeur cible en pixels. `-1` (défaut) laisse ffmpeg calculer la largeur
(`scale=-1:hauteur`). Seules `-1` et les valeurs strictement positives sont
acceptées. Sans `-Upscale` ni `-UpscaleFit`, un agrandissement n'a lieu que si
cette largeur est supérieure à celle de la source.
Largeur cible en pixels.
`-1` (défaut) laisse ffmpeg calculer la largeur
(`scale=-1:hauteur`).
Seules `-1` et les valeurs strictement positives sont
acceptées.
Sans `-Upscale` ni `-UpscaleFit`, un agrandissement n'a lieu que si
cette largeur est supérieure à celle de la source.
Largeur cible en pixels.
`-1` (défaut) laisse ffmpeg calculer la largeur
(`scale=-1:hauteur`).
Seules `-1` et les valeurs strictement positives sont
acceptées.
Sans `-Upscale` ni `-UpscaleFit`, un agrandissement n'a lieu que si
cette largeur est supérieure à celle de la source.

```yaml
Type: System.Int32
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Codec vidéo cible : `HEVC` (défaut, libx265) ou `AV1` (libsvtav1). Les pistes
déjà HEVC `main*`, AV1 ou VC1 sont copiées sauf `-ForceRecodeVideo` ou
`-AllowVideoCodecUpgrade`.
Codec vidéo cible : `HEVC` (défaut, libx265) ou `AV1` (libsvtav1).
Les pistes
déjà HEVC `main*`, AV1 ou VC1 sont copiées sauf `-ForceRecodeVideo` ou
`-AllowVideoCodecUpgrade`.
Codec vidéo cible : `HEVC` (défaut, libx265) ou `AV1` (libsvtav1).
Les pistes
déjà HEVC `main*`, AV1 ou VC1 sont copiées sauf `-ForceRecodeVideo` ou
`-AllowVideoCodecUpgrade`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: SetExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: SetExtensionFromPath
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: KeepExtensionFromPath
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

Prérequis : PowerShell 7+, module chargé depuis son `.psd1` (NestedModules `Utils\`). ffmpeg/ffprobe >= 9.0.1.

Ne pas faire : passer `-FFToolsBase` pour changer les binaires ; combiner `-Path` et `-ListFile` ; combiner les modes `-CheckOnly` / `-Rewrite` / `-KeepExtension` ; prendre `-CheckOnly` pour un dry-run ; prendre `-WhatIf` pour « aucune écriture disque » (`reencode-errors.log` reste possible) ; attendre un code de retour par fichier (la commande continue).

Skip « No reencoding needed » / « No stream filtering needed » = déjà conforme, ce n'est pas une erreur.

`-UpdateList` réécrit `-ListFile` après chaque ligne (sous ShouldProcess).

## RELATED LINKS

- [Test-MediaSimilarity]()
- [Remove-EmptyDirs]()
