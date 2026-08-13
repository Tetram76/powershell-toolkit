# Étendre la suite autour du module SUD Utils/Tetram.Media.VideoUtils.psd1.
#
# RepoRoot depuis tests/Utils (deux `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Utils/Tetram.Media.VideoUtils.psd1') ; pour comportements combinés FFmpeg, importer Tetram.Media.FFmpeg en amont avec Mock sur exécution.
# It : mocks ffprobe/ffmpeg ou petits artefacts sous $TestDrive ; évite dépendances à médias volumineux du repo sur agents CI légers.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootVideoUtils = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootVideoUtils 'Utils/Tetram.Media.VideoUtils.psd1') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.VideoUtils' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-ColorSpaceRemapFilter' {

    It 'retourne setparams quand color_space=gbr et chroma 420 (cas SVT-AV1)' {
        $filter = Get-ColorSpaceRemapFilter -ColorSpace 'gbr' -TargetChroma '420'
        $filter | Should -BeExactly 'setparams=colorspace=bt709:color_primaries=bt709:color_trc=bt709'
    }

    It 'retourne setparams pour rgb en 422' {
        $filter = Get-ColorSpaceRemapFilter -ColorSpace 'rgb' -TargetChroma '422'
        $filter | Should -BeExactly 'setparams=colorspace=bt709:color_primaries=bt709:color_trc=bt709'
    }

    It 'ne remappe pas en 444 (identity/GBR y est valide)' {
        Get-ColorSpaceRemapFilter -ColorSpace 'gbr' -TargetChroma '444' | Should -BeNullOrEmpty
    }

    It 'ne remappe pas une matrice déjà valide (bt709)' {
        Get-ColorSpaceRemapFilter -ColorSpace 'bt709' -TargetChroma '420' | Should -BeNullOrEmpty
    }

    It 'ne remappe pas si color_space absent' {
        Get-ColorSpaceRemapFilter -ColorSpace $null -TargetChroma '420' | Should -BeNullOrEmpty
    }
}
