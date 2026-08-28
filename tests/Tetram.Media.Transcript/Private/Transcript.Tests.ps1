# Étendre la suite autour de l'orchestration générique de transcription Tetram.
#
# RepoRoot depuis tests/<Module>/Private : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Transcript') -Force
# InModuleScope 'Tetram.Media.Transcript' : les fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Join-Path / [IO.Path] : ne pas figer D:\... — Linux CI n'a pas le lecteur D: et `\` n'est pas un séparateur.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranscript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranscript = Join-Path $script:RepoRootTranscript 'Tetram.Media.Transcript'
    Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-TetramTranscriptPath' {
    It 'place track avant langue et utilise le nom canonique large-v3' {
        InModuleScope 'Tetram.Media.Transcript' {
            $dir = Join-Path 'Videos' 'Shows'
            $got = Get-TetramTranscriptPath -Directory $dir -MediaBase 'Episode' -Language 'ja' -Model 'large-v3'
            $got | Should -Be (Join-Path $dir 'Episode.track 1.ja.large-v3.json')
        }
    }

    It 'reprend la piste demandée dans le nom' {
        InModuleScope 'Tetram.Media.Transcript' {
            $dir = Join-Path 'Videos' 'Shows'
            $got = Get-TetramTranscriptPath -Directory $dir -MediaBase 'Episode' -Language 'ja' -Model 'large-v3' -AudioTrack 2
            $got | Should -Be (Join-Path $dir 'Episode.track 2.ja.large-v3.json')
        }
    }

    It 'utilise kotoba-v2 comme nom de modèle, pas un dossier CTranslate2' {
        InModuleScope 'Tetram.Media.Transcript' {
            $dir = Join-Path 'Videos' 'Shows'
            $got = Get-TetramTranscriptPath -Directory $dir -MediaBase 'Episode' -Language 'ja' -Model 'kotoba-v2'
            $got | Should -Be (Join-Path $dir 'Episode.track 1.ja.kotoba-v2.json')
            $got | Should -Not -Match 'ctranslate'
        }
    }
}

Describe 'Resolve-TranscriptMediaFile' {
    It 'retourne le chemin concret d''un fichier existant' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $media = Join-Path $Work 'Episode.mkv'
            Set-Content -LiteralPath $media -Value 'x'
            Resolve-TranscriptMediaFile -LiteralPath $media | Should -Be (Get-Item -LiteralPath $media).FullName
        }
    }

    It 'refuse un dossier' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'films'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            { Resolve-TranscriptMediaFile -LiteralPath $dir } | Should -Throw '*pas un dossier*'
        }
    }

    It 'ne refuse pas un .lst : la contrainte fichier-liste est propre à Purfview' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $lst = Join-Path $Work 'lot.lst'
            Set-Content -LiteralPath $lst -Value 'D:\Films\a.mkv'
            Resolve-TranscriptMediaFile -LiteralPath $lst | Should -Be (Get-Item -LiteralPath $lst).FullName
        }
    }
}

Describe 'Get-TranscriptEngineName' {
    It 'route <Model> vers Whisper' -TestCases @(
        @{ Model = 'large-v2' }
        @{ Model = 'large-v3' }
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'kotoba-v2' }
    ) {
        param($Model)
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Model = $Model } {
            param($Model)
            Get-TranscriptEngineName -Model $Model | Should -Be 'Whisper'
        }
    }
}

Describe 'Write-TetramTranscript' {
    It 'écrit le JSON Tetram et ne laisse pas de temporaire de publication' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $transcript = ConvertFrom-WhisperTranscript -InputObject '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Model 'large-v3' -UseLanguage 'ja'
            $dest = Join-Path $Work 'Episode.track 1.ja.large-v3.json'
            Write-TetramTranscript -Transcript $transcript -Path $dest
            Test-Path -LiteralPath $dest | Should -BeTrue
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
            $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
            $parsed.engine | Should -Be 'faster-whisper'
            $parsed.language | Should -Be 'ja'
        }
    }

    It 'remplace un sidecar déjà présent' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dest = Join-Path $Work 'Episode.track 1.ja.large-v3.json'
            Set-Content -LiteralPath $dest -Value 'ancien'
            $transcript = ConvertFrom-WhisperTranscript -InputObject '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"nouveau"}]}' -Model 'large-v3' -UseLanguage 'ja'
            Write-TetramTranscript -Transcript $transcript -Path $dest
            $raw = Get-Content -LiteralPath $dest -Raw -Encoding UTF8
            $raw | Should -Not -Be 'ancien'
            $parsed = ConvertFrom-Json -InputObject $raw
            $parsed.segments[0].text | Should -Be 'nouveau'
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        }
    }

    It 'conserve le sidecar précédent si la publication échoue' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dest = Join-Path $Work 'Keep.track 1.en.large-v3.json'
            Set-Content -LiteralPath $dest -Value 'ancien'
            $transcript = ConvertFrom-WhisperTranscript -InputObject '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Model 'large-v3'
            Mock Move-Item { throw 'publication impossible' }
            { Write-TetramTranscript -Transcript $transcript -Path $dest } | Should -Throw '*publication impossible*'
            Get-Content -LiteralPath $dest -Raw | Should -BeLike 'ancien*'
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        }
    }

    It 'crée le .tmp de publication dans le dossier destination' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $transcript = ConvertFrom-WhisperTranscript -InputObject '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Model 'large-v3' -UseLanguage 'ja'
            $dest = Join-Path $Work 'Episode.track 1.ja.large-v3.json'
            $script:SeenTemp = $null
            Mock Move-Item {
                param($LiteralPath)
                $script:SeenTemp = $LiteralPath
            }
            Write-TetramTranscript -Transcript $transcript -Path $dest
            $script:SeenTemp | Should -Not -BeNullOrEmpty
            [IO.Path]::GetExtension($script:SeenTemp) | Should -Be '.tmp'
            $gotDir = [IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($script:SeenTemp)).TrimEnd('\', '/')
            $wantDir = [IO.Path]::GetFullPath($Work).TrimEnd('\', '/')
            $gotDir | Should -Be $wantDir
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        }
    }

    It 'ne laisse ni JSON final ni .tmp si la publication échoue' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $transcript = ConvertFrom-WhisperTranscript -InputObject '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Model 'large-v3'
            $dest = Join-Path $Work 'Episode.track 1.en.large-v3.json'
            Mock Move-Item { throw 'publication impossible' }
            { Write-TetramTranscript -Transcript $transcript -Path $dest } | Should -Throw '*publication impossible*'
            Test-Path -LiteralPath $dest | Should -BeFalse
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        }
    }
}

Describe 'Publish-TetramTranscript' {
    It 'écrit le sidecar à côté du média, pas à côté du JSON natif' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $nativeDir = Join-Path $Work 'native-temp'
            $mediaDir = Join-Path $Work 'Videos'
            New-Item -ItemType Directory -Path $nativeDir -Force | Out-Null
            New-Item -ItemType Directory -Path $mediaDir -Force | Out-Null
            $media = Join-Path $mediaDir 'Episode.mkv'
            Set-Content -LiteralPath $media -Value 'x'
            $transcript = ConvertFrom-WhisperTranscript -InputObject '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Model 'large-v3' -UseLanguage 'ja' -AudioTrack 2

            Publish-TetramTranscript -Transcript $transcript -MediaPath $media

            $dest = Join-Path $mediaDir 'Episode.track 2.ja.large-v3.json'
            Test-Path -LiteralPath $dest | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $nativeDir 'Episode.track 2.ja.large-v3.json') | Should -BeFalse
            $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
            $parsed.audioTrack | Should -Be 2
            $parsed.language | Should -Be 'ja'
        }
    }
}
