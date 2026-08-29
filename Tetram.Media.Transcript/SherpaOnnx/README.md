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
  sherpa-onnx-vad.exe
  sherpa-onnx-offline.exe
  <DLL/runtime upstream>
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

### Exécutables

`sherpa-onnx-vad.exe` et `sherpa-onnx-offline.exe` doivent être présents **à la racine de ce dossier**, avec les DLL / runtime de la même distribution (onnxruntime, etc.), `silero_vad.onnx` et `ten-vad.onnx` (même dossier que les exe). Les deux fichiers VAD sont requis pour chaque modèle Sherpa.

Si un exécutable n'est pas ici, le backend cherche le nom correspondant (`sherpa-onnx-vad` / `sherpa-onnx-offline`) dans le `PATH`.

Le binaire combiné `sherpa-onnx-vad-with-offline-asr.exe` n'est plus utilisé.

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

Tetram utilise le chemin **NeMo CTC** (`--nemo-ctc-model`), pas TDT/transducer.

#### `sensevoice-small`

Archive officielle Sherpa : `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17`.

Référence : <https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html>

Y déposer exactement :

- `tokens.txt`
- `model.int8.onnx`

L'intégration Tetram force le japonais (`--sense-voice-language=ja`). Les autres langues upstream ne sont pas exposées.

Les binaires, DLL et poids tiers ne sont **pas** versionnés.

Les archives ASR pré-entraînées sont sur [asr-models](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models). Extraire le contenu dans `models/<nom>/`. `Get-MediaTranscript` ne télécharge rien automatiquement.

## Pipeline natif

Les tests Pester ne lancent jamais `sherpa-onnx-vad.exe` ni `sherpa-onnx-offline.exe`.

`Get-MediaTranscript -Model <modèle-sherpa>` :

1. extrait **un** WAV maître temporaire (PCM signed 16-bit, mono, 16 kHz via `Tetram.Media.FFmpeg`) ;
2. lance `sherpa-onnx-vad.exe` une fois pour Silero, une fois pour TEN, sur ce WAV maître ;
3. découpe un chunk WAV par intervalle VAD **depuis le WAV maître** (pas depuis le WAV parole concaténé imposé par le VAD) ;
4. lance `sherpa-onnx-offline.exe` sur ces chunks, par lots bornés (détail privé) ;
5. recale segments et timestamps token-level sur la timeline du média : `TimelineOffset + vadStart + tokenLocal`.

Silero et TEN restent deux observations séparées. Une seule passe ASR par chunk. Le flag `--num-threads` n'est pas passé : Sherpa conserve son défaut.

Le WAV concaténé produit par `sherpa-onnx-vad.exe` est un artefact jetable. Tous les temporaires sont supprimés après succès ou échec.

### VAD Silero

```text
sherpa-onnx-vad.exe ^
  --silero-vad-model=silero_vad.onnx ^
  --silero-vad-threshold=0.40 ^
  --silero-vad-min-silence-duration=0.5 ^
  --silero-vad-min-speech-duration=0.25 ^
  --silero-vad-max-speech-duration=6 ^
  --silero-vad-window-size=512 ^
  --silero-vad-neg-threshold=-1 ^
  <wav-maitre>.wav ^
  <wav-parole-jetable>.wav
```

### VAD TEN

```text
sherpa-onnx-vad.exe ^
  --ten-vad-model=ten-vad.onnx ^
  --ten-vad-threshold=0.5 ^
  --ten-vad-min-silence-duration=0.5 ^
  --ten-vad-min-speech-duration=0.25 ^
  --ten-vad-max-speech-duration=6 ^
  --ten-vad-window-size=256 ^
  <wav-maitre>.wav ^
  <wav-parole-jetable>.wav
```

### ASR offline

Une fois la distribution et les poids posés, valider **exactement** les fichiers que le backend sélectionne.

#### Reazon (recette INT8 : encoder INT8 + decoder FP32 + joiner INT8)

```text
sherpa-onnx-offline.exe ^
  --tokens=models\reazon-k2-v2\tokens.txt ^
  --encoder=models\reazon-k2-v2\encoder-epoch-99-avg-1.int8.onnx ^
  --decoder=models\reazon-k2-v2\decoder-epoch-99-avg-1.onnx ^
  --joiner=models\reazon-k2-v2\joiner-epoch-99-avg-1.int8.onnx ^
  <chunk-1>.wav <chunk-2>.wav ...
```

#### Parakeet japonais (NeMo CTC)

```text
sherpa-onnx-offline.exe ^
  --tokens=models\parakeet-0.6b-ja\tokens.txt ^
  --nemo-ctc-model=models\parakeet-0.6b-ja\model.int8.onnx ^
  <chunk-1>.wav <chunk-2>.wav ...
```

#### SenseVoiceSmall (japonais forcé)

```text
sherpa-onnx-offline.exe ^
  --tokens=models\sensevoice-small\tokens.txt ^
  --sense-voice-model=models\sensevoice-small\model.int8.onnx ^
  --sense-voice-language=ja ^
  <chunk-1>.wav <chunk-2>.wav ...
```

`sherpa-onnx-offline.exe` écrit un JSON natif par WAV (`text`, `tokens`, `timestamps`, et éventuellement `durations`, `ys_log_probs`, `lang`, `emotion`, `event`). Tetram conserve ces champs dans `diagnostics` **uniquement lorsqu'ils sont réellement présents**. Les timestamps token sont recalés sur la timeline média. Les `words` numériques Sherpa (IDs CTC/FST) ne sont pas transformés en objets word-level Faster-Whisper.

Le JSON compact envoyé à Gemini par `ConvertTo-FrenchSubtitle` reste limité à `engine`, `model`, `vad`, `language` et `segments[].start/end/text`. Les tokens et autres diagnostics Sherpa n'y figurent pas.

Sidecars durables :

```text
<media-base>.track <trackid>.<langue>.<model>.silero.json
<media-base>.track <trackid>.<langue>.<model>.ten.json
```

Sous Windows, Sherpa demande le code page UTF-8 (65001) si le japonais se corrompt. Le backend capture stdout et stderr en UTF-8, indépendamment de l'encodage de la console.
