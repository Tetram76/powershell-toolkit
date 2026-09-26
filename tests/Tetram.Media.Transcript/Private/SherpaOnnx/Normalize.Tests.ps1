# Étendre la suite autour du mapping Sherpa natif -> transcript Tetram.
#
# Tout passe par InModuleScope 'Tetram.Media.Transcript' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranscript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
    $script:ModuleRootTranscript = Join-Path $script:RepoRootTranscript 'Tetram.Media.Transcript'
    Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop

    $module = Get-Module -Name 'Tetram.Media.Transcript'
    . $module {
        . (Join-Path $script:TranscriptPrivateRoot 'SherpaOnnx.ps1')
    }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-SherpaOnnxTranscript' {
    It 'recale un timestamp token : TimelineOffset + vadStart + tokenLocal, sans dérive cumulative' {
        InModuleScope 'Tetram.Media.Transcript' {
            $intervals = @(
                [pscustomobject]@{ start = 10.5; end = 12.0 }
                [pscustomobject]@{ start = 150.0; end = 152.5 }
            )
            $asr = @(
                [pscustomobject]@{
                    text         = 'early'
                    tokens       = @('a')
                    timestamps   = @(0.32)
                    durations    = @()
                    ys_log_probs = @()
                    lang         = $null
                    emotion      = $null
                    event        = $null
                }
                [pscustomobject]@{
                    text         = 'late'
                    tokens       = @('b')
                    timestamps   = @(0.16)
                    durations    = @()
                    ys_log_probs = @()
                    lang         = $null
                    emotion      = $null
                    event        = $null
                }
            )
            $got = ConvertFrom-SherpaOnnxTranscript `
                -Intervals $intervals `
                -AsrResults $asr `
                -Model 'reazon-k2-v2' `
                -Vad 'silero' `
                -TimelineOffset -0.250
            $got.segments.Count | Should -Be 2
            $got.segments[0].start | Should -Be 10.25
            $got.segments[0].end | Should -Be 11.75
            $got.segments[0].text | Should -Be 'early'
            $got.segments[0].diagnostics.tokens | Should -Be @('a')
            $got.segments[0].diagnostics.timestamps | Should -Be @(10.57)
            $got.segments[1].start | Should -Be 149.75
            $got.segments[1].end | Should -Be 152.25
            $got.segments[1].diagnostics.timestamps | Should -Be @(149.91)
            $got.segments[0].PSObject.Properties.Name | Should -Not -Contain 'words'
            $got.PSObject.Properties.Name | Should -Not -Contain 'confidence'
        }
    }

    It 'applique TimelineOffset=0 et un offset positif sans inventer segment.words' {
        InModuleScope 'Tetram.Media.Transcript' {
            $intervals = @([pscustomobject]@{ start = 1.25; end = 3.75 })
            $asr = @([pscustomobject]@{
                    text         = 'texte'
                    tokens       = @('t')
                    timestamps   = @(0.10)
                    durations    = @(0.16)
                    ys_log_probs = @(-0.12)
                    lang         = $null
                    emotion      = $null
                    event        = $null
                })
            $zero = ConvertFrom-SherpaOnnxTranscript -Intervals $intervals -AsrResults $asr -Model 'reazon-k2-v2'
            $zero.segments[0].start | Should -Be 1.25
            $zero.segments[0].diagnostics.timestamps | Should -Be @(1.35)
            $zero.segments[0].diagnostics.durations | Should -Be @(0.16)
            $zero.segments[0].diagnostics.ys_log_probs | Should -Be @(-0.12)
            $zero.segments[0].PSObject.Properties.Name | Should -Not -Contain 'words'

            $pos = ConvertFrom-SherpaOnnxTranscript -Intervals $intervals -AsrResults $asr -Model 'reazon-k2-v2' -TimelineOffset 0.007
            $pos.segments[0].start | Should -Be 1.257
            $pos.segments[0].end | Should -Be 3.757
            $pos.segments[0].diagnostics.timestamps | Should -Be @(1.357)
        }
    }

    It 'arrondit les timestamps token à 3 décimales pour éviter le bruit binaire du double' {
        InModuleScope 'Tetram.Media.Transcript' {
            $intervals = @([pscustomobject]@{ start = 0.2; end = 1.0 })
            $asr = @([pscustomobject]@{
                    text         = 'x'
                    tokens       = @('t')
                    timestamps   = @(0.0)
                    durations    = @()
                    ys_log_probs = @()
                })
            $got = ConvertFrom-SherpaOnnxTranscript -Intervals $intervals -AsrResults $asr -Model 'reazon-k2-v2' -TimelineOffset 0.1
            $got.segments[0].diagnostics.timestamps | Should -Be @(0.3)
            $json = ConvertTo-Json -InputObject $got.segments[0].diagnostics.timestamps -Compress
            $json | Should -Not -Match '0000000'
            $json | Should -Not -Match '9999999'
        }
    }

    It 'omet un résultat ASR au texte vide sans casser l''association des suivants' {
        InModuleScope 'Tetram.Media.Transcript' {
            $intervals = @(
                [pscustomobject]@{ start = 1.0; end = 2.0 }
                [pscustomobject]@{ start = 3.0; end = 4.0 }
            )
            $asr = @(
                [pscustomobject]@{ text = ''; tokens = @(); timestamps = @(); durations = @(); ys_log_probs = @() }
                [pscustomobject]@{ text = 'ok'; tokens = @('o'); timestamps = @(0.04); durations = @(); ys_log_probs = @() }
            )
            $got = ConvertFrom-SherpaOnnxTranscript -Intervals $intervals -AsrResults $asr -Model 'reazon-k2-v2' -Vad 'ten'
            $got.segments.Count | Should -Be 1
            $got.segments[0].text | Should -Be 'ok'
            $got.segments[0].start | Should -Be 3
            $got.vad | Should -Be 'ten'
        }
    }

    It 'publie language=ja et languageSource=<LanguageSource> pour <Model>' -TestCases @(
        @{ Model = 'reazon-k2-v2'; LanguageSource = 'model' }
        @{ Model = 'parakeet-0.6b-ja'; LanguageSource = 'model' }
        @{ Model = 'sensevoice-small'; LanguageSource = 'forced' }
    ) {
        param($Model, $LanguageSource)
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Model = $Model; LanguageSource = $LanguageSource } {
            param($Model, $LanguageSource)
            $intervals = @([pscustomobject]@{ start = 0.08; end = 1.32 })
            $asr = @([pscustomobject]@{
                    text         = 'こんにちは'
                    tokens       = @('こん')
                    timestamps   = @(0.00)
                    durations    = @()
                    ys_log_probs = @()
                    lang         = 'zh'
                    emotion      = 'happy'
                    event        = 'Speech'
                })
            $got = ConvertFrom-SherpaOnnxTranscript -Intervals $intervals -AsrResults $asr -Model $Model -Vad 'silero' -UseLanguage 'ja' -AudioTrack 2
            $got.engine | Should -Be 'sherpa-onnx'
            $got.model | Should -Be $Model
            $got.vad | Should -Be 'silero'
            $got.language | Should -Be 'ja'
            $got.languageSource | Should -Be $LanguageSource
            $got.audioTrack | Should -Be 2
            $got.segments[0].diagnostics.tokens | Should -Be @('こん')
            if ($Model -eq 'sensevoice-small') {
                $got.segments[0].diagnostics.lang | Should -Be 'zh'
                $got.segments[0].diagnostics.emotion | Should -Be 'happy'
                $got.segments[0].diagnostics.event | Should -Be 'Speech'
            }
            { ConvertFrom-SherpaOnnxTranscript -Intervals $intervals -AsrResults $asr -Model $Model -UseLanguage 'en' } |
                Should -Throw '*incompatible*'
        }
    }

    It 'lève s''il n''existe aucun segment textuel final' {
        InModuleScope 'Tetram.Media.Transcript' {
            $intervals = @([pscustomobject]@{ start = 1.0; end = 2.0 })
            $asr = @([pscustomobject]@{ text = ''; tokens = @(); timestamps = @(); durations = @(); ys_log_probs = @() })
            { ConvertFrom-SherpaOnnxTranscript -Intervals $intervals -AsrResults $asr -Model 'reazon-k2-v2' } |
                Should -Throw '*segment*'
        }
    }
}
