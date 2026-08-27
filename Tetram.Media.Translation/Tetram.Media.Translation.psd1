@{
    RootModule = 'Tetram.Media.Translation.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'f4c86b9c-9c56-4bc8-b6b4-2ab400192367'
    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Traduction française de sous-titres via Gemini ou Ollama, à partir d''une source principale et de sources secondaires facultatives (sous-titres ou JSON Whisper). -Model accepte un suffixe optionnel [thinking] ou [thinking=<level>].'
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
            Tags = @('gemini', 'ollama', 'subtitle', 'translation', 'media', 'ps7')
            ReleaseNotes = @'
- 1.0.0 : ConvertTo-FrenchSubtitle (Gemini ou Ollama, source principale + sources secondaires facultatives).
'@
        }
    }
}
