@{
    RootModule = 'Tetram.Media.Streams.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'e7d4a1c8-3b92-4f6e-a1d5-8c9b0e2f4a71'
    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Extraction de flux MKV (sidecars nommés) et réinjection des sous-titres.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    RequiredModules = @()
    RequiredAssemblies = @()
    NestedModules = @(
        '.\Utils\Tetram.Common',
        '.\Utils\Tetram.Media.FFmpeg'
    )
    FunctionsToExport = @(
        'Get-MediaStream'
        'Merge-MediaSubtitle'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('ffmpeg', 'mkv', 'media', 'demux', 'subtitle', 'ps7')
            ReleaseNotes = @'
- 1.0.0 : Get-MediaStream / Merge-MediaSubtitle (sous-titres muxés, WhatIf/Force).
'@
        }
    }
}
