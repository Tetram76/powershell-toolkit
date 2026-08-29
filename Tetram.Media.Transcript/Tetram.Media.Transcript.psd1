@{
    RootModule = 'Tetram.Media.Transcript.psm1'
    ModuleVersion = '1.0.0'
    GUID = '3f5a9c21-6d84-4b17-9e0c-2a7f8d4b6e35'
    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Transcription des pistes audio d''un fichier média.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    RequiredModules = @()
    RequiredAssemblies = @()
    NestedModules = @()
    FunctionsToExport = @(
        'Get-MediaTranscript'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('transcript', 'whisper', 'sherpa-onnx', 'transcription', 'subtitle', 'media', 'ps7')
            ReleaseNotes = @'
- 1.0.0 : Get-MediaTranscript (pilote faster-whisper-xxl, jeux Path/LiteralPath/Mixed, WhatIf).
- Routage local Faster-Whisper et Sherpa-ONNX selon le modèle ; plus de -WhisperPath public.
'@
        }
    }
}
