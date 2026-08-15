---
document type: cmdlet
external help file: Tetram.Common-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Common
ms.date: 08/15/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-AbsolutePath
---

# ConvertTo-AbsolutePath

## SYNOPSIS

Absolutise un chemin, même inexistant.

## SYNTAX

### __AllParameterSets

```
ConvertTo-AbsolutePath [-Path] <string>
```

## ALIASES

## DESCRIPTION

Développe `~`, puis absolutise relativement à l'emplacement PowerShell courant.

## EXAMPLES

### Example 1: Absolutiser un chemin relatif

```powershell
ConvertTo-AbsolutePath -Path '.\film.mkv'
```

## PARAMETERS

### -Path

Chemin à absolutiser. N'a pas besoin d'exister.

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

### System.String

Chemin absolutisé.

## NOTES

Contrairement à `Resolve-Path`, n'échoue pas sur un chemin inexistant ; la base est l'emplacement PowerShell et non le répertoire de travail du processus, les deux ne coïncidant pas nécessairement.

## RELATED LINKS
