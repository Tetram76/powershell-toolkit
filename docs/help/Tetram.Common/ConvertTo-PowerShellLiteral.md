---
document type: cmdlet
external help file: Tetram.Common-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Common
ms.date: 09/08/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-PowerShellLiteral
---

# ConvertTo-PowerShellLiteral

## SYNOPSIS

Produit un littéral PowerShell à quotes simples, sûr à coller dans une ligne de commande.

## SYNTAX

### __AllParameterSets

```
ConvertTo-PowerShellLiteral [[-Value] <string>]
```

## ALIASES

## DESCRIPTION

Entoure `$Value` de quotes simples après `CodeGeneration.EscapeSingleQuotedStringContent` (recette documentée : `"'" + Escape(...) + "'"`). Les apostrophes internes, y compris les équivalents Unicode, sont échappées. Une chaîne vide donne `''`.

Utile pour une ligne copiable (`& 'mkvmerge.exe' 'C:\Media\It''s a film.mkv'`), pas pour passer des arguments à un processus natif (là, un tableau d'arguments suffit).

## EXAMPLES

### Example 1: Chemin sans apostrophe

```powershell
ConvertTo-PowerShellLiteral -Value 'C:\Windows'
```

### Example 2: Apostrophe interne

```powershell
ConvertTo-PowerShellLiteral -Value "It's a film"
```

## PARAMETERS

### -Value

Texte à représenter en littéral. Peut être vide.

```yaml
Type: System.String
DefaultValue: ''
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

Littéral quotes simples, y compris les délimiteurs.

## NOTES

Pas de cmdlet native équivalente : `Join-String -SingleQuote` n'échappe pas les apostrophes.

## RELATED LINKS
