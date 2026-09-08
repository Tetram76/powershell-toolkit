---
document type: cmdlet
external help file: Tetram.Common-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Common
ms.date: 09/08/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-ExtendedLengthPath
---

# ConvertTo-ExtendedLengthPath

## SYNOPSIS

Ajoute le préfixe Win32 de chemin étendu (`\\?\` / `\\?\UNC\`) au-delà d'un seuil de longueur.

## SYNTAX

### __AllParameterSets

```
ConvertTo-ExtendedLengthPath [-Path] <string> [-Threshold <int>]
```

## ALIASES

## DESCRIPTION

Résout `$Path` en chemin complet. Si sa longueur dépasse `-Threshold` (défaut 250, marge sous MAX_PATH 260), le préfixe `\\?\` est ajouté (ou `\\?\UNC\` pour un UNC). Un chemin déjà préfixé `\\?\` est renvoyé inchangé, sans re-résolution.

En dessous du seuil, le chemin complet est renvoyé sans préfixe.

## EXAMPLES

### Example 1: Chemin court, inchangé hors préfixe

```powershell
ConvertTo-ExtendedLengthPath -Path 'C:\Windows'
```

### Example 2: Forcer le préfixe

```powershell
ConvertTo-ExtendedLengthPath -Path 'C:\Windows' -Threshold 1
```

## PARAMETERS

### -Path

Chemin à normaliser. Obligatoire.

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

### -Threshold

Longueur à partir de laquelle le préfixe étendu est ajouté. Défaut : 250.

```yaml
Type: System.Int32
DefaultValue: 250
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
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

Chemin complet, éventuellement préfixé `\\?\` / `\\?\UNC\`.

## NOTES

Le seuil 250 est volontairement sous MAX_PATH (260) : certains outils Win32 échouent avant la limite documentée.

## RELATED LINKS

- [ConvertFrom-ExtendedLengthPath](ConvertFrom-ExtendedLengthPath.md)
