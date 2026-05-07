@{
    # --- Identité du module ---
    RootModule = 'Tetram.Media.AudioUtils.psm1'
    ModuleVersion = '1.0.0'
    GUID = '613efe73-baa6-42c7-a778-3e418cf9d27d'

    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Utilitaires pour l''analyse et la configuration des flux audio (codecs, bitrates).'

    # --- Compatibilité ---
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    # --- Dépendances ---
    RequiredModules = @()
    RequiredAssemblies = @()

    # --- Export ---
    FunctionsToExport = @(
		'Test-IsLosslessAudioCodec', 'Test-HasBitrateGain',
		'Get-TargetAudioCodec', 'Get-TargetAudioBitrate', 
		'ConvertTo-IntBitrate', 'ConvertTo-IntBitrateK'
	)
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()

    # --- Métadonnées additionnelles ---
    PrivateData = @{
        PSData = @{
            Tags = @(
				'audio', 
				'ffmpeg', 
				'ffprobe', 
				'media', 
				'ps7'
			)
        }
    }
}
