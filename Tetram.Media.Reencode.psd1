@{
    # --- Identité du module ---
    RootModule = 'Tetram.Media.Reencode.psm1'
    ModuleVersion = '2.5.0'
    GUID = 'd4f3b1ab-7c6a-4a3a-9d9f-9d1a82bf7b95'

    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Outils de ré-encodage/normalisation de médias (PS7+, WhatIf/Confirm), avec statistiques optionnelles. Mode -Rewrite : remux sans réencodage (copy vidéo/audio), filtrage des pistes et nettoyage des métadonnées.'

    # --- Compatibilité ---
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    # --- Dépendances ---
    RequiredModules = @()
    RequiredAssemblies= @()
	NestedModules = @(
		'.\Tetram.Common', 
		'.\Tetram.Media.VideoUtils', 
		'.\Tetram.Media.AudioUtils', 
		'.\Tetram.Media.FFmpeg'
	)

    # --- Export ---
    FunctionsToExport = @(
		'Invoke-ReencodeMedia'
	)
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()

    # --- Métadonnées additionnelles ---
    PrivateData = @{
        PSData = @{
            Tags = @(
				'ffmpeg',
				'ffprobe',
				'media',
				'transcode',
				'remux',
				'video',
				'audio',
				'subtitles',
				'ps7'
			)
            ReleaseNotes = @'
- 1.0.0 : Version initiale du module, export de Invoke-ReencodeMedia (WhatIf/Confirm).
- 2.0.0 : Ajout du paramètre VideoCodec 
- 2.1.0 : Réecriture (découpage en modules, découpages en méthodes plus simples, ...)
- 2.2.0 : Ajout de l'activation AMF AMD en qualité Low (avec fallback CPU), switch NoGpu et refactor des arguments encodeurs audio/vidéo.
- 2.3.0 : Switch AllowVideoCodecUpgrade (réencodage HEVC main* vers AV1 lorsque -VideoCodec AV1 ; absent des modes -CheckOnly).
- 2.4.0 : Suppression du chemin GPU AMF (performance en mode Low inférieure au CPU).
- 2.5.0 : Mode -Rewrite (ParameterSets RewriteFromPath / RewriteFromFile) : remux avec -c:v/-c:a copy, filtrage des pistes (sous-titres, vignettes) et nettoyage des métadonnées ; correction du skip lorsque seules des pistes sont retirées.
'@
        }
    }
}
