@{
# --- Identité du module ---
    RootModule = 'Tetram.Media.Reencode.psm1'
    ModuleVersion = '3.2.0'
    GUID = 'd4f3b1ab-7c6a-4a3a-9d9f-9d1a82bf7b95'

    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Outils de ré-encodage/normalisation de médias (PS7+, WhatIf/Confirm), avec statistiques optionnelles. Réencodage vers MKV. Mode -NoTranscode : filtrage des pistes et nettoyage des métadonnées sans transcodage des flux conservés.'

    # --- Compatibilité ---
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    # --- Dépendances ---
    RequiredModules = @()
    RequiredAssemblies = @()
    # Les modules dépendants sont importés depuis le .psm1 (chemins $PSScriptRoot\..),
    # car NestedModules n'accepte pas de segments '..' (Test-ModuleManifest).
    NestedModules = @()

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
- 2.6.0 : Contrôle d'intégrité de la durée après encodage (comparaison source/sortie avec tolérance configurable) ; correction de la détection des flux attached-picture et de la sonde de durée pilotée par la sélection de flux.
- 2.6.1 : Découpage interne du module en sous-modules privés (Probe, Streams, EncoderArgs, NFO, Scan) ; aucun changement fonctionnel.
- 3.0.0 : API simplifiée — réencodage toujours en MKV ; mode -NoTranscode (filtrage conservé, aucun transcodage des flux retenus, extension source) ; suppression de -KeepExtension, -OutputExtension et -Rewrite.
- 3.1.0 : Ajout de -AllowIntegrityMismatch (jeux Reencode* uniquement) : un mismatch de durée reste rejeté par défaut ; avec le switch, le contrôle s'exécute toujours mais l'écart devient un warning et la sortie est acceptée. Absent de -NoTranscode et -CheckOnly ; aucun contrôle d'intégrité de durée en -NoTranscode.
- 3.2.0 : Ajout de -RemoveAttachments (Reencode* et NoTranscode*) pour supprimer tous les flux de type attachment de la sortie ; comportement inchangé par défaut.
'@
        }
    }
}
