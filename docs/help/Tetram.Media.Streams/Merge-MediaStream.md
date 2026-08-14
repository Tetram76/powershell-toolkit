---
document type: cmdlet
external help file: Tetram.Media.Streams-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Streams
ms.date: 08/14/2026
PlatyPS schema version: 2024-05-01
title: Merge-MediaStream
---

# Merge-MediaStream

## SYNOPSIS

Réinjecte les sidecars dans le MKV (replace / add / keep).

## SYNTAX

### __AllParameterSets

```
Merge-MediaStream [-LiteralPath] <string> [-Destination <string>] [-RemoveSidecars] [-Force]
 [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Toujours un update du MKV passé en `-LiteralPath` (fichier `.mkv` existant). Sidecars du même basename : même clé (classe, langue, flags, extension, index) = replace ; sinon add ; piste MKV sans sidecar = keep. Pas de suppression de piste.

`-Destination` optionnel (sinon in-place via `.tmp`). `-RemoveSidecars` après mux réussi seulement. `-WhatIf` affiche la ligne FFmpeg, n'écrit pas, ne supprime pas. `commentary` fichier = `comment` FFmpeg.

Codec non mappé (`mpeg4`, `mov_text`, `alac`, …) : le split échoue ; au merge la piste reste keep dans le MKV. Covers, polices et chapitres : keep uniquement (pas de sidecar). Aucun objet pipeline. Importer `Tetram.Media.Streams.psd1` (PowerShell 7+).

## EXAMPLES

### Example 1: Réinjecter après édition d'un SRT

Intention : round-trip. `film.fra.srt` a la même clé qu'une piste MKV → replace.
Les autres pistes sans sidecar sont keep. Aucune piste n'est supprimée.

```powershell
Merge-MediaStream -LiteralPath 'D:\Media\film.mkv' -Force
```

### Example 2: Ajouter une piste (film.spa.srt)

Intention : `film.spa.srt` n'a pas de clé correspondante dans le MKV → add.
Le mux conserve toutes les pistes existantes (keep) et ajoute l'espagnol.

```powershell
Merge-MediaStream -LiteralPath 'D:\Media\film.mkv' -Force
```

### Example 3: Supprimer les sidecars après un mux réussi

Intention : `-RemoveSidecars` n'agit qu'après un mux et un `Move-Item` réussis.
En cas d'échec FFmpeg, les sidecars restent. `-Force` évite `ShouldContinue` sur
le MKV cible.

```powershell
Merge-MediaStream -LiteralPath 'D:\Media\film.mkv' -Force -RemoveSidecars
```

### Example 4: Simuler le mux

Intention : afficher la ligne FFmpeg sans écrire le MKV, sans créer de `.tmp`
finalisé, sans supprimer de sidecar.

```powershell
Merge-MediaStream -LiteralPath 'D:\Media\film.mkv' -WhatIf
```

## PARAMETERS

### -Confirm

Demande confirmation avant chaque `ShouldProcess` (impact Medium : pas de prompt
sauf si `-Confirm` est passé). N'équivaut pas à `-Force` (celui-ci concerne
`ShouldContinue` sur le MKV cible déjà présent).

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

### -Destination

Chemin `.mkv` de sortie. Omit : update in-place de `-LiteralPath` (mux vers un
`.tmp` unique puis `Move-Item`). Si fourni, doit se terminer par `.mkv`. Un
chemin déjà présent doit être un fichier, pas un dossier.

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

### -Force

Écrase le MKV cible déjà présent sans `ShouldContinue`. Sans `-Force`, une cible
existante demande confirmation ; un refus annule tout le merge. Sans effet sur
`-WhatIf` (rien n'est écrit).

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

### -LiteralPath

Fichier `.mkv` à mettre à jour, existant. Chemin littéral (pas de jokers).
Obligatoire. Les sidecars sont cherchés dans le même dossier, même basename.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
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

### -RemoveSidecars

Supprime uniquement les sidecars réellement muxés (replace/add), via le chemin
énuméré, après un mux réussi (`Move-Item` ok). La casse suit le système de
fichiers du dossier. Échec FFmpeg, `-WhatIf` ou `ShouldProcess` refusé :
aucune suppression. Les pistes keep n'ont pas de sidecar à retirer.

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

### -WhatIf

Affiche la ligne FFmpeg (`Show-CommandLine`), n'écrit pas le MKV, ne crée pas de
sortie finalisée, ne supprime pas de sidecar.

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

Prérequis : PowerShell 7+, ffmpeg/ffprobe (`Tetram.Media.FFmpeg`). Importer `.\Tetram.Media.Streams.psd1`. Toujours un update d'un MKV existant (pas de mux from-scratch).

Ne pas faire : attendre une suppression de piste (replace / add / keep seulement) ; compter sur `-RemoveSidecars` si FFmpeg échoue ; prendre le jeton fichier `commentary` pour autre chose que le disposition FFmpeg `comment` ; croire qu'un codec non mappé disparaît (il reste keep dans le MKV).

## RELATED LINKS

- [Split-MediaStream]()
