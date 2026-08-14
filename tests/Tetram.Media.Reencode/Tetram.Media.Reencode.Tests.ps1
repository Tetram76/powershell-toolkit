# Étendre la suite autour du module SUD Tetram.Media.Reencode (Exports / comportement public après chargement réel du .psm1).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Sanity : Test-ModuleManifest (Join-Path $RepoRoot 'Tetram.Media.Reencode' 'Tetram.Media.Reencode.psd1') avant Import-Module sur ce chemin avec -Force
# Nouvelle couverture : un Describe par commande FunctionsToExport (ou famille logique), It minimaux puis mocks sur Utils/ffmpeg si nécessaires

Describe 'Tetram.Media.Reencode (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}

Describe 'Invoke-ReencodeMedia - résolution FFmpeg au démarrage' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $script:RepoRootReencode = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module -Name (Join-Path $script:RepoRootReencode 'Tetram.Media.Reencode') -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module -Name 'Tetram.Media.Reencode' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName Tetram.Media.Reencode Get-FFmpegPath { throw "FFmpeg introuvable (test)" }
        Mock -ModuleName Tetram.Media.Reencode Write-ErrorLog {}
    }

    It "log une erreur via Write-ErrorLog et ne lève pas d'exception quand FFmpeg est introuvable" {
        { Invoke-ReencodeMedia -Path $TestDrive -CheckOnly } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Reencode Write-ErrorLog -Times 1
    }
}
