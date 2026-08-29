# Sherpa-ONNX

Ce dossier accueille la distribution Windows locale de [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) utilisée par `Get-MediaTranscript` pour le modèle provisoire `reazon-k2-v2`.

Ce modèle sert à valider le routage vers Sherpa-ONNX. Ce n'est pas le résultat d'un benchmark ASR.

## Contenu attendu

### Exécutable

`sherpa-onnx-offline.exe` doit être présent **à la racine de ce dossier**, avec les DLL / runtime de la même distribution (onnxruntime, etc.).

Si l'exécutable n'est pas ici, le backend cherche `sherpa-onnx-offline` dans le `PATH`.

### Modèle provisoire `reazon-k2-v2`

Déposer dans un sous-dossier (par exemple `reazon-k2-v2/` ou `sherpa-onnx-zipformer-ja-reazonspeech-2024-08-01/`) les fichiers :

- `tokens.txt`
- `encoder*.onnx` (les poids `*.int8.onnx` sont préférés s'ils sont présents)
- `decoder*.onnx`
- `joiner*.onnx` (idem `*.int8.onnx`)

Les binaires, DLL et poids tiers ne sont **pas** versionnés.

`Get-MediaTranscript` ne télécharge rien automatiquement.

## Commande native validée

Une fois la distribution et les poids posés, la commande à valider manuellement est de la forme :

```text
sherpa-onnx-offline.exe ^
  --tokens=<dossier-modele>\tokens.txt ^
  --encoder=<dossier-modele>\encoder-epoch-99-avg-1.onnx ^
  --decoder=<dossier-modele>\decoder-epoch-99-avg-1.onnx ^
  --joiner=<dossier-modele>\joiner-epoch-99-avg-1.onnx ^
  --num-threads=1 ^
  <wav-japonais>.wav
```

Le JSON natif est émis sur stdout (`text`, `tokens`, `timestamps`, éventuellement `durations` et `ys_log_probs`). Les timestamps sont au niveau token, pas une segmentation phrase. Le backend Tetram en fait un seul segment durable.

Le WAV passé à Sherpa doit être PCM 16-bit ; le backend le prépare via `Tetram.Media.FFmpeg` à partir de la piste `-AudioTrack`.
