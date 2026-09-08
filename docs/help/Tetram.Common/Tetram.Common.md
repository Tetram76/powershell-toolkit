---
document type: module
Help Version: 1.4.0
HelpInfoUri: ''
Locale: fr-FR
Module Guid: 1c6e2a0f-bf1a-4a92-8a7a-1d5a0f6a6b90
Module Name: Tetram.Common
ms.date: 09/08/2026
PlatyPS schema version: 2024-05-01
title: Tetram.Common Module
---

# Tetram.Common Module

## Description

Fonctions de journalisation, de formatage, et utilitaires de chemin (syntaxe PowerShell, chemins Win32 longs). Importer `.\Tetram.Common`.

## Tetram.Common Cmdlets

### [ConvertFrom-ExtendedLengthPath](ConvertFrom-ExtendedLengthPath.md)

Retire le préfixe Win32 de chemin étendu (`\\?\` / `\\?\UNC\`).

### [ConvertTo-ExtendedLengthPath](ConvertTo-ExtendedLengthPath.md)

Ajoute le préfixe Win32 de chemin étendu (`\\?\` / `\\?\UNC\`) au-delà d'un seuil de longueur.

### [ConvertTo-PowerShellLiteral](ConvertTo-PowerShellLiteral.md)

Produit un littéral PowerShell à quotes simples, sûr à coller dans une ligne de commande.

### [Test-PowerShellSpecificPath](Test-PowerShellSpecificPath.md)

Indique si un chemin emploie de la syntaxe que seul PowerShell comprend.

### [Test-SameFilesystemPath](Test-SameFilesystemPath.md)

Indique si deux chemins désignent le même fichier (préfixe `\\?\`, casse du système de fichiers).

### [Write-InfoWarning](Write-InfoWarning.md)

Affiche un message d'information de niveau avertissement en jaune.
