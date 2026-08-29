# Purfview Faster-Whisper

Ce dossier accueille la distribution Windows locale de [Purfview Faster-Whisper](https://github.com/Purfview/whisper-standalone-win) utilisée par `Get-MediaTranscript` pour les modèles :

- `large-v2`
- `large-v3`
- `large-v3-turbo`
- `kotoba-v2`

## Contenu attendu

Copier ici la distribution Purfview, notamment :

- `faster-whisper-xxl.exe`
- les DLL et runtime livrés avec cette distribution
- éventuellement `ffmpeg.exe` si la distribution l'embarque
- les poids des modèles Whisper / Kotoba déjà téléchargés

Les binaires, DLL et poids tiers ne sont **pas** versionnés.

## Notes

- `Get-MediaTranscript` ne télécharge rien automatiquement.
- `kotoba-v2` doit déjà être présent dans cette distribution ; le module ne le récupère pas.
- Si l'exécutable n'est pas dans ce dossier, le backend cherche `faster-whisper-xxl` dans le `PATH`.
