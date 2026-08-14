---
document type: module
Help Version: 2.6.1
HelpInfoUri: ''
Locale: fr-FR
Module Guid: d4f3b1ab-7c6a-4a3a-9d9f-9d1a82bf7b95
Module Name: Tetram.Media.Reencode
ms.date: 08/14/2026
PlatyPS schema version: 2024-05-01
title: Tetram.Media.Reencode Module
---

# Tetram.Media.Reencode Module

## Description

Réencodage / remux / contrôle de fichiers média, in-place. Une seule commande exportée. Importer le dossier du module (`Import-Module .\Tetram.Media.Reencode`). Consommateur principal de cette aide : agent IA — voir le contrat d'appel dans la page commande (modes exclusifs, skips, remplacement de l'original, `-CheckOnly` n'est pas un dry-run, absence d'objets pipeline).

## Tetram.Media.Reencode Cmdlets

### [Invoke-ReencodeMedia](Invoke-ReencodeMedia.md)

Remplace in-place des fichiers média : réencodage HEVC/AV1, remux (`-Rewrite`) ou contrôle ffmpeg (`-CheckOnly`, pas un dry-run).

