---
document type: cmdlet
external help file: Tetram.Common-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Common
ms.date: 09/08/2026
PlatyPS schema version: 2024-05-01
title: ConvertFrom-ExtendedLengthPath
---

# ConvertFrom-ExtendedLengthPath

## SYNOPSIS

Retire le préfixe Win32 de chemin étendu (`\\?\` / `\\?\UNC\`).

## SYNTAX

### __AllParameterSets

```
ConvertFrom-ExtendedLengthPath [-Path] <string>
```

## ALIASES

## DESCRIPTION

Ramène un chemin d'outil Win32 vers sa forme logique : `\\?\C:\...` devient `C:\...`, `\\?\UNC\serveur\share\...` devient `\\serveur\share\...`. Un chemin déjà sans préfixe est renvoyé inchangé.

Cette conversion n'accède pas au disque et n'appelle pas `GetFullPath`.

## EXAMPLES

### Example 1: Préfixe disque local

```powershell
ConvertFrom-ExtendedLengthPath -Path '\\?\C:\Media\film.mkv'
```

### Example 2: Préfixe UNC

```powershell
ConvertFrom-ExtendedLengthPath -Path '\\?\UNC\nas\films\film.mkv'
```

## PARAMETERS

### -Path

Chemin éventuellement préfixé `\\?\`.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

Cette commande prend en charge les paramètres communs : -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction et -WarningVariable. Pour plus d'informations, voir
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.String

Le chemin logique, sans préfixe `\\?\`.

## NOTES

Complémentaire de `ConvertTo-ExtendedLengthPath` : les API .NET et les outils natifs préfèrent souvent le chemin étendu ; l'affichage et les comparaisons, le chemin logique.

## RELATED LINKS

- [ConvertTo-ExtendedLengthPath](ConvertTo-ExtendedLengthPath.md)
- [Test-SameFilesystemPath](Test-SameFilesystemPath.md)
