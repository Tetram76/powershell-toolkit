@{
# --- Identité du module ---
    RootModule = 'Tetram.Common.psm1'
    ModuleVersion = '1.3.0'
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
        'Write-Log', 'Write-ErrorLog', 'Write-InfoLog', 'Write-InfoWarning', 'Write-DebugLog'
        'Format-FileSize', 'Format-Duration'
        'Show-CommandLine'
        'Test-PowerShellSpecificPath'
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
- 1.2.0 : Détection de syntaxe PowerShell spécifique pour processus natifs.
- 1.3.0 : Ajout de Write-InfoWarning, helper de journalisation jaune basé sur Write-InfoLog.
'@
        }
    }
}
