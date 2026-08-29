# Étendre la suite autour de la segmentation VAD Sherpa (Silero / TEN).
#
# Tout passe par InModuleScope 'Tetram.Media.Transcript' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Aucun test ici ne lance sherpa-onnx-vad.exe.

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

Describe 'Get-SherpaOnnxVadArguments' {
    It 'Silero : flags Silero uniquement, WAV maître puis WAV parole jetable, aucun argument ASR' {
        InModuleScope 'Tetram.Media.Transcript' {
            $silero = Join-Path 'bin' 'silero_vad.onnx'
            $wav = Join-Path 'tmp' 'audio.wav'
            $speech = Join-Path 'tmp' 'vad-silero-speech.wav'
            $got = Get-SherpaOnnxVadArguments -SileroVadModel $silero -WavPath $wav -SpeechWavPath $speech
            $got | Should -Be @(
                "--silero-vad-model=$silero"
                '--silero-vad-threshold=0.40'
                '--silero-vad-min-silence-duration=0.5'
                '--silero-vad-min-speech-duration=0.25'
                '--silero-vad-max-speech-duration=6'
                '--silero-vad-window-size=512'
                '--silero-vad-neg-threshold=-1'
                $wav
                $speech
            )
            ($got -join ' ') | Should -Not -Match 'ten-vad'
            ($got -join ' ') | Should -Not -Match 'num-threads'
            ($got -join ' ') | Should -Not -Match 'tokens'
            ($got -join ' ') | Should -Not -Match 'encoder'
            ($got -join ' ') | Should -Not -Match 'nemo-ctc'
            ($got -join ' ') | Should -Not -Match 'sense-voice'
        }
    }

    It 'TEN : flags TEN uniquement, WAV maître puis WAV parole jetable, aucun argument ASR' {
        InModuleScope 'Tetram.Media.Transcript' {
            $ten = Join-Path 'bin' 'ten-vad.onnx'
            $wav = Join-Path 'tmp' 'audio.wav'
            $speech = Join-Path 'tmp' 'vad-ten-speech.wav'
            $got = Get-SherpaOnnxVadArguments -TenVadModel $ten -WavPath $wav -SpeechWavPath $speech
            $got | Should -Be @(
                "--ten-vad-model=$ten"
                '--ten-vad-threshold=0.5'
                '--ten-vad-min-silence-duration=0.5'
                '--ten-vad-min-speech-duration=0.25'
                '--ten-vad-max-speech-duration=6'
                '--ten-vad-window-size=256'
                $wav
                $speech
            )
            ($got -join ' ') | Should -Not -Match 'silero-vad'
            ($got -join ' ') | Should -Not -Match 'num-threads'
            ($got -join ' ') | Should -Not -Match 'tokens'
            ($got -join ' ') | Should -Not -Match 'encoder'
            ($got -join ' ') | Should -Not -Match 'nemo-ctc'
            ($got -join ' ') | Should -Not -Match 'sense-voice'
        }
    }

    It 'refuse SileroVadModel et TenVadModel ensemble' {
        InModuleScope 'Tetram.Media.Transcript' {
            $silero = Join-Path 'bin' 'silero_vad.onnx'
            $ten = Join-Path 'bin' 'ten-vad.onnx'
            $wav = Join-Path 'tmp' 'audio.wav'
            $speech = Join-Path 'tmp' 'speech.wav'
            { Get-SherpaOnnxVadArguments -SileroVadModel $silero -TenVadModel $ten -WavPath $wav -SpeechWavPath $speech } |
                Should -Throw
        }
    }
}

Describe 'ConvertFrom-SherpaOnnxVadStdout' {
    It 'extrait uniquement les intervalles start -- end et ignore les logs' {
        InModuleScope 'Tetram.Media.Transcript' {
            $stdout = @(
                'Creating VAD ...'
                '0.080 -- 1.320'
                ''
                'some warning'
                '2.560 -- 4.800'
            ) -join "`n"
            $got = @(ConvertFrom-SherpaOnnxVadStdout -Stdout $stdout)
            $got.Count | Should -Be 2
            $got[0].start | Should -Be 0.08
            $got[0].end | Should -Be 1.32
            $got[1].start | Should -Be 2.56
            $got[1].end | Should -Be 4.8
        }
    }

    It 'parse les timestamps en InvariantCulture même si la culture courante utilise la virgule' {
        InModuleScope 'Tetram.Media.Transcript' {
            $saved = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
                $got = @(ConvertFrom-SherpaOnnxVadStdout -Stdout '12.345 -- 14.678')
                $got[0].start | Should -Be 12.345
                $got[0].end | Should -Be 14.678
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $saved
            }
        }
    }

    It 'refuse un intervalle dont la fin précède le début' {
        InModuleScope 'Tetram.Media.Transcript' {
            { ConvertFrom-SherpaOnnxVadStdout -Stdout '2.000 -- 1.000' } | Should -Throw '*end*'
        }
    }

    It 'retourne une collection vide si aucun intervalle n''est présent' {
        InModuleScope 'Tetram.Media.Transcript' {
            @(ConvertFrom-SherpaOnnxVadStdout -Stdout "Creating VAD ...`n") | Should -HaveCount 0
            @(ConvertFrom-SherpaOnnxVadStdout -Stdout '') | Should -HaveCount 0
        }
    }

    It 'accepte les fins de ligne LF et CRLF' {
        InModuleScope 'Tetram.Media.Transcript' {
            $fromLf = @(ConvertFrom-SherpaOnnxVadStdout -Stdout "0.080 -- 1.320`n2.560 -- 4.800")
            $fromCrlf = @(ConvertFrom-SherpaOnnxVadStdout -Stdout "0.080 -- 1.320`r`n2.560 -- 4.800")
            $fromLf.Count | Should -Be 2
            $fromCrlf.Count | Should -Be 2
            $fromCrlf[1].end | Should -Be 4.8
        }
    }

    It 'ne traite pas une ligne UTF-8 non temporelle comme une erreur de parsing' {
        InModuleScope 'Tetram.Media.Transcript' {
            $stdout = "設定を読み込みます`n0.080 -- 1.320`n完了"
            $got = @(ConvertFrom-SherpaOnnxVadStdout -Stdout $stdout)
            $got.Count | Should -Be 1
            $got[0].start | Should -Be 0.08
        }
    }
}

Describe 'Get-SherpaOnnxVadModelPath' {
    It 'pointe silero_vad.onnx dans le dossier de l''exécutable' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'dist'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $exe = Join-Path $dir 'sherpa-onnx-vad.exe'
            $vad = Join-Path $dir 'silero_vad.onnx'
            Set-Content -LiteralPath $exe -Value 'stub'
            Set-Content -LiteralPath $vad -Value 'stub'
            Get-SherpaOnnxVadModelPath -Exe $exe -FileName 'silero_vad.onnx' | Should -Be $vad
        }
    }

    It 'pointe ten-vad.onnx dans le dossier de l''exécutable' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'dist-ten'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $exe = Join-Path $dir 'sherpa-onnx-vad.exe'
            $vad = Join-Path $dir 'ten-vad.onnx'
            Set-Content -LiteralPath $exe -Value 'stub'
            Set-Content -LiteralPath $vad -Value 'stub'
            Get-SherpaOnnxVadModelPath -Exe $exe -FileName 'ten-vad.onnx' | Should -Be $vad
        }
    }

    It 'lève si silero_vad.onnx est absent à côté de l''exe' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'sans-vad'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $exe = Join-Path $dir 'sherpa-onnx-vad.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            { Get-SherpaOnnxVadModelPath -Exe $exe -FileName 'silero_vad.onnx' } | Should -Throw '*silero_vad.onnx*'
        }
    }

    It 'lève si ten-vad.onnx est absent à côté de l''exe' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'sans-ten'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $exe = Join-Path $dir 'sherpa-onnx-vad.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            { Get-SherpaOnnxVadModelPath -Exe $exe -FileName 'ten-vad.onnx' } | Should -Throw '*ten-vad.onnx*'
        }
    }
}
