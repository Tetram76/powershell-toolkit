# Étendre la suite autour du backend Sherpa-ONNX.
#
# Tout passe par InModuleScope 'Tetram.Media.Transcript' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Get-SherpaOnnx* n'appelle aucun binaire. Invoke-SherpaOnnx s'exerce via un mock,
# jamais via sherpa-onnx-offline.exe.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranscript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranscript = Join-Path $script:RepoRootTranscript 'Tetram.Media.Transcript'
    Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop

    $module = Get-Module -Name 'Tetram.Media.Transcript'
    . $module {
        . (Join-Path $script:TranscriptPrivateRoot 'SherpaOnnx.ps1')
    }

    $script:NativeSherpaJson = '{"lang":"","emotion":"","event":"","text":"こんにちは","timestamps":[0.08, 0.32, 0.56],"durations":[],"tokens":["こん","に","ちは"],"ys_log_probs":[-0.12, -0.08, -0.05],"words":[]}'
    $script:FakeCmdlet = [PSCustomObject]@{}
    $script:FakeCmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $true }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SherpaOnnxPath' {
    It 'retourne l''override quand c''est un fichier' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $exe = Join-Path $Work 'ailleurs.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            Get-SherpaOnnxPath -OverridePath $exe | Should -Be $exe
        }
    }

    It 'rejette un override qui est un dossier' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'dossier-exe'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            { Get-SherpaOnnxPath -OverridePath $dir } | Should -Throw '*pas un dossier*'
        }
    }

    It 'rejette un override inexistant' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            { Get-SherpaOnnxPath -OverridePath (Join-Path $Work 'absent.exe') } | Should -Throw '*inexistant*'
        }
    }

    It 'prend le binaire du dossier du module quand il existe' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $fakeRoot = Join-Path $Work 'sherpa'
            New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
            $exe = Join-Path $fakeRoot 'sherpa-onnx-offline.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $fakeRoot
                Get-SherpaOnnxPath | Should -Be $exe
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'échoue avec un message qui indique où poser la distribution' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'sherpa-onnx-offline' }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = Join-Path $Work 'vide'
                { Get-SherpaOnnxPath } | Should -Throw '*SherpaOnnx*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }
}

Describe 'Get-SherpaOnnxModelFiles' {
    It 'trouve tokens/encoder/decoder/joiner sous le dossier local' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $modelDir = Join-Path $Work 'reazon-k2-v2'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            foreach ($name in @('tokens.txt', 'encoder-epoch-99-avg-1.onnx', 'decoder-epoch-99-avg-1.onnx', 'joiner-epoch-99-avg-1.onnx')) {
                Set-Content -LiteralPath (Join-Path $modelDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $Work
                $got = Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2'
                $got.Tokens | Should -Be (Join-Path $modelDir 'tokens.txt')
                $got.Encoder | Should -Be (Join-Path $modelDir 'encoder-epoch-99-avg-1.onnx')
                $got.Decoder | Should -Be (Join-Path $modelDir 'decoder-epoch-99-avg-1.onnx')
                $got.Joiner | Should -Be (Join-Path $modelDir 'joiner-epoch-99-avg-1.onnx')
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'préfère les poids int8 quand encoder et joiner existent en double' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $modelDir = Join-Path $Work 'reazon-k2-v2'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            foreach ($name in @(
                    'tokens.txt',
                    'encoder-epoch-99-avg-1.onnx',
                    'encoder-epoch-99-avg-1.int8.onnx',
                    'decoder-epoch-99-avg-1.onnx',
                    'joiner-epoch-99-avg-1.onnx',
                    'joiner-epoch-99-avg-1.int8.onnx'
                )) {
                Set-Content -LiteralPath (Join-Path $modelDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $Work
                $got = Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2'
                $got.Encoder | Should -Be (Join-Path $modelDir 'encoder-epoch-99-avg-1.int8.onnx')
                $got.Joiner | Should -Be (Join-Path $modelDir 'joiner-epoch-99-avg-1.int8.onnx')
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'lève si les fichiers du modèle sont absents' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = Join-Path $Work 'vide'
                New-Item -ItemType Directory -Path $script:SherpaOnnxRoot -Force | Out-Null
                { Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2' } | Should -Throw '*tokens.txt*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }
}

Describe 'Get-SherpaOnnxArguments' {
    It 'produit tokens/encoder/decoder/joiner puis le WAV, frontières préservées' {
        InModuleScope 'Tetram.Media.Transcript' {
            $tokens = Join-Path 'm' 'tokens.txt'
            $encoder = Join-Path 'm' 'encoder.onnx'
            $decoder = Join-Path 'm' 'decoder.onnx'
            $joiner = Join-Path 'm' 'joiner.onnx'
            $wav = Join-Path 'tmp' 'a.wav'
            $got = Get-SherpaOnnxArguments -Tokens $tokens -Encoder $encoder -Decoder $decoder -Joiner $joiner -WavPath $wav
            $got | Should -Be @(
                "--tokens=$tokens"
                "--encoder=$encoder"
                "--decoder=$decoder"
                "--joiner=$joiner"
                '--num-threads=1'
                $wav
            )
        }
    }
}

Describe 'Get-SherpaOnnxFfmpegArguments' {
    It 'mappe AudioTrack 1-based vers 0:a:N' {
        InModuleScope 'Tetram.Media.Transcript' {
            $media = Join-Path 'media' 'a.mkv'
            $wav = Join-Path 't' 'audio.wav'
            $got = Get-SherpaOnnxFfmpegArguments -MediaPath $media -AudioTrack 2 -OutputPath $wav
            $got | Should -Contain '-map'
            $mapAt = [array]::IndexOf(@($got), '-map')
            $got[$mapAt + 1] | Should -Be '0:a:1'
            $got | Should -Contain '-ac'
            $got | Should -Contain 'pcm_s16le'
            $got[-1] | Should -Be $wav
        }
    }
}

Describe 'ConvertFrom-SherpaOnnxTranscript' {
    It 'normalise le JSON natif vers le contrat Tetram' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeSherpaJson } {
            param($Native)
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject $Native -Model 'reazon-k2-v2'
            $got.engine | Should -Be 'sherpa-onnx'
            $got.model | Should -Be 'reazon-k2-v2'
            $got.language | Should -Be 'ja'
            $got.languageSource | Should -Be 'model'
            $got.audioTrack | Should -Be 1
            $got.segments.Count | Should -Be 1
            $got.segments[0].text | Should -Be 'こんにちは'
            $got.segments[0].start | Should -Be 0.08
            $got.segments[0].end | Should -Be 0.56
            $got.segments[0].words.Count | Should -Be 3
            $got.segments[0].words[0].text | Should -Be 'こん'
            $got.segments[0].words[0].start | Should -Be 0.08
            $got.segments[0].diagnostics.ys_log_probs.Count | Should -Be 3
        }
    }

    It 'accepte UseLanguage ja comme forcé' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeSherpaJson } {
            param($Native)
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject $Native -Model 'reazon-k2-v2' -UseLanguage 'ja'
            $got.language | Should -Be 'ja'
            $got.languageSource | Should -Be 'forced'
        }
    }

    It 'conserve les timestamps token-level et les durées natives' {
        InModuleScope 'Tetram.Media.Transcript' {
            $native = '{"lang":"","emotion":"","event":"","text":"ab","timestamps":[0.10, 0.40],"durations":[0.30, 0.50],"tokens":["a","b"],"ys_log_probs":[],"words":[]}'
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject $native -Model 'reazon-k2-v2'
            $got.segments[0].words[0].end | Should -Be 0.40
            $got.segments[0].words[1].end | Should -Be 0.90
            $got.segments[0].end | Should -Be 0.90
        }
    }

    It 'n''invente pas de métrique de confiance générique' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeSherpaJson } {
            param($Native)
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject $Native -Model 'reazon-k2-v2'
            $got.PSObject.Properties.Name | Should -Not -Contain 'confidence'
            $got.segments[0].PSObject.Properties.Name | Should -Not -Contain 'avg_logprob'
        }
    }
}

Describe 'Invoke-SherpaOnnxTranscript' {
    BeforeEach {
        Mock -ModuleName Tetram.Media.Transcript Write-DebugLog {}
        Mock -ModuleName Tetram.Media.Transcript Show-CommandLine {}
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxPath { 'sherpa-onnx-offline.exe' }
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxModelFiles {
            [pscustomobject]@{
                Tokens   = 'tokens.txt'
                Encoder  = 'encoder.onnx'
                Decoder  = 'decoder.onnx'
                Joiner   = 'joiner.onnx'
            }
        }
        Mock -ModuleName Tetram.Media.Transcript Get-FFmpegPath { 'ffmpeg.exe' }
        $script:SeenFfmpeg = $null
        $script:SeenSherpa = $null
        $script:SeenWav = $null
    }

    It 'refuse une langue incompatible avant tout binaire' {
        $media = Join-Path $TestDrive 'lang.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg { throw 'ne doit pas tourner' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx { throw 'ne doit pas tourner' }
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            { Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -UseLanguage 'en' -Cmdlet $Cmdlet } |
                Should -Throw '*incompatible*'
        }
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-FFmpeg -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx -Times 0
    }

    It 'prépare le WAV de la piste demandée puis invoque Sherpa' {
        $media = Join-Path $TestDrive 'track.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg {
            param($Arguments, $ExePath, $CaptureOutput)
            $script:SeenFfmpeg = $Arguments
            $script:SeenWav = $Arguments[-1]
            Set-Content -LiteralPath $Arguments[-1] -Value 'RIFF'
            return 0
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenSherpa = $Arguments
            $State['ExitCode'] = 0
            $State['Stdout'] = $script:NativeSherpaJson
        }

        $got = InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -AudioTrack 2 -Cmdlet $Cmdlet
        }

        $mapAt = [array]::IndexOf(@($script:SeenFfmpeg), '-map')
        $script:SeenFfmpeg[$mapAt + 1] | Should -Be '0:a:1'
        $script:SeenSherpa[-1] | Should -Be $script:SeenWav
        $got.engine | Should -Be 'sherpa-onnx'
        $got.model | Should -Be 'reazon-k2-v2'
        $got.audioTrack | Should -Be 2
        Test-Path -LiteralPath $script:SeenWav | Should -BeFalse
    }

    It 'nettoie le temporaire si FFmpeg échoue' {
        $media = Join-Path $TestDrive 'ffmpeg-fail.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg {
            param($Arguments)
            $script:SeenWav = $Arguments[-1]
            return 1
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx { throw 'ne doit pas tourner' }
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            { Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet } |
                Should -Throw '*FFmpeg*'
        }
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx -Times 0
        $wavDir = Split-Path -Parent $script:SeenWav
        Test-Path -LiteralPath $wavDir | Should -BeFalse
    }

    It 'nettoie le temporaire si le binaire Sherpa échoue' {
        $media = Join-Path $TestDrive 'sherpa-fail.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg {
            param($Arguments)
            $script:SeenWav = $Arguments[-1]
            Set-Content -LiteralPath $Arguments[-1] -Value 'RIFF'
            return 0
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 2
            $State['Stdout'] = ''
        }
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            { Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet } |
                Should -Throw '*sherpa-onnx-offline a échoué (code 2)*'
        }
        Test-Path -LiteralPath (Split-Path -Parent $script:SeenWav) | Should -BeFalse
    }

    It 'sous -WhatIf n''appelle ni FFmpeg ni Sherpa ni ne crée de WAV' {
        $media = Join-Path $TestDrive 'whatif.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg { throw 'ne doit pas tourner' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenSherpa = $Arguments
        }
        $got = InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet -WhatIf
        }
        $got | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-FFmpeg -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx -Times 1
        $script:SeenSherpa[-1] | Should -Match '\.wav$'
        Test-Path -LiteralPath $script:SeenSherpa[-1] | Should -BeFalse
    }

    It 'lève si l''exécutable est introuvable' {
        $media = Join-Path $TestDrive 'no-exe.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxPath { throw 'sherpa-onnx-offline introuvable (test)' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg { throw 'ne doit pas tourner' }
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            { Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet } |
                Should -Throw '*sherpa-onnx-offline*'
        }
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-FFmpeg -Times 0
    }
}

Describe 'Invoke-ProviderTranscript (Sherpa)' {
    It 'est le point d''entrée commun du backend Sherpa' {
        InModuleScope 'Tetram.Media.Transcript' {
            (Get-Command Invoke-ProviderTranscript).Name | Should -Be 'Invoke-ProviderTranscript'
        }
    }
}
