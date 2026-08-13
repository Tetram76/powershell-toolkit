BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'Utils/Tetram.Media.FFmpeg.psd1'
}

Describe 'Tetram.Media.FFmpeg manifest' {
    It 'déclare FFToolsMinVersion = 9.0.1 dans PrivateData' {
        $data = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
        $data.PrivateData.FFToolsMinVersion | Should -Be '9.0.1'
    }
}
