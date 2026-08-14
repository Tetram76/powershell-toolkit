---
document type: cmdlet
external help file: Tetram.Media.Streams-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Media.Streams
ms.date: 08/14/2026
PlatyPS schema version: 2024-05-01
title: Split-MediaStream
---

# Split-MediaStream

## SYNOPSIS

Extrait des flux d'un MKV vers des sidecars à côté du fichier.

## SYNTAX

### __AllParameterSets

```text
Split-MediaStream [-LiteralPath] <string> [-StreamType <string[]>] [-Language <string[]>] [-Force]
 [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Importer `Tetram.Media.Streams.psd1` (PowerShell 7+). `-LiteralPath` est un fichier `.mkv` existant.

`ffprobe` lit toutes les pistes ; l'index de collision (`.2`, `.3`) est calculé sur le MKV entier avant `-StreamType` / `-Language`. Extraire seulement la 2e VO anglais produit `film.eng.2.srt`.

Noms : `{basename}[.{langue}][.default][.forced][.commentary][.original][.dub][.hearing_impaired][.visual_impaired][.{n}].{ext}`. `basename` vient du MKV. Lecture depuis la fin ; un jeton restant = pas un sidecar. Langue omise si `und`/`unk`/absente. `dub` est un flag, pas une langue. Uniquement vidéo, audio et sous-titres : covers, polices et chapitres restent dans le MKV.

Copie FFmpeg (`-c copy`) vers un temporaire dans TEMP (`{guid}.srt`, etc.), puis `Move-Item` si succès. Le merge utilise `{guid}.mkv` dans TEMP. `Show-CommandLine` avant `ShouldProcess` (y compris `-WhatIf`). Cible existante : `-Force` ou confirmation. Codec A/V/S hors table : `Write-ErrorLog`, aucun sidecar. Flux hors A/V/S : ignorés (restent dans le MKV). Échec FFmpeg : pas de sidecar partiel. FFmpeg manquant : `Write-ErrorLog`, pas d'exception.

Aucun objet pipeline. Round-trip prévu avec `Merge-MediaStream` (les sidecars portent la grammaire ci-dessus).

## EXAMPLES

### Example 1: Extraire les sous-titres français

Intention : n'écrire que les pistes `Subtitle` dont la langue est `fra`. L'index
de collision a déjà été calculé sur tout le MKV : si deux SRT français existent,
le second s'appelle `film.fra.2.srt`.

```powershell
Split-MediaStream -LiteralPath 'D:\Media\film.mkv' -StreamType Subtitle -Language fra
```

### Example 2: Simuler l'extraction

Intention : afficher la ligne FFmpeg (`Show-CommandLine`) sans écrire de sidecar.
`-WhatIf` n'empêche pas l'affichage de la commande.

```powershell
Split-MediaStream -LiteralPath 'D:\Media\film.mkv' -WhatIf
```

### Example 3: Écraser des sidecars déjà présents

Intention : run réel après un dry-run. `-Force` saute `ShouldContinue` sur chaque
fichier cible existant.

```powershell
Split-MediaStream -LiteralPath 'D:\Media\film.mkv' -Force
```

### Example 4: Extraire la 2e VO anglais (collision source)

Intention : filtrer `eng` ne renumérote pas. Si le MKV a deux pistes anglais de
même clé, extraire seulement les sous-titres anglais écrit `film.eng.srt` et
`film.eng.2.srt` (le `.2` vient du MKV entier, pas du filtre).

```powershell
Split-MediaStream -LiteralPath 'D:\Media\film.mkv' -StreamType Subtitle -Language eng
```

### Example 5: Extraire toutes les pistes audio

Intention : `-StreamType Audio` n'extrait pas la vidéo ni les sous-titres.
Covers, polices et chapitres du MKV ne sont jamais extraits.

```powershell
Split-MediaStream -LiteralPath 'D:\Media\film.mkv' -StreamType Audio
```

## PARAMETERS

### -Confirm

Demande confirmation avant chaque `ShouldProcess` (impact Medium : pas de prompt
sauf si `-Confirm` est passé). N'équivaut pas à `-Force` (celui-ci concerne
`ShouldContinue` sur un sidecar déjà présent).

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

Écrase un sidecar déjà présent sans `ShouldContinue`. Sans `-Force`, une cible
existante demande confirmation ; un refus saute ce fichier. Sans effet sur
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

### -Language

Codes langue à extraire, tels quels (ex. `fra`, `eng`, `pt-BR`). Plusieurs valeurs = union.
L'index de collision (`.2`, `.3`) est calculé sur le MKV entier avant ce filtre :
extraire seulement la 2e VO anglais produit `film.eng.2.srt`. Omit pour toutes
les langues.

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

### -LiteralPath

Fichier `.mkv` source, existant. Chemin littéral (pas de jokers). Obligatoire.
Les sidecars sont écrits dans le même dossier.

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

### -StreamType

Classes à extraire : `Video`, `Audio`, `Subtitle`.
Plusieurs valeurs = union. Omit = ces trois classes. Covers, pièces jointes et
chapitres ne sont pas extraits. Un codec A/V/S hors
table (ex. `mpeg4`, `mov_text`, `alac`, `pcm_*`) fait échouer tout le split
(`Write-ErrorLog`, aucun sidecar) — même arrêt au merge.

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

### -WhatIf

Affiche la ligne FFmpeg (`Show-CommandLine`) et n'écrit aucun sidecar. La
commande est montrée avant `ShouldProcess`.

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

Prérequis : PowerShell 7+, ffmpeg/ffprobe (`Tetram.Media.FFmpeg`). Importer `.\Tetram.Media.Streams.psd1`. Copie bit-exacte (`-c copy`), pas de réencodage.

Ne pas faire : attendre une exception si ffmpeg manque ou si le chemin n'est pas un `.mkv` ; croire que `-Language` / `-StreamType` recalculent l'index `.2` (il vient du MKV source entier) ; traiter `dub` comme une langue ; prendre le jeton fichier `commentary` pour le disposition FFmpeg `comment` au split (le mapping est automatique au merge).

## RELATED LINKS

- [Merge-MediaStream]()
