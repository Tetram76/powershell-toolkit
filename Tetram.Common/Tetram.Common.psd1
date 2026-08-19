@{
# --- Identité du module ---
    RootModule = 'Tetram.Common.psm1'
    ModuleVersion = '1.2.0'
    GUID = '1c6e2a0f-bf1a-4a92-8a7a-1d5a0f6a6b90'

    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Fonctions de journalisation et de formattage.'

    # --- Compatibilité ---
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    # --- Dépendances ---
    RequiredModules = @()
    RequiredAssemblies = @()
    NestedModules = @()

    # --- Export ---
    FunctionsToExport = @(
        'Show-Colors'
        'Write-Log', 'Write-ErrorLog', 'Write-InfoLog', 'Write-DebugLog'
        'Format-FileSize', 'Format-Duration'
        'Show-CommandLine'
        'Test-PowerShellSpecificPath'
        'ConvertTo-AbsolutePath'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()

    # --- Métadonnées additionnelles ---
    PrivateData = @{
        PSData = @{
            Tags = @(
                'logging',
                'utilities',
                'ps7',
                'color'
            )
            ReleaseNotes = @'
- 1.1.0 : Renommage des fonctions pour verbes approuvés.
- 1.2.0 : Utilitaires de chemin pour processus natifs (syntaxe PowerShell, absolutisation).
'@
        }
    }
}
