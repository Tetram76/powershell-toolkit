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

    $script:FakeCmdlet = [PSCustomObject]@{}
    $script:FakeCmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $true }

    function script:New-TestTetramTranscript {
        param(
            [string] $Model = 'large-v3',
            [string] $Language = 'ja',
            [int] $AudioTrack = 1,
            [string] $Text = 'x',
            [string] $Engine = 'faster-whisper'
        )
        [pscustomobject]@{
            engine         = $Engine
            model          = $Model
            language       = $Language
            languageSource = 'forced'
            audioTrack     = $AudioTrack
            segments       = @(
                [pscustomobject]@{
                    start = 1.0
                    end   = 2.0
                    text  = $Text
                }
            )
        }
    }
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
            Set-Content -LiteralPath $lst -Value (Join-Path 'Films' 'a.mkv')
            Resolve-TranscriptMediaFile -LiteralPath $lst | Should -Be (Get-Item -LiteralPath $lst).FullName
        }
    }

    It 'traite les crochets comme un nom de fichier, pas comme un glob' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Set-Content -LiteralPath (Join-Path $Work 'Episode[1].mkv') -Value 'x'
            Set-Content -LiteralPath (Join-Path $Work 'Episode1.mkv') -Value 'x'
            $got = Resolve-TranscriptMediaFile -LiteralPath (Join-Path $Work 'Episode[1].mkv')
            $got | Should -Be (Get-Item -LiteralPath (Join-Path $Work 'Episode[1].mkv')).FullName
            $got | Should -Not -Be (Get-Item -LiteralPath (Join-Path $Work 'Episode1.mkv')).FullName
        }
    }

    It 'refuse un chemin inexistant' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            { Resolve-TranscriptMediaFile -LiteralPath (Join-Path $Work 'absent.mkv') } | Should -Throw '*fichier unique*'
        }
    }

    It 'refuse un masque qui n''est pas un nom de fichier littéral' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            1..2 | ForEach-Object { Set-Content -LiteralPath (Join-Path $Work "f$_.mkv") -Value 'x' }
            { Resolve-TranscriptMediaFile -LiteralPath (Join-Path $Work '*.mkv') } | Should -Throw '*fichier unique*'
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

    It 'route reazon-k2-v2 vers SherpaOnnx' {
        InModuleScope 'Tetram.Media.Transcript' {
            Get-TranscriptEngineName -Model 'reazon-k2-v2' | Should -Be 'SherpaOnnx'
        }
    }
}

Describe 'chargement paresseux des backends de transcription' {
    It 'charge la couche commune sans définir Invoke-ProviderTranscript ni les helpers moteur' {
        $names = InModuleScope 'Tetram.Media.Transcript' {
            @(
                Get-Command -Name Invoke-TranscriptBackend -ErrorAction SilentlyContinue
                Get-Command -Name Invoke-ProviderTranscript -ErrorAction SilentlyContinue
                Get-Command -Name Invoke-WhisperTranscript -ErrorAction SilentlyContinue
                Get-Command -Name Get-WhisperPath -ErrorAction SilentlyContinue
                Get-Command -Name Invoke-SherpaOnnxTranscript -ErrorAction SilentlyContinue
                Get-Command -Name Get-SherpaOnnxPath -ErrorAction SilentlyContinue
            ) | ForEach-Object { $_.Name } | Sort-Object
        }

        $names | Should -Be @('Invoke-TranscriptBackend')
    }

    It 'n''embarque aucune dépendance binaire Whisper ou Sherpa dans le code générique' {
        $repo = $script:RepoRootTranscript
        $generic = @(
            Get-Content -LiteralPath (Join-Path $repo 'Tetram.Media.Transcript' 'Tetram.Media.Transcript.psm1') -Raw
            Get-Content -LiteralPath (Join-Path $repo 'Tetram.Media.Transcript' 'Private' 'Transcript.ps1') -Raw
        ) -join "`n"

        $generic | Should -Not -Match 'faster-whisper-xxl'
        $generic | Should -Not -Match 'sherpa-onnx-offline'
        $generic | Should -Not -Match 'Get-WhisperPath'
        $generic | Should -Not -Match 'Get-SherpaOnnxPath'
        $generic | Should -Not -Match 'Invoke-FFmpeg'
        $generic | Should -Not -Match 'pcm_s16le'
        $generic | Should -Not -Match '--ff_track'
        $generic | Should -Not -Match '--encoder'
    }

    Context 'isolation du fichier non demandé' {
        BeforeEach {
            $script:SavedPrivateRoot = InModuleScope 'Tetram.Media.Transcript' {
                $script:TranscriptPrivateRoot
            }
        }

        AfterEach {
            $savedRoot = $script:SavedPrivateRoot
            InModuleScope 'Tetram.Media.Transcript' -Parameters @{ SavedRoot = $savedRoot } {
                param($SavedRoot)
                $script:TranscriptPrivateRoot = $SavedRoot
            }
        }

        It 'n''exécute pas SherpaOnnx.ps1 pour un modèle Whisper' {
            $tempRoot = Join-Path $TestDrive 'transcript-private-whisper'
            New-Item -ItemType Directory -Path $tempRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $tempRoot 'Whisper.ps1') -Value @'
function Invoke-ProviderTranscript {
    param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, [switch] $WhatIf)
    [pscustomobject]@{ model = $Model; engine = 'faster-whisper' }
}
'@ -Encoding utf8
            Set-Content -LiteralPath (Join-Path $tempRoot 'SherpaOnnx.ps1') -Value "throw 'Sherpa ne devait pas être chargé'" -Encoding utf8

            $got = InModuleScope 'Tetram.Media.Transcript' -Parameters @{
                TempRoot = $tempRoot
                Cmdlet   = $script:FakeCmdlet
            } {
                param($TempRoot, $Cmdlet)
                $script:TranscriptPrivateRoot = $TempRoot
                Invoke-TranscriptBackend -MediaPath (Join-Path 'Videos' 'a.mkv') -Model 'large-v3' -Cmdlet $Cmdlet
            }

            $got.model | Should -Be 'large-v3'
        }

        It 'n''exécute pas Whisper.ps1 pour un modèle Sherpa' {
            $tempRoot = Join-Path $TestDrive 'transcript-private-sherpa'
            New-Item -ItemType Directory -Path $tempRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $tempRoot 'SherpaOnnx.ps1') -Value @'
function Invoke-ProviderTranscript {
    param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, [switch] $WhatIf)
    [pscustomobject]@{ model = $Model; engine = 'sherpa-onnx' }
}
'@ -Encoding utf8
            Set-Content -LiteralPath (Join-Path $tempRoot 'Whisper.ps1') -Value "throw 'Whisper ne devait pas être chargé'" -Encoding utf8

            $got = InModuleScope 'Tetram.Media.Transcript' -Parameters @{
                TempRoot = $tempRoot
                Cmdlet   = $script:FakeCmdlet
            } {
                param($TempRoot, $Cmdlet)
                $script:TranscriptPrivateRoot = $TempRoot
                Invoke-TranscriptBackend -MediaPath (Join-Path 'Videos' 'a.mkv') -Model 'reazon-k2-v2' -Cmdlet $Cmdlet
            }

            $got.model | Should -Be 'reazon-k2-v2'
        }
    }
}

Describe 'Invoke-TranscriptBackend' {
    BeforeEach {
        $script:SavedPrivateRoot = InModuleScope 'Tetram.Media.Transcript' {
            $script:TranscriptPrivateRoot
        }
    }

    AfterEach {
        $savedRoot = $script:SavedPrivateRoot
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ SavedRoot = $savedRoot } {
            param($SavedRoot)
            $script:TranscriptPrivateRoot = $SavedRoot
        }
    }

    It 'délègue un modèle Whisper au contrat commun sans résoudre Purfview' {
        $tempRoot = Join-Path $TestDrive 'dispatch-whisper'
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'Whisper.ps1') -Value @'
function Get-WhisperPath { throw 'le dispatcher ne doit pas résoudre Purfview' }
function Invoke-ProviderTranscript {
    param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, [switch] $WhatIf)
    [pscustomobject]@{
        model      = $Model
        mediaPath  = $MediaPath
        audioTrack = $AudioTrack
        language   = $UseLanguage
        whatIf     = [bool]$WhatIf
    }
}
'@ -Encoding utf8
        Set-Content -LiteralPath (Join-Path $tempRoot 'SherpaOnnx.ps1') -Value "throw 'Sherpa ne devait pas être chargé'" -Encoding utf8

        $media = Join-Path 'Videos' 'Episode.mkv'
        $got = InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            TempRoot = $tempRoot
            Cmdlet   = $script:FakeCmdlet
            Media    = $media
        } {
            param($TempRoot, $Cmdlet, $Media)
            $script:TranscriptPrivateRoot = $TempRoot
            Invoke-TranscriptBackend -MediaPath $Media -Model 'large-v3' -AudioTrack 2 -UseLanguage 'ja' -Cmdlet $Cmdlet
        }

        $got.model | Should -Be 'large-v3'
        $got.mediaPath | Should -Be $media
        $got.audioTrack | Should -Be 2
        $got.language | Should -Be 'ja'
        $got.whatIf | Should -BeFalse
    }

    It 'délègue reazon-k2-v2 au contrat commun sans résoudre Sherpa' {
        $tempRoot = Join-Path $TestDrive 'dispatch-sherpa'
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'SherpaOnnx.ps1') -Value @'
function Get-SherpaOnnxPath { throw 'le dispatcher ne doit pas résoudre Sherpa' }
function Invoke-FFmpeg { throw 'le dispatcher ne doit pas invoquer FFmpeg' }
function Invoke-ProviderTranscript {
    param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, [switch] $WhatIf)
    [pscustomobject]@{
        model      = $Model
        mediaPath  = $MediaPath
        audioTrack = $AudioTrack
        language   = $UseLanguage
        whatIf     = [bool]$WhatIf
    }
}
'@ -Encoding utf8
        Set-Content -LiteralPath (Join-Path $tempRoot 'Whisper.ps1') -Value "throw 'Whisper ne devait pas être chargé'" -Encoding utf8

        $media = Join-Path 'Videos' 'Episode.mkv'
        $got = InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            TempRoot = $tempRoot
            Cmdlet   = $script:FakeCmdlet
            Media    = $media
        } {
            param($TempRoot, $Cmdlet, $Media)
            $script:TranscriptPrivateRoot = $TempRoot
            Invoke-TranscriptBackend -MediaPath $Media -Model 'reazon-k2-v2' -AudioTrack 2 -UseLanguage 'ja' -Cmdlet $Cmdlet
        }

        $got.model | Should -Be 'reazon-k2-v2'
        $got.mediaPath | Should -Be $media
        $got.audioTrack | Should -Be 2
        $got.language | Should -Be 'ja'
        $got.whatIf | Should -BeFalse
    }

    It 'propage -WhatIf vers le contrat commun' {
        $tempRoot = Join-Path $TestDrive 'dispatch-whatif'
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'Whisper.ps1') -Value @'
function Invoke-ProviderTranscript {
    param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, [switch] $WhatIf)
    [pscustomobject]@{ WhatIf = [bool]$WhatIf }
}
'@ -Encoding utf8
        Set-Content -LiteralPath (Join-Path $tempRoot 'SherpaOnnx.ps1') -Value "throw 'Sherpa ne devait pas être chargé'" -Encoding utf8

        $got = InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            TempRoot = $tempRoot
            Cmdlet   = $script:FakeCmdlet
        } {
            param($TempRoot, $Cmdlet)
            $script:TranscriptPrivateRoot = $TempRoot
            Invoke-TranscriptBackend -MediaPath (Join-Path 'Videos' 'a.mkv') -Model 'kotoba-v2' -Cmdlet $Cmdlet -WhatIf
        }

        $got.WhatIf | Should -BeTrue
    }

    It 'n''accepte plus WhisperPath' {
        InModuleScope 'Tetram.Media.Transcript' {
            (Get-Command Invoke-TranscriptBackend).Parameters.ContainsKey('WhisperPath') | Should -BeFalse
        }
    }
}

Describe 'Write-TetramTranscript' {
    It 'écrit le JSON Tetram et ne laisse pas de temporaire de publication' {
        $transcript = script:New-TestTetramTranscript
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive"; Transcript = $transcript } {
            param($Work, $Transcript)
            $dest = Join-Path $Work 'Episode.track 1.ja.large-v3.json'
            Write-TetramTranscript -Transcript $Transcript -Path $dest
            Test-Path -LiteralPath $dest | Should -BeTrue
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
            $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
            $parsed.engine | Should -Be 'faster-whisper'
            $parsed.language | Should -Be 'ja'
        }
    }

    It 'remplace un sidecar déjà présent' {
        $transcript = script:New-TestTetramTranscript -Text 'nouveau'
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive"; Transcript = $transcript } {
            param($Work, $Transcript)
            $dest = Join-Path $Work 'Episode.track 1.ja.large-v3.json'
            Set-Content -LiteralPath $dest -Value 'ancien'
            Write-TetramTranscript -Transcript $Transcript -Path $dest
            $raw = Get-Content -LiteralPath $dest -Raw -Encoding UTF8
            $raw | Should -Not -Be 'ancien'
            $parsed = ConvertFrom-Json -InputObject $raw
            $parsed.segments[0].text | Should -Be 'nouveau'
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        }
    }

    It 'conserve le sidecar précédent si la publication échoue' {
        $transcript = script:New-TestTetramTranscript -Language 'en'
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive"; Transcript = $transcript } {
            param($Work, $Transcript)
            $dest = Join-Path $Work 'Keep.track 1.en.large-v3.json'
            Set-Content -LiteralPath $dest -Value 'ancien'
            Mock Move-Item { throw 'publication impossible' }
            { Write-TetramTranscript -Transcript $Transcript -Path $dest } | Should -Throw '*publication impossible*'
            Get-Content -LiteralPath $dest -Raw | Should -BeLike 'ancien*'
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        }
    }

    It 'crée le .tmp de publication dans le dossier destination' {
        $transcript = script:New-TestTetramTranscript
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive"; Transcript = $transcript } {
            param($Work, $Transcript)
            $dest = Join-Path $Work 'Episode.track 1.ja.large-v3.json'
            $script:SeenTemp = $null
            Mock Move-Item {
                param($LiteralPath)
                $script:SeenTemp = $LiteralPath
            }
            Write-TetramTranscript -Transcript $Transcript -Path $dest
            $script:SeenTemp | Should -Not -BeNullOrEmpty
            [IO.Path]::GetExtension($script:SeenTemp) | Should -Be '.tmp'
            $gotDir = [IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($script:SeenTemp)).TrimEnd('\', '/')
            $wantDir = [IO.Path]::GetFullPath($Work).TrimEnd('\', '/')
            $gotDir | Should -Be $wantDir
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        }
    }

    It 'ne laisse ni JSON final ni .tmp si la publication échoue' {
        $transcript = script:New-TestTetramTranscript -Language 'en'
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive"; Transcript = $transcript } {
            param($Work, $Transcript)
            $dest = Join-Path $Work 'Episode.track 1.en.large-v3.json'
            Mock Move-Item { throw 'publication impossible' }
            { Write-TetramTranscript -Transcript $Transcript -Path $dest } | Should -Throw '*publication impossible*'
            Test-Path -LiteralPath $dest | Should -BeFalse
            @(Get-ChildItem -LiteralPath $Work -Filter '*.tmp' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        }
    }
}

Describe 'Publish-TetramTranscript' {
    It 'écrit le sidecar à côté du média, pas à côté du JSON natif' {
        $transcript = script:New-TestTetramTranscript -AudioTrack 2
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive"; Transcript = $transcript } {
            param($Work, $Transcript)
            $nativeDir = Join-Path $Work 'native-temp'
            $mediaDir = Join-Path $Work 'Videos'
            New-Item -ItemType Directory -Path $nativeDir -Force | Out-Null
            New-Item -ItemType Directory -Path $mediaDir -Force | Out-Null
            $media = Join-Path $mediaDir 'Episode.mkv'
            Set-Content -LiteralPath $media -Value 'x'

            Publish-TetramTranscript -Transcript $Transcript -MediaPath $media

            $dest = Join-Path $mediaDir 'Episode.track 2.ja.large-v3.json'
            Test-Path -LiteralPath $dest | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $nativeDir 'Episode.track 2.ja.large-v3.json') | Should -BeFalse
            $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
            $parsed.audioTrack | Should -Be 2
            $parsed.language | Should -Be 'ja'
        }
    }
}
