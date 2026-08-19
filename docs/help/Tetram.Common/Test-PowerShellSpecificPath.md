---
document type: cmdlet
external help file: Tetram.Common-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Common
ms.date: 08/15/2026
PlatyPS schema version: 2024-05-01
title: Test-PowerShellSpecificPath
---

# Test-PowerShellSpecificPath

## SYNOPSIS

Indique si un chemin emploie de la syntaxe que seul PowerShell comprend.

## SYNTAX

### __AllParameterSets

```
Test-PowerShellSpecificPath [-Path] <string>
```

## ALIASES

## DESCRIPTION

Renvoie `$true` pour les crochets, l'échappement backtick et les PSDrive nommés, c'est-à-dire les formes qu'un processus natif ne saura pas interpréter et qu'il faut résoudre avant de les lui remettre. Renvoie `$false` pour une lettre de lecteur, un UNC, un chemin relatif et un masque `*` / `?`, que les outils natifs savent lire.

## EXAMPLES

### Example 1: Chemin à crochets

```powershell
Test-PowerShellSpecificPath -Path 'D:\Films\film[1].mkv'
```

### Example 2: Masque natif

```powershell
Test-PowerShellSpecificPath -Path 'D:\Films\*.mkv'
```

## PARAMETERS

### -Path

Chemin à inspecter.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Boolean

`$true` si le chemin emploie une syntaxe propre à PowerShell ; sinon `$false`.

## NOTES

## RELATED LINKS
