# Design — Tetram.Media.Streams (split / merge de flux)

Date : 2026-08-14  
Module : `Tetram.Media.Streams` (nouveau, racine du repo)  
Dépendances : `Utils/Tetram.Common`, `Utils/Tetram.Media.FFmpeg`

## Objectif

Round-trip **MKV uniquement** : extraire des pistes, éditer les **sous-titres** hors conteneur, réinjecter un MKV **équivalent** (vidéo/audio du MKV conservés).

Deux commandes, FFmpeg uniquement (`-c copy`) :

1. **Get-MediaStream** — extraire certains flux d’un `.mkv` vers des fichiers de flux **à côté** du fichier (grammaire unique : langue, flags de disposition, collision). Vidéo et audio extraits = **référence** (timestamps hors sujet). Verbe `Get` (pas `Split`) : le MKV source n’est jamais modifié, seulement lu et copié.
2. **Merge-MediaSubtitle** — réinjecter **un seul** fichier sous-titre, donné explicitement en paramètre, dans **ce** MKV : `-Add` l’ajoute (échoue s’il matche déjà une piste), `-Update` remplace une piste existante (échoue si aucune ne matche), le reste du MKV (y compris vidéo/audio) est **conservé**.

Une invocation de Merge = un fichier MKV **et** un seul fichier sous-titre. Pas de scan de dossier, pas de `-Recurse`, pas de masques, pas de reconstruction à partir des seuls fichiers de flux.

Les polices, covers, chapitres, vidéo et audio du MKV restent grâce au merge-update : le round-trip de fichiers de flux ne concerne que les **sous-titres**.

## Décisions validées

| Sujet | Choix |
|---|---|
| Outil | FFmpeg / ffprobe uniquement (pas de mkvmerge, pas de manifeste JSON) |
| Copie | Stream copy, jamais de réencodage |
| Conteneur v1 | `.mkv` en entrée des deux commandes |
| Unité d’appel | Un fichier MKV ; pas de lot, pas de stem, pas de dossier |
| Merge | Un seul sous-titre par appel, chemin donné explicitement (`-Path`) ; pas de scan de dossier |
| Intention explicite | `-Add` / `-Update` (`ParameterSetName`, exclusifs, l’un des deux obligatoire) ; `-Add` + piste déjà existante = rejet ; `-Update` + aucune piste à remplacer = rejet |
| Fichier `-Path` après merge | Jamais supprimé par la commande ; nettoyage à la charge de l’appelant |
| Collision de noms | Suffixe `.2`, `.3`, … seulement si besoin ; **pas** de `.1` |
| Flags de disposition dans le nom | `default`, `forced`, `commentary`, `original`, `dub`, `hearing_impaired`, `visual_impaired` |
| Index de collision | Calculé sur **toutes** les pistes du MKV **source**, même si le split est filtré |
| Merge sortie | Toujours in-place sur `-MediaFile` (via temporaire) ; pas de `-Destination` |
| Suppression de piste | Hors v1 (un fichier de flux manquant = keep) |
| Overwrite | `-Force` écrit ; sinon `ShouldContinue` ; refus = skip |
| WhatIf | Pas d’écriture ; **la ligne FFmpeg est quand même affichée** (`Show-CommandLine` avant `ShouldProcess`, comme Reencode) |
| Erreurs publiques | `Write-ErrorLog` puis return/continue ; pas d’exception vers l’appelant |
| Aide | Pages PlatyPS complètes (module + commandes), pas de stub |

## Hors scope (v1)

- Extraction / réinjection de covers (`attached_pic`), pièces jointes (polices) et chapitres : keep dans le MKV, pas de fichier de flux.
- Conversion d’un autre conteneur (MP4, AVI, …) vers MKV.
- Reconstruction d’un MKV à partir **uniquement** des fichiers de flux (mux from-scratch).
- Suppression de piste.
- Traitement d’un dossier / `-Recurse` / `-InputMasks` / stem sans fichier.
- mkvmerge, manifeste JSON, conservation d’un ordre de pistes autre que : ordre du MKV source, puis ajouts par classe.
- Réencodage, décalage temporel (`delay`), noms de piste (`title`) dans le nom de fichier.
- Autres flags de disposition FFmpeg (`lyrics`, `karaoke`, `captions`, `descriptions`, `clean_effects`, …) : non représentés dans le nom ; perdus au replace, conservés sur les pistes keep.
- Codecs A/V/S sans entrée dans la table (dont `mpeg4`, `mov_text`, `alac`, `pcm_*`, VobSub) : **split** échoue (`Write-ErrorLog` + return). **Mux** : keep depuis le MKV (pas d’échec). Tout flux ni vidéo, ni audio, ni sous-titre (`data`, covers, polices, chapitres, …) : skip au split, keep au mux.
- Réinjection vidéo/audio depuis fichier de flux (timestamps élémentaires hors sujet : extraits pour référence seulement).
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
| `docs/help/Tetram.Media.Streams/` | Page module + `Get-MediaStream.md` + `Merge-MediaSubtitle.md` (fr-FR, PlatyPS) |
| `fr-FR/Tetram.Media.Streams-Help.xml` | MAML généré via `tools/New-HelpMaml.ps1`, comme les autres modules |

Les `.ps1` privés sont dot-sourcés depuis le root psm1 (pas en `NestedModules`) pour que `Write-ErrorLog` / `Show-CommandLine` / `Get-FFmpegPath` du scope parent soient visibles.

### Commandes exportées

```
Get-MediaStream -MediaFile <fichier.mkv>
    [-StreamType Video, Audio, Subtitle]
    [-Language <code[]>]
    [-Force] [-WhatIf] [-Confirm]

Merge-MediaSubtitle -MediaFile <fichier.mkv> -Path <sous-titre>
    (-Add | -Update)
    [-Force] [-WhatIf] [-Confirm]
```

`SupportsShouldProcess = $true`, `ConfirmImpact = 'Medium'`, `PositionalBinding = $false`. `begin`/`process` : résolution ffmpeg/ffprobe une seule fois en `begin`, logique par fichier en `process` (les deux commandes partagent cette structure).  
`Get-MediaStream` : `-MediaFile` (position 0) est obligatoire, **fichier `.mkv` existant**, accepte le pipeline (`ValueFromPipeline`, chaîne simple). Pas d’objets émis (journalisation console uniquement, comme `Remove-EmptyDirs`).

`Merge-MediaSubtitle` : `-MediaFile` (position 0) est obligatoire, **fichier `.mkv` existant**, accepte le pipeline (`ValueFromPipeline`, chaîne simple, comme `-Path` de `Test-MediaSimilarity`) — permet `Get-ChildItem *.mkv | Merge-MediaSubtitle -Path ... -Update`. `-Path` (position 1) est obligatoire, **fichier existant**, dont le **nom** doit se parser (grammaire ci-dessous) avec le basename du MKV et donner la classe `Subtitle` ; sinon `Write-ErrorLog` + return. `-LiteralPath` est un alias de `-Path` (même paramètre, même comportement — convention de nommage uniquement, pas de résolution de wildcard). `-Add` et `-Update` sont deux `ParameterSetName` distincts (switches, chacun `Mandatory` dans son set) : exactement l’un des deux doit être fourni, jamais les deux, jamais aucun (erreur de binding PowerShell native sinon).

`-Force` est le switch d’overwrite des **fichiers de sortie** (fichiers de flux au split, MKV cible au merge). Il n’est pas le `-Force` de `Write-InfoLog`.

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
- Parse (flux A/V/S) : depuis la **fin** du nom (suffixe `n`, puis flags, puis au plus un tag langue tel quel). Basename = celui du MKV, jamais du fichier de flux. S’il reste un jeton → ce n’était pas un fichier de flux. `dub` est un flag. `und` / `unk` = pas de langue.

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

Parse : depuis la fin (insensible à la casse) : `n` ≥ 2, puis les flags (ordre indifférent), puis au plus un tag langue. Alias lecture seulement : `comment` et `comments` → `commentary`. Jeton restant → pas un fichier de flux de ce MKV.

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

Les conteneurs (`.mkv`, `.mp4`, `.avi`, `.mov`, `.webm`, `.m4v`, `.wmv`, `.flv`, `.mpeg`, `.mpg`, `.ts`) ne sont **jamais** des fichiers de flux.

### Sanitisation des noms d’attachement

Caractères interdits Windows / séparateur `.` de grammaire : remplacés par `_`. Le nom original (avant sanitisation) est réinjecté au mux via metadata `filename` si ffprobe l’a fourni à l’extract ; sinon le nom sanitisé.

## Carte codec → extension

Copie uniquement. Codec A/V/S absent de la table → split **échoue** (`Write-ErrorLog` + return, aucun fichier de flux) ; merge **conserve** la piste telle quelle (`Add-UnmappedKeepDescriptors`, map depuis l'input 0, pas de fichier de flux). Pas de fichier élémentaire « fourre-tout ». Flux hors A/V/S : skip au split, keep au merge.

| Codec ffprobe (`codec_name`) | Ext | Classe |
|---|---|---|
| `h264`, `avc` | `.h264` | Vidéo |
| `hevc`, `h265` | `.hevc` | Vidéo |
| `av1`, `vp8`, `vp9` | `.ivf` | Vidéo |
| `mpeg2video` | `.m2v` | Vidéo |
| `vc1` | `.vc1` | Vidéo |
| `mjpeg` / `png` / tout autre codec **avec** `attached_pic` | (non extrait) | Cover : skip split, keep mux |
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
| `mpeg4`, `mov_text`, `alac`, `pcm_*`, `dvd_subtitle`, `dvb_subtitle`, autres A/V/S | non mappé (split : échec ; mux : keep MKV) | — |

Pièces jointes (`codec_type` = `attachment`) : classe et extension calculées en interne (`tags.filename` / mime ; défaut `.bin`) pour le mapping de préservation au merge, mais **jamais extraites en fichier de flux** par `Get-MediaStream` (qui ne sélectionne que Video/Audio/Subtitle) ; toujours conservées depuis le MKV source au merge.

Chapitres : présence d’entrées `chapters` dans ffprobe → détectée en interne pour le mapping de préservation, mais **jamais extraits en fichier de flux `.ffmeta`** par `Get-MediaStream` ; toujours conservés depuis le MKV source au merge. La grammaire de nommage (`.ffmeta` + jeton `chapters`) reste définie côté `Naming.ps1` mais n’est produite/consommée par aucune des deux commandes.

## Flux — Get-MediaStream

1. Résoudre ffmpeg/ffprobe ; échec → `Write-ErrorLog` + return.
2. Fichier existant, extension `.mkv` (insensible à la casse) ; sinon log + return. Le chemin est ensuite résolu via le provider (`Resolve-Path -LiteralPath`) : `~` et lecteurs PS deviennent un chemin filesystem, contrairement à `GetFullPath`.
3. ffprobe JSON (`-show_format -show_streams -show_chapters -of json`). JSON invalide ou vide → log + return.
4. Codec A/V/S absent de la table → `Write-ErrorLog` + return (aucun fichier de flux), même si `-StreamType` / `-Language` l’aurait exclu. Flux hors A/V/S (`data`, attachment, …) : ignorés, pas un échec.
5. Construire les descripteurs, **attribuer les index de collision sur l’ensemble du MKV**, puis filtrer :
   - `-StreamType` : si omis, Video + Audio + Subtitle. `attached_pic` n’est **jamais** extrait (classe Cover, keep mux).
   - `-Language` : comparaison insensible à la casse sur le code **tel que dans le fichier**. Les flux sans langue (indéterminés) **ne matchent pas** un filtre `-Language`. Chapitres et pièces jointes **ignorent** `-Language`.
6. Pour chaque descripteur retenu : calculer le chemin du fichier de flux (même dossier que le MKV).
   - Si la cible existe et n’est pas un fichier (dossier nommé comme le fichier de flux) : `Write-ErrorLog` + skip (sinon `Move-Item` rangerait le fichier dans le dossier).
   - Si la cible est un fichier : `-WhatIf` → pas de prompt, on affiche quand même la commande FFmpeg prévue ; exécution réelle → `-Force` ou `ShouldContinue` ; refus → skip + `Write-InfoLog`.
   - `Show-CommandLine` puis `ShouldProcess` puis `ffmpeg` vers un temporaire dans le dossier TEMP (`{guid}{ext}` du fichier de flux, ex. `{TEMP}\{guid}.srt`). Succès → `Move-Item` vers le fichier de flux ; échec → suppression du temporaire. Le temporaire du **merge** est `{TEMP}\{guid}.mkv` + `-f matroska`. Pas de voisin `.tmp` du MKV (Merge le prendrait pour un fichier de flux).
7. Un flux en erreur FFmpeg : `Write-ErrorLog`, **continuer** les autres ; aucun fichier de flux partiel laissé.
8. Aucun flux retenu après filtre : `Write-InfoLog` (pas une erreur).

Le MKV d’origine n’est pas modifié par le split.

## Flux — Merge-MediaSubtitle

`-MediaFile` = le MKV à mettre à jour (fichier `.mkv` existant). Répertoire, stem, autre extension → `Write-ErrorLog` + return. Accepte le pipeline (une chaîne par appel de `process {}` ; `Get-FFmpegPath`/`Get-FfprobePath` résolus une seule fois en `begin {}`).

`-Path` (alias `-LiteralPath`) = le fichier sous-titre à injecter, donné **explicitement** par l’appelant : pas de scan de dossier, pas de collecte automatique. Basename = nom du MKV sans extension. Le **nom** du fichier `-Path` (pas son dossier, qui peut être n’importe où) doit se parser avec ce basename via la grammaire (langue, flags, index de collision) et donner la classe `Subtitle` ; sinon `Write-ErrorLog` + return. `-Path` doit exister (fichier).

Codec A/V/S hors table → keep (`-map 0:<index>`), pas d’échec au mux. Tout flux ni vidéo, ni audio, ni sous-titre : keep, jamais fichier de flux.

### Sortie

Toujours in-place sur `-MediaFile` (update via temporaire) : pas de `-Destination`.

Overwrite de la cible (le MKV d’entrée existe forcément) : `-Force` ou `ShouldContinue` ; refus → return sans mux. Sous `-WhatIf` : pas de prompt `ShouldContinue`, `Show-CommandLine` du mux prévu, pas d’écriture.

### `-Add` / `-Update` : rendre l’intention explicite

Le fichier `-Path` est comparé aux pistes du MKV via sa clé de classe (section Collision) **et** son index de collision (calculés depuis son propre nom, comme un descripteur de split) :

- **Collision** (même clé + même index qu’une piste sous-titre du MKV) → action possible : **replace**.
- **Pas de collision** → action possible : **add**.

L’action **réellement exécutée** dépend du switch fourni ; sinon rejet (`Write-ErrorLog` + return, aucun mux) :

| Switch | Collision trouvée | Pas de collision |
|---|---|---|
| `-Add` | **Rejet** (« une piste existe déjà, utilisez -Update ») | OK → **add** |
| `-Update` | OK → **replace** | **Rejet** (« aucune piste à remplacer, utilisez -Add ») |

Ceci élimine l’ambiguïté : le nom de fichier (langue/flags/index) ne fait que déterminer s’il y a collision ; c’est le switch qui déclare l’intention et qui est validé contre ce constat.

### Remap (replace / add / keep)

Entrée 0 = le MKV source. Entrée 1 = le fichier de flux `-Path` (uniquement s’il est retenu, cf. ci-dessus).

Pour chaque piste du MKV (ordre ffprobe) :

- Piste **sous-titre** qui matche `-Path` (replace retenu) → mapper le fichier de flux.
- Toute autre piste (vidéo, audio, sous-titre non matchée, keep) → toujours **keep**.

Si l’action retenue est **add** : le fichier de flux est mappé en plus, après les pistes d’origine.

Chapitres : toujours conservés depuis le MKV (hors scope de `-Path`, qui est toujours un sous-titre).

Chaque piste **issue du fichier de flux** (replace ou add) reçoit **explicitement** :

- `-metadata:s:<type>:<i> language=<code>` si langue présente, sinon `language=und`
- `-disposition:<type>:<i>` : `0` si aucun flag, sinon les noms FFmpeg du tableau joints par `+` (ex. `default+comment+hearing_impaired`). Le jeton fichier `commentary` devient `comment` côté FFmpeg.

Les pistes **keep** conservent métadonnées et dispositions du MKV source (pas de réécriture).

Écriture : temporaire `{TEMP}\{guid}.mkv` (même modèle que Reencode), puis `Move-Item` vers la destination si succès. Sous `-WhatIf`, le temporaire n’est pas créé.

Une piste sans `-Path` correspondant n’est jamais enlevée (pas de suppression de piste, hors scope v1).

Le fichier `-Path` n’est **jamais supprimé** par `Merge-MediaSubtitle`, qu’il ait été muxé ou rejeté : le nettoyage (suppression du sous-titre source après un merge réussi) est à la charge de l’appelant.

## Journalisation

- `Show-CommandLine` pour **chaque** invocation FFmpeg, y compris WhatIf, **avant** `ShouldProcess`.
- `Write-ErrorLog` : échecs (voir ci-dessus).
- `Write-InfoLog` : skip overwrite, aucun flux filtré, résumé WhatIf (couleur Magenta, comme Reencode / Remove-EmptyDirs).
- `Write-DebugLog` : descripteurs / clés de matching.

Pas de `Write-InfoLog -Force` : les infos suivent le Verbose / préférence par défaut de `Write-InfoLog` (comme EmptyDirs), hors `Show-CommandLine` qui s’affiche toujours.

## Aide

Livrable **complet**, généré/tenu via `tools/New-HelpMarkdown.ps1` (découverte auto des `.psd1` racine) puis rédaction manuelle du fond (fr-FR), comme les autres modules :

- Synopsis, description (round-trip MKV, grammaire, collision source, replace/add/keep, contrat `-Add`/`-Update`).
- Tous les paramètres, y compris WhatIf / Confirm / Force / Add / Update / Path.
- Exemples : split `-StreamType Subtitle -Language fra` ; merge `-Update` (remplace une piste existante) ; merge `-Add` (ajoute un `.srt` posé à la main) ; `-WhatIf` (la commande FFmpeg s’affiche).
- Notes : le MKV n’est pas un fichier de flux ; le merge ne supprime pas de piste ; `-Path` n’est jamais supprimé par la commande ; `-Add`/`-Update` rejettent respectivement collision/absence ; codec A/V/S hors table arrête `Get-MediaStream` mais est conservé (keep) par `Merge-MediaSubtitle` ; hors A/V/S = keep dans les deux cas.

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
| `-Add` sur `-Path` qui matche une piste existante | Rejet, `Write-ErrorLog`, pas de mux |
| `-Update` sur `-Path` sans piste correspondante | Rejet, `Write-ErrorLog`, pas de mux |
| `-Add` / `-Update` fournis ensemble ou aucun des deux | Erreur de binding PowerShell (ParameterSetName) |
| `-Path` introuvable ou nom ne parsant pas en sous-titre pour ce basename | `Write-ErrorLog`, pas de mux |

Les tests de grammaire passent des descripteurs / noms de fichiers synthétiques, pas de médias réels.

## Critères de succès

- Extraire un `.srt` (y compris la 2ᵉ piste d’une langue), l’éditer, `Merge-MediaSubtitle -Update` : la bonne piste est remplacée ; vidéo, audio, polices et chapitres non extraits sont intacts.
- Poser un nouveau `film.spa.srt` et `Merge-MediaSubtitle -Add` : la piste est **ajoutée**, le reste inchangé ; le même appel avec `-Update` échoue (aucune piste espagnole à remplacer) ; un `-Add` sur une piste déjà existante échoue aussi.
- `-WhatIf` affiche les lignes FFmpeg via `Show-CommandLine` et ne crée/écrase aucun fichier.
- `-Force` écrase ; sans `-Force`, une cible existante demande confirmation.
- L’aide `Get-Help Get-MediaStream` / `Merge-MediaSubtitle` est exploitable (pas un stub).
- Aucune exception non gérée au niveau des deux commandes exportées si FFmpeg manque ou si le fichier n’est pas un MKV.
