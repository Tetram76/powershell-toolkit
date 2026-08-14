# Design — Tetram.Media.Streams (split / merge de flux)

Date : 2026-08-14  
Module : `Tetram.Media.Streams` (nouveau, racine du repo)  
Dépendances : `Utils/Tetram.Common`, `Utils/Tetram.Media.FFmpeg`

## Objectif

Deux commandes symétriques, FFmpeg uniquement (`-c copy`) :

1. **Split** — extraire les flux d’un fichier média vers des sidecars **à côté** du fichier, nommés selon une grammaire unique (langue, forced, default, collision).
2. **Merge** — réassembler les sidecars qui partagent une base de nom en un MKV, soit **reconstruction** (uniquement les sidecars), soit **update** (MKV d’origine + sidecars en remplacement ou ajout).

Usage principal : éditer des pistes hors conteneur puis reconstruire un MKV équivalent. Archivage des flux et conversion conteneur → MKV via demux/mux restent possibles.

Une invocation = un fichier (ou une base de recherche pour le merge). Pas de `-Recurse`, pas de masques configurables.

## Décisions validées

| Sujet | Choix |
|---|---|
| Outil | FFmpeg / ffprobe uniquement (pas de mkvmerge, pas de manifeste JSON) |
| Copie | Stream copy, jamais de réencodage |
| Unité d’appel | Un fichier / une base ; pas de lot récursif |
| Collision de noms | Suffixe `.2`, `.3`, … seulement si besoin ; **pas** de `.1` |
| Index de collision | Calculé sur **toutes** les pistes du fichier **source**, même si le split est filtré |
| Merge entrée | Fichier de la famille **ou** stem sans extension |
| Merge sortie | `-Destination` optionnel ; sinon `{basename}.mkv` d’après les sidecars retenus |
| Update | `-Update` : l’entrée est un MKV ; replace / add / keep selon la clé de matching |
| Suppression de piste | Uniquement en reconstruction (merge **sans** `-Update`) |
| Sidecars après merge | Jamais supprimés |
| Overwrite | `-Force` écrit ; sinon `ShouldContinue` ; refus = skip |
| WhatIf | Pas d’écriture ; **la ligne FFmpeg est quand même affichée** (`Show-CommandLine` avant `ShouldProcess`, comme Reencode) |
| Erreurs publiques | `Write-ErrorLog` puis return/continue ; pas d’exception vers l’appelant |
| Aide | Pages PlatyPS complètes (module + commandes), pas de stub |

## Hors scope (v1)

- Traitement d’un dossier / `-Recurse` / `-InputMasks`.
- mkvmerge, manifeste JSON, conservation de l’ordre original des pistes au-delà de l’ordre par type + index de collision.
- Suppression automatique des sidecars après mux.
- Réencodage, décalage temporel (`delay`), noms de piste (`title`) dans le nom de fichier.
- Codecs sans entrée dans la table (dont `mpeg4`, `mov_text`, VobSub) : skip + log ; ils restent dans le MKV via `-Update` si on ne les extrait pas.
- Modification de `Tetram.Media.FFmpeg` / factorisation du probe Reencode.

## Architecture

### Fichiers

| Chemin | Rôle |
|---|---|
| `Tetram.Media.Streams.psd1` | Manifeste v1.0.0, PS 7+ / Core, `NestedModules` Common + FFmpeg, export des deux commandes |
| `Tetram.Media.Streams.psm1` | Commandes publiques + orchestration |
| `Tetram.Media.Streams.Private/*.ps1` | Grammaire, carte codec→ext, sonde, construction d’arguments FFmpeg (dot-source depuis le psm1, même schéma que Reencode) |
| `tests/Tetram.Media.Streams.Tests.ps1` | Manifeste, exports, WhatIf, FFmpeg absent, overwrite |
| `tests/Tetram.Media.Streams.Private/*.Tests.ps1` | Grammaire, collision, matching update — sans binaire FFmpeg |
| `docs/help/Tetram.Media.Streams/` | Page module + `Split-MediaStream.md` + `Merge-MediaStream.md` (fr-FR, PlatyPS) |
| `fr-FR/Tetram.Media.Streams-Help.xml` | MAML généré via `tools/New-HelpMaml.ps1`, comme les autres modules |

Les `.ps1` privés sont dot-sourcés depuis le root psm1 (pas en `NestedModules`) pour que `Write-ErrorLog` / `Show-CommandLine` / `Get-FFmpegPath` du scope parent soient visibles.

### Commandes exportées

```
Split-MediaStream -LiteralPath <média>
    [-StreamType Video, Audio, Subtitle, Attachment, Chapter]
    [-Language <code[]>]
    [-Force] [-WhatIf] [-Confirm]

Merge-MediaStream -LiteralPath <base>
    [-Destination <mkv>]
    [-Update]
    [-Force] [-WhatIf] [-Confirm]
```

`SupportsShouldProcess = $true`, `ConfirmImpact = 'Medium'`, `PositionalBinding = $false`.  
`-LiteralPath` est obligatoire, position 0. Pas de pipeline, pas d’objets émis (journalisation console uniquement, comme `Remove-EmptyDirs`).

`-Force` est le switch d’overwrite des **fichiers de sortie** (sidecars ou MKV cible). Il n’est pas le `-Force` de `Write-InfoLog`.

### Helpers privés (contrats)

- `ConvertTo-StreamFileName` / `ConvertFrom-StreamFileName` — purs, sans I/O.
- `Get-ElementaryExtension` — codec (+ type) → extension ; `$null` si non mappable.
- `Get-MediaStreamDescriptors` — JSON ffprobe → descripteurs (type, index global, langue, flags, codec, nom d’attachement, clé de collision).
- `Resolve-StreamCollisionIndex` — attribue `n` (absent si 1, sinon ≥ 2) **parmi les descripteurs du fichier source** qui partagent la même clé de classe (voir ci-dessous).
- `Invoke-StreamsFFmpeg` — `Show-CommandLine` **puis** `ShouldProcess` **puis** exécution. Miroir de Reencode : sous `-WhatIf` la ligne s’affiche, FFmpeg ne tourne pas. `NoPathDetectionParameters` : `'metadata*'`, `'disposition*'`, `'map*'`.

FFmpeg / ffprobe : `Get-FFmpegPath` / `Get-FfprobePath`. Échec → catch au point d’entrée → `Write-ErrorLog` → return.

## Grammaire des noms

Écriture (ordre stable) :

```
{basename}[.{langue}][.forced][.default][.{n}].{ext}
```

Exemples : `film.h264`, `film.eng.aac`, `film.fra.forced.srt`, `film.eng.default.2.ac3`, `film.cover.jpg`, `film.Arial.ttf`, `film.ffmeta`.

### Langue

- Source : `tags.language` ffprobe.
- **Omise** si absente, vide, ou équivalente à indéterminée : `und`, `unk` (comparaison insensible à la casse).
- Écriture : code tel quel (typiquement ISO 639-2, 3 lettres). Pas de normalisation `fre`↔`fra` ni `en`↔`eng`.
- Parse (flux A/V/S uniquement) : jeton de 2 ou 3 lettres qui n’est pas un flag réservé. `und` / `unk` ne sont jamais écrits et, s’ils apparaissent, sont traités comme « pas de langue ».

### Flags

- `.forced` si `disposition.forced == 1`.
- `.default` si `disposition.default == 1`.
- Présents seulement quand le flag est à 1 (norme MKVToolNix : mot délimité par `.`).
- Parse : ordre des jetons `forced` / `default` / langue / `n` indifférent ; l’écriture suit toujours langue → forced → default → n.

### Collision

Clé selon la classe :

- A/V/S : `(classe, langue normalisée, forced, default, extension)`
- Cover : `(cover, extension)` — le jeton `cover` est fixe
- Pièce jointe : `(attachment, nom d’origine sanitisé, extension)`
- Chapitres : singleton (un seul `basename.ffmeta`)

Parmi les pistes du **source** qui partagent cette clé, index 1, 2, 3… dans l’ordre ffprobe. L’index 1 **n’apparaît pas** dans le nom ; à partir de 2 : `.2`, `.3`, … Un split filtré qui n’extrait que la 2ᵉ piste anglaise produit `film.eng.2.srt`, pas `film.eng.srt`.

### Classes de fichiers (parse)

Le parse commence par l’extension (allowlist). Selon la classe :

| Classe | Extensions | Jetons |
|---|---|---|
| Vidéo / audio / sous-titres | voir table codec | langue, forced, default, n |
| Cover | `.jpg`, `.jpeg`, `.png` **et** jeton réservé `cover` | `cover`, n optionnel — pas de langue |
| Pièce jointe (police, etc.) | `.ttf`, `.otf`, `.ttc`, `.woff`, `.woff2`, `.bin` | pas de langue / flags ; tous les jetons restants (sauf n) = nom d’origine sanitisé, recollés par `.` |
| Chapitres | `.ffmeta` | aucun jeton de piste ; le fichier entier est le sidecar chapitres |

Les conteneurs (`.mkv`, `.mp4`, `.avi`, `.mov`, `.webm`, `.m4v`, `.wmv`, `.flv`, `.mpeg`, `.mpg`, `.ts`) ne sont **jamais** des sidecars. Pas de fallback `.ts` : un codec non tabulaire n’est pas extrait.

### Sanitisation des noms d’attachement

Caractères interdits Windows / séparateur `.` de grammaire : remplacés par `_`. Le nom original (avant sanitisation) est réinjecté au mux via metadata `filename` si ffprobe l’a fourni à l’extract ; sinon le nom sanitisé.

## Carte codec → extension

Copie uniquement. Codec absent de la table → **skip + `Write-ErrorLog`** (le flux n’est pas extrait ; en `-Update` il reste dans le MKV si on ne l’a pas extraite). Pas de fichier élémentaire « fourre-tout ».

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
| `pcm_*`, `alac` | `.wav` | Audio |
| `subrip` | `.srt` | Sous-titres |
| `ass` | `.ass` | Sous-titres |
| `ssa` | `.ssa` | Sous-titres |
| `webvtt` | `.vtt` | Sous-titres |
| `hdmv_pgs_subtitle` | `.sup` | Sous-titres |
| `mpeg4`, `mov_text`, `dvd_subtitle`, `dvb_subtitle`, autres | non mappé (skip + log) | — |

Pièces jointes (`codec_type` = `attachment`) : extension d’après `tags.filename` / mime ; défaut `.bin` si inconnue mais toujours extraite (classe pièce jointe).

Chapitres : présence d’entrées `chapters` dans ffprobe → un seul `basename.ffmeta` (dump `-f ffmetadata`).

## Flux — Split-MediaStream

1. Résoudre ffmpeg/ffprobe ; échec → `Write-ErrorLog` + return.
2. `Test-Path -LiteralPath` fichier ; sinon log + return.
3. ffprobe JSON (`-show_format -show_streams -show_chapters -of json`). JSON invalide ou vide → log + return.
4. Construire les descripteurs, **attribuer les index de collision sur l’ensemble du fichier**, puis filtrer :
   - `-StreamType` : si omis, tout. `Chapter` = sidecar ffmeta. `Attachment` = pièces jointes (pas les covers). `Video` = pistes vidéo **y compris** `attached_pic` (covers).
   - `-Language` : comparaison insensible à la casse sur le code **tel que dans le fichier**. Les flux sans langue (indéterminés) **ne matchent pas** un filtre `-Language`. Chapitres et pièces jointes **ignorent** `-Language`.
5. Pour chaque descripteur retenu : calculer le chemin sidecar (même dossier que le média).
   - Si la cible existe : `-WhatIf` → pas de prompt, on affiche quand même la commande FFmpeg prévue ; exécution réelle → `-Force` ou `ShouldContinue` ; refus → skip + `Write-InfoLog`.
   - `Show-CommandLine` puis `ShouldProcess` puis `ffmpeg -hide_banner -i <média> -map 0:<index> -c copy -y <sidecar>` (et variante chapitres / `-dump_attachment` ou `-map 0:t:N` selon le type). Pour `h264` / `hevc` extraits d’un MP4/MOV : bitstream filter `h264_mp4toannexb` / `hevc_mp4toannexb` afin que le fichier élémentaire soit lisible.
6. Un flux en erreur FFmpeg : `Write-ErrorLog`, **continuer** les autres.
7. Aucun flux retenu après filtre : `Write-InfoLog` (pas une erreur).

Le fichier média d’origine n’est jamais modifié ni supprimé.

## Flux — Merge-MediaStream

### Résolution de la base

`-LiteralPath` = base de recherche :

- Fichier existant (leaf) → dossier = parent, basename = nom sans extension.
- Répertoire existant → `Write-ErrorLog` + return (ambigu : plusieurs films).
- Sinon, **stem** : le parent doit exister ; basename = dernier segment (ex. `D:\Media\film`). Parent absent → log + return.

Ramasser les fichiers du dossier dont le nom commence par `{basename}.` **ou** égalité `{basename}.{ext}`, extension dans l’allowlist sidecar, parse de grammaire réussi. **Toujours exclure** : le fichier `-LiteralPath` s’il existe, `-Destination`, et toute extension conteneur (`.mkv`, `.mp4`, `.ts`, …).

Aucun sidecar → `Write-ErrorLog` + return.

### Destination

- Si `-Destination` fourni : ce chemin (doit se terminer par `.mkv` ; sinon log + return).
- Sinon : `Join-Path <dossier> (<basename> + '.mkv')`.
- `-Update` : l’entrée résolue **doit** être un fichier `.mkv` existant ; si `-Destination` est omis, la cible **est** ce MKV (update in-place via temporaire). `-Update` sur un stem ou un `.srt` → log + return.

### Reconstruction (pas de `-Update`)

Entrées FFmpeg = uniquement les sidecars, ordre :

1. Vidéo (covers en dernier parmi la vidéo, disposition `attached_pic`)
2. Audio
3. Sous-titres
4. Pièces jointes (`-attach` + metadata filename/mimetype)
5. Chapitres (`-f ffmetadata` + `-map_chapters`)

Dans une classe : index de collision croissant (absent = 1).

Chaque piste reçoit **explicitement** :

- `-metadata:s:<type>:<i> language=<code>` si langue présente, sinon `language=und`
- `-disposition:<type>:<i>` : `0` par défaut, ou `default`, `forced`, `default+forced` selon les jetons. Obligatoire : sans cela FFmpeg/Matroska remettrait `default=1` sur trop de pistes.

Sortie : fichier temporaire `{Destination}.tmp` dans le même dossier (nom unique si collision), puis `Move-Item` vers la destination si succès. Sous `-WhatIf`, le temporaire n’est pas créé.

### Update (`-Update`)

Entrée 0 = le MKV source. Entrées suivantes = sidecars.

Pour chaque piste du MKV (ordre ffprobe) :

- Si un sidecar a la **même clé de classe** (section Collision) **et le même index de collision** → mapper le sidecar (**replace**).
- Sinon → mapper la piste d’origine (**keep**).

Sidecars sans match → mappés en plus (**add**), après les pistes d’origine, même ordre de classes.

Chapitres : si `basename.ffmeta` présent → remplace les chapitres ; sinon conserve ceux du MKV.

Couverture : même logique de clé (`cover` + n + ext).

Écriture via temporaire puis remplacement de la cible (in-place ou `-Destination`).

Il n’y a **pas** de suppression de piste en update : un sidecar manquant = keep.

### Overwrite de la destination

Si la cible existe déjà (reconstruction vers `film.mkv` encore présent, ou update in-place) : `-Force` ou `ShouldContinue` ; refus → return sans mux. Sous `-WhatIf` : pas de prompt `ShouldContinue`, `Show-CommandLine` du mux prévu, pas d’écriture.

## Journalisation

- `Show-CommandLine` pour **chaque** invocation FFmpeg, y compris WhatIf, **avant** `ShouldProcess`.
- `Write-ErrorLog` : échecs (voir ci-dessus).
- `Write-InfoLog` : skip overwrite, aucun flux filtré, résumé WhatIf (couleur Magenta, comme Reencode / Remove-EmptyDirs).
- `Write-DebugLog` : descripteurs / clés de matching.

Pas de `Write-InfoLog -Force` : les infos suivent le Verbose / préférence par défaut de `Write-InfoLog` (comme EmptyDirs), hors `Show-CommandLine` qui s’affiche toujours.

## Aide

Livrable **complet**, généré/tenu via `tools/New-HelpMarkdown.ps1` (découverte auto des `.psd1` racine) puis rédaction manuelle du fond (fr-FR), comme les autres modules :

- Synopsis, description (split vs merge vs update, grammaire, collision source).
- Tous les paramètres, y compris WhatIf / Confirm / Force.
- Exemples : split intégral ; split `-StreamType Subtitle -Language fra` ; merge reconstruction ; merge `-Update` (replace + add) ; `-WhatIf` (la commande FFmpeg s’affiche).
- Notes : le MKV d’origine n’est pas un sidecar ; `-Update` ne supprime pas de piste ; codecs non mappés.

Commentaires d’aide `.EXTERNALHELP Tetram.Media.Streams-Help.xml` sur les deux fonctions exportées.

## Tests

Tag `Integration` pour tout appel au vrai FFmpeg (exclu du CI, cf. `Invoke-Tests.ps1 -ExcludeTag Integration`). Le CI couvre déjà tout `*.psm1` racine + `Utils/` : le nouveau module entre dans la couverture sans changer le script.

| Cas | Attendu |
|---|---|
| `Test-ModuleManifest` | OK |
| Exports = Split + Merge uniquement | OK |
| Format : `eng` + forced + default + n | Nom et parse inverses |
| Langue `und` / absente | Pas de jeton langue |
| Collision 2 pistes `eng`+`.srt` | `.srt` et `.2.srt` |
| Split filtré sur la 2ᵉ | Fichier `.2.srt` (index source) |
| Cover / police / ffmeta | Parse de classe, pas de langue sur police |
| Merge matching : replace / add / keep | Clés stables |
| `-Update` sans MKV | `Write-ErrorLog`, pas de throw |
| FFmpeg introuvable | `Write-ErrorLog`, pas de throw |
| `-WhatIf` | Aucune écriture disque ; `Show-CommandLine` invoqué |
| Cible existante sans `-Force` | `ShouldContinue` mocké refus → pas d’écriture |
| Allowlist merge | `film.mkv` / `film.mp4` non ramassés comme sidecars |

Les tests de grammaire passent des descripteurs / noms de fichiers synthétiques, pas de médias réels.

## Critères de succès

- `Split-MediaStream` d’un MKV puis `Merge-MediaStream -Update` avec un `.srt` édité remplace la bonne piste (y compris la 2ᵉ d’une langue) et conserve vidéo, audio, polices et chapitres non extraits.
- `Merge-MediaStream` sans `-Update` produit un MKV **uniquement** à partir des sidecars (piste absente des sidecars = absente du MKV).
- `-WhatIf` affiche les lignes FFmpeg via `Show-CommandLine` et ne crée/écrase aucun fichier.
- `-Force` écrase ; sans `-Force`, une cible existante demande confirmation.
- L’aide `Get-Help Split-MediaStream` / `Merge-MediaStream` est exploitable (pas un stub).
- Aucune exception non gérée au niveau des deux commandes exportées si FFmpeg manque ou si le fichier est invalide.
