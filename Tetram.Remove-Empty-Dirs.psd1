@{
# --- Identité du module ---
    RootModule = 'Tetram.Remove-Empty-Dirs.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'b0f3c7d6-3a8b-49a5-9b4a-2c5f3f1b8b31'

    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Supprime les répertoires vides avec prise en charge de -WhatIf / -Confirm et DeepScan (PowerShell 7+).'

    # --- Compatibilité ---
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    # --- Dépendances ---
    RequiredModules = @()
    RequiredAssemblies = @()
    NestedModules = @(
        '.\Utils\Tetram.Common'
    )

    # --- Export ---
    FunctionsToExport = @(
        'Remove-EmptyDirs'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()

    # --- Métadonnées additionnelles ---
    PrivateData = @{
        PSData = @{
            Tags = @(
                'filesystem',
                'cleanup',
                'directories',
                'empty-folders',
                'utilities',
                'ps7'
            )
            ReleaseNotes = @'
- 1.0.0 : Version initiale (optimisée PowerShell 7)
'@
        }
    }
}
