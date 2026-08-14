---
document type: cmdlet
external help file: Tetram.Media.Streams-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Streams
ms.date: 08/14/2026
PlatyPS schema version: 2024-05-01
title: Merge-MediaSubtitle
---

# Merge-MediaSubtitle

## SYNOPSIS

Réinjecte un sous-titre explicite dans un MKV (`-Add` ou `-Update`).

## SYNTAX

### Add

```
Merge-MediaSubtitle [-MediaFile] <string> [-Path] <string> -Add [-Force]
 [-WhatIf] [-Confirm]
```

### Update

```
Merge-MediaSubtitle [-MediaFile] <string> [-Path] <string> -Update [-Force]
 [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Toujours un update **in-place** du MKV passé en `-MediaFile` (fichier `.mkv` existant, accepte le pipeline). `-Path` (alias `-LiteralPath`) est **un seul** fichier sous-titre (`.srt` `.ass` `.ssa` `.vtt` `.sup`), donné explicitement par l'appelant — pas de scan de dossier. Le **nom** de ce fichier doit se parser avec le basename du MKV (langue, flags, index de collision) et donner la classe sous-titre ; sinon la commande échoue sans mux.

`-Add` et `-Update` sont deux jeux de paramètres exclusifs, l'un des deux est obligatoire : ils rendent l'intention explicite plutôt que de la déduire silencieusement d'une collision de nom.

- Le sous-titre a la **même clé** (classe, langue, flags, extension) **et le même index de collision** qu'une piste du MKV → collision.
- `-Add` + collision → **rejet** (`Write-ErrorLog`, pas de mux) : utilisez `-Update`.
- `-Update` + pas de collision → **rejet** (`Write-ErrorLog`, pas de mux) : utilisez `-Add`.
- `-Add` sans collision → la piste est **ajoutée**. `-Update` avec collision → la piste est **remplacée**.

Les autres pistes du MKV (vidéo, audio, sous-titres non concernés, polices, chapitres, covers) sont toujours **conservées** telles quelles. Pas de suppression de piste. Le fichier `-Path` n'est **jamais supprimé** par la commande, réussite ou non : le nettoyage est à la charge de l'appelant.

Pas de `-Destination` : toujours in-place via un temporaire dans TEMP. `-WhatIf` affiche la ligne FFmpeg, n'écrit pas. `commentary` fichier = `comment` FFmpeg.

Codec A/V/S hors table (`mpeg4`, `mov_text`, `alac`, `pcm_*`, …) présent dans le MKV : pas d'échec au mux, la piste est conservée telle quelle. Tout flux ni vidéo, ni audio, ni sous-titre (covers, polices, chapitres, `data`, …) : keep. Aucun objet pipeline. Importer `.\Tetram.Media.Streams` (PowerShell 7+).

## EXAMPLES

### Example 1: Réinjecter après édition d'un SRT (remplacement)

Intention : round-trip. `film.fra.srt` a la même clé qu'une piste MKV → `-Update` accepte.
Les autres pistes sans fichier de flux correspondant sont keep. Aucune piste n'est supprimée.

```powershell
Merge-MediaSubtitle -MediaFile 'D:\Media\film.mkv' -Path 'D:\Media\film.fra.srt' -Update -Force
```

### Example 2: Ajouter une piste (film.spa.srt)

Intention : `film.spa.srt` n'a pas de clé correspondante dans le MKV → `-Add` accepte.
Le mux conserve toutes les pistes existantes (keep) et ajoute l'espagnol.

```powershell
Merge-MediaSubtitle -MediaFile 'D:\Media\film.mkv' -Path 'D:\Media\film.spa.srt' -Add -Force
```

### Example 3: Intention incorrecte : rejet sans mux

`-Add` sur un fichier qui matche déjà une piste (ou `-Update` sans piste correspondante)
est rejeté : `Write-ErrorLog`, aucun FFmpeg n'est lancé, le MKV n'est pas touché.

```powershell
Merge-MediaSubtitle -MediaFile 'D:\Media\film.mkv' -Path 'D:\Media\film.fra.srt' -Add -Force
```

### Example 4: Simuler le mux

Intention : afficher la ligne FFmpeg sans écrire le MKV, sans créer de temporaire finalisé.

```powershell
Merge-MediaSubtitle -MediaFile 'D:\Media\film.mkv' -Path 'D:\Media\film.fra.srt' -Update -WhatIf
```

### Example 5: Passer -MediaFile depuis le pipeline

`-MediaFile` accepte le pipeline (chaîne simple, comme `-Path` de `Test-MediaSimilarity`) :
utile en fin d'une chaîne de commandes qui produit le chemin du MKV.

```powershell
'D:\Media\film.mkv' | Merge-MediaSubtitle -Path 'D:\Media\film.fra.srt' -Update -Force
```

## PARAMETERS

### -Add

Déclare l'intention d'**ajouter** une nouvelle piste. Rejeté (`Write-ErrorLog`, pas de
mux) si `-Path` matche déjà une piste du MKV (même clé, même index de collision) —
utilisez `-Update` dans ce cas. Exclusif avec `-Update` ; l'un des deux est obligatoire.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Add
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Update

Déclare l'intention de **remplacer** une piste existante. Rejeté (`Write-ErrorLog`, pas
de mux) si `-Path` ne matche aucune piste du MKV (même clé, même index de collision) —
utilisez `-Add` dans ce cas. Exclusif avec `-Add` ; l'un des deux est obligatoire.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Update
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Confirm

Demande confirmation avant d'exécuter FFmpeg (impact Medium : pas de prompt
sauf si `-Confirm` est passé). Un refus est traité comme `-WhatIf` : rien n'est
exécuté ni déplacé, aucune erreur `ffmpeg failed` n'est loguée. Distinct de la
confirmation `ShouldContinue` déclenchée par le MKV cible déjà présent sans
`-Force`.

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

### -Force

Écrase le MKV cible déjà présent sans `ShouldContinue`. Sans `-Force`, une cible
existante demande confirmation ; un refus annule tout le merge. Sans effet sur
`-WhatIf` (rien n'est écrit ; la commande est prévisualisée même si la cible
existe, sans aucun prompt — nécessaire pour l'update in-place, toujours sur un
MKV existant).

```yaml
Type: System.Management.Automation.SwitchParameter
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

### -MediaFile

Fichier `.mkv` à mettre à jour, existant. Chemin littéral (pas de jokers).
Obligatoire. Accepte le pipeline (chaîne simple).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

Fichier sous-titre à injecter, existant, donné explicitement (n'importe quel
dossier). Son **nom** doit se parser avec le basename de `-MediaFile` (grammaire
Get-MediaStream : langue, flags, index de collision) et donner la classe
sous-titre ; sinon la commande échoue sans mux. Jamais supprimé par la commande.
`-LiteralPath` est un alias (même paramètre, même comportement — convention de
nommage uniquement, pas de résolution de jokers).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases:
- LiteralPath
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WhatIf

Affiche la ligne FFmpeg (`Show-CommandLine`), n'écrit pas le MKV, ne crée pas de
sortie finalisée.

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

Prérequis : PowerShell 7+, ffmpeg/ffprobe (`Tetram.Media.FFmpeg`). Importer `.\Tetram.Media.Streams`. Toujours un update d'un MKV existant (pas de mux from-scratch). Un appel = un seul sous-titre ; pour en réinjecter plusieurs, appeler la commande plusieurs fois de suite sur le même MKV.

Ne pas faire : attendre une suppression de piste (replace / add / keep seulement) ; compter sur la commande pour supprimer `-Path` après succès (à faire soi-même) ; fournir `-Add` et `-Update` ensemble ou aucun des deux (erreur de paramètre) ; prendre le jeton fichier `commentary` pour autre chose que le disposition FFmpeg `comment` ; attendre que le mux réinjecte un `.h264` / `.aac` (référence split seulement).

## RELATED LINKS

- [Get-MediaStream](Get-MediaStream.md)
