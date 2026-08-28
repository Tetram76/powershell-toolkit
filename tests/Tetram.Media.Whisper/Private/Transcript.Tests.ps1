# Étendre la suite autour de la normalisation JSON natif Faster-Whisper → JSON Tetram.
#
# RepoRoot depuis tests/<Module>/Private : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Whisper') -Force
# InModuleScope 'Tetram.Media.Whisper' : les fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Join-Path / [IO.Path] : ne pas figer D:\... — Linux CI n'a pas le lecteur D: et `\` n'est pas un séparateur.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootWhisper = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootWhisper = Join-Path $script:RepoRootWhisper 'Tetram.Media.Whisper'
    Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop

    $script:NativeWhisperJson = @'
{
  "text": "texte global dupliqué",
  "language": "ja",
  "duration": 1400.0,
  "segments": [
    {
      "id": 7,
      "seek": 1000,
      "start": 12.34,
      "end": 15.67,
      "text": "recognized text",
      "tokens": [50365, 1234, 50620],
      "temperature": 0.0,
      "avg_logprob": -0.31,
      "compression_ratio": 1.18,
      "no_speech_prob": 0.002,
      "words": [
        {
          "start": 12.34,
          "end": 12.72,
          "word": "recognized",
          "probability": 0.96
        }
      ]
    }
  ]
}
'@
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-TetramTranscriptPath' {
    It 'place track avant langue et utilise le nom canonique large-v3' {
        InModuleScope 'Tetram.Media.Whisper' {
            $dir = Join-Path 'Videos' 'Shows'
            $got = Get-TetramTranscriptPath -Directory $dir -MediaBase 'Episode' -Language 'ja' -Model 'large-v3'
            $got | Should -Be (Join-Path $dir 'Episode.track 1.ja.large-v3.json')
        }
    }

    It 'utilise kotoba-v2 comme nom de modèle, pas un dossier CTranslate2' {
        InModuleScope 'Tetram.Media.Whisper' {
            $dir = Join-Path 'Videos' 'Shows'
            $got = Get-TetramTranscriptPath -Directory $dir -MediaBase 'Episode' -Language 'ja' -Model 'kotoba-v2'
            $got | Should -Be (Join-Path $dir 'Episode.track 1.ja.kotoba-v2.json')
            $got | Should -Not -Match 'ctranslate'
        }
    }
}

Describe 'Get-WhisperMediaBaseName' {
    It 'retire le postfixe de langue du JSON natif Purfview' {
        InModuleScope 'Tetram.Media.Whisper' {
            $path = Join-Path 'Videos' 'Episode.ja.json'
            Get-WhisperMediaBaseName -NativeJsonPath $path -Language 'ja' |
                Should -Be 'Episode'
        }
    }

    It 'conserve le stem si le postfixe de langue est absent' {
        InModuleScope 'Tetram.Media.Whisper' {
            $path = Join-Path 'Videos' 'Episode.json'
            Get-WhisperMediaBaseName -NativeJsonPath $path -Language 'ja' |
                Should -Be 'Episode'
        }
    }
}

Describe 'ConvertFrom-WhisperTranscript' {
    It 'produit le contrat racine Tetram avec langue forcée' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Native = $script:NativeWhisperJson } {
            param($Native)
            $got = ConvertFrom-WhisperTranscript -InputObject $Native -Model 'large-v3' -UseLanguage 'ja'
            $got.engine | Should -Be 'faster-whisper'
            $got.model | Should -Be 'large-v3'
            $got.language | Should -Be 'ja'
            $got.languageSource | Should -Be 'forced'
            $got.audioTrack | Should -Be 1
            $got.PSObject.Properties['schemaVersion'] | Should -BeNullOrEmpty
            $got.PSObject.Properties['source'] | Should -BeNullOrEmpty
            $got.PSObject.Properties['text'] | Should -BeNullOrEmpty
        }
    }

    It 'reprend la langue native avec languageSource detected' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Native = $script:NativeWhisperJson } {
            param($Native)
            $got = ConvertFrom-WhisperTranscript -InputObject $Native -Model 'large-v2'
            $got.language | Should -Be 'ja'
            $got.languageSource | Should -Be 'detected'
        }
    }

    It 'conserve l''ordre, start, end, text, sans id Tetram' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Native = $script:NativeWhisperJson } {
            param($Native)
            $got = ConvertFrom-WhisperTranscript -InputObject $Native -Model 'large-v3' -UseLanguage 'ja'
            $segments = @($got.segments)
            $segments.Count | Should -Be 1
            $segments[0].start | Should -Be 12.34
            $segments[0].end | Should -Be 15.67
            $segments[0].text | Should -Be 'recognized text'
            $segments[0].PSObject.Properties['id'] | Should -BeNullOrEmpty
            $segments[0].PSObject.Properties['segmentId'] | Should -BeNullOrEmpty
            $segments[0].PSObject.Properties['cueId'] | Should -BeNullOrEmpty
            $segments[0].PSObject.Properties['seek'] | Should -BeNullOrEmpty
        }
    }

    It 'conserve les diagnostics Whisper connus sous diagnostics, y compris les tokens natifs' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Native = $script:NativeWhisperJson } {
            param($Native)
            $got = ConvertFrom-WhisperTranscript -InputObject $Native -Model 'large-v3' -UseLanguage 'ja'
            $diag = @($got.segments)[0].diagnostics
            $diag.temperature | Should -Be 0
            $diag.avg_logprob | Should -Be -0.31
            $diag.compression_ratio | Should -Be 1.18
            $diag.no_speech_prob | Should -Be 0.002
            @($diag.tokens) | Should -Be @(50365, 1234, 50620)
        }
    }

    It 'n''invente pas un diagnostic absent' {
        InModuleScope 'Tetram.Media.Whisper' {
            $json = '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"hello","avg_logprob":-0.1}]}'
            $got = ConvertFrom-WhisperTranscript -InputObject $json -Model 'large-v3'
            $segment = @($got.segments)[0]
            $segment.diagnostics.avg_logprob | Should -Be -0.1
            $segment.diagnostics.PSObject.Properties['temperature'] | Should -BeNullOrEmpty
            $segment.diagnostics.PSObject.Properties['compression_ratio'] | Should -BeNullOrEmpty
            $segment.diagnostics.PSObject.Properties['no_speech_prob'] | Should -BeNullOrEmpty
            $segment.diagnostics.PSObject.Properties['tokens'] | Should -BeNullOrEmpty
            $segment.PSObject.Properties['words'] | Should -BeNullOrEmpty
        }
    }

    It 'conserve words au niveau du segment en normalisant word vers text' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Native = $script:NativeWhisperJson } {
            param($Native)
            $got = ConvertFrom-WhisperTranscript -InputObject $Native -Model 'large-v3' -UseLanguage 'ja'
            $words = @(@($got.segments)[0].words)
            $words.Count | Should -Be 1
            $words[0].text | Should -Be 'recognized'
            $words[0].start | Should -Be 12.34
            $words[0].end | Should -Be 12.72
            $words[0].probability | Should -Be 0.96
            $words[0].PSObject.Properties['word'] | Should -BeNullOrEmpty
        }
    }

    It 'accepte un segment sans words' {
        InModuleScope 'Tetram.Media.Whisper' {
            $json = '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $got = ConvertFrom-WhisperTranscript -InputObject $json -Model 'kotoba-v2' -UseLanguage 'ja'
            $segment = @($got.segments)[0]
            $segment.PSObject.Properties['words'] | Should -BeNullOrEmpty
            $got.model | Should -Be 'kotoba-v2'
        }
    }

    It 'n''ajoute pas un tableau words vide' {
        InModuleScope 'Tetram.Media.Whisper' {
            $json = '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"x","words":[]}]}'
            $got = ConvertFrom-WhisperTranscript -InputObject $json -Model 'large-v3'
            @($got.segments)[0].PSObject.Properties['words'] | Should -BeNullOrEmpty
        }
    }

    It 'lève si segments est absent' {
        InModuleScope 'Tetram.Media.Whisper' {
            { ConvertFrom-WhisperTranscript -InputObject '{"language":"ja"}' -Model 'large-v3' } |
                Should -Throw '*segments*'
        }
    }

    It 'lève si la langue détectée est absente' {
        InModuleScope 'Tetram.Media.Whisper' {
            { ConvertFrom-WhisperTranscript -InputObject '{"segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Model 'large-v3' } |
                Should -Throw '*langue*'
        }
    }
}

Describe 'Write-TetramTranscript' {
    It 'écrit le JSON Tetram via TEMP et ne laisse pas de fichier temporaire' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $transcript = ConvertFrom-WhisperTranscript -InputObject '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Model 'large-v3' -UseLanguage 'ja'
            $dest = Join-Path $Work 'Episode.track 1.ja.large-v3.json'
            $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
            $before = @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Name
            Write-TetramTranscript -Transcript $transcript -Path $dest
            Test-Path -LiteralPath $dest | Should -BeTrue
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File).Count | Should -Be 0
            $after = @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Name
            @($after | Where-Object { $_ -notin $before }).Count | Should -Be 0
            $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
            $parsed.engine | Should -Be 'faster-whisper'
            $parsed.language | Should -Be 'ja'
        }
    }

    It 'ne laisse pas de JSON Tetram partiel si la destination est illégale' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $transcript = ConvertFrom-WhisperTranscript -InputObject '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Model 'large-v3'
            $dest = Join-Path (Join-Path $Work ('no-such-dir-' + [guid]::NewGuid())) 'Episode.track 1.en.large-v3.json'
            { Write-TetramTranscript -Transcript $transcript -Path $dest } | Should -Throw
            Test-Path -LiteralPath $dest | Should -BeFalse
        }
    }
}

Describe 'Get-WhisperNativeJsonFromOutputDir' {
    It 'liste les JSON natifs du dossier de sortie et ignore le sidecar Tetram' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $outDir = Join-Path $Work 'whisper-out'
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            $native = Join-Path $outDir 'Episode.ja.json'
            Set-Content -LiteralPath $native -Value '{"language":"ja","segments":[]}'
            Set-Content -LiteralPath (Join-Path $outDir 'Episode.track 1.ja.large-v3.json') -Value '{}'
            Set-Content -LiteralPath (Join-Path $outDir 'notes.txt') -Value 'x'

            $got = @(Get-WhisperNativeJsonFromOutputDir -OutputDir $outDir)
            $got | Should -Be @($native)
        }
    }
}

Describe 'Resolve-WhisperTranscriptDirectory' {
    It 'prend le dossier d''un fichier source au stem égal, sans exiger l''existence' {
        InModuleScope 'Tetram.Media.Whisper' {
            $media = Join-Path 'Videos' 'Episode.mkv'
            Resolve-WhisperTranscriptDirectory -MediaBase 'Episode' -Source @($media) |
                Should -Be ([IO.Path]::GetDirectoryName($media))
        }
    }

    It 'trouve le média sous un masque et ignore un sidecar Tetram homonyme' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $media = Join-Path $Work 'Episode.mkv'
            Set-Content -LiteralPath $media -Value 'x'
            Set-Content -LiteralPath (Join-Path $Work 'Episode.track 1.ja.large-v3.json') -Value '{}'
            $got = Resolve-WhisperTranscriptDirectory -MediaBase 'Episode' -Source @((Join-Path $Work '*.mkv'))
            $got | Should -Be $Work
        }
    }

    It 'ne rattache pas un stem sans média correspondant' {
        InModuleScope 'Tetram.Media.Whisper' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'no-match'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'Other.mkv') -Value 'x'
            $got = Resolve-WhisperTranscriptDirectory -MediaBase 'Episode' -Source @((Join-Path $dir '*.mkv'))
            [string]::IsNullOrWhiteSpace($got) | Should -BeTrue
        }
    }
}
