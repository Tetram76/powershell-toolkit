# Étendre la suite autour du module SUD Tetram.Media.AudioUtils/Tetram.Media.AudioUtils.psd1.
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path (deux niveaux jusqu’à la racine repo)
# Import du manifeste : Import-Module (Join-Path $RepoRoot 'Tetram.Media.AudioUtils') -Force ; optionnel Import-Module préalable FFmpeg si tests croisés
# It : cibler fonction exportée précise ; mocks des appels FFmpeg/IO suivant signatures réelles plutôt qu’un binaire installé uniquement localement.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootAudioUtils = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootAudioUtils 'Tetram.Media.AudioUtils') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.AudioUtils' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-TargetAudioCodec' {

    It 'cible eac3 pour .mkv + High' {
        Get-TargetAudioCodec -FinalExtension '.mkv' -Quality 'High' | Should -BeExactly 'eac3'
    }

    It 'cible eac3 pour .mkv + Medium' {
        Get-TargetAudioCodec -FinalExtension '.mkv' -Quality 'Medium' | Should -BeExactly 'eac3'
    }

    It 'cible opus pour .mkv + Low' {
        Get-TargetAudioCodec -FinalExtension '.mkv' -Quality 'Low' | Should -BeExactly 'opus'
    }

    It 'cible aac pour .mp4 + High' {
        Get-TargetAudioCodec -FinalExtension '.mp4' -Quality 'High' | Should -BeExactly 'aac'
    }

    It 'cible aac pour .mp4 + Medium' {
        Get-TargetAudioCodec -FinalExtension '.mp4' -Quality 'Medium' | Should -BeExactly 'aac'
    }

    It 'cible aac pour .mp4 + Low' {
        Get-TargetAudioCodec -FinalExtension '.mp4' -Quality 'Low' | Should -BeExactly 'aac'
    }

    It 'cible eac3 pour .webm + High (extension non-MP4 autre que .mkv)' {
        Get-TargetAudioCodec -FinalExtension '.webm' -Quality 'High' | Should -BeExactly 'eac3'
    }

    It 'cible opus pour .webm + Low (extension non-MP4 autre que .mkv)' {
        Get-TargetAudioCodec -FinalExtension '.webm' -Quality 'Low' | Should -BeExactly 'opus'
    }

    It 'compare l''extension sans tenir compte de la casse' {
        Get-TargetAudioCodec -FinalExtension '.MP4' -Quality 'High' | Should -BeExactly 'aac'
        Get-TargetAudioCodec -FinalExtension '.MKV' -Quality 'High' | Should -BeExactly 'eac3'
    }
}
