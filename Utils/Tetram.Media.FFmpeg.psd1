@{
# --- Identité du module ---
    RootModule = 'Tetram.Media.FFmpeg.psm1'
    ModuleVersion = '1.0.0'
    GUID = '7b9c3f1e-8a2d-4e5c-9b1a-6d4f3e2a1b9c'

    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Utilitaires d''exécution FFmpeg et génération de hash rapide pour les médias.'

    # --- Compatibilité ---
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    # --- Dépendances ---
    RequiredModules = @()
    RequiredAssemblies = @()

    # --- Export ---
    FunctionsToExport = @(
        'Get-FFmpegPath', 'Get-FfprobePath',
        'Invoke-FFmpeg',
        'Get-MediaFastHash'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @(
                'ffmpeg',
                'media',
                'hash',
                'ps7'
            )
        }
    }
}