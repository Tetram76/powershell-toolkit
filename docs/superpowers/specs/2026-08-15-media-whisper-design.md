# Design — Tetram.Media.Whisper (Get-MediaTranscript)

Date : 2026-08-15  
Module : `Tetram.Media.Whisper` (nouveau, racine du repo)  
Dépendances : `Tetram.Common`

## Objectif

Produire des transcripts des pistes audio de fichiers médias en pilotant le binaire
`faster-whisper-xxl.exe` (Purfview Standalone Faster-Whisper), depuis une commande PowerShell unique :
`Get-MediaTranscript`.

Les transcripts sont écrits **à côté du fichier source**, au(x) format(s) demandé(s), avec le code de langue
ajouté au nom du fichier produit.

La commande est un **pilote de binaire** : elle traduit ce que whisper ne comprend pas, construit la ligne de
commande, l'affiche, la lance, et journalise. Elle **ne valide pas les chemins** — l'existence des sources et
la présence de médias sont l'affaire de whisper — n'inspecte pas le disque avant ou après l'exécution, et
n'émet rien dans le pipeline.

## Décisions validées


| Sujet                             | Choix                                                                                                                        |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Commande                          | `Get-MediaTranscript`, seule commande exportée                                                                               |
| Moteur                            | `faster-whisper-xxl.exe` uniquement                                                                                          |
| Conventions                       | Guidelines PowerShell (jeux `Path` / `LiteralPath`, `ValidateSet`, `ShouldProcess`), pas d'alignement sur l'existant du repo |
| Sources                           | Transmises au binaire comme arguments nus : `"file1" "file2"...` (pas de préfixe `file_list=`)                               |
| Formes acceptées                  | Les quatre du binaire : fichier média, masque, dossier, fichier-liste (`.txt`, `.m3u`, `.m3u8`, `.lst`)                       |
| Masques                           | Masque `*` / `?` transmis tel quel à whisper ; seules les spécificités PowerShell sont traduites             |
| Jeux de paramètres                | Trois : `Path`, `LiteralPath`, et `Mixed` autorisant les deux dans le même appel                                             |
| Entrée pipeline                   | Aucune : elle rendrait le jeu `Mixed` piégeux (double liaison d'un même `FileInfo`)                                          |
| Invocations                       | **Une seule** pour tout le lot                                                                                               |
| Validation des chemins            | **Aucune** : existence, contenu et présence de médias sont délégués à whisper                                                |
| Sortie pipeline                   | Aucune. Journalisation console uniquement                                                                                    |
| Sortie du binaire                 | Non capturée : progression et messages vont directement à la console (schéma `Invoke-ReencodeMedia`)                         |
| Source introuvable                | Transmise quand même ; c'est whisper qui signale l'absence de média                                                          |
| Résolution du binaire             | `Get-WhisperPath`, calqué sur `Get-FFmpegPath` sans la sélection de version                                                  |
| Override du binaire               | Exposé sur la commande via `-WhisperPath`                                                                                    |
| Destination                       | `--output_dir source` : transcript écrit à côté de la source                                                                 |
| Récursivité                       | `--batch_recursive` toujours activé                                                                                          |
| Formats                           | `--output_format` alimenté par `-Format`, `ValidateSet`, défaut `srt`                                                        |
| Vérification des sources          | `--check_files` toujours activé                                                                                              |
| Modèle                            | `--model`, `ValidateSet`, défaut `large-v2`                                                                                  |
| Piste audio                       | `--ff_track 1` : premier et unique flux audio                                                                                |
| Langue                            | `--language <code>` uniquement si `-UseLanguage` est fourni ; `ValidateSet` sur les codes ISO                                |
| Nommage                           | `--postfix` : code de langue ajouté au nom du fichier produit                                                                |
| Console binaire                   | `--print_progress` : barre de progression au lieu de la transcription                                                        |
| Tâche                             | `--task transcribe` : jamais de traduction                                                                                   |
| WhatIf                            | `Show-CommandLine` **puis** `ShouldProcess` : sous `-WhatIf` la ligne s'affiche, le binaire ne tourne pas                    |
| Erreurs publiques                 | `Write-ErrorLog` puis return ; pas d'exception vers l'appelant                                                               |
| Conversions de chemin             | Génériques : promues dans `Tetram.Common` (exportées, v1.2.0). Seule la politique reste dans le module        |
| Suivi git du binaire              | Dossier ignoré, seul `.keep` est poussé                                                                                      |
| Aide                              | Pages PlatyPS complètes (module + commande), pas de stub                                                                     |


## Hors scope (v1)

- Traduction (`--task translate`).
- Diarisation (`--diarize` et paramètres associés).
- Filtres audio `--ff_*` autres que `--ff_track 1`.
- Sélection d'une piste audio autre que la première.
- Saut des fichiers déjà transcrits (`--skip`) : une réexécution réécrit les transcripts.
- Réglages VAD, `--batched`, `--compute_type`, `--device`, `--threads`.
- Découpage de lignes (`--sentence`, `--standard`, `--max_line_*`, `--one_word`).
- Découverte des fichiers produits, émission d'objets, langue détectée : aucun traitement avant ou après
l'exécution du binaire.
- Téléchargement ou installation du binaire et des modèles.
- Post-traitement des transcripts (nettoyage, remux dans le conteneur).

## Architecture

### Fichiers


| Chemin                                                      | Rôle                                                            |
| ----------------------------------------------------------- | --------------------------------------------------------------- |
| `Tetram.Media.Whisper/Tetram.Media.Whisper.psd1`            | Manifeste v1.0.0, PS 7+ / Core, export de `Get-MediaTranscript` |
| `Tetram.Media.Whisper/Tetram.Media.Whisper.psm1`            | Commande publique + orchestration                               |
| `Tetram.Media.Whisper/Private/Whisper.ps1`                  | `Get-WhisperPath`, `Resolve-WhisperSource`, `Get-WhisperArguments`, `Invoke-Whisper` |
| `Tetram.Common/`                                            | **+** les quatre conversions de chemin génériques, exportées (v1.2.0) |
| `Tetram.Media.Whisper/Purfview-Whisper-Faster/.keep`        | Marqueur du dossier d'accueil du binaire (seul fichier suivi)   |
| `Tetram.Media.Whisper/fr-FR/Tetram.Media.Whisper-Help.xml`  | MAML généré via `tools/New-HelpMaml.ps1`                        |
| `docs/help/Tetram.Media.Whisper/`                           | Page module + `Get-MediaTranscript.md` (fr-FR, PlatyPS)         |
| `tests/Tetram.Media.Whisper/Tetram.Media.Whisper.Tests.ps1` | Manifeste, exports, binding, binaire absent, `-WhatIf`          |
| `tests/Tetram.Media.Whisper/Private/Whisper.Tests.ps1`      | Construction des arguments, résolution du binaire               |


`Private/Whisper.ps1` est dot-sourcé depuis le `psm1` (pas en `NestedModules`) pour que les fonctions de
`Tetram.Common` du scope parent restent visibles.

### Signature

```
Get-MediaTranscript [-Path] <string[]>
    [-Format <string[]>] [-Model <string>] [-UseLanguage <string>]
    [-WhisperPath <string>] [-WhatIf] [-Confirm]

Get-MediaTranscript -LiteralPath <string[]>
    [-Format <string[]>] [-Model <string>] [-UseLanguage <string>]
    [-WhisperPath <string>] [-WhatIf] [-Confirm]

Get-MediaTranscript -Path <string[]> -LiteralPath <string[]>
    [-Format <string[]>] [-Model <string>] [-UseLanguage <string>]
    [-WhisperPath <string>] [-WhatIf] [-Confirm]
```

Trois jeux de paramètres, `Path` par défaut (`DefaultParameterSetName = 'Path'`).
`[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Path')]`.


| Paramètre      | Type / attributs                                                                                                                 | Défaut     | Rôle                                                           |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------------- |
| `-Path`        | `string[]`, jeux `Path` et `Mixed`, `Mandatory` dans les deux, `Position = 0` dans `Path` **seulement**, `[SupportsWildcards()]` | —          | Sources ; caractères génériques PowerShell autorisés           |
| `-LiteralPath` | `string[]`, jeux `LiteralPath` et `Mixed`, `Mandatory` dans les deux, `[Alias('PSPath')]`                                        | —          | Sources prises au pied de la lettre                            |
| `-Format`      | `string[]`, `ValidateSet`                                                                                                        | `@('srt')` | Alimente `--output_format`                                     |
| `-Model`       | `string`, `ValidateSet`                                                                                                          | `large-v2` | Alimente `--model`                                             |
| `-UseLanguage` | `string`, `ValidateSet`                                                                                                          | (absent)   | Si fourni, ajoute `--language <code>`                          |
| `-WhisperPath` | `string`                                                                                                                         | (absent)   | Chemin d'un `faster-whisper-xxl.exe` hors du dossier du module |


`ValidateSet` de `-Format` : `json`, `lrc`, `txt`, `text`, `vtt`, `srt`, `tsv`, `all`.

`ValidateSet` de `-Model` : `large-v2`, `large-v3-turbo`, `large-v3`.

`ValidateSet` de `-UseLanguage` — codes ISO acceptés par `--language` (les noms anglais du binaire, `French`,
`Japanese`, … ne sont volontairement pas repris : une seule façon d'écrire une langue) :

```
af am ar as az ba be bg bn bo br bs ca cs cy da de el en es et eu fa fi fo fr gl gu ha haw he hi hr ht hu hy
id is it ja jw ka kk km kn ko la lb ln lo lt lv mg mi mk ml mn mr ms mt my ne nl nn no oc pa pl ps pt ro ru
sa sd si sk sl sn so sq sr su sv sw ta te tg th tk tl tr tt uk ur uz vi yi yo yue zh
```

### Les trois jeux

Chaque paramètre de source porte **deux attributs `Parameter`**, un par jeu auquel il appartient :

```powershell
[Parameter(ParameterSetName = 'Path', Mandatory, Position = 0)]
[Parameter(ParameterSetName = 'Mixed', Mandatory)]
[SupportsWildcards()]
[string[]] $Path,

[Parameter(ParameterSetName = 'LiteralPath', Mandatory)]
[Parameter(ParameterSetName = 'Mixed', Mandatory)]
[Alias('PSPath')]
[string[]] $LiteralPath
```

`-Path` n'est positionnel que dans le jeu `Path`. Dans `Mixed`, il doit être nommé : un appel combinant deux
listes de sources ne doit jamais laisser deviner à quelle liste appartient une valeur écrite sans nom de
paramètre.

Résolution : `-Path` seul → jeu `Path` ; `-LiteralPath` seul → jeu `LiteralPath` ; les deux → jeu `Mixed`,
dont les sources sont concaténées (les chemins de `-Path` résolus, ceux de `-LiteralPath` bruts) avant
construction de la ligne de commande. Aucune source → refus au binding, PowerShell exigeant le paramètre
obligatoire du jeu par défaut.

L'intérêt du jeu `Mixed` par rapport à des paramètres simplement facultatifs : la règle « au moins une
source » reste **déclarative**, portée par le binder et visible dans les trois blocs de syntaxe de l'aide,
au lieu d'être un contrôle écrit à la main dans le corps de la fonction.

### Pas d'entrée pipeline

Aucun paramètre n'accepte le pipeline : ni `ValueFromPipeline`, ni `ValueFromPipelineByPropertyName`.
L'alias `PSPath` sur `-LiteralPath` est conservé comme convention de nommage, sans rôle de liaison.

C'est une conséquence assumée du jeu `Mixed` : si les deux paramètres de source acceptaient le pipeline, un
objet `FileInfo` se lierait à `-Path` par valeur **et** à `-LiteralPath` par la propriété `PSPath`, ce qui
résoudrait vers `Mixed` — une résolution parfaitement valide dans laquelle le même fichier serait transcrit
deux fois. Avec deux jeux exclusifs, cette double liaison ne correspondait à aucun jeu et PowerShell la
rejetait ; avec `Mixed`, elle deviendrait un piège silencieux.

`Get-ChildItem *.mkv | Get-MediaTranscript` n'est donc pas supporté ; l'appelant écrit
`Get-MediaTranscript -Path 'D:\Films\*.mkv'`, le masque étant précisément la fonctionnalité de `-Path`.

### Helpers privés (contrats)

- `Get-WhisperPath -OverridePath <string>` — résolution du binaire, ordre strict :
  1. `-OverridePath` fourni : fichier existant → retourné ; dossier → erreur ; inexistant → erreur.
  2. `<racine du module>\Purfview-Whisper-Faster\faster-whisper-xxl.exe` s'il existe.
  3. `Get-Command faster-whisper-xxl` (PATH).
  4. Sinon erreur indiquant où poser la distribution Purfview.
  Même principe que `Get-FFmpegPath`, sans la recherche de la meilleure version : il n'y a qu'une
  distribution possible.
- `Resolve-WhisperSource -Path <string[]> -LiteralPath <string[]>` — applique la règle de transmission
ci-dessous et retourne la liste des sources à passer au binaire. Porte la **politique** ; les conversions
de chemin qu'elle enchaîne viennent de `Tetram.Common`.
- `Get-WhisperArguments -Source <string[]> -Format <string[]> -Model <string> -UseLanguage <string>` —
**pur, sans I/O** : retourne le `string[]` d'arguments dans un ordre stable. C'est le cœur testable du
module.
- `Invoke-Whisper -Exe <string> -Arguments <string[]> -Cmdlet <PSCmdlet>` — `Show-CommandLine`, **puis**
`ShouldProcess`, **puis** `& $Exe @Arguments`. La sortie du binaire n'est pas capturée : elle va
directement à la console.

## Ligne de commande produite

Ordre des arguments stable — les tests comparent la séquence produite.

`Get-MediaTranscript -Path "D:\Films\a.mkv", "D:\Films\b.mkv"` :

```
faster-whisper-xxl.exe "D:\Films\a.mkv" "D:\Films\b.mkv"
    --batch_recursive
    --output_dir source
    --output_format srt
    --check_files
    --model large-v2
    --ff_track 1
    --postfix
    --print_progress
    --task transcribe
```

`Get-MediaTranscript -Path "D:\Films\a.mkv" -Format srt, vtt -Model large-v3 -UseLanguage fr` :

```
faster-whisper-xxl.exe "D:\Films\a.mkv"
    --batch_recursive
    --output_dir source
    --output_format srt vtt
    --check_files
    --model large-v3
    --ff_track 1
    --language fr
    --postfix
    --print_progress
    --task transcribe
```

Chaque source est un argument distinct, sans préfixe `file_list=` (les frontières d'arguments sont
préservées par `& $Exe @Arguments`, jamais par une chaîne unique).

### Transmission des sources : masque conservé, spécificités traduites

Un masque qui correspond à 500 fichiers ne doit pas produire 500 arguments source. Whisper sachant
lui-même globaliser, une entrée de `-Path` est **transmise telle quelle** dès qu'elle est un masque que le
binaire interprète comme PowerShell. Seules les **spécificités PowerShell** sont traduites, en résolvant
l'entrée et en transmettant les fichiers obtenus.

Effet de bord recherché : l'aide du binaire indique que `--check_files` ne s'applique qu'à une entrée de type
masque ou dossier. Transmettre le masque le rend opérant, là où une liste de fichiers déjà résolus le
neutraliserait.

Métacaractères communs et sûrs : `*` et `?`. Les classes de caractères divergent (`[!a]` est une négation
côté glob, un jeu littéral côté PowerShell), donc tout crochet fait basculer l'entrée en résolution
PowerShell — ce qui règle du même coup le cas des fichiers réellement nommés `film[1].mkv`.

Règle, appliquée entrée par entrée. Aucun cas ne teste l'existence de quoi que ce soit :

| Entrée de `-Path` | Traitement |
|---|---|
| Contient `[`, un échappement backtick, ou vise un PSDrive hors système de fichiers | **Résolue** par PowerShell ; un élément par fichier trouvé ; crochets neutralisés. Résolution vide → l'entrée **ne produit aucun élément** |
| Contient `*` ou `?`, y compris dans un segment intermédiaire (`D:\Films\*\*.mkv`) | **Transmise telle quelle**, en un seul élément, après absolutisation du préfixe sans métacaractère (couvre `.\*.mkv` et `~`) |
| Aucun métacaractère | Transmise absolue telle quelle, crochets neutralisés. Fichier, dossier ou chemin inexistant : la commande ne fait pas la différence, le binaire acceptant fichier comme dossier |

`-LiteralPath` ne suit aucune de ces règles : ses entrées sont toujours littérales, jamais résolues, et sont
transmises absolues avec les crochets neutralisés.

### Conversions de chemin : dans `Tetram.Common`, pas dans le module

La règle ci-dessus est une **politique** propre à whisper, parce qu'elle découle d'une de ses propriétés :
il globalise lui-même. Les conversions qu'elle enchaîne, elles, ne connaissent rien à whisper — développer
`~`, absolutiser sans exiger l'existence, échapper les crochets à la convention glob, reconnaître de la
syntaxe que seul PowerShell comprend. Elles valent pour n'importe quel exécutable natif qui globalise.

Elles sont donc portées par `Tetram.Common`, exportées, sous des noms sans infixe comme le reste du module
commun : `Test-PowerShellSpecificPath`, `ConvertTo-GlobLiteral`, `ConvertTo-AbsolutePath`,
`ConvertTo-AbsoluteMask`. `Tetram.Common` passe en 1.2.0, et ces quatre fonctions reçoivent leur page
d'aide au même titre que les autres exports.

Seul `Resolve-WhisperSource` reste privé au module : c'est lui qui décide *quelle* conversion appliquer à
quelle entrée.

Une résolution vide ne se rabat pas sur le littéral : la résolution a établi que l'entrée est un motif, la
retransmettre telle quelle en tant que chemin inventerait une interprétation que l'appelant n'a pas
demandée, et ferait signaler par whisper un fichier manquant qui n'a jamais été désigné.

L'absolutisation utilise `[System.IO.Path]::GetFullPath` relatif à l'emplacement PowerShell courant, et non
`Resolve-Path` qui échouerait sur un chemin inexistant. Elle reste indispensable : l'emplacement PowerShell
et le répertoire de travail du processus ne coïncident pas nécessairement, et whisper ne connaît que le
second.

### Ce que l'argument positionnel du binaire accepte

La règle ci-dessus est calquée sur les quatre formes d'entrée que le binaire sait traiter : un fichier
média, un masque, un dossier, ou un **fichier-liste**. Ce dernier point est un piège à documenter : une
source d'extension `.txt`, `.m3u`, `.m3u8` ou `.lst` n'est pas transcrite, elle est **lue comme une liste de
médias**. La commande ne l'interdit pas — elle respecte le contrat du binaire — mais l'aide le signale, car
l'appelant qui passe un `.txt` en croyant le faire transcrire n'obtiendrait pas ce qu'il attend.

Le binaire filtre par ailleurs lui-même les non-médias présents dans un dossier ou une liste.

Conséquence assumée : une source fautive — masque sans correspondance, chemin mal orthographié, dossier vide
— ne produit aucun message côté PowerShell. C'est whisper qui signale n'avoir trouvé aucun média. En
contrepartie, la ligne de commande reste courte (un argument par entrée), `--check_files` fonctionne, et la
commande n'a pas de règle de validation à maintenir en parallèle de celles du binaire.

Neutralisation des crochets, pour les chemins **littéraux** transmis : `[` → `[[]`, convention glob. À
confirmer au smoke test d'implémentation (première étape du plan) : si le binaire teste l'existence du chemin
avant de globaliser, la neutralisation est inutile et sera retirée.

## Flux d'exécution

La commande n'acceptant pas le pipeline, tout se déroule en une passe, sans `begin` / `process` / `end`.

1. `Get-WhisperPath -OverridePath $WhisperPath`. Échec → `Write-ErrorLog`, aucune invocation.
2. Collecte des sources selon le jeu retenu, en appliquant la règle de transmission ci-dessus :
  - `-Path` : masque `*` / `?` transmis tel quel ; entrée à crochets ou à backtick résolue ; tout le reste
   transmis absolu. Aucun test d'existence.
  - `-LiteralPath` : aucune résolution, aucun test d'existence, transmission absolue.
  - jeu `Mixed` : les deux collectes ci-dessus, concaténées dans l'ordre `-Path` puis `-LiteralPath`.
3. Plus aucune source après collecte → `Write-InfoLog` et fin, sans invocation. Le binding garantissant au
  moins une source, ce cas n'est atteignable que si **toutes** les entrées étaient des motifs à crochets
  résolus à vide ; il évite d'invoquer le binaire sans aucune source.
4. Construction des arguments (`Get-WhisperArguments`), `Write-DebugLog` de la séquence obtenue.
5. `Invoke-Whisper` : `Show-CommandLine`, `ShouldProcess`, exécution. Sous `-WhatIf`, la ligne s'affiche et
  le binaire ne tourne pas.
6. Le binaire écrit les transcripts à côté des sources (`--output_dir source`) et affiche sa progression
  (`--print_progress`) directement sur la console. C'est lui qui signale une source introuvable ou sans
  média.
7. Échec d'exécution → `Write-ErrorLog`. Aucune exception ne remonte à l'appelant.

Aucun objet n'est émis dans le pipeline.

## Journalisation

Tous les affichages console passent par `Tetram.Common`.

- `Show-CommandLine` pour l'invocation, y compris sous `-WhatIf`, **avant** `ShouldProcess`.
`NoPathDetectionParameters` : `'output_dir'`, `'output_format'`, `'model'`, `'task'`, `'language'`,
`'ff_track'`.
- `Write-ErrorLog` : binaire introuvable, échec d'exécution.
- `Write-InfoLog` : plus aucune source après collecte.
- `Write-DebugLog` : arguments construits.

Aucun `Write-WarningLog` n'est ajouté : la délégation de la validation à whisper supprime les seuls cas qui
en auraient demandé un.

`Tetram.Common` est en revanche étendu, pour une autre raison — voir « Conversions de chemin » ci-dessous.

## Suivi git

Le binaire et ses données (`_xxl_data`, `_models`, DLL CUDA, `ffmpeg.exe`) ne sont pas versionnés. Règle
ajoutée au `.gitignore` racine, sur le modèle de `Tetram.Media.FFmpeg/ffmpeg/` :

```
Tetram.Media.Whisper/Purfview-Whisper-Faster/*
!Tetram.Media.Whisper/Purfview-Whisper-Faster/.keep
```

## Aide

Livrable complet, généré via `tools/New-HelpMarkdown.ps1` puis rédigé à la main en fr-FR, MAML produit par
`tools/New-HelpMaml.ps1` :

- Synopsis et description : transcription des pistes audio, sortie à côté de la source, code de langue en
postfixe, une seule invocation du binaire par appel.
- Tous les paramètres, y compris `-WhisperPath`, `WhatIf` et `Confirm`.
- Exemples : un fichier ; plusieurs fichiers ; masque `-Path` ; un dossier ; `-LiteralPath` sur un nom à
  crochets ; `-Path` et `-LiteralPath` combinés ; `-Format srt, vtt` ; `-Model large-v3-turbo` ;
  `-UseLanguage fr` ; `-WhatIf`.
- Notes : une source peut être un fichier, un masque ou un dossier ; une source d'extension `.txt`, `.m3u`,
  `.m3u8` ou `.lst` est lue par le binaire comme une **liste de médias**, pas transcrite ;
  la distribution Purfview doit être posée dans `Purfview-Whisper-Faster` (dossier non versionné) ;
le modèle est téléchargé au premier usage, le premier appel est donc long ; seul le premier flux audio est
transcrit ; jamais de traduction ; une réexécution réécrit les transcripts existants.

Commentaire `.EXTERNALHELP Tetram.Media.Whisper-Help.xml` sur la fonction exportée.

## Tests

Tag `Integration` pour tout appel au vrai binaire (exclu du CI, cf. `Invoke-Tests.ps1 -ExcludeTag Integration`).
Le module entre automatiquement dans la couverture du CI (découverte des `*.psm1` racine + `Private/`).


| Cas                                                                | Attendu                                                                                                                                                                                                    |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Test-ModuleManifest`                                              | OK                                                                                                                                                                                                         |
| Exports = `Get-MediaTranscript` uniquement                         | OK                                                                                                                                                                                                         |
| Arguments par défaut                                               | `<source1>` [sources…], `--batch_recursive`, `--output_dir source`, `--output_format srt`, `--check_files`, `--model large-v2`, `--ff_track 1`, `--postfix`, `--print_progress`, `--task transcribe`, dans cet ordre |
| `-Format srt, vtt`                                                 | `--output_format srt vtt`                                                                                                                                                                                  |
| `-Format`, `-Model` ou `-UseLanguage` hors liste                   | Erreur de binding `ValidateSet`                                                                                                                                                                            |
| `-Model large-v3-turbo`                                            | `--model large-v3-turbo`                                                                                                                                                                                   |
| `-UseLanguage` absent / `fr`                                       | Aucun `--language` / `--language fr`                                                                                                                                                                       |
| Sources multiples                                                  | Une seule invocation, toutes les sources dans la ligne                                                                                                                                                     |
| Masque `*` / `?`, y compris `D:\Films\*\*.mkv`                     | Transmis tel quel, un seul élément, aucune résolution PowerShell                                                                                                                                           |
| Masque relatif `.\*.mkv`                                           | Préfixe absolutisé, masque conservé sur la feuille                                                                                                                                                         |
| Source dossier, sur `-Path` comme sur `-LiteralPath`               | Transmise absolue telle quelle, un seul élément                                                                                                                                                            |
| Source `.lst` / `.m3u`                                             | Transmise telle quelle ; comportement de fichier-liste documenté dans l'aide                                                                                                                               |
| Entrée à crochets                                                  | Résolue par PowerShell, un élément par fichier, crochets neutralisés                                                                                                                                       |
| Chemin littéral contenant des crochets                             | Crochets neutralisés dans l'argument transmis                                                                                                                                                              |
| `-Path` seul / `-LiteralPath` seul / les deux                      | Jeux `Path` / `LiteralPath` / `Mixed` résolus sans ambiguïté                                                                                                                                               |
| Jeu `Mixed`                                                        | Sources concaténées, `-Path` selon la règle de transmission puis `-LiteralPath` littéral, une seule invocation                                                                                             |
| Valeur positionnelle                                               | Acceptée pour `-Path` dans le jeu `Path`, refusée dans le jeu `Mixed`                                                                                                                                      |
| Aucun des deux paramètres de source                                | Erreur de binding (paramètre obligatoire du jeu par défaut)                                                                                                                                                |
| Entrée pipeline                                                    | Rejetée : aucun paramètre ne se lie depuis le pipeline                                                                                                                                                     |
| Entrée à crochets sans correspondance                              | Ne produit aucun élément ; jamais rabattue en littéral                                                                                                                                                     |
| Toutes les entrées résolues à vide                                 | `Write-InfoLog`, aucune invocation : pas d'appel sans source                                                                                                                                               |
| Source inexistante                                                 | Transmise quand même : aucun test d'existence, aucune erreur PowerShell                                                                                                                                    |
| Binaire introuvable                                                | `Write-ErrorLog`, pas de throw, aucune invocation                                                                                                                                                          |
| `-WhisperPath` vers un fichier / un dossier / un chemin inexistant | Retenu / erreur / erreur                                                                                                                                                                                   |
| `-WhatIf`                                                          | `Show-CommandLine` invoqué, binaire non exécuté                                                                                                                                                            |
| Transcription réelle (`Integration`)                               | Fichier `.srt` produit à côté de la source                                                                                                                                                                 |


Les tests unitaires n'appellent jamais le binaire : `Get-WhisperArguments` est pur et `Invoke-Whisper` est
mocké.

## Notes d'observation du binaire (r245.4)

Constats faits en exécutant `faster-whisper-xxl.exe`, à prendre en compte à l'implémentation :

- **Code de sortie non fiable** : un lot sans média trouvé affiche `Error: Media files were not found.` et
sort malgré tout en code `0`. Le succès ne peut pas être déduit du seul code de retour ; le module
journalise l'échec quand il en voit un, sans prétendre garantir la production des fichiers (la découverte
des fichiers produits est hors scope).
- **Téléchargement du modèle** : au premier usage d'un modèle, le binaire le télécharge dans
`Purfview-Whisper-Faster\_models` (~1,5 Go pour `medium`, davantage pour les `large`), avant même la
validation des sources. Le premier appel est donc long.
- **`--check_files` et `--skip`** : l'aide du binaire indique qu'ils ne s'appliquent qu'à une entrée de type
masque ou dossier. C'est l'une des raisons de transmettre les masques tels quels plutôt que de les résoudre :
`--check_files`, toujours activé, reste alors opérant.
- **Première étape du plan d'implémentation** : smoke test réel de la ligne de commande (sources en
arguments nus, neutralisation des crochets) contre le binaire, avec un vrai fichier média court, avant
d'écrire le reste du module.

## Critères de succès

- `Get-MediaTranscript -Path "film.mkv"` produit le transcript à côté de `film.mkv`, avec le code de langue
dans le nom.
- Plusieurs fichiers, ou un masque, en une seule invocation : le modèle n'est chargé qu'une fois.
- `-Path 'D:\Films\*.mkv' -LiteralPath 'D:\Films\film[1].mkv'` transcrit les deux ensembles en un seul appel.
- Un masque couvrant 500 fichiers produit **un seul** argument source, pas 500.
- `-Path 'D:\Films'` transcrit le dossier, récursivement, sans que PowerShell énumère quoi que ce soit.
- `-Format srt, vtt` produit les deux formats ; une valeur hors liste est refusée au binding.
- `-UseLanguage fr` force la langue ; sans lui, whisper la détecte.
- Une source inexistante n'est pas rejetée par la commande : whisper reçoit la ligne et rend le verdict.
- `-WhatIf` affiche la ligne de commande et ne lance rien.
- Binaire absent : message d'erreur explicite, aucune exception.
- `Get-Help Get-MediaTranscript` est exploitable (pas un stub).

