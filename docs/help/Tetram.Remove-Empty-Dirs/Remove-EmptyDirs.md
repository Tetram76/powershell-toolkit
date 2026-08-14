---
document type: cmdlet
external help file: Tetram.Remove-Empty-Dirs-Help.xml
HelpUri: ''
Locale: fr-FR
Module Name: Tetram.Remove-Empty-Dirs
ms.date: 08/14/2026
PlatyPS schema version: 2024-05-01
title: Remove-EmptyDirs
---

# Remove-EmptyDirs

## SYNOPSIS

Supprime uniquement des répertoires vides. Ne touche pas aux fichiers. Un passage, ou boucle (`-DeepScan`) jusqu'à stabilité.

## SYNTAX

### __AllParameterSets

```
Remove-EmptyDirs [[-Path] <string>] [-DeepScan] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Importer `Tetram.Remove-Empty-Dirs.psd1` (PowerShell 7+). Cible : `-Path` doit être un dossier existant (défaut `.`).

Fait : `Get-ChildItem -Directory -Recurse` sous la racine, du plus profond au plus proche, puis `Remove-Item` si le dossier n'a aucun enfant.

Ne fait pas : supprimer des fichiers ; suivre/supprimer les reparse points (jonctions, liens symboliques) — ils ne sont jamais « vides » au sens de cette commande ; émettre d'objets pipeline.

Sans `-DeepScan` : un seul passage. Un parent qui ne devient vide qu'après la suppression de ses enfants reste. Avec `-DeepScan` : nouveaux passages tant qu'un dossier a été retiré.

Dry-run : `-WhatIf`. `ConfirmImpact` Medium : pas de prompt sauf `-Confirm`. Chemin invalide : message d'erreur console, retour immédiat, pas d'exception.

Les échecs d'inspection ou de suppression sont écrits sur la console (`Write-ErrorLog`), pas dans le pipeline.

## EXAMPLES

### Example 1: Simuler un nettoyage

Intention : lister les dossiers actuellement vides sans les supprimer. Sous `-WhatIf`,
`-DeepScan` n'enchaîne pas de passages virtuels : les parents qui ne se videraient
qu'après coup n'apparaissent pas.

```powershell
Remove-EmptyDirs -Path 'D:\Media' -DeepScan -WhatIf
```

### Example 2: Supprimer jusqu'à ce qu'il ne reste plus de dossier vide

Intention : run réel après un dry-run. Préférer `-DeepScan` sauf besoin d'un seul niveau de feuilles.

```powershell
Remove-EmptyDirs -Path 'D:\Media' -DeepScan
```

### Example 3: Un seul passage (feuilles vides seulement)

Intention : ne pas retirer les parents nouvellement vidés.

```powershell
Remove-EmptyDirs -Path 'D:\Media'
```

## PARAMETERS

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
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

### -DeepScan

Répète le scan tant qu'un passage a supprimé au moins un dossier. Permet de
retirer les parents qui ne deviennent vides qu'après la suppression de leurs
enfants.
Répète le scan tant qu'un passage a supprimé au moins un dossier.
Permet de
retirer les parents qui ne deviennent vides qu'après la suppression de leurs
enfants.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
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

### -Path

Répertoire racine à nettoyer. Doit exister et être un conteneur. Valeur par
défaut : répertoire courant (`.`).
Répertoire racine à nettoyer.
Doit exister et être un conteneur.
Valeur par
défaut : répertoire courant (`.`).

```yaml
Type: System.String
DefaultValue: .
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
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

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

Prérequis : PowerShell 7+. La racine `-Path` n'est jamais supprimée : le scan ne liste que ses sous-dossiers.

Ne pas faire : l'utiliser pour effacer des fichiers ; omettre `-WhatIf` sur un arbre inconnu ; conclure « rien à faire » sans `-DeepScan` alors que des parents sont devenus vides.

## RELATED LINKS

- [Invoke-ReencodeMedia]()
