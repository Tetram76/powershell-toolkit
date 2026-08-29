# Sherpa-ONNX

Ce dossier accueille la distribution Windows locale de [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) utilisée par `Get-MediaTranscript` pour le modèle provisoire `reazon-k2-v2`.

Préférer un package `win-x64-shared-MT-Release-no-tts`. Utiliser le contenu du dossier `bin` du package.

Ce modèle sert à valider le routage vers Sherpa-ONNX. Ce n'est pas le résultat d'un benchmark ASR.

## Contenu attendu

### Exécutable

`sherpa-onnx-vad-with-offline-asr.exe` doit être présent **à la racine de ce dossier**, avec les DLL / runtime de la même distribution (onnxruntime, etc.), `silero_vad.onnx` et `ten-vad.onnx` (même dossier que l'exe). Les deux fichiers VAD sont requis pour le pipeline Reazon actuel.

Si l'exécutable n'est pas ici, le backend cherche `sherpa-onnx-vad-with-offline-asr` dans le `PATH`.

### Modèles (`models/<nom>`)

Chaque `-Model` Sherpa correspond à **exactement** `models/<nom>/`. Pour `reazon-k2-v2` :

`models/reazon-k2-v2/`

y déposer :

- `tokens.txt`
- `encoder*.onnx` (INT8 préféré s'il existe aussi en FP32)
- `decoder*.onnx` (FP32 préféré : la recette INT8 Reazon documentée est encoder INT8 + decoder FP32 + joiner INT8)
- `joiner*.onnx` (INT8 préféré s'il existe aussi en FP32)

Un dossier homonyme à la racine de `SherpaOnnx/` ou un autre sous-dossier de `models/` n'est pas utilisé. Dossier absent ou fichiers incomplets : le backend lève une erreur.

Les binaires, DLL et poids tiers ne sont **pas** versionnés.

Les archives ASR pré-entraînées sont sur [asr-models](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models). Extraire le contenu dans `models/<nom>/`. `Get-MediaTranscript` ne télécharge rien automatiquement.

## Commandes natives (deux invocations)

Les tests Pester ne lancent jamais `sherpa-onnx-vad-with-offline-asr.exe`.

`Get-MediaTranscript -Model reazon-k2-v2` prépare **un** WAV temporaire (PCM 16-bit, mono, 16 kHz via `Tetram.Media.FFmpeg`) puis lance **deux** invocations séparées du même binaire sur ce WAV : Silero, puis TEN. Silero et TEN ne sont jamais combinés dans la même commande. Le flag `--num-threads` n'est pas passé : Sherpa conserve son défaut.

Une fois la distribution et les poids posés, valider **exactement** les fichiers que le backend sélectionne (recette Reazon INT8 : encoder INT8 + decoder FP32 + joiner INT8) :

```text
sherpa-onnx-vad-with-offline-asr.exe ^
  --tokens=models\reazon-k2-v2\tokens.txt ^
  --encoder=models\reazon-k2-v2\encoder-epoch-99-avg-1.int8.onnx ^
  --decoder=models\reazon-k2-v2\decoder-epoch-99-avg-1.onnx ^
  --joiner=models\reazon-k2-v2\joiner-epoch-99-avg-1.int8.onnx ^
  --silero-vad-model=silero_vad.onnx ^
  --silero-vad-threshold=0.40 ^
  --silero-vad-min-silence-duration=0.5 ^
  --silero-vad-min-speech-duration=0.25 ^
  --silero-vad-max-speech-duration=6 ^
  --silero-vad-window-size=512 ^
  --silero-vad-neg-threshold=-1 ^
  <wav-japonais>.wav
```

```text
sherpa-onnx-vad-with-offline-asr.exe ^
  --tokens=models\reazon-k2-v2\tokens.txt ^
  --encoder=models\reazon-k2-v2\encoder-epoch-99-avg-1.int8.onnx ^
  --decoder=models\reazon-k2-v2\decoder-epoch-99-avg-1.onnx ^
  --joiner=models\reazon-k2-v2\joiner-epoch-99-avg-1.int8.onnx ^
  --ten-vad-model=ten-vad.onnx ^
  --ten-vad-threshold=0.5 ^
  --ten-vad-min-silence-duration=0.5 ^
  --ten-vad-min-speech-duration=0.25 ^
  --ten-vad-max-speech-duration=6 ^
  --ten-vad-window-size=256 ^
  <wav-japonais>.wav
```

Le binaire écrit **une ligne par segment** sur stdout :

```text
<start> -- <end>: <text>
```

Pas de JSON natif. Le backend parse ces lignes, replace les timestamps sur la timeline du média (arrondi à 3 décimales) et publie deux sidecars Tetram. Le champ `model` reste `reazon-k2-v2` ; `vad` vaut `silero` ou `ten`.

```text
<media-base>.track <trackid>.<langue>.reazon-k2-v2.silero.json
<media-base>.track <trackid>.<langue>.reazon-k2-v2.ten.json
```

Sous Windows, Sherpa demande le code page UTF-8 (65001) si le japonais se corrompt. Le backend capture stdout en UTF-8, indépendamment de l'encodage de la console.

Le WAV temporaire est commun aux deux runs et n'est pas conservé après succès ou échec.
