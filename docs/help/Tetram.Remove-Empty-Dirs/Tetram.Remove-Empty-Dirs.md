---
document type: module
Help Version: 1.0.0
HelpInfoUri: ''
Locale: fr-FR
Module Guid: b0f3c7d6-3a8b-49a5-9b4a-2c5f3f1b8b31
Module Name: Tetram.Remove-Empty-Dirs
ms.date: 08/14/2026
PlatyPS schema version: 2024-05-01
title: Tetram.Remove-Empty-Dirs Module
---

# Tetram.Remove-Empty-Dirs Module

## Description

Nettoyage de dossiers vides uniquement (pas de fichiers). Une seule commande exportée. Importer `.\Tetram.Remove-Empty-Dirs.psd1`. Un passage (profondeur d'abord) retire aussi les parents vidés dans ce passage ; `-DeepScan` relance jusqu'à stabilité. Toujours `-WhatIf` d'abord (le dry-run ne montre pas ces parents).

## Tetram.Remove-Empty-Dirs Cmdlets

### [Remove-EmptyDirs](Remove-EmptyDirs.md)

Supprime uniquement des répertoires vides. Ne touche pas aux fichiers. Un passage, ou boucle (`-DeepScan`) jusqu'à stabilité.

