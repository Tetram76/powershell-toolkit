---
document type: cmdlet
external help file: Tetram.Common-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Common
ms.date: 08/15/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-AbsoluteMask
---

# ConvertTo-AbsoluteMask

## SYNOPSIS

Absolutise le préfixe d'un masque sans toucher au masque.

## SYNTAX

### __AllParameterSets

```
ConvertTo-AbsoluteMask [-Mask] <string>
```

## ALIASES

## DESCRIPTION

Le préfixe sans métacaractère est absolutisé, les segments à partir du premier `*` ou `?` sont conservés tels quels, y compris un masque de segment intermédiaire.

## EXAMPLES

### Example 1: Masque relatif

```powershell
ConvertTo-AbsoluteMask -Mask '.\*.mkv'
```

### Example 2: Masque de segment intermédiaire

```powershell
ConvertTo-AbsoluteMask -Mask 'D:\Films\*\*.mkv'
```

## PARAMETERS

### -Mask

Masque dont le préfixe sans métacaractère doit être absolutisé.

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

Masque dont le préfixe est absolutisé.

## NOTES

## RELATED LINKS
