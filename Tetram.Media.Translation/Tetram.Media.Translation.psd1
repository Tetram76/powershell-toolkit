@{
    RootModule = 'Tetram.Media.Translation.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'f4c86b9c-9c56-4bc8-b6b4-2ab400192367'
    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Traduction française de sous-titres via Gemini, à partir du fichier source et d''une transcription Whisper.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    RequiredModules = @()
    RequiredAssemblies = @()
    NestedModules = @()
    FunctionsToExport = @(
        'ConvertTo-FrenchSubtitle'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('gemini', 'subtitle', 'translation', 'media', 'ps7')
            ReleaseNotes = @'
- 1.0.0 : ConvertTo-FrenchSubtitle (Gemini, couple sous-titre + transcription Whisper).
'@
        }
    }
}
