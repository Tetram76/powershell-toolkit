# Étendre la suite autour du module SUD Tetram.Media.Reencode (Exports / comportement public après chargement réel du .psm1).
#
# RepoRoot depuis tests/ racine : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
# Sanity : Test-ModuleManifest (Join-Path $RepoRoot 'Tetram.Media.Reencode.psd1') avant Import-Module sur ce chemin avec -Force
# Nouvelle couverture : un Describe par commande FunctionsToExport (ou famille logique), It minimaux puis mocks sur Utils/ffmpeg si nécessaires

Describe 'Tetram.Media.Reencode (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}

Describe 'Invoke-ReencodeMedia - résolution FFmpeg au démarrage' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $script:RepoRootReencode = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        Import-Module -Name (Join-Path $script:RepoRootReencode 'Tetram.Media.Reencode.psd1') -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module -Name 'Tetram.Media.Reencode' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName Tetram.Media.Reencode Get-FFmpegPath { throw "FFmpeg introuvable (test)" }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It "log une erreur via Write-ErrorLog et ne lève pas d'exception quand FFmpeg est introuvable" {
        # $TestDrive peut être vide selon le runner ; un dossier temp garantit un -Path bindable.
        $in = Join-Path ([IO.Path]::GetTempPath()) ('reencode-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $in -Force | Out-Null
        try
        {
            { Invoke-ReencodeMedia -Path $in -CheckOnly } | Should -Not -Throw
            Should -Invoke -ModuleName Tetram.Media.Reencode Write-ErrorLog -Times 1
        }
        finally
        {
            Remove-Item -LiteralPath $in -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
