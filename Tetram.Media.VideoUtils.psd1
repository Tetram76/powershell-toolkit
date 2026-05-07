@{
    # --- Identité du module ---
    RootModule = 'Tetram.Media.VideoUtils.psm1'
    ModuleVersion = '1.0.0'
    GUID = '5f14ae6d-65e9-4033-a402-903dbff1d95b'

    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Utilitaires pour l''analyse des flux vidéo (profondeur de bits, chroma).'

    # --- Compatibilité ---
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    # --- Dépendances ---
    RequiredModules = @()
    RequiredAssemblies = @()

    # --- Export ---
    FunctionsToExport = @(
		'Test-Is10BitVideoStream', 
		'Get-SourceChromaMode'
	)
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()

    # --- Métadonnées additionnelles ---
    PrivateData = @{
        PSData = @{
            Tags = @(
				'video', 
				'ffmpeg', 
				'ffprobe', 
				'media', 
				'ps7'
			)
        }
    }
}
