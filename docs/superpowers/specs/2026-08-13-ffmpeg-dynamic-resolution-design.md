# Design — résolution dynamique FFmpeg sous RecodeVideo

Date : 2026-08-13  
Module : `Utils/Tetram.Media.FFmpeg`  
Consommateurs : `Tetram.Media.Reencode`, `Tetram.Media.Similarity`

## Objectif

Remplacer le chemin figé vers une build FFmpeg (`ffmpeg-9.0.1-full_build`) par une découverte automatique de la build la plus récente **utilisable** sous `RecodeVideo/`, avec une version minimale configurable, tout en conservant l’API publique de `Get-FFmpegPath` / `Get-FfprobePath` (override → base locale → PATH).

## Décisions validées

| Sujet | Choix |
|---|---|
| Identification de version | Uniquement via `ffmpeg -version` (pas de SemVer dérivé du nom de dossier) |
| Candidats | Dossiers dont le nom commence par `ffmpeg-` sous `RecodeVideo/` |
| Binaire non identifiable | Exclu (considéré corrompu / non officiel) |
| Version minimale | `9.0.1`, stockée dans `PrivateData` du manifeste `.psd1` |
| Cache | Une résolution par session module (`$script:FFToolsDefaultBase`) |
| Architecture | Helper privé + cache partagé par ffmpeg et ffprobe |
| Absence totale | `throw` avec message actionnable ; points d’entrée attrapent et affichent via `Write-ErrorLog` sans rethrow |

## Architecture

### Fichiers touchés

- `Utils/Tetram.Media.FFmpeg.psm1` — logique de résolution
- `Utils/Tetram.Media.FFmpeg.psd1` — `PrivateData.FFToolsMinVersion` (pas de dépendance ajoutée à `Tetram.Common` : le module FFmpeg **throw** ; le logging reste aux points d’entrée)
- `Tetram.Media.Reencode.psm1` — catch propre autour de la résolution au démarrage de `Invoke-ReencodeMedia`
- `Tetram.Media.Similarity.psm1` — même traitement aux points d’entrée qui appellent `Get-FFmpegPath` / `Invoke-FFmpeg`
- `tests/Utils/Tetram.Media.FFmpeg.Tests.ps1` — remplacer le stub

### Helper privé `Resolve-FFToolsDefaultBase`

Non exporté. Responsabilités :

1. Si `$script:FFToolsDefaultBase` déjà résolu (y compris `$null` explicite après échec) → retourner le cache.
2. Sinon scanner `Join-Path (Split-Path -Parent $PSScriptRoot) 'RecodeVideo'` pour les dossiers `ffmpeg-*`.
3. Pour chaque dossier : exiger `bin/ffmpeg.exe` (Windows) / `bin/ffmpeg` (non-Windows, aligné sur le reste du module si applicable).
4. Exécuter le binaire avec `-version` ; parser la première ligne / motif `ffmpeg version <X.Y[.Z…]>` ; ignorer suffixes (`-full_build-…`).
5. Si parsing impossible → exclure le candidat.
6. Si version `< FFToolsMinVersion` (lue depuis le manifeste du module) → exclure.
7. Parmi les restants, retenir la version **maximale** (`[version]`) ; en cas d’égalité, premier trouvé (ordre de scan stable).
8. Mettre en cache le chemin `…\bin` gagnant, ou `$null` si aucun candidat valide.
9. Retourner ce chemin.

`Get-FfprobePath` utilise **le même** dossier `bin` que le ffmpeg gagnant (pas de scan indépendant sur `ffprobe -version`).

### Flux public (inchangé en forme)

```
Get-FFmpegPath [-OverridePath]
  1. Override non vide + Test-Path → return override
  2. base = Resolve-FFToolsDefaultBase
     si base + ffmpeg présent → return Join-Path base ffmpeg
  3. Get-Command ffmpeg → return Source si trouvé
  4. throw message actionnable
```

Idem pour `Get-FfprobePath` avec `ffprobe`.

### Version minimale (manifeste)

Dans `Utils/Tetram.Media.FFmpeg.psd1` :

```powershell
PrivateData = @{
    PSData = @{ … }
    FFToolsMinVersion = '9.0.1'
}
```

Lecture au runtime via métadonnées du module importé (ex. `$MyInvocation.MyCommand.Module.PrivateData.FFToolsMinVersion` ou équivalent robuste après `Import-Module`). Valeur lue une fois et mise en cache script si utile.

### Message d’erreur (throw)

Le message doit indiquer clairement :

- quel outil manque (`ffmpeg` ou `ffprobe`) ;
- le dossier attendu : `RecodeVideo\` à la racine du repo ;
- le motif de dossier : `ffmpeg-<version>-…` avec `bin\` contenant les exécutables ;
- la version minimale requise (valeur du manifeste, ex. `9.0.1`).

Exemple de fond (formulation exacte libre tant que ces infos sont présentes) :

> FFmpeg introuvable : placez une build officielle ≥ 9.0.1 sous `<repo>\RecodeVideo\ffmpeg-<version>-…\bin\`, ou fournissez -OverridePath / PATH.

### Points d’entrée — affichage propre

- `Invoke-ReencodeMedia` : entourer la résolution (`Get-FFmpegPath` / `Get-FfprobePath`) d’un `try/catch` → `Write-ErrorLog` avec `$_.Exception.Message` (ou message dédié) → **return** sans rethrow.
- `Tetram.Media.Similarity` : même pattern sur les fonctions exportées qui appellent la résolution sans catch aujourd’hui.
- `Invoke-FFmpeg` : conserve le `throw` si l’exe est introuvable (appelant responsable du catch) ; le message doit rester cohérent avec celui des getters si la résolution échoue via `Get-FFmpegPath`.

## Hors scope

- Téléchargement automatique de FFmpeg.
- Validation de signature / hash des binaires au-delà de `-version`.
- Changement du layout gyan.dev (`bin/`, `doc/`, …).
- Versionnement git des binaires (`RecodeVideo/*` reste ignoré).

## Tests

Remplacer le stub `tests/Utils/Tetram.Media.FFmpeg.Tests.ps1` :

| Cas | Attendu |
|---|---|
| Plusieurs fixtures `ffmpeg-*` avec stubs contrôlés | Sélection de la plus haute version ≥ min |
| Version `<` min | Candidat ignoré |
| `-version` sans numéro parsable | Candidat ignoré |
| Aucun candidat + PATH mocké absent | `throw` avec message contenant chemin + version mini |
| Override valide | Retour override sans scan |
| Même base pour ffmpeg et ffprobe | Même répertoire `bin` |

Les fixtures utilisent des stubs / mocks (pas le vrai binaire gyan en CI). Le scan doit pouvoir être redirigé vers un dossier temporaire de test (paramètre interne testable ou injection du root `RecodeVideo` pour les tests).

## Critères de succès

- Déposer une nouvelle build `ffmpeg-X.Y.Z-…` ≥ min sous `RecodeVideo` suffit ; aucun changement de code pour pointer la version.
- Une build `<` min ou sans `-version` lisible n’est jamais utilisée.
- L’utilisateur final voit un message `Write-ErrorLog` clair, sans exception non gérée au niveau des cmdlets d’entrée.
