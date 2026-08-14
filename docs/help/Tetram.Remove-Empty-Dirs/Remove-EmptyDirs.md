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

Fait : `Get-ChildItem -Directory -Recurse` sous la racine, tri par longueur de chemin décroissante (enfant avant parent), puis `Remove-Item` si le dossier n'a aucun enfant. Un `parent/child` tous deux vides : `child` puis `parent` dans le même passage. Ce n'est pas « feuilles seulement ».

Ne fait pas : supprimer des fichiers ; suivre/supprimer les reparse points (jonctions, liens symboliques) — ils ne sont jamais « vides » au sens de cette commande ; émettre d'objets pipeline.

Sans `-DeepScan` : un seul passage (suffit pour une chaîne de dossiers déjà vides). Avec `-DeepScan` : nouveaux passages tant qu'une suppression réelle a eu lieu. Sous `-WhatIf`, rien n'est retiré : un parent qui a encore un enfant vide n'est pas « vide », donc n'apparaît pas.

Dry-run : `-WhatIf`. `ConfirmImpact` Medium : pas de prompt sauf `-Confirm`. Chemin invalide : message d'erreur console, retour immédiat, pas d'exception.

Les échecs d'inspection ou de suppression sont écrits sur la console (`Write-ErrorLog`), pas dans le pipeline.

## EXAMPLES

### Example 1: Simuler un nettoyage

Intention : lister les dossiers actuellement vides sans les supprimer. Sous `-WhatIf`,
aucune suppression n'a lieu, donc `-DeepScan` n'enchaîne pas de passages : seuls les
dossiers déjà sans enfant apparaissent (un parent qui contient encore un enfant vide
n'est pas listé).

```powershell
Remove-EmptyDirs -Path 'D:\Media' -DeepScan -WhatIf
```

### Example 2: Répéter jusqu'à un passage sans suppression

Intention : run réel après un dry-run. `-DeepScan` relance un scan complet tant qu'un
dossier a vraiment été retiré. Pour une chaîne déjà vide, le premier passage suffit
déjà (enfant puis parent).

```powershell
Remove-EmptyDirs -Path 'D:\Media' -DeepScan
```

### Example 3: Un seul passage

Intention : un scan, pas de rescan. Les parents vidés pendant ce passage sont quand
même retirés (tri du plus long chemin au plus court). Ce n'est pas limité aux feuilles.

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

Répète le scan tant qu'un passage a réellement supprimé au moins un dossier.
Un passage unique retire déjà les parents vidés dans ce passage (tri par
longueur de chemin). `-DeepScan` n'est pas le moyen d'obtenir « plus que les
feuilles ». Sous `-WhatIf`, aucun rescan : rien n'est supprimé.

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

Ne pas faire : l'utiliser pour effacer des fichiers ; omettre `-WhatIf` sur un arbre inconnu ; prendre un passage unique pour « feuilles seulement » (les parents vidés dans ce passage partent aussi) ; conclure du `-WhatIf` la liste exacte des suppressions d'un run réel (le WhatIf ne vide pas les enfants, donc pas les parents).

## RELATED LINKS

- [Invoke-ReencodeMedia]()
