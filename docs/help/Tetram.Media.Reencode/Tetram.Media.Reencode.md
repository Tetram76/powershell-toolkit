---
document type: module
Help Version: 3.3.0
HelpInfoUri: ''
Locale: fr-FR
Module Guid: d4f3b1ab-7c6a-4a3a-9d9f-9d1a82bf7b95
Module Name: Tetram.Media.Reencode
ms.date: 09/08/2026
PlatyPS schema version: 2024-05-01
title: Tetram.Media.Reencode Module
---

# Tetram.Media.Reencode Module

## Description

Réencodage / normalisation / contrôle de fichiers média, in-place, et réparation d'interleaving MKV. Trois commandes exportées. Importer le dossier du module (`Import-Module .\Tetram.Media.Reencode`). Consommateur principal de cette aide : agent IA — voir le contrat d'appel dans les pages commande (modes exclusifs CheckOnly / réencodage MKV / NoTranscode ; remux mkvmerge in-place ; skips ; `-CheckOnly` n'est pas un dry-run).

## Tetram.Media.Reencode Cmdlets

### [Get-MkvInterleaveRepairCommand](Get-MkvInterleaveRepairCommand.md)

Construit la ligne `mkvmerge` qui répare l'interleaving d'un MKV, sans remplacer le fichier.

### [Invoke-MkvRepair](Invoke-MkvRepair.md)

Répare l'interleaving d'un MKV (ou des `*.mkv` d'un dossier) et remplace le fichier source in-place.

### [Invoke-ReencodeMedia](Invoke-ReencodeMedia.md)

Remplace in-place des fichiers média : réencodage HEVC/AV1 vers MKV, `-NoTranscode` (filtrage sans transcodage) ou contrôle ffmpeg (`-CheckOnly`, pas un dry-run).
