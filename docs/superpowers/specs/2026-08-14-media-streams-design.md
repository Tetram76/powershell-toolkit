# Design — Tetram.Media.Streams (split / merge de flux)

Date : 2026-08-14  
Module : `Tetram.Media.Streams` (nouveau, racine du repo)  
Dépendances : `Utils/Tetram.Common`, `Utils/Tetram.Media.FFmpeg`

## Objectif

Round-trip **MKV uniquement** : extraire des pistes, les éditer hors conteneur, réinjecter un MKV **équivalent**.

Deux commandes, FFmpeg uniquement (`-c copy`) :

1. **Split** — extraire certains flux d’un `.mkv` vers des sidecars **à côté** du fichier (grammaire unique : langue, flags de disposition, collision).
2. **Merge** — réinjecter les sidecars dans **ce** MKV : un sidecar qui matche une piste la **remplace**, un sidecar sans match est **ajouté**, le reste du MKV est **conservé**.

Une invocation = un fichier MKV. Pas de `-Recurse`, pas de masques, pas de reconstruction à partir des seuls sidecars.

Les polices, covers, chapitres et pistes non extraites restent dans le MKV grâce au merge-update : le round-trip sidecar ne concerne que **vidéo, audio et sous-titres**.

## Décisions validées

| Sujet | Choix |
|---|---|
| Outil | FFmpeg / ffprobe uniquement (pas de mkvmerge, pas de manifeste JSON) |
| Copie | Stream copy, jamais de réencodage |
| Conteneur v1 | `.mkv` en entrée des deux commandes |
| Unité d’appel | Un fichier MKV ; pas de lot, pas de stem, pas de dossier |
| Merge | **Toujours** update du MKV (pas de switch `-Update`, pas de mux « sidecars seuls ») |
| Collision de noms | Suffixe `.2`, `.3`, … seulement si besoin ; **pas** de `.1` |
| Flags de disposition dans le nom | `default`, `forced`, `commentary`, `original`, `dub`, `hearing_impaired`, `visual_impaired` |
| Index de collision | Calculé sur **toutes** les pistes du MKV **source**, même si le split est filtré |
| Merge sortie | `-Destination` optionnel ; sinon le MKV d’entrée (in-place via temporaire) |
| Suppression de piste | Hors v1 (un sidecar manquant = keep) |
| Sidecars après merge | Conservés par défaut ; `-RemoveSidecars` les supprime après un mux **réussi** |
| Overwrite | `-Force` écrit ; sinon `ShouldContinue` ; refus = skip |
| WhatIf | Pas d’écriture ; **la ligne FFmpeg est quand même affichée** (`Show-CommandLine` avant `ShouldProcess`, comme Reencode) |
| Erreurs publiques | `Write-ErrorLog` puis return/continue ; pas d’exception vers l’appelant |
| Aide | Pages PlatyPS complètes (module + commandes), pas de stub |

## Hors scope (v1)

- Extraction / réinjection de covers (`attached_pic`), pièces jointes (polices) et chapitres : keep dans le MKV, pas de sidecar.
- Conversion d’un autre conteneur (MP4, AVI, …) vers MKV.
- Reconstruction d’un MKV à partir **uniquement** des sidecars (mux from-scratch).
- Suppression de piste.
- Traitement d’un dossier / `-Recurse` / `-InputMasks` / stem sans fichier.
- mkvmerge, manifeste JSON, conservation d’un ordre de pistes autre que : ordre du MKV source, puis ajouts par classe.
- Réencodage, décalage temporel (`delay`), noms de piste (`title`) dans le nom de fichier.
- Autres flags de disposition FFmpeg (`lyrics`, `karaoke`, `captions`, `descriptions`, `clean_effects`, …) : non représentés dans le nom ; perdus au replace, conservés sur les pistes keep.
- Codecs A/V/S sans entrée dans la table (dont `mpeg4`, `mov_text`, `alac`, `pcm_*`, VobSub) : split **et** merge **échouent** (`Write-ErrorLog` + return). Tout flux ni vidéo, ni audio, ni sous-titre (`data`, covers, polices, chapitres, …) : skip au split, keep au merge.
- Modification de `Tetram.Media.FFmpeg` / factorisation du probe Reencode.

## Architecture

### Fichiers

| Chemin | Rôle |
|---|---|
| `Tetram.Media.Streams.psd1` | Manifeste v1.0.0, PS 7+ / Core, `NestedModules` Common + FFmpeg, export des deux commandes |
| `Tetram.Media.Streams.psm1` | Commandes publiques + orchestration |
| `Tetram.Media.Streams.Private/*.ps1` | Grammaire, carte codec→ext, sonde, construction d’arguments FFmpeg (dot-source depuis le psm1, même schéma que Reencode) |
| `tests/Tetram.Media.Streams.Tests.ps1` | Manifeste, exports, WhatIf, FFmpeg absent, overwrite, MKV obligatoire |
| `tests/Tetram.Media.Streams.Private/*.Tests.ps1` | Grammaire, collision, matching replace/add/keep — sans binaire FFmpeg |
| `docs/help/Tetram.Media.Streams/` | Page module + `Split-MediaStream.md` + `Merge-MediaStream.md` (fr-FR, PlatyPS) |
| `fr-FR/Tetram.Media.Streams-Help.xml` | MAML généré via `tools/New-HelpMaml.ps1`, comme les autres modules |

Les `.ps1` privés sont dot-sourcés depuis le root psm1 (pas en `NestedModules`) pour que `Write-ErrorLog` / `Show-CommandLine` / `Get-FFmpegPath` du scope parent soient visibles.

### Commandes exportées

```
Split-MediaStream -LiteralPath <fichier.mkv>
    [-StreamType Video, Audio, Subtitle]
    [-Language <code[]>]
    [-Force] [-WhatIf] [-Confirm]

Merge-MediaStream -LiteralPath <fichier.mkv>
    [-Destination <fichier.mkv>]
    [-RemoveSidecars]
    [-Force] [-WhatIf] [-Confirm]
```

`SupportsShouldProcess = $true`, `ConfirmImpact = 'Medium'`, `PositionalBinding = $false`.  
`-LiteralPath` est obligatoire, position 0, **fichier `.mkv` existant**. Pas de pipeline, pas d’objets émis (journalisation console uniquement, comme `Remove-EmptyDirs`).

`-Force` est le switch d’overwrite des **fichiers de sortie** (sidecars au split, MKV cible au merge). Il n’est pas le `-Force` de `Write-InfoLog`.

### Helpers privés (contrats)

- `ConvertTo-StreamFileName` / `ConvertFrom-StreamFileName` — purs, sans I/O.
- `Get-ElementaryExtension` — codec (+ type) → extension ; `$null` si non mappable.
- `Get-MediaStreamDescriptors` — JSON ffprobe → descripteurs (type, index global, langue, flags, codec, nom d’attachement, clé de collision).
- `Resolve-StreamCollisionIndex` — attribue `n` (absent si 1, sinon ≥ 2) **parmi les descripteurs du MKV source** qui partagent la même clé de classe (voir ci-dessous).
- `Invoke-StreamsFFmpeg` — `Show-CommandLine` **puis** `ShouldProcess` **puis** exécution. Miroir de Reencode : sous `-WhatIf` la ligne s’affiche, FFmpeg ne tourne pas. `NoPathDetectionParameters` : `'metadata*'`, `'disposition*'`, `'map*'`.

FFmpeg / ffprobe : `Get-FFmpegPath` / `Get-FfprobePath`. Échec → catch au point d’entrée → `Write-ErrorLog` → return.

## Grammaire des noms

Écriture (ordre stable) :

```
{basename}[.{langue}][.default][.forced][.commentary][.original][.dub][.hearing_impaired][.visual_impaired][.{n}].{ext}
```

Exemples : `film.h264`, `film.eng.aac`, `film.fra.forced.srt`, `film.eng.commentary.aac`, `film.eng.hearing_impaired.srt`, `film.eng.default.2.ac3`, `film.cover.jpg`, `film.chapters.ffmeta`, `film.Arial.ttf`.

Jetons de classe réservés (pas des flags de disposition) : `cover`, `chapters`. Un fichier n’est cover / chapitres que s’il porte le jeton **et** l’extension de la classe.

### Langue

- Source : `tags.language` ffprobe.
- **Omise** si absente, vide, ou équivalente à indéterminée : `und`, `unk` (comparaison insensible à la casse).
- Écriture : code tel quel (ISO 639 ou BCP-47, ex. `pt-BR`). Pas de normalisation `fre`↔`fra` ni `en`↔`eng`.
- Parse (flux A/V/S) : depuis la **fin** du nom (suffixe `n`, puis flags, puis au plus un tag langue tel quel). Basename = celui du MKV, jamais du sidecar. S’il reste un jeton → ce n’était pas un sidecar. `dub` est un flag. `und` / `unk` = pas de langue.

### Flags

Présents seulement quand le bit ffprobe correspondant vaut 1 (mot délimité par `.`, norme MKVToolNix). Couverture A/V/S uniquement (pas les covers, pièces jointes, chapitres).

| Jeton fichier (écriture) | Champ ffprobe `disposition.*` | Valeur FFmpeg `-disposition` |
|---|---|---|
| `default` | `default` | `default` |
| `forced` | `forced` | `forced` |
| `commentary` | `comment` | `comment` |
| `original` | `original` | `original` |
| `dub` | `dub` | `dub` |
| `hearing_impaired` | `hearing_impaired` | `hearing_impaired` |
| `visual_impaired` | `visual_impaired` | `visual_impaired` |

Parse : depuis la fin (insensible à la casse) : `n` ≥ 2, puis les flags (ordre indifférent), puis au plus un tag langue. Alias lecture seulement : `comment` et `comments` → `commentary`. Jeton restant → pas un sidecar de ce MKV.

Écriture : toujours langue, puis les flags **présents** dans l’ordre du tableau, puis `n`.

### Collision

Clé selon la classe :

- A/V/S : `(classe, langue normalisée, ensemble des flags ci-dessus, extension)`
- Cover : `(cover, extension)` — le jeton `cover` est fixe
- Pièce jointe : `(attachment, nom d’origine sanitisé, extension)`
- Chapitres : singleton — jeton réservé `chapters` + `.ffmeta`

Parmi les pistes du **MKV source** qui partagent cette clé, index 1, 2, 3… dans l’ordre ffprobe. L’index 1 **n’apparaît pas** dans le nom ; à partir de 2 : `.2`, `.3`, … Un split filtré qui n’extrait que la 2ᵉ piste anglaise produit `film.eng.2.srt`, pas `film.eng.srt`.

### Classes de fichiers (parse)

Le parse commence par l’extension (allowlist). Selon la classe :

| Classe | Extensions | Jetons |
|---|---|---|
| Vidéo / audio / sous-titres | voir table codec | langue, flags de disposition, n |
| Cover | `.jpg`, `.jpeg`, `.png` **et** jeton réservé `cover` | `cover`, n optionnel — pas de langue |
| Pièce jointe (police, etc.) | `.ttf`, `.otf`, `.ttc`, `.woff`, `.woff2`, `.bin` | pas de langue / flags ; tous les jetons restants (sauf n) = nom d’origine sanitisé, recollés par `.` |
| Chapitres | `.ffmeta` **et** jeton réservé `chapters` | `chapters` — pas de langue / flags / n |

Les conteneurs (`.mkv`, `.mp4`, `.avi`, `.mov`, `.webm`, `.m4v`, `.wmv`, `.flv`, `.mpeg`, `.mpg`, `.ts`) ne sont **jamais** des sidecars.

### Sanitisation des noms d’attachement

Caractères interdits Windows / séparateur `.` de grammaire : remplacés par `_`. Le nom original (avant sanitisation) est réinjecté au mux via metadata `filename` si ffprobe l’a fourni à l’extract ; sinon le nom sanitisé.

## Carte codec → extension

Copie uniquement. Codec A/V/S absent de la table → split **et** merge **échouent** (`Write-ErrorLog` + return). Pas de fichier élémentaire « fourre-tout ». Flux hors A/V/S : skip au split, keep au merge.

| Codec ffprobe (`codec_name`) | Ext | Classe |
|---|---|---|
| `h264`, `avc` | `.h264` | Vidéo |
| `hevc`, `h265` | `.hevc` | Vidéo |
| `av1`, `vp8`, `vp9` | `.ivf` | Vidéo |
| `mpeg2video` | `.m2v` | Vidéo |
| `vc1` | `.vc1` | Vidéo |
| `mjpeg` avec `attached_pic` | `.jpg` + jeton `cover` | Cover |
| `png` avec `attached_pic` | `.png` + jeton `cover` | Cover |
| `aac` | `.aac` | Audio |
| `ac3` | `.ac3` | Audio |
| `eac3` | `.eac3` | Audio |
| `dts`, `dca` | `.dts` | Audio |
| `truehd` | `.thd` | Audio |
| `flac` | `.flac` | Audio |
| `opus` | `.opus` | Audio |
| `mp3` | `.mp3` | Audio |
| `mp2` | `.mp2` | Audio |
| `vorbis` | `.ogg` | Audio |
| `subrip` | `.srt` | Sous-titres |
| `ass` | `.ass` | Sous-titres |
| `ssa` | `.ssa` | Sous-titres |
| `webvtt` | `.vtt` | Sous-titres |
| `hdmv_pgs_subtitle` | `.sup` | Sous-titres |
| `mpeg4`, `mov_text`, `alac`, `pcm_*`, `dvd_subtitle`, `dvb_subtitle`, autres A/V/S | non mappé (split et merge : échec de l’opération) | — |

Pièces jointes (`codec_type` = `attachment`) : extension d’après `tags.filename` / mime ; défaut `.bin` si inconnue mais toujours extraite (classe pièce jointe).

Chapitres : présence d’entrées `chapters` dans ffprobe → un seul `basename.chapters.ffmeta` (dump `-f ffmetadata`). Un `.ffmeta` sans jeton `chapters` n’est pas un sidecar.

## Flux — Split-MediaStream

1. Résoudre ffmpeg/ffprobe ; échec → `Write-ErrorLog` + return.
2. Fichier existant, extension `.mkv` (insensible à la casse) ; sinon log + return. Le chemin est ensuite résolu via le provider (`Resolve-Path -LiteralPath`) : `~` et lecteurs PS deviennent un chemin filesystem, contrairement à `GetFullPath`.
3. ffprobe JSON (`-show_format -show_streams -show_chapters -of json`). JSON invalide ou vide → log + return.
4. Codec A/V/S absent de la table → `Write-ErrorLog` + return (aucun sidecar), même si `-StreamType` / `-Language` l’aurait exclu. Flux hors A/V/S (`data`, attachment, …) : ignorés, pas un échec.
5. Construire les descripteurs, **attribuer les index de collision sur l’ensemble du MKV**, puis filtrer :
   - `-StreamType` : si omis, tout. `Chapter` = sidecar ffmeta. `Attachment` = pièces jointes (pas les covers). `Video` = pistes vidéo **y compris** `attached_pic` (covers).
   - `-Language` : comparaison insensible à la casse sur le code **tel que dans le fichier**. Les flux sans langue (indéterminés) **ne matchent pas** un filtre `-Language`. Chapitres et pièces jointes **ignorent** `-Language`.
6. Pour chaque descripteur retenu : calculer le chemin sidecar (même dossier que le MKV).
   - Si la cible existe : `-WhatIf` → pas de prompt, on affiche quand même la commande FFmpeg prévue ; exécution réelle → `-Force` ou `ShouldContinue` ; refus → skip + `Write-InfoLog`.
   - `Show-CommandLine` puis `ShouldProcess` puis `ffmpeg` vers un temporaire (`{sidecar}.tmp`), `-c copy`. Succès → `Move-Item` vers le sidecar ; échec → suppression du temporaire (un `-y` direct tronquerait un sidecar déjà bon).
7. Un flux en erreur FFmpeg : `Write-ErrorLog`, **continuer** les autres ; aucun sidecar partiel laissé.
8. Aucun flux retenu après filtre : `Write-InfoLog` (pas une erreur).

Le MKV d’origine n’est pas modifié par le split.

## Flux — Merge-MediaStream

`-LiteralPath` = le MKV à mettre à jour (fichier `.mkv` existant). Répertoire, stem, autre extension → `Write-ErrorLog` + return.

Basename = nom sans extension, dossier = parent. Ramasser les fichiers du dossier dont le nom commence par `{basename}.` **ou** égalité `{basename}.{ext}`, extension dans l’allowlist sidecar, parse de grammaire réussi. La comparaison de casse du préfixe **suit le système de fichiers du dossier** (sensible ⇔ `Ordinal`, insensible ⇔ `OrdinalIgnoreCase`). Détection **sans écriture** : autre casse du MKV source déjà présent (`film.mkv` / `Film.mkv`) ; `Get-Item.FullName` pour savoir si c’est le même fichier. **Toujours exclure** le MKV d’entrée, `-Destination`, et toute extension conteneur.

Aucun sidecar → `Write-ErrorLog` + return.

Codec A/V/S hors table → `Write-ErrorLog` + return (pas de mux), comme au split. Tout flux ni vidéo, ni audio, ni sous-titre : keep (`-map 0:<index>`), jamais sidecar.

### Destination

- Si `-Destination` fourni : ce chemin (doit se terminer par `.mkv` ; sinon log + return). S’il existe déjà, ce doit être un **fichier** (pas un dossier nommé `*.mkv`).
- Sinon : le MKV d’entrée (update in-place).

Overwrite de la cible (in-place ou `-Destination` déjà présent) : `-Force` ou `ShouldContinue` ; refus → return sans mux. Sous `-WhatIf` : pas de prompt `ShouldContinue`, `Show-CommandLine` du mux prévu, pas d’écriture.

### Remap (replace / add / keep)

Entrée 0 = le MKV source. Entrées suivantes = sidecars.

Pour chaque piste du MKV (ordre ffprobe) :

- Si un sidecar a la **même clé de classe** (section Collision) **et le même index de collision** → mapper le sidecar (**replace**).
- Sinon → mapper la piste d’origine (**keep**).

Sidecars sans match → mappés en plus (**add**), après les pistes d’origine, ordre de classes : vidéo (covers en dernier parmi la vidéo, disposition `attached_pic`), audio, sous-titres, pièces jointes (`-attach` + metadata filename/mimetype), chapitres.

Chapitres : si `basename.chapters.ffmeta` présent → remplace les chapitres ; sinon conserve ceux du MKV.

Chaque piste **issue d’un sidecar** (replace ou add) reçoit **explicitement** :

- `-metadata:s:<type>:<i> language=<code>` si langue présente, sinon `language=und`
- `-disposition:<type>:<i>` : `0` si aucun flag, sinon les noms FFmpeg du tableau joints par `+` (ex. `default+comment+hearing_impaired`). Le jeton fichier `commentary` devient `comment` côté FFmpeg.

Les pistes **keep** conservent métadonnées et dispositions du MKV source (pas de réécriture).

Écriture : temporaire `{Destination}.tmp` dans le même dossier (nom unique si collision), puis `Move-Item` vers la destination si succès. Sous `-WhatIf`, le temporaire n’est pas créé.

Un sidecar manquant n’enlève jamais une piste.

### `-RemoveSidecars`

Après un mux **réussi** seulement : supprimer uniquement les sidecars **effectivement muxés** (replace + add), via leur `FullName` issu de l’énumération du dossier — jamais un nom reconstruit ni un glob. Un fichier du dossier non retenu (autre basename, y compris si seule la casse diffère sur un FS sensible) n’est pas touché. Le MKV source/cible n’est jamais dans cette liste.

- Échec FFmpeg / `Move-Item` → aucune suppression.
- Chaque suppression passe par `ShouldProcess` (donc `-WhatIf` affiche sans effacer).
- `-Force` n’est pas requis pour ces sidecars : ce sont des fichiers de travail que l’utilisateur a demandé d’enlever ; un sidecar en lecture seule → `Write-ErrorLog` et on continue les autres.

## Journalisation

- `Show-CommandLine` pour **chaque** invocation FFmpeg, y compris WhatIf, **avant** `ShouldProcess`.
- `Write-ErrorLog` : échecs (voir ci-dessus).
- `Write-InfoLog` : skip overwrite, aucun flux filtré, résumé WhatIf (couleur Magenta, comme Reencode / Remove-EmptyDirs).
- `Write-DebugLog` : descripteurs / clés de matching.

Pas de `Write-InfoLog -Force` : les infos suivent le Verbose / préférence par défaut de `Write-InfoLog` (comme EmptyDirs), hors `Show-CommandLine` qui s’affiche toujours.

## Aide

Livrable **complet**, généré/tenu via `tools/New-HelpMarkdown.ps1` (découverte auto des `.psd1` racine) puis rédaction manuelle du fond (fr-FR), comme les autres modules :

- Synopsis, description (round-trip MKV, grammaire, collision source, replace/add/keep).
- Tous les paramètres, y compris WhatIf / Confirm / Force / RemoveSidecars.
- Exemples : split `-StreamType Subtitle -Language fra` ; merge (replace) ; merge (add d’un `.srt` posé à la main) ; merge `-RemoveSidecars` ; `-WhatIf` (la commande FFmpeg s’affiche).
- Notes : le MKV n’est pas un sidecar ; le merge ne supprime pas de piste ; `-RemoveSidecars` uniquement après mux réussi ; codec A/V/S hors table arrête split et merge ; hors A/V/S = keep.

Commentaires d’aide `.EXTERNALHELP Tetram.Media.Streams-Help.xml` sur les deux fonctions exportées.

## Tests

Tag `Integration` pour tout appel au vrai FFmpeg (exclu du CI, cf. `Invoke-Tests.ps1 -ExcludeTag Integration`). Le CI couvre déjà tout `*.psm1` racine + `Utils/` : le nouveau module entre dans la couverture sans changer le script.

| Cas | Attendu |
|---|---|
| `Test-ModuleManifest` | OK |
| Exports = Split + Merge uniquement | OK |
| Split / merge sur non-`.mkv` | `Write-ErrorLog`, pas de throw |
| Format : flags `commentary` / `hearing_impaired` / `dub` + `n` | Nom et parse inverses ; `comment` lu comme `commentary` |
| Langue `und` / absente | Pas de jeton langue |
| Collision 2 pistes `eng`+`.srt` | `.srt` et `.2.srt` |
| Split filtré sur la 2ᵉ | Fichier `.2.srt` (index source) |
| Cover / police / `chapters.ffmeta` | Parse de classe ; `film.ffmeta` sans jeton `chapters` ignoré |
| Matching : replace / add / keep | Clés stables |
| FFmpeg introuvable | `Write-ErrorLog`, pas de throw |
| `-WhatIf` | Aucune écriture disque ; `Show-CommandLine` invoqué |
| Cible existante sans `-Force` | `ShouldContinue` mocké refus → pas d’écriture |
| Allowlist merge | `film.mkv` non ramassé comme sidecar |
| `-RemoveSidecars` après succès | Sidecars retenus absents ; MKV intact |
| `-RemoveSidecars` + mux échoué | Sidecars toujours présents |
| `-RemoveSidecars -WhatIf` | Sidecars toujours présents |

Les tests de grammaire passent des descripteurs / noms de fichiers synthétiques, pas de médias réels.

## Critères de succès

- Extraire un `.srt` (y compris la 2ᵉ piste d’une langue), l’éditer, merger : la bonne piste est remplacée ; vidéo, audio, polices et chapitres non extraits sont intacts.
- Poser un nouveau `film.spa.srt` à côté et merger : la piste est **ajoutée**, le reste inchangé.
- `Merge -RemoveSidecars` après succès : les sidecars retenus disparaissent ; le MKV reste. Échec mux ou `-WhatIf` : sidecars intacts.
- `-WhatIf` affiche les lignes FFmpeg via `Show-CommandLine` et ne crée/écrase aucun fichier.
- `-Force` écrase ; sans `-Force`, une cible existante demande confirmation.
- L’aide `Get-Help Split-MediaStream` / `Merge-MediaStream` est exploitable (pas un stub).
- Aucune exception non gérée au niveau des deux commandes exportées si FFmpeg manque ou si le fichier n’est pas un MKV.
