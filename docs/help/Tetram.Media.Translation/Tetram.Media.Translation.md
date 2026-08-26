---
document type: module
Help Version: 1.0.0
HelpInfoUri: ''
Locale: fr-FR
Module Guid: f4c86b9c-9c56-4bc8-b6b4-2ab400192367
Module Name: Tetram.Media.Translation
ms.date: 08/26/2026
PlatyPS schema version: 2024-05-01
title: Tetram.Media.Translation Module
---

# Tetram.Media.Translation Module

## Description

Traduction française de sous-titres via Gemini ou Ollama, à partir du fichier source et d'une transcription Whisper. Une seule commande exportée. Importer `.\Tetram.Media.Translation`.

Gemini est le fournisseur par défaut (`GEMINI_API_KEY`, modèle `gemini-3.6-flash`). Ollama est un fournisseur local (`http://localhost:11434`) : il doit être installé et démarré, `-Model` est obligatoire, `GEMINI_API_KEY` n'est pas utilisée.

`-Model` accepte un suffixe d'options terminal. Formes : `<model>`, `<model>[thinking]` (Gemini et Ollama), `<model>[thinking=<level>]` (Gemini uniquement). Les options ne sont jamais envoyées dans le nom du modèle au fournisseur.

## Tetram.Media.Translation Cmdlets

### [ConvertTo-FrenchSubtitle](ConvertTo-FrenchSubtitle.md)

Produit un fichier de sous-titres français à partir d'un sous-titre source et d'une transcription Whisper, via Gemini ou Ollama.
