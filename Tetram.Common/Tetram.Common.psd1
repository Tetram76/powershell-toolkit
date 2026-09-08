@{
# --- Identité du module ---
    RootModule = 'Tetram.Common.psm1'
    ModuleVersion = '1.4.0'
    GUID = '1c6e2a0f-bf1a-4a92-8a7a-1d5a0f6a6b90'

    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Fonctions de journalisation, de formatage, et utilitaires de chemin.'

    # --- Compatibilité ---
    PowerShellVersion = '7.6'
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
        'ConvertFrom-ExtendedLengthPath', 'ConvertTo-ExtendedLengthPath'
        'ConvertTo-PowerShellLiteral'
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
- 1.4.0 : ConvertFrom-ExtendedLengthPath / ConvertTo-ExtendedLengthPath (préfixe Win32 \\?\, seuil 250) ; ConvertTo-PowerShellLiteral.
'@
        }
    }
}
