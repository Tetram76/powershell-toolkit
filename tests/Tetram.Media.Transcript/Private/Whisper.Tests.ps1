# Étendre la suite autour des unités privées Faster-Whisper / Purfview.
#
# Tout passe par InModuleScope 'Tetram.Media.Transcript' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Get-Whisper* n'appelle aucun binaire. Invoke-Whisper s'exerce via pwsh (stand-in),
# jamais via faster-whisper-xxl.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranscript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranscript = Join-Path $script:RepoRootTranscript 'Tetram.Media.Transcript'
    Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop

    $module = Get-Module -Name 'Tetram.Media.Transcript'
    . $module {
        . (Join-Path $script:TranscriptPrivateRoot 'Whisper.ps1')
    }

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
    Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
}

# La fonction est pure et déterministe : chaque cas assert la séquence entière plutôt qu'un fragment.
# Aucun paramètre n'est donc fourni sans être couvert, et toute régression d'ordre est vue partout.
Describe 'Get-WhisperArguments' {
    It 'produit la séquence unitaire par défaut, sans --batch_recursive ni --language' {
        InModuleScope 'Tetram.Media.Transcript' {
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\Films\a.mkv' -Model 'large-v2' -OutputDir $outDir
            $got | Should -Be @(
                'D:\Films\a.mkv'
                '--output_dir', $outDir
                '--output_format', 'json'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
                '--beep_off'
            )
            $got | Should -Not -Contain '--batch_recursive'
            (Get-Command Get-WhisperArguments).Parameters['Source'].ParameterType | Should -Be ([string])
        }
    }

    It 'n''accepte plus Format' {
        InModuleScope 'Tetram.Media.Transcript' {
            (Get-Command Get-WhisperArguments).Parameters.ContainsKey('Format') | Should -BeFalse
        }
    }

    It 'passe --ff_track avec la piste demandée' {
        InModuleScope 'Tetram.Media.Transcript' {
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\a.mkv' -Model 'large-v2' -OutputDir $outDir -AudioTrack 2
            $ff = [array]::IndexOf(@($got), '--ff_track')
            $got[$ff + 1] | Should -Be '2'
        }
    }

    It 'reprend le modèle demandé' {
        InModuleScope 'Tetram.Media.Transcript' {
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\a.mkv' -Model 'large-v3-turbo' -OutputDir $outDir
            $got | Should -Be @(
                'D:\a.mkv'
                '--output_dir', $outDir
                '--output_format', 'json'
                '--check_files'
                '--model', 'large-v3-turbo'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
                '--beep_off'
            )
        }
    }

    It 'insère --language entre --ff_track et --postfix quand UseLanguage est fourni' {
        InModuleScope 'Tetram.Media.Transcript' {
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\a.mkv' -Model 'large-v2' -UseLanguage 'fr' -OutputDir $outDir
            $got | Should -Be @(
                'D:\a.mkv'
                '--output_dir', $outDir
                '--output_format', 'json'
                '--check_files'
                '--model', 'large-v2'
                '--ff_track', '1'
                '--language', 'fr'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
                '--beep_off'
            )
        }
    }

    It 'ajoute les options Kotoba après la séquence générique pour kotoba-v2' {
        InModuleScope 'Tetram.Media.Transcript' {
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\a.mkv' -Model 'kotoba-v2' -UseLanguage 'ja' -OutputDir $outDir
            $got | Should -Be @(
                'D:\a.mkv'
                '--output_dir', $outDir
                '--output_format', 'json'
                '--check_files'
                '--model', 'kotoba-v2'
                '--ff_track', '1'
                '--language', 'ja'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
                '--beep_off'
                '--condition_on_previous_text', 'False'
                '-prompt', 'None'
                '--word_timestamps', 'False'
                '--chunk_length', '15'
                '--compute_type', 'float16'
            )
        }
    }

    It 'n''ajoute aucune option Kotoba pour large-v3' {
        InModuleScope 'Tetram.Media.Transcript' {
            $outDir = Join-Path ([IO.Path]::GetTempPath()) 'whisper-args-out'
            $got = Get-WhisperArguments -Source 'D:\a.mkv' -Model 'large-v3' -OutputDir $outDir
            $got | Should -Be @(
                'D:\a.mkv'
                '--output_dir', $outDir
                '--output_format', 'json'
                '--check_files'
                '--model', 'large-v3'
                '--ff_track', '1'
                '--postfix'
                '--print_progress'
                '--task', 'transcribe'
                '--beep_off'
            )
        }
    }
}

Describe 'Get-WhisperPath' {
    It 'retourne l''override quand c''est un fichier' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $exe = Join-Path $Work 'ailleurs.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            Get-WhisperPath -OverridePath $exe | Should -Be $exe
        }
    }

    It 'rejette un override qui est un dossier' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'dossier-exe'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            { Get-WhisperPath -OverridePath $dir } | Should -Throw '*pas un dossier*'
        }
    }

    It 'rejette un override inexistant' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            { Get-WhisperPath -OverridePath (Join-Path $Work 'absent.exe') } | Should -Throw '*inexistant*'
        }
    }

    It 'prend le binaire du dossier du module quand il existe' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $fakeRoot = Join-Path $Work 'purfview'
            New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
            $exe = Join-Path $fakeRoot 'faster-whisper-xxl.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            $saved = $script:WhisperRoot
            try {
                $script:WhisperRoot = $fakeRoot
                Get-WhisperPath | Should -Be $exe
            }
            finally {
                $script:WhisperRoot = $saved
            }
        }
    }

    It 'échoue avec un message qui indique où poser la distribution' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'faster-whisper-xxl' }
            $saved = $script:WhisperRoot
            try {
                $script:WhisperRoot = Join-Path $Work 'vide'
                { Get-WhisperPath } | Should -Throw '*Purfview*'
            }
            finally {
                $script:WhisperRoot = $saved
            }
        }
    }

    It 'ignore une fonction de même nom au lieu de renvoyer une Source vide' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            function faster-whisper-xxl { 'ne doit jamais être choisie' }
            $saved = $script:WhisperRoot
            try {
                $script:WhisperRoot = Join-Path $Work 'vide'
                { Get-WhisperPath } | Should -Throw '*Purfview*'
            }
            finally {
                $script:WhisperRoot = $saved
                Remove-Item -Path 'function:faster-whisper-xxl' -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Invoke-Whisper' {
    It 'affiche la ligne de commande avant toute exécution' {
        InModuleScope 'Tetram.Media.Transcript' {
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $false }
            $state = @{}
            Invoke-Whisper -Exe 'binaire-absent-xyz.exe' -Arguments @('a.mkv', '--task', 'transcribe') -Cmdlet $cmdlet -State $state
            Should -Invoke Show-CommandLine -Times 1
        }
    }

    It 'laisse ExitCode à $null et n''exécute rien si ShouldProcess refuse' {
        InModuleScope 'Tetram.Media.Transcript' {
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $false }
            $state = @{}
            Invoke-Whisper -Exe 'binaire-absent-xyz.exe' -Arguments @('a.mkv') -Cmdlet $cmdlet -State $state
            $state['ExitCode'] | Should -BeNullOrEmpty
        }
    }

    It 'relève le code de sortie du binaire' {
        InModuleScope 'Tetram.Media.Transcript' {
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $true }
            $state = @{}
            Invoke-Whisper -Exe (Get-Command pwsh).Source -Arguments @('-NoProfile', '-Command', 'exit 3') -Cmdlet $cmdlet -State $state
            $state['ExitCode'] | Should -Be 3
        }
    }

    It 'préserve les frontières d''arguments, y compris les chemins à espaces' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            Mock Show-CommandLine {}
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $true }
            $helper = Join-Path $Work 'ecrit-args.ps1'
            Set-Content -LiteralPath $helper -Value 'param($Destination, $Contenu) Set-Content -LiteralPath $Destination -Value $Contenu'
            $out = Join-Path $Work 'sortie avec espaces.txt'
            $state = @{}
            Invoke-Whisper -Exe (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', $helper, $out, 'ok') -Cmdlet $cmdlet -State $state
            Get-Content -LiteralPath $out | Should -Be 'ok'
        }
    }
}

Describe 'New-WhisperTempDirectory' {
    It 'crée un dossier GUID sous TEMP, sans stem média' {
        InModuleScope 'Tetram.Media.Transcript' {
            $dir = New-WhisperTempDirectory
            try {
                $gotDir = [IO.Path]::GetFullPath((Split-Path -Parent $dir)).TrimEnd('\', '/')
                $wantDir = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
                $gotDir | Should -Be $wantDir
                [IO.Path]::GetFileName($dir) | Should -Match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                [IO.Path]::GetFileName($dir) | Should -Not -Match 'Episode'
                Test-Path -LiteralPath $dir -PathType Container | Should -BeTrue
            }
            finally {
                Remove-WhisperTempDirectory -Path $dir
            }
            Test-Path -LiteralPath $dir | Should -BeFalse
        }
    }

    It 'ne retourne pas un chemin si New-Item échoue' {
        InModuleScope 'Tetram.Media.Transcript' {
            Mock New-Item { throw 'TEMP inaccessible' }
            { New-WhisperTempDirectory } | Should -Throw '*TEMP inaccessible*'
        }
    }
}

Describe 'ConvertFrom-WhisperTranscript' {
    It 'produit le contrat racine Tetram avec langue forcée' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeWhisperJson } {
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

    It 'reprend la piste demandée dans audioTrack' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeWhisperJson } {
            param($Native)
            $got = ConvertFrom-WhisperTranscript -InputObject $Native -Model 'large-v3' -UseLanguage 'ja' -AudioTrack 2
            $got.audioTrack | Should -Be 2
        }
    }

    It 'reprend la langue native avec languageSource detected' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeWhisperJson } {
            param($Native)
            $got = ConvertFrom-WhisperTranscript -InputObject $Native -Model 'large-v2'
            $got.language | Should -Be 'ja'
            $got.languageSource | Should -Be 'detected'
        }
    }

    It 'conserve l''ordre, start, end, text, sans id Tetram' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeWhisperJson } {
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
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeWhisperJson } {
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
        InModuleScope 'Tetram.Media.Transcript' {
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
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Native = $script:NativeWhisperJson } {
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
        InModuleScope 'Tetram.Media.Transcript' {
            $json = '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $got = ConvertFrom-WhisperTranscript -InputObject $json -Model 'kotoba-v2' -UseLanguage 'ja'
            $segment = @($got.segments)[0]
            $segment.PSObject.Properties['words'] | Should -BeNullOrEmpty
            $got.model | Should -Be 'kotoba-v2'
        }
    }

    It 'n''ajoute pas un tableau words vide' {
        InModuleScope 'Tetram.Media.Transcript' {
            $json = '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"x","words":[]}]}'
            $got = ConvertFrom-WhisperTranscript -InputObject $json -Model 'large-v3'
            @($got.segments)[0].PSObject.Properties['words'] | Should -BeNullOrEmpty
        }
    }

    It 'lève si segments est absent' {
        InModuleScope 'Tetram.Media.Transcript' {
            { ConvertFrom-WhisperTranscript -InputObject '{"language":"ja"}' -Model 'large-v3' } |
                Should -Throw '*segments*'
        }
    }

    It 'lève si la langue détectée est absente' {
        InModuleScope 'Tetram.Media.Transcript' {
            { ConvertFrom-WhisperTranscript -InputObject '{"segments":[{"start":1.0,"end":2.0,"text":"x"}]}' -Model 'large-v3' } |
                Should -Throw '*langue*'
        }
    }
}

Describe 'Convert-WhisperNativeToTetram' {
    It 'retourne le transcript Tetram en mémoire sans publier de sidecar' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $nativeDir = Join-Path $Work 'native-temp'
            $mediaDir = Join-Path $Work 'Videos'
            New-Item -ItemType Directory -Path $nativeDir -Force | Out-Null
            New-Item -ItemType Directory -Path $mediaDir -Force | Out-Null
            $native = Join-Path $nativeDir 'Episode.ja.json'
            Set-Content -LiteralPath $native -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'

            $got = Convert-WhisperNativeToTetram -NativeJsonPath $native -Model 'large-v3' -UseLanguage 'ja' -AudioTrack 2

            $got.audioTrack | Should -Be 2
            $got.language | Should -Be 'ja'
            $got.model | Should -Be 'large-v3'
            Test-Path -LiteralPath (Join-Path $mediaDir 'Episode.track 2.ja.large-v3.json') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $nativeDir 'Episode.track 2.ja.large-v3.json') | Should -BeFalse
        }
    }
}

Describe 'Get-WhisperNativeJsonFromOutputDir' {
    It 'liste les JSON natifs du dossier de sortie et ignore le sidecar Tetram' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
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

    It 'reconnaît le JSON natif Purfview en postfixe underscore' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $outDir = Join-Path $Work 'whisper-out-underscore'
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            $native = Join-Path $outDir 'sample_en.json'
            Set-Content -LiteralPath $native -Value '{"language":"en","segments":[]}'

            $got = @(Get-WhisperNativeJsonFromOutputDir -OutputDir $outDir)
            $got | Should -Be @($native)
        }
    }

    It 'liste plusieurs JSON natifs sans en choisir un' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $outDir = Join-Path $Work 'whisper-out-multi'
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            $a = Join-Path $outDir 'Episode.ja.json'
            $b = Join-Path $outDir 'Other.en.json'
            Set-Content -LiteralPath $a -Value '{}'
            Set-Content -LiteralPath $b -Value '{}'
            $got = @(Get-WhisperNativeJsonFromOutputDir -OutputDir $outDir)
            $got.Count | Should -Be 2
            $got | Should -Contain $a
            $got | Should -Contain $b
        }
    }
}

Describe 'Invoke-WhisperTranscript' {
    BeforeAll {
        function Invoke-PrivateWhisperTranscript {
            param(
                [Parameter(Mandatory)] [string] $MediaPath,
                [Parameter(Mandatory)] [string] $Model,
                [Parameter(Mandatory)] $Cmdlet,
                [int] $AudioTrack = 1,
                [string] $UseLanguage,
                [string] $WhisperPath,
                [switch] $WhatIf
            )

            InModuleScope 'Tetram.Media.Transcript' -Parameters @{
                MediaPath   = $MediaPath
                Model       = $Model
                Cmdlet      = $Cmdlet
                AudioTrack  = $AudioTrack
                UseLanguage = $UseLanguage
                WhisperPath = $WhisperPath
                WhatIf      = [bool]$WhatIf
            } {
                param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, $WhisperPath, $WhatIf)
                Invoke-WhisperTranscript -MediaPath $MediaPath -Model $Model -Cmdlet $Cmdlet -AudioTrack $AudioTrack -UseLanguage $UseLanguage -WhisperPath $WhisperPath -WhatIf:$WhatIf
            }
        }

        $script:FakeCmdlet = [PSCustomObject]@{}
        $script:FakeCmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $true }
        # Fixture minimal : un crash Purfview 0xC0000409 n'autorise pas de valider via un
        # décompte de segments (Maison Ikkoku a déjà oscillé entre 315 et 321).
        $script:PurfviewCrashExitCode = -1073740791
        $script:RecoverableNativeJson = @'
{
  "language": "ja",
  "segments": [
    {
      "id": 1,
      "start": 1.25,
      "end": 2.50,
      "text": "テスト",
      "temperature": 0.0,
      "avg_logprob": -0.2,
      "compression_ratio": 1.1,
      "no_speech_prob": 0.0,
      "tokens": [1, 2, 3],
      "words": [
        {
          "start": 1.25,
          "end": 2.50,
          "word": "テスト",
          "probability": 0.95
        }
      ]
    }
  ]
}
'@
    }

    BeforeEach {
        Mock -ModuleName Tetram.Media.Transcript Get-WhisperPath { 'whisper.exe' }
        Mock -ModuleName Tetram.Media.Transcript Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Transcript Write-DebugLog {}
        Mock -ModuleName Tetram.Media.Transcript Show-CommandLine {}
        $script:SeenArguments = $null
    }

    It 'invoque le binaire une seule fois avec le JSON natif et --ff_track' {
        $media = Join-Path $TestDrive 'once.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $State['ExitCode'] = 0
        }
        $null = Invoke-PrivateWhisperTranscript -MediaPath $media -Model large-v2 -Cmdlet $script:FakeCmdlet
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-Whisper -Times 1
        $script:SeenArguments[0] | Should -Be $media
        $script:SeenArguments | Should -Not -Contain '--batch_recursive'
        $fmt = [array]::IndexOf(@($script:SeenArguments), '--output_format')
        $script:SeenArguments[$fmt + 1] | Should -Be 'json'
        $ff = [array]::IndexOf(@($script:SeenArguments), '--ff_track')
        $script:SeenArguments[$ff + 1] | Should -Be '1'
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        $gotTemp = [IO.Path]::GetFullPath((Split-Path -Parent $script:SeenArguments[$outIndex + 1])).TrimEnd('\', '/')
        $wantTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
        $gotTemp | Should -Be $wantTemp
    }

    It 'refuse un fichier-liste <Name> avant d''invoquer Purfview' -TestCases @(
        @{ Name = 'lot.lst' }
        @{ Name = 'lot.m3u' }
        @{ Name = 'lot.m3u8' }
        @{ Name = 'lot.txt' }
    ) {
        param($Name)
        $listFile = Join-Path $TestDrive $Name
        Set-Content -LiteralPath $listFile -Value (Join-Path 'Films' 'a.mkv')
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper { throw 'ne doit pas tourner' }
        { Invoke-PrivateWhisperTranscript -MediaPath $listFile -Model large-v2 -Cmdlet $script:FakeCmdlet } | Should -Throw '*fichier-liste*'
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-Whisper -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Get-WhisperPath -Times 0
    }

    It 'lève le message faster-whisper-xxl si le binaire est introuvable' {
        $media = Join-Path $TestDrive 'missing-exe.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Get-WhisperPath { throw 'faster-whisper-xxl introuvable (test)' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper { throw 'ne doit pas tourner' }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model large-v2 -Cmdlet $script:FakeCmdlet } | Should -Throw '*faster-whisper-xxl*'
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-Whisper -Times 0
    }

    It 'lève si le binaire rend un code non nul, sans produire de transcript' {
        $media = Join-Path $TestDrive 'exit-nonzero.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 1
        }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model large-v2 -Cmdlet $script:FakeCmdlet } |
            Should -Throw '*faster-whisper-xxl a échoué (code 1)*'
    }

    It 'ne récupère pas le crash 0xC0000409 pour <Model>' -TestCases @(
        @{ Model = 'large-v2' }
        @{ Model = 'kotoba-v2' }
    ) {
        param($Model)
        $media = Join-Path $TestDrive "crash-other-$Model.mkv"
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value $script:RecoverableNativeJson
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model $Model -Cmdlet $script:FakeCmdlet -UseLanguage ja } |
            Should -Throw '*faster-whisper-xxl a échoué (code -1073740791)*'
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-InfoLog -Times 0
    }

    It 'ne récupère pas <Model> pour un autre code non nul que 0xC0000409' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $media = Join-Path $TestDrive "other-crash-$Model.mkv"
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value $script:RecoverableNativeJson
            $State['ExitCode'] = -1073741819
        }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model $Model -Cmdlet $script:FakeCmdlet -UseLanguage ja } |
            Should -Throw '*faster-whisper-xxl a échoué (code -1073741819)*'
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-InfoLog -Times 0
    }

    It 'échoue si <Model> crashe en 0xC0000409 sans JSON natif et nettoie le temporaire' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $media = Join-Path $TestDrive "crash-no-json-$Model.mkv"
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model $Model -Cmdlet $script:FakeCmdlet -UseLanguage ja } |
            Should -Throw '*Aucun JSON natif*'
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-InfoLog -Times 0
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        Test-Path -LiteralPath $script:SeenArguments[$outIndex + 1] | Should -BeFalse
    }

    It 'échoue si <Model> crashe en 0xC0000409 avec plusieurs JSON natifs' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $media = Join-Path $TestDrive "crash-ambiguous-$Model.mkv"
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            $outDir = $Arguments[$outIndex + 1]
            Set-Content -LiteralPath (Join-Path $outDir 'Episode.ja.json') -Value $script:RecoverableNativeJson
            Set-Content -LiteralPath (Join-Path $outDir 'Other.en.json') -Value '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"y"}]}'
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model $Model -Cmdlet $script:FakeCmdlet -UseLanguage ja } |
            Should -Throw '*Résultat natif ambigu*'
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-InfoLog -Times 0
    }

    It 'échoue si <Model> crashe en 0xC0000409 avec un JSON natif tronqué et nettoie le temporaire' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $media = Join-Path $TestDrive "crash-truncated-$Model.mkv"
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0'
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model $Model -Cmdlet $script:FakeCmdlet -UseLanguage ja } | Should -Throw
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-InfoLog -Times 0
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        Test-Path -LiteralPath $script:SeenArguments[$outIndex + 1] | Should -BeFalse
    }

    It 'échoue si <Model> crashe en 0xC0000409 avec un JSON sans segments exploitable' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $media = Join-Path $TestDrive "crash-no-segments-$Model.mkv"
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja"}'
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model $Model -Cmdlet $script:FakeCmdlet -UseLanguage ja } |
            Should -Throw '*segments*'
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-InfoLog -Times 0
    }

    It 'récupère <Model> après 0xC0000409 si le JSON natif est exploitable' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $work = Join-Path $TestDrive "crash-recover-$Model"
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value $script:RecoverableNativeJson
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        $got = Invoke-PrivateWhisperTranscript -MediaPath $media -Model $Model -Cmdlet $script:FakeCmdlet
        $got.engine | Should -Be 'faster-whisper'
        $got.model | Should -Be $Model
        $got.language | Should -Be 'ja'
        $got.languageSource | Should -Be 'detected'
        $got.audioTrack | Should -Be 1
        $got.segments.Count | Should -Be 1
        $got.segments[0].text | Should -Be 'テスト'
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-InfoLog -Times 1 -ParameterFilter {
            $Force -and
            $Text -match 'faster-whisper-xxl' -and
            $Text -match "\(modèle $([regex]::Escape($Model))\)" -and
            $Text -match '-1073740791' -and
            $Text -match '0xC0000409' -and
            $Text -match 'JSON natif exploitable et normalisation Tetram terminée malgré le crash'
        }
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File).Count | Should -Be 0
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        Test-Path -LiteralPath $script:SeenArguments[$outIndex + 1] | Should -BeFalse
    }

    It 'force la langue sur une récupération <Model> comme sur le chemin de succès' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $media = Join-Path $TestDrive "crash-forced-lang-$Model.mkv"
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value $script:RecoverableNativeJson
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        $got = Invoke-PrivateWhisperTranscript -MediaPath $media -Model $Model -Cmdlet $script:FakeCmdlet -UseLanguage ja
        $got.language | Should -Be 'ja'
        $got.languageSource | Should -Be 'forced'
    }

    It 'sous -WhatIf, n''applique aucune récupération <Model> et ne crée pas le temporaire' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $media = Join-Path $TestDrive "whatif-crash-$Model.mkv"
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript New-WhisperTempDirectory { throw 'ne doit pas créer TEMP' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
        }
        $got = Invoke-PrivateWhisperTranscript -MediaPath $media -Model $Model -Cmdlet $script:FakeCmdlet -UseLanguage ja -WhatIf
        $got | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Tetram.Media.Transcript New-WhisperTempDirectory -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-InfoLog -Times 0
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        Test-Path -LiteralPath $script:SeenArguments[$outIndex + 1] | Should -BeFalse
    }

    It 'propage une exception d''exécution du binaire' {
        $media = Join-Path $TestDrive 'invoke-throw.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper { throw 'accès refusé' }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model large-v2 -Cmdlet $script:FakeCmdlet } | Should -Throw '*accès refusé*'
    }

    It 'retourne le transcript Tetram sans publier de sidecar à côté du média' {
        $work = Join-Path $TestDrive 'success'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $State['ExitCode'] = 0
        }
        $got = Invoke-PrivateWhisperTranscript -MediaPath $media -Model large-v3 -Cmdlet $script:FakeCmdlet -UseLanguage ja
        $got.engine | Should -Be 'faster-whisper'
        $got.model | Should -Be 'large-v3'
        $got.language | Should -Be 'ja'
        $got.languageSource | Should -Be 'forced'
        $got.audioTrack | Should -Be 1
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File).Count | Should -Be 0
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        Test-Path -LiteralPath $script:SeenArguments[$outIndex + 1] | Should -BeFalse
    }

    It 'propage -AudioTrack 2 jusqu''à --ff_track et audioTrack' {
        $media = Join-Path $TestDrive 'track2.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $State['ExitCode'] = 0
        }
        $got = Invoke-PrivateWhisperTranscript -MediaPath $media -Model large-v3 -Cmdlet $script:FakeCmdlet -AudioTrack 2 -UseLanguage ja
        $ff = [array]::IndexOf(@($script:SeenArguments), '--ff_track')
        $script:SeenArguments[$ff + 1] | Should -Be '2'
        $got.audioTrack | Should -Be 2
    }

    It 'lève si le JSON natif est ambigu' {
        $media = Join-Path $TestDrive 'ambiguous.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            $outDir = $Arguments[$outIndex + 1]
            Set-Content -LiteralPath (Join-Path $outDir 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            Set-Content -LiteralPath (Join-Path $outDir 'Other.en.json') -Value '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"y"}]}'
            $State['ExitCode'] = 0
        }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model large-v3 -Cmdlet $script:FakeCmdlet -UseLanguage ja } |
            Should -Throw '*Résultat natif ambigu*'
    }

    It 'reprend kotoba-v2 comme nom de modèle dans le transcript' {
        $media = Join-Path $TestDrive 'kotoba.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $State['ExitCode'] = 0
        }
        $got = Invoke-PrivateWhisperTranscript -MediaPath $media -Model kotoba-v2 -Cmdlet $script:FakeCmdlet -UseLanguage ja
        $got.model | Should -Be 'kotoba-v2'
        $got.model | Should -Not -Match 'ctranslate'
    }

    It 'reprend la langue détectée du JSON natif sans -UseLanguage' {
        $media = Join-Path $TestDrive 'detected.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.en.json') -Value '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"hi"}]}'
            $State['ExitCode'] = 0
        }
        $got = Invoke-PrivateWhisperTranscript -MediaPath $media -Model large-v3 -Cmdlet $script:FakeCmdlet
        $got.language | Should -Be 'en'
        $got.languageSource | Should -Be 'detected'
    }

    It 'lève si le JSON natif est invalide et nettoie le temporaire' {
        $media = Join-Path $TestDrive 'invalid.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value 'not-json'
            $State['ExitCode'] = 0
        }
        { Invoke-PrivateWhisperTranscript -MediaPath $media -Model large-v3 -Cmdlet $script:FakeCmdlet -UseLanguage ja } | Should -Throw
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        Test-Path -LiteralPath $script:SeenArguments[$outIndex + 1] | Should -BeFalse
    }
}
