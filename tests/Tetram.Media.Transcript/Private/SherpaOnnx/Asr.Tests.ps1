# Étendre la suite autour de l'ASR offline Sherpa (JSON natif, batching).
#
# Tout passe par InModuleScope 'Tetram.Media.Transcript' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Aucun test ici ne lance sherpa-onnx-offline.exe.

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

Describe 'Get-SherpaOnnxOfflineArguments' {
    It 'Reazon : arguments modèle puis chunks dans l''ordre, sans VAD ni num-threads' {
        InModuleScope 'Tetram.Media.Transcript' {
            $asr = @(
                '--tokens=m\tokens.txt'
                '--encoder=m\encoder.onnx'
                '--decoder=m\decoder.onnx'
                '--joiner=m\joiner.onnx'
            )
            $chunks = @(
                (Join-Path 'tmp' 'silero' 'chunk-0001.wav')
                (Join-Path 'tmp' 'silero' 'chunk-0002.wav')
            )
            $got = Get-SherpaOnnxOfflineArguments -AsrArguments $asr -ChunkPaths $chunks
            $got[0..3] | Should -Be $asr
            $got[4] | Should -Be $chunks[0]
            $got[5] | Should -Be $chunks[1]
            ($got -join ' ') | Should -Not -Match 'silero-vad'
            ($got -join ' ') | Should -Not -Match 'ten-vad'
            ($got -join ' ') | Should -Not -Match 'num-threads'
        }
    }

    It '<Label> : reprend les arguments modèle, sans VAD ni num-threads' -TestCases @(
        @{
            Label = 'Parakeet'
            Asr   = @('--tokens=p\tokens.txt', '--nemo-ctc-model=p\model.int8.onnx')
        }
        @{
            Label = 'SenseVoice'
            Asr   = @('--tokens=s\tokens.txt', '--sense-voice-model=s\model.int8.onnx', '--sense-voice-language=ja')
        }
    ) {
        param($Label, $Asr)
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Asr = $Asr } {
            param($Asr)
            $chunk = Join-Path 'tmp' 'ten' 'chunk-0001.wav'
            $got = Get-SherpaOnnxOfflineArguments -AsrArguments $Asr -ChunkPaths @($chunk)
            $got[0..($Asr.Count - 1)] | Should -Be $Asr
            $got[-1] | Should -Be $chunk
            ($got -join ' ') | Should -Not -Match 'silero-vad'
            ($got -join ' ') | Should -Not -Match 'ten-vad'
            ($got -join ' ') | Should -Not -Match 'num-threads'
        }
    }
}

Describe 'ConvertFrom-SherpaOnnxOfflineStdout' {
    It 'associe un JSON par chunk : text + tokens + timestamps' {
        InModuleScope 'Tetram.Media.Transcript' {
            $stdout = @(
                '{"text":"こんにちは","tokens":["こん","にちは"],"timestamps":[0.00,0.32]}'
                '{"text":"どうしたの","tokens":["どう"],"timestamps":[0.08]}'
            ) -join "`n"
            $got = @(ConvertFrom-SherpaOnnxOfflineStdout -Stdout $stdout -ExpectedCount 2)
            $got.Count | Should -Be 2
            $got[0].text | Should -Be 'こんにちは'
            $got[0].tokens | Should -Be @('こん', 'にちは')
            $got[0].timestamps | Should -Be @(0.00, 0.32)
            $got[1].text | Should -Be 'どうしたの'
            $got[1].tokens | Should -Be @('どう')
        }
    }

    It 'conserve ys_log_probs quand le tableau natif est non vide' {
        InModuleScope 'Tetram.Media.Transcript' {
            $stdout = '{"text":"x","tokens":["a","b"],"timestamps":[0.1,0.2],"ys_log_probs":[-0.12,-0.08]}'
            $got = ConvertFrom-SherpaOnnxOfflineStdout -Stdout $stdout -ExpectedCount 1
            @($got)[0].ys_log_probs | Should -Be @(-0.12, -0.08)
        }
    }

    It 'laisse ys_log_probs vide s''il est absent ou vide' {
        InModuleScope 'Tetram.Media.Transcript' {
            $absent = ConvertFrom-SherpaOnnxOfflineStdout -Stdout '{"text":"x","tokens":["a"],"timestamps":[0.1]}' -ExpectedCount 1
            $empty = ConvertFrom-SherpaOnnxOfflineStdout -Stdout '{"text":"x","tokens":["a"],"timestamps":[0.1],"ys_log_probs":[]}' -ExpectedCount 1
            @($absent)[0].ys_log_probs | Should -HaveCount 0
            @($empty)[0].ys_log_probs | Should -HaveCount 0
        }
    }

    It 'conserve durations quand le tableau natif est non vide' {
        InModuleScope 'Tetram.Media.Transcript' {
            $stdout = '{"text":"x","tokens":["a"],"timestamps":[0.1],"durations":[0.16]}'
            $got = ConvertFrom-SherpaOnnxOfflineStdout -Stdout $stdout -ExpectedCount 1
            @($got)[0].durations | Should -Be @(0.16)
        }
    }

    It 'laisse durations vide s''il est absent ou vide' {
        InModuleScope 'Tetram.Media.Transcript' {
            $absent = ConvertFrom-SherpaOnnxOfflineStdout -Stdout '{"text":"x","tokens":["a"],"timestamps":[0.1]}' -ExpectedCount 1
            $empty = ConvertFrom-SherpaOnnxOfflineStdout -Stdout '{"text":"x","tokens":["a"],"timestamps":[0.1],"durations":[]}' -ExpectedCount 1
            @($absent)[0].durations | Should -HaveCount 0
            @($empty)[0].durations | Should -HaveCount 0
        }
    }

    It 'conserve lang, emotion et event SenseVoice quand ils sont non vides' {
        InModuleScope 'Tetram.Media.Transcript' {
            $stdout = '{"text":"x","tokens":["a"],"timestamps":[0.1],"lang":"ja","emotion":"happy","event":"Speech"}'
            $got = ConvertFrom-SherpaOnnxOfflineStdout -Stdout $stdout -ExpectedCount 1
            $row = @($got)[0]
            $row.lang | Should -Be 'ja'
            $row.emotion | Should -Be 'happy'
            $row.event | Should -Be 'Speech'
        }
    }

    It 'lève si le stdout n''est pas du JSON' {
        InModuleScope 'Tetram.Media.Transcript' {
            { ConvertFrom-SherpaOnnxOfflineStdout -Stdout '{not-json' -ExpectedCount 1 } | Should -Throw '*JSON*'
        }
    }

    It 'lève si le nombre de JSON diffère du nombre de chunks' {
        InModuleScope 'Tetram.Media.Transcript' {
            $stdout = '{"text":"un","tokens":[],"timestamps":[]}'
            { ConvertFrom-SherpaOnnxOfflineStdout -Stdout $stdout -ExpectedCount 2 } | Should -Throw '*2*'
        }
    }

    It 'lève si tokens.Count != timestamps.Count' {
        InModuleScope 'Tetram.Media.Transcript' {
            $stdout = '{"text":"x","tokens":["a","b"],"timestamps":[0.1]}'
            { ConvertFrom-SherpaOnnxOfflineStdout -Stdout $stdout -ExpectedCount 1 } | Should -Throw '*incohérent*'
        }
    }
}

Describe 'Split-SherpaOnnxChunkBatches' {
    It 'découpe un jeu plus grand qu''un batch en lots bornés, chaque chunk une seule fois, ordre conservé' {
        InModuleScope 'Tetram.Media.Transcript' {
            $chunks = 1..5 | ForEach-Object { "chunk-000$_.wav" }
            $got = Split-SherpaOnnxChunkBatches -ChunkPaths $chunks -BatchSize 2
            $got.Count | Should -Be 3
            $got[0] | Should -Be @('chunk-0001.wav', 'chunk-0002.wav')
            $got[1] | Should -Be @('chunk-0003.wav', 'chunk-0004.wav')
            $got[2] | Should -Be @('chunk-0005.wav')
            ($got | ForEach-Object { $_ }) | Should -Be $chunks
        }
    }
}
