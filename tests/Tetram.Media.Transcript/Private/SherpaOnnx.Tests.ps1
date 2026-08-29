# Étendre la suite autour du backend Sherpa-ONNX.
#
# Tout passe par InModuleScope 'Tetram.Media.Transcript' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Get-SherpaOnnx* n'appelle aucun binaire. Invoke-SherpaOnnx s'exerce via un mock,
# jamais via sherpa-onnx-vad-with-offline-asr.exe.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranscript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranscript = Join-Path $script:RepoRootTranscript 'Tetram.Media.Transcript'
    Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop

    $module = Get-Module -Name 'Tetram.Media.Transcript'
    . $module {
        . (Join-Path $script:TranscriptPrivateRoot 'SherpaOnnx.ps1')
    }

    $script:NativeSherpaVadStdout = "0.080 -- 1.320: こんにちは`n2.560 -- 4.800: どうしたの"
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
            $exe = Join-Path $fakeRoot 'sherpa-onnx-vad-with-offline-asr.exe'
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
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'sherpa-onnx-vad-with-offline-asr' }
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
    It 'trouve tokens/encoder/decoder/joiner dans models/reazon-k2-v2' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'fp32-only'
            $modelDir = Join-Path $root 'models' 'reazon-k2-v2'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            foreach ($name in @('tokens.txt', 'encoder-epoch-99-avg-1.onnx', 'decoder-epoch-99-avg-1.onnx', 'joiner-epoch-99-avg-1.onnx')) {
                Set-Content -LiteralPath (Join-Path $modelDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
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

    It 'suit la recette Reazon INT8 : encoder/joiner int8, decoder FP32' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'reazon-int8-recipe'
            $modelDir = Join-Path $root 'models' 'reazon-k2-v2'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            foreach ($name in @(
                    'tokens.txt',
                    'encoder-epoch-99-avg-1.onnx',
                    'encoder-epoch-99-avg-1.int8.onnx',
                    'decoder-epoch-99-avg-1.onnx',
                    'decoder-epoch-99-avg-1.int8.onnx',
                    'joiner-epoch-99-avg-1.onnx',
                    'joiner-epoch-99-avg-1.int8.onnx'
                )) {
                Set-Content -LiteralPath (Join-Path $modelDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                $got = Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2'
                $got.Encoder | Should -Be (Join-Path $modelDir 'encoder-epoch-99-avg-1.int8.onnx')
                $got.Decoder | Should -Be (Join-Path $modelDir 'decoder-epoch-99-avg-1.onnx')
                $got.Joiner | Should -Be (Join-Path $modelDir 'joiner-epoch-99-avg-1.int8.onnx')
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'prend le decoder int8 seulement s''il n''y a pas de FP32' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'int8-decoder-only'
            $modelDir = Join-Path $root 'models' 'reazon-k2-v2'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            foreach ($name in @(
                    'tokens.txt',
                    'encoder-epoch-99-avg-1.int8.onnx',
                    'decoder-epoch-99-avg-1.int8.onnx',
                    'joiner-epoch-99-avg-1.int8.onnx'
                )) {
                Set-Content -LiteralPath (Join-Path $modelDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                $got = Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2'
                $got.Decoder | Should -Be (Join-Path $modelDir 'decoder-epoch-99-avg-1.int8.onnx')
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'lève si models/reazon-k2-v2 est absent' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = Join-Path $Work 'vide'
                New-Item -ItemType Directory -Path $script:SherpaOnnxRoot -Force | Out-Null
                { Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2' } | Should -Throw '*models*reazon-k2-v2*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'ignore un dossier homonyme à la racine SherpaOnnx' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'legacy-racine'
            $legacyDir = Join-Path $root 'reazon-k2-v2'
            New-Item -ItemType Directory -Path $legacyDir -Force | Out-Null
            foreach ($name in @('tokens.txt', 'encoder.onnx', 'decoder.onnx', 'joiner.onnx')) {
                Set-Content -LiteralPath (Join-Path $legacyDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                { Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2' } | Should -Throw '*models*reazon-k2-v2*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'ignore un autre sous-dossier de models/' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'autre-modele'
            $otherDir = Join-Path $root 'models' 'sherpa-onnx-zipformer-en'
            New-Item -ItemType Directory -Path $otherDir -Force | Out-Null
            foreach ($name in @('tokens.txt', 'encoder.onnx', 'decoder.onnx', 'joiner.onnx')) {
                Set-Content -LiteralPath (Join-Path $otherDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                { Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2' } | Should -Throw '*models*reazon-k2-v2*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'lève si models/reazon-k2-v2 est incomplet même si un autre modèle l''est' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'incomplet-plus-autre'
            $modelDir = Join-Path $root 'models' 'reazon-k2-v2'
            $otherDir = Join-Path $root 'models' 'sherpa-onnx-zipformer-en'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            New-Item -ItemType Directory -Path $otherDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $modelDir 'tokens.txt') -Value 'stub'
            foreach ($file in @('tokens.txt', 'encoder.onnx', 'decoder.onnx', 'joiner.onnx')) {
                Set-Content -LiteralPath (Join-Path $otherDir $file) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                { Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2' } | Should -Throw '*incomplet*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'prend models/reazon-k2-v2 et ignore un autre sous-dossier de models/' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'deux-modeles'
            $modelDir = Join-Path $root 'models' 'reazon-k2-v2'
            $otherDir = Join-Path $root 'models' 'sherpa-onnx-zipformer-en'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            New-Item -ItemType Directory -Path $otherDir -Force | Out-Null
            foreach ($file in @('tokens.txt', 'encoder.onnx', 'decoder.onnx', 'joiner.onnx')) {
                Set-Content -LiteralPath (Join-Path $modelDir $file) -Value 'stub'
                Set-Content -LiteralPath (Join-Path $otherDir $file) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                $got = Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2'
                $got.Tokens | Should -Be (Join-Path $modelDir 'tokens.txt')
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }
}

Describe 'Get-SherpaOnnxArguments' {
    It 'produit tokens/encoder/decoder/joiner, le VAD puis le WAV, frontières préservées' {
        InModuleScope 'Tetram.Media.Transcript' {
            $tokens = Join-Path 'm' 'tokens.txt'
            $encoder = Join-Path 'm' 'encoder.onnx'
            $decoder = Join-Path 'm' 'decoder.onnx'
            $joiner = Join-Path 'm' 'joiner.onnx'
            $vad = Join-Path 'bin' 'silero_vad.onnx'
            $wav = Join-Path 'tmp' 'a.wav'
            $got = Get-SherpaOnnxArguments -Tokens $tokens -Encoder $encoder -Decoder $decoder -Joiner $joiner -SileroVadModel $vad -WavPath $wav
            $got | Should -Be @(
                "--tokens=$tokens"
                "--encoder=$encoder"
                "--decoder=$decoder"
                "--joiner=$joiner"
                "--silero-vad-model=$vad"
                '--num-threads=1'
                $wav
            )
        }
    }
}

Describe 'Get-SherpaOnnxVadModelPath' {
    It 'pointe silero_vad.onnx dans le dossier de l''exécutable' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'dist'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $exe = Join-Path $dir 'sherpa-onnx-offline.exe'
            $vad = Join-Path $dir 'silero_vad.onnx'
            Set-Content -LiteralPath $exe -Value 'stub'
            Set-Content -LiteralPath $vad -Value 'stub'
            Get-SherpaOnnxVadModelPath -Exe $exe | Should -Be $vad
        }
    }

    It 'lève si silero_vad.onnx est absent à côté de l''exe' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'sans-vad'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $exe = Join-Path $dir 'sherpa-onnx-offline.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            { Get-SherpaOnnxVadModelPath -Exe $exe } | Should -Throw '*silero_vad.onnx*'
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
    It 'produit un segment Tetram par ligne VAD, sans segment unique couvrant le WAV' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeSherpaVadStdout } {
            param($Native)
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject $Native -Model 'reazon-k2-v2'
            $got.engine | Should -Be 'sherpa-onnx'
            $got.model | Should -Be 'reazon-k2-v2'
            $got.language | Should -Be 'ja'
            $got.languageSource | Should -Be 'model'
            $got.audioTrack | Should -Be 1
            $got.segments.Count | Should -Be 2
            $got.segments[0].start | Should -Be 0.08
            $got.segments[0].end | Should -Be 1.32
            $got.segments[0].text | Should -Be 'こんにちは'
            $got.segments[1].start | Should -Be 2.56
            $got.segments[1].end | Should -Be 4.8
            $got.segments[1].text | Should -Be 'どうしたの'
            $got.segments[0].PSObject.Properties.Name | Should -Not -Contain 'diagnostics'
            $got.segments[0].PSObject.Properties.Name | Should -Not -Contain 'words'
        }
    }

    It 'accepte UseLanguage ja sans forcer une langue que le moteur n''expose pas' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeSherpaVadStdout } {
            param($Native)
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject $Native -Model 'reazon-k2-v2' -UseLanguage 'ja'
            $got.language | Should -Be 'ja'
            $got.languageSource | Should -Be 'model'
        }
    }

    It 'conserve la piste demandée' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeSherpaVadStdout } {
            param($Native)
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject $Native -Model 'reazon-k2-v2' -AudioTrack 2
            $got.audioTrack | Should -Be 2
        }
    }

    It 'ajoute TimelineOffset à chaque début et chaque fin' {
        InModuleScope 'Tetram.Media.Transcript' {
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject "1.250 -- 3.750: texte" -Model 'reazon-k2-v2' -TimelineOffset 0.007
            $got.segments.Count | Should -Be 1
            $got.segments[0].start | Should -Be 1.257
            $got.segments[0].end | Should -Be 3.757
            $got.segments[0].text | Should -Be 'texte'
        }
    }

    It 'conserve un offset négatif sur la timeline du média' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeSherpaVadStdout } {
            param($Native)
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject $Native -Model 'reazon-k2-v2' -TimelineOffset -1.25
            $got.segments[0].start | Should -Be (0.08 - 1.25)
            $got.segments[0].end | Should -Be (1.32 - 1.25)
            $got.segments[1].start | Should -Be (2.56 - 1.25)
            $got.segments[1].end | Should -Be (4.8 - 1.25)
        }
    }

    It 'parse les timestamps en InvariantCulture même si la culture courante utilise la virgule' {
        InModuleScope 'Tetram.Media.Transcript' {
            $saved = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
                $got = ConvertFrom-SherpaOnnxTranscript -InputObject '12.345 -- 14.678: texte' -Model 'reazon-k2-v2'
                $got.segments[0].start | Should -Be 12.345
                $got.segments[0].end | Should -Be 14.678
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $saved
            }
        }
    }

    It 'préserve le texte après le premier séparateur temporel, y compris un deux-points' {
        InModuleScope 'Tetram.Media.Transcript' {
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject '1.000 -- 2.000: A: B' -Model 'reazon-k2-v2'
            $got.segments[0].text | Should -Be 'A: B'
        }
    }

    It 'accepte les fins de ligne LF et CRLF' {
        InModuleScope 'Tetram.Media.Transcript' {
            $lf = "0.080 -- 1.320: こんにちは`n2.560 -- 4.800: どうしたの"
            $crlf = "0.080 -- 1.320: こんにちは`r`n2.560 -- 4.800: どうしたの"
            $fromLf = ConvertFrom-SherpaOnnxTranscript -InputObject $lf -Model 'reazon-k2-v2'
            $fromCrlf = ConvertFrom-SherpaOnnxTranscript -InputObject $crlf -Model 'reazon-k2-v2'
            $fromLf.segments.Count | Should -Be 2
            $fromCrlf.segments.Count | Should -Be 2
            $fromCrlf.segments[1].text | Should -Be 'どうしたの'
        }
    }

    It 'ignore les lignes vides périphériques ou intercalées' {
        InModuleScope 'Tetram.Media.Transcript' {
            $native = "`n0.080 -- 1.320: こんにちは`n`n2.560 -- 4.800: どうしたの`n"
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject $native -Model 'reazon-k2-v2'
            $got.segments.Count | Should -Be 2
            $got.segments[0].text | Should -Be 'こんにちは'
            $got.segments[1].text | Should -Be 'どうしたの'
        }
    }

    It 'refuse une ligne non vide qui n''est pas un segment Sherpa' {
        InModuleScope 'Tetram.Media.Transcript' {
            { ConvertFrom-SherpaOnnxTranscript -InputObject "ceci n'est pas un segment sherpa" -Model 'reazon-k2-v2' } |
                Should -Throw '*ceci n''est pas un segment sherpa*'
        }
    }

    It 'refuse un segment dont la fin précède le début' {
        InModuleScope 'Tetram.Media.Transcript' {
            { ConvertFrom-SherpaOnnxTranscript -InputObject '2.000 -- 1.000: texte' -Model 'reazon-k2-v2' } |
                Should -Throw '*end*'
        }
    }

    It 'refuse une sortie vide ou sans segment exploitable' {
        InModuleScope 'Tetram.Media.Transcript' {
            { ConvertFrom-SherpaOnnxTranscript -InputObject '' -Model 'reazon-k2-v2' } |
                Should -Throw '*segment*'
            { ConvertFrom-SherpaOnnxTranscript -InputObject "`n`n" -Model 'reazon-k2-v2' } |
                Should -Throw '*segment*'
        }
    }

    It 'n''invente pas de métrique de confiance générique' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeSherpaVadStdout } {
            param($Native)
            $got = ConvertFrom-SherpaOnnxTranscript -InputObject $Native -Model 'reazon-k2-v2'
            $got.PSObject.Properties.Name | Should -Not -Contain 'confidence'
            $got.segments[0].PSObject.Properties.Name | Should -Not -Contain 'avg_logprob'
        }
    }
}

Describe 'Invoke-SherpaOnnx' {
    It 'ne fusionne pas stderr dans stdout' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $helper = Join-Path $Work 'emit-streams.ps1'
            Set-Content -LiteralPath $helper -Value @'
$out = [System.Text.Encoding]::UTF8.GetBytes("0.080 -- 1.320: こんにちは")
[Console]::OpenStandardOutput().Write($out, 0, $out.Length)
$err = [System.Text.Encoding]::UTF8.GetBytes("Creating recognizer ...")
[Console]::OpenStandardError().Write($err, 0, $err.Length)
'@
            $state = @{ ExitCode = $null; Stdout = $null }
            Invoke-SherpaOnnx -Exe (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', $helper) -State $state
            $state['ExitCode'] | Should -Be 0
            $state['Stdout'] | Should -Match 'こんにちは'
            $state['Stdout'] | Should -Not -Match 'Creating recognizer'
        }
    }

    It 'décode stdout en UTF-8 même si la console n''est pas UTF-8' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Mock Show-CommandLine {}
            $helper = Join-Path $Work 'emit-utf8.ps1'
            Set-Content -LiteralPath $helper -Value @'
$bytes = [System.Text.Encoding]::UTF8.GetBytes("0.080 -- 1.320: こんにちは")
[Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)
'@
            $saved = [Console]::OutputEncoding
            try {
                [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437)
                $state = @{ ExitCode = $null; Stdout = $null }
                Invoke-SherpaOnnx -Exe (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', $helper) -State $state
                $state['ExitCode'] | Should -Be 0
                $state['Stdout'] | Should -Match 'こんにちは'
            }
            finally {
                [Console]::OutputEncoding = $saved
            }
        }
    }
}

Describe 'Get-SherpaOnnxTimelineOffset' {
    It 'lit le start_time du flux audio demandé' {
        InModuleScope 'Tetram.Media.Transcript' {
            Mock Invoke-SherpaOnnxFfprobe {
                param($Arguments)
                $script:SeenFfprobe = $Arguments
                '1.250000'
            }
            Get-SherpaOnnxTimelineOffset -MediaPath 'film.mkv' -AudioTrack 2 | Should -Be 1.25
            $script:SeenFfprobe | Should -Contain 'a:1'
            $script:SeenFfprobe | Should -Contain 'stream=start_time'
        }
    }

    It 'retourne 0 si ffprobe n''a pas de start_time' {
        InModuleScope 'Tetram.Media.Transcript' {
            Mock Invoke-SherpaOnnxFfprobe { 'N/A' }
            Get-SherpaOnnxTimelineOffset -MediaPath 'film.mkv' -AudioTrack 1 | Should -Be 0
        }
    }

    It 'lève si start_time est illisible' {
        InModuleScope 'Tetram.Media.Transcript' {
            Mock Invoke-SherpaOnnxFfprobe { 'pas-un-nombre' }
            { Get-SherpaOnnxTimelineOffset -MediaPath 'film.mkv' -AudioTrack 1 } | Should -Throw '*start_time*'
        }
    }

    It 'conserve un start_time négatif : c''est un offset média, pas une erreur de probe' {
        InModuleScope 'Tetram.Media.Transcript' {
            Mock Invoke-SherpaOnnxFfprobe { '-1.250000' }
            Get-SherpaOnnxTimelineOffset -MediaPath 'film.mkv' -AudioTrack 1 | Should -Be -1.25
        }
    }
}

Describe 'Invoke-SherpaOnnxTranscript' {
    BeforeEach {
        Mock -ModuleName Tetram.Media.Transcript Write-DebugLog {}
        Mock -ModuleName Tetram.Media.Transcript Show-CommandLine {}
        $script:FakeSherpaDir = Join-Path $TestDrive 'sherpa-dist'
        New-Item -ItemType Directory -Path $script:FakeSherpaDir -Force | Out-Null
        $script:FakeSherpaExe = Join-Path $script:FakeSherpaDir 'sherpa-onnx-offline.exe'
        Set-Content -LiteralPath $script:FakeSherpaExe -Value 'stub'
        Set-Content -LiteralPath (Join-Path $script:FakeSherpaDir 'silero_vad.onnx') -Value 'stub'
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxPath { $script:FakeSherpaExe }
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxModelFiles {
            [pscustomobject]@{
                Tokens   = 'tokens.txt'
                Encoder  = 'encoder.onnx'
                Decoder  = 'decoder.onnx'
                Joiner   = 'joiner.onnx'
            }
        }
        Mock -ModuleName Tetram.Media.Transcript Get-FFmpegPath { 'ffmpeg.exe' }
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxTimelineOffset { 0 }
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
        Mock -ModuleName Tetram.Media.Transcript Show-CommandLine {
            param($Exe, $Arguments)
            $script:ShownWavs += @($Arguments[-1])
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenSherpa = $Arguments
            $State['ExitCode'] = 0
            $State['Stdout'] = $script:NativeSherpaVadStdout
        }

        $script:ShownWavs = @()
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
        $script:SeenSherpa | Should -Contain ("--silero-vad-model=" + (Join-Path $script:FakeSherpaDir 'silero_vad.onnx'))
        $script:ShownWavs | Should -Be @($script:SeenWav, $script:SeenWav)
        $got.engine | Should -Be 'sherpa-onnx'
        $got.model | Should -Be 'reazon-k2-v2'
        $got.audioTrack | Should -Be 2
        $got.segments.Count | Should -Be 2
        $got.segments[0].text | Should -Be 'こんにちは'
        $got.segments[1].text | Should -Be 'どうしたの'
        Test-Path -LiteralPath $script:SeenWav | Should -BeFalse
        Should -Invoke -ModuleName Tetram.Media.Transcript Show-CommandLine -Times 2
    }

    It 'applique l''offset de piste à la timeline du média' {
        $media = Join-Path $TestDrive 'offset.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxTimelineOffset { 10 }
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg {
            param($Arguments)
            Set-Content -LiteralPath $Arguments[-1] -Value 'RIFF'
            return 0
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 0
            $State['Stdout'] = $script:NativeSherpaVadStdout
        }

        $got = InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet
        }

        $got.segments.Count | Should -Be 2
        $got.segments[0].start | Should -Be 10.08
        $got.segments[0].end | Should -Be 11.32
        $got.segments[1].start | Should -Be 12.56
        $got.segments[1].end | Should -Be 14.8
        $got.segments[0].PSObject.Properties.Name | Should -Not -Contain 'diagnostics'
    }

    It 'n''appelle ni ffprobe ni FFmpeg si ShouldProcess refuse' {
        $media = Join-Path $TestDrive 'confirm.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        $cmdlet = [PSCustomObject]@{}
        $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $false }
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg { throw 'ne doit pas tourner' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx { throw 'ne doit pas tourner' }
        $got = InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $cmdlet
        } {
            param($Media, $Cmdlet)
            Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet
        }
        $got | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Tetram.Media.Transcript Get-SherpaOnnxTimelineOffset -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-FFmpeg -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx -Times 0
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

    It 'signale une absence de segments plutôt qu''une absence de JSON' {
        $media = Join-Path $TestDrive 'empty-stdout.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg {
            param($Arguments)
            Set-Content -LiteralPath $Arguments[-1] -Value 'RIFF'
            return 0
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 0
            $State['Stdout'] = ''
        }
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            { Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet } |
                Should -Throw '*segment*'
        }
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
                Should -Throw '*sherpa-onnx-vad-with-offline-asr a échoué (code 2)*'
        }
        Test-Path -LiteralPath (Split-Path -Parent $script:SeenWav) | Should -BeFalse
    }

    It 'sous -WhatIf n''appelle ni FFmpeg ni Sherpa ni ne crée de WAV' {
        $media = Join-Path $TestDrive 'whatif.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg { throw 'ne doit pas tourner' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx { throw 'ne doit pas tourner' }
        $got = InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet -WhatIf
        }
        $got | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-FFmpeg -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Get-SherpaOnnxTimelineOffset -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Show-CommandLine -Times 2
    }

    It 'lève si silero_vad.onnx est absent à côté de l''exe' {
        $media = Join-Path $TestDrive 'no-vad.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        $dir = Join-Path $TestDrive 'exe-sans-vad'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $exe = Join-Path $dir 'sherpa-onnx-offline.exe'
        Set-Content -LiteralPath $exe -Value 'stub'
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxPath { $exe }
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg { throw 'ne doit pas tourner' }
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            { Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet } |
                Should -Throw '*silero_vad.onnx*'
        }
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-FFmpeg -Times 0
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
