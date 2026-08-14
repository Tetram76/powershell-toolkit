# Étendre la suite autour du module SUD Tetram.Media.Similarity (comparaisons médias/image).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Manifeste : Tetram.Media.Similarity/Tetram.Media.Similarity.psd1 — Test-ModuleManifest puis Import-Module (Join-Path $RepoRoot 'Tetram.Media.Similarity') -Force
# Scénarios : paires fichiers légers sous $TestDrive ou mocks des lectures coûteuses ; couvrir d’abord exports documentés puis cas limites erreurs fichier manquant/types.

Describe 'Tetram.Media.Similarity (stub)' {

    It 'Stub — tests à ajouter' -Skip {
    }
}

Describe 'Test-MediaSimilarity - résolution FFmpeg au démarrage' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $script:RepoRootSimilarity = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module -Name (Join-Path $script:RepoRootSimilarity 'Tetram.Media.Similarity') -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module -Name 'Tetram.Media.Similarity' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName Tetram.Media.Similarity Get-FFmpegPath { throw "FFmpeg introuvable (test)" }
        Mock -ModuleName Tetram.Media.Similarity Write-ErrorLog {}
    }

    It "log une erreur via Write-ErrorLog et ne lève pas d'exception quand FFmpeg est introuvable" {
        { Test-MediaSimilarity -Path $TestDrive } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Similarity Write-ErrorLog -Times 1
    }
}
