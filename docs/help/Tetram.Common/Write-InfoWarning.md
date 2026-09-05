---
document type: cmdlet
external help file: Tetram.Common-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Common
ms.date: 09/05/2026
PlatyPS schema version: 2024-05-01
title: Write-InfoWarning
---

# Write-InfoWarning

## SYNOPSIS

Affiche un message d'information de niveau warning en jaune.

## SYNTAX

### __AllParameterSets

```
Write-InfoWarning [-Text] <string> [-Force]
```

## ALIASES

## DESCRIPTION

Raccourci sémantique vers `Write-InfoLog` avec une couleur jaune fixe. Il n'introduit pas un nouveau système de journalisation et n'écrit pas dans le warning stream PowerShell (`Write-Warning` n'est pas appelé).

Sans `-Force`, la visibilité suit exactement `Write-InfoLog` : le message n'apparaît que si `-Verbose` est présent ou si `$VerbosePreference` vaut `Continue`. Avec `-Force`, le message s'affiche indépendamment de `Verbose`.

Aucun objet n'est écrit dans le pipeline : il s'agit d'un affichage console, avec le timestamp fourni par `Write-Log`.

## EXAMPLES

### Example 1: Warning forcé

```powershell
Write-InfoWarning -Text 'durée incohérente acceptée' -Force
```

### Example 2: Même politique de visibilité que Write-InfoLog

```powershell
Write-InfoWarning -Text 'détail visible seulement en Verbose'
```

## PARAMETERS

### -Force

Affiche le message même si Verbose n'est pas actif. Relais direct du `-Force` de `Write-InfoLog`.

```yaml
Type: System.Management.Automation.SwitchParameter
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

### -Text

Texte à afficher. Obligatoire. La couleur n'est pas paramétrable : elle est toujours jaune.

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

## NOTES

Ne pas utiliser pour le warning stream PowerShell. Pour un message d'information bleu, utiliser `Write-InfoLog`.

## RELATED LINKS
