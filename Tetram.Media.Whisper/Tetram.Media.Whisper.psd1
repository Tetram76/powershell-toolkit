@{
    RootModule = 'Tetram.Media.Whisper.psm1'
    ModuleVersion = '1.0.0'
    GUID = '3f5a9c21-6d84-4b17-9e0c-2a7f8d4b6e35'
    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Transcription des pistes audio via le binaire Purfview Standalone Faster-Whisper.'
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
            Tags = @('whisper', 'transcription', 'subtitle', 'media', 'ps7')
            ReleaseNotes = @'
- 1.0.0 : Get-MediaTranscript (pilote faster-whisper-xxl, jeux Path/LiteralPath/Mixed, WhatIf).
'@
        }
    }
}
