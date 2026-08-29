# Sherpa-ONNX

Ce dossier accueille la distribution Windows locale de [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) utilisée par `Get-MediaTranscript` pour les modèles Sherpa :

- `reazon-k2-v2`
- `parakeet-0.6b-ja`
- `sensevoice-small`

Préférer un package `win-x64-shared-MT-Release-no-tts`. Utiliser le contenu du dossier `bin` du package.

Les trois modèles servent à valider le routage vers Sherpa-ONNX. Ce n'est pas le résultat d'un benchmark ASR.

## Contenu attendu

```text
SherpaOnnx/
  sherpa-onnx-vad-with-offline-asr.exe
  silero_vad.onnx
  ten-vad.onnx
  models/
    reazon-k2-v2/
      tokens.txt
      encoder*.onnx
      decoder*.onnx
      joiner*.onnx
    parakeet-0.6b-ja/
      tokens.txt
      model.int8.onnx
    sensevoice-small/
      tokens.txt
      model.int8.onnx
```

### Exécutable

`sherpa-onnx-vad-with-offline-asr.exe` doit être présent **à la racine de ce dossier**, avec les DLL / runtime de la même distribution (onnxruntime, etc.), `silero_vad.onnx` et `ten-vad.onnx` (même dossier que l'exe). Les deux fichiers VAD sont requis pour chaque modèle Sherpa.

Si l'exécutable n'est pas ici, le backend cherche `sherpa-onnx-vad-with-offline-asr` dans le `PATH`.

### Modèles (`models/<nom>`)

Chaque `-Model` Sherpa correspond à **exactement** `models/<nom>/`. Un dossier homonyme à la racine de `SherpaOnnx/` ou un autre sous-dossier de `models/` n'est pas utilisé. Dossier absent ou fichiers incomplets : le backend lève une erreur.

#### `reazon-k2-v2`

- `tokens.txt`
- `encoder*.onnx` (INT8 préféré s'il existe aussi en FP32)
- `decoder*.onnx` (FP32 préféré : la recette INT8 Reazon documentée est encoder INT8 + decoder FP32 + joiner INT8)
- `joiner*.onnx` (INT8 préféré s'il existe aussi en FP32)

#### `parakeet-0.6b-ja`

Archive officielle Sherpa : `sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8`.

Référence : <https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-ctc/nemo/japanese.html>

Y déposer exactement :

- `tokens.txt`
- `model.int8.onnx`

#### `sensevoice-small`

Archive officielle Sherpa : `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17`.

Référence : <https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html>

Y déposer exactement :

- `tokens.txt`
- `model.int8.onnx`

L'intégration Tetram force le japonais (`--sense-voice-language=ja`). Les autres langues upstream ne sont pas exposées.

Les binaires, DLL et poids tiers ne sont **pas** versionnés.

Les archives ASR pré-entraînées sont sur [asr-models](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models). Extraire le contenu dans `models/<nom>/`. `Get-MediaTranscript` ne télécharge rien automatiquement.

## Commandes natives (deux invocations par modèle)

Les tests Pester ne lancent jamais `sherpa-onnx-vad-with-offline-asr.exe`.

`Get-MediaTranscript -Model <modèle-sherpa>` prépare **un** WAV temporaire (PCM 16-bit, mono, 16 kHz via `Tetram.Media.FFmpeg`) puis lance **deux** invocations séparées du même binaire sur ce WAV : Silero, puis TEN. Silero et TEN ne sont jamais combinés dans la même commande. Le flag `--num-threads` n'est pas passé : Sherpa conserve son défaut.

Une fois la distribution et les poids posés, valider **exactement** les fichiers que le backend sélectionne.

### Reazon (recette INT8 : encoder INT8 + decoder FP32 + joiner INT8)

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

### Parakeet japonais

```text
sherpa-onnx-vad-with-offline-asr.exe ^
  --tokens=models\parakeet-0.6b-ja\tokens.txt ^
  --nemo-ctc-model=models\parakeet-0.6b-ja\model.int8.onnx ^
  --silero-vad-model=silero_vad.onnx ^
  ...mêmes flags Silero...
  <wav-japonais>.wav
```

```text
sherpa-onnx-vad-with-offline-asr.exe ^
  --tokens=models\parakeet-0.6b-ja\tokens.txt ^
  --nemo-ctc-model=models\parakeet-0.6b-ja\model.int8.onnx ^
  --ten-vad-model=ten-vad.onnx ^
  ...mêmes flags TEN...
  <wav-japonais>.wav
```

### SenseVoiceSmall (japonais forcé)

```text
sherpa-onnx-vad-with-offline-asr.exe ^
  --tokens=models\sensevoice-small\tokens.txt ^
  --sense-voice-model=models\sensevoice-small\model.int8.onnx ^
  --sense-voice-language=ja ^
  --silero-vad-model=silero_vad.onnx ^
  ...mêmes flags Silero...
  <wav-japonais>.wav
```

```text
sherpa-onnx-vad-with-offline-asr.exe ^
  --tokens=models\sensevoice-small\tokens.txt ^
  --sense-voice-model=models\sensevoice-small\model.int8.onnx ^
  --sense-voice-language=ja ^
  --ten-vad-model=ten-vad.onnx ^
  ...mêmes flags TEN...
  <wav-japonais>.wav
```

Le binaire écrit **une ligne par segment** sur stdout :

```text
<start> -- <end>: <text>
```

Pas de JSON natif. Le backend parse ces lignes, replace les timestamps sur la timeline du média (arrondi à 3 décimales) et publie deux sidecars Tetram. Le champ `model` reste le nom canonique ; `vad` vaut `silero` ou `ten`.

```text
<media-base>.track <trackid>.<langue>.<model>.silero.json
<media-base>.track <trackid>.<langue>.<model>.ten.json
```

Sous Windows, Sherpa demande le code page UTF-8 (65001) si le japonais se corrompt. Le backend capture stdout en UTF-8, indépendamment de l'encodage de la console.

Le WAV temporaire est commun aux deux runs et n'est pas conservé après succès ou échec.
