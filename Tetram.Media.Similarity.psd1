@{
# --- Identité du module ---
    RootModule = 'Tetram.Media.Similarity.psm1'
    ModuleVersion = '1.0.0'
    GUID = '7b2e3a1f-ce2d-4b92-9a7a-2d5a0f6a6c88'

    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Identification de similarités visuelles entre vidéos via signatures MPEG-7.'

    # --- Compatibilité ---
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    # --- Dépendances ---
    RequiredModules = @()
    RequiredAssemblies = @()
    NestedModules = @(
        '.\Tetram.Common',
        '.\Tetram.Media.FFmpeg'
    )

    # --- Export ---
    FunctionsToExport = @(
        'Test-MediaSimilarity'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()

    # --- Métadonnées ---
    PrivateData = @{
        PSData = @{
            Tags = @(
                'video',
                'similarity',
                'ffmpeg',
                'fingerprinting',
                'ps7'
            )
        }
    }
}