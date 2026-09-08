---
document type: cmdlet
external help file: Tetram.Common-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Common
ms.date: 09/08/2026
PlatyPS schema version: 2024-05-01
title: Test-SameFilesystemPath
---

# Test-SameFilesystemPath

## SYNOPSIS

Indique si deux chemins désignent le même fichier selon le système de fichiers.

## SYNTAX

### __AllParameterSets

```
Test-SameFilesystemPath [-LiteralPath] <string> -ReferenceLiteralPath <string>
```

## ALIASES

## DESCRIPTION

Retire un éventuel préfixe `\\?\` / `\\?\UNC\`, résout via `GetFullPath`, puis compare avec `Path.GetRelativePath`. Un résultat `.` signifie le même fichier. La casse suit le système de fichiers : insensible sous Windows, sensible sous Linux et macOS. N'accède pas au disque : les fichiers n'ont pas besoin d'exister.

Sans ça, comparer les chaînes brutes rate `C:\film.mkv` contre `\\?\C:\film.mkv`, ou traite à tort `film.mkv` et `FILM.mkv` comme identiques hors Windows.

## EXAMPLES

### Example 1: Même fichier, formes courte et étendue

```powershell
Test-SameFilesystemPath -LiteralPath 'C:\Media\film.mkv' -ReferenceLiteralPath '\\?\C:\Media\film.mkv'
```

### Example 2: Fichiers distincts

```powershell
Test-SameFilesystemPath -LiteralPath 'C:\Media\film.mkv' -ReferenceLiteralPath 'C:\Media\film.repaired.mkv'
```

## PARAMETERS

### -LiteralPath

Premier chemin (éventuellement préfixé `\\?\`).

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

### -ReferenceLiteralPath

Second chemin à comparer.

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

### System.Boolean

`$true` si les deux chemins désignent le même fichier ; sinon `$false`.

## NOTES

Complémentaire de `ConvertFrom-ExtendedLengthPath` : la comparaison se fait sur les formes logiques.

## RELATED LINKS

- [ConvertFrom-ExtendedLengthPath](ConvertFrom-ExtendedLengthPath.md)
- [ConvertTo-ExtendedLengthPath](ConvertTo-ExtendedLengthPath.md)
