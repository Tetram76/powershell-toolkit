# Étendre la suite autour du module SUD Tetram.Media.Whisper (pilote faster-whisper-xxl).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Manifeste : Tetram.Media.Whisper/Tetram.Media.Whisper.psd1 — Test-ModuleManifest puis Import-Module -Force
# Privé : mocks -ModuleName Tetram.Media.Whisper sur Get-WhisperPath / Invoke-Whisper / Write-*Log / Show-CommandLine
# Le vrai binaire n'est appelé que sous le tag Integration.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootWhisper = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRootWhisper = Join-Path $script:RepoRootWhisper 'Tetram.Media.Whisper'
    $script:ManifestWhisper = Join-Path $script:ModuleRootWhisper 'Tetram.Media.Whisper.psd1'
}

Describe 'Tetram.Media.Whisper manifest' {
    It 'passe Test-ModuleManifest' {
        { Test-ModuleManifest -Path $script:ManifestWhisper -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'Tetram.Media.Whisper exports' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
    }

    It 'exporte uniquement Get-MediaTranscript' {
        $names = @(Get-Command -Module 'Tetram.Media.Whisper' | Select-Object -ExpandProperty Name | Sort-Object)
        $names | Should -Be @('Get-MediaTranscript')
    }
}

Describe 'Get-MediaTranscript binding' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
    }

    It 'refuse un appel sans aucune source' {
        # N'invoque jamais la cmdlet sans lier -LiteralPath : PowerShell ne lèverait pas
        # d'erreur de binding mais déclencherait son prompt interactif natif pour le paramètre
        # obligatoire manquant, qui bloque en console réelle (seul un hôte non interactif comme la CI
        # échoue immédiatement). On vérifie donc l'obligation via les métadonnées.
        $meta = Get-Command Get-MediaTranscript
        foreach ($setName in @($meta.ParameterSets | Select-Object -ExpandProperty Name)) {
            $set = $meta.ParameterSets | Where-Object Name -EQ $setName
            $sourceParams = @($set.Parameters | Where-Object { $_.Name -eq 'LiteralPath' -and $_.IsMandatory })
            $sourceParams.Count | Should -Be 1 -Because "le jeu '$setName' doit exiger LiteralPath"
        }
    }

    It 'n''expose plus -Format' {
        (Get-Command Get-MediaTranscript).Parameters.ContainsKey('Format') | Should -BeFalse
    }

    It 'n''expose plus -Path' {
        (Get-Command Get-MediaTranscript).Parameters.ContainsKey('Path') | Should -BeFalse
    }

    It 'expose LiteralPath scalaire, positionnel, avec alias PSPath' {
        $p = (Get-Command Get-MediaTranscript).Parameters['LiteralPath']
        $p.ParameterType | Should -Be ([string])
        $p.Aliases | Should -Contain 'PSPath'
        $attrs = @($p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
        $attrs.Count | Should -BeGreaterThan 0
        $attrs[0].Position | Should -Be 0
        $attrs[0].Mandatory | Should -BeTrue
    }

    It 'n''a plus les jeux Path / Mixed / LiteralPath de l''ancien contrat multiple' {
        $names = @((Get-Command Get-MediaTranscript).ParameterSets | Select-Object -ExpandProperty Name)
        $names | Should -Not -Contain 'Path'
        $names | Should -Not -Contain 'Mixed'
        $names | Should -Not -Contain 'LiteralPath'
    }

    It 'expose AudioTrack entier 1-based avec défaut 1' {
        $p = (Get-Command Get-MediaTranscript).Parameters['AudioTrack']
        $p.ParameterType | Should -Be ([int])
        { Get-MediaTranscript -LiteralPath 'a.mkv' -AudioTrack 0 -ErrorAction Stop } | Should -Throw
        { Get-MediaTranscript -LiteralPath 'a.mkv' -AudioTrack @(1, 2) -ErrorAction Stop } | Should -Throw
    }

    It 'expose Model comme tableau, défaut large-v2' {
        $p = (Get-Command Get-MediaTranscript).Parameters['Model']
        $p.ParameterType | Should -Be ([string[]])
    }

    It 'refuse un modèle hors liste' {
        { Get-MediaTranscript -LiteralPath 'a.mkv' -Model 'tiny' -ErrorAction Stop } | Should -Throw
        { Get-MediaTranscript -LiteralPath 'a.mkv' -Model large-v3, tiny -ErrorAction Stop } | Should -Throw
    }

    It 'accepte kotoba-v2 comme modèle' {
        $validate = (Get-Command Get-MediaTranscript).Parameters['Model'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        @($validate.ValidValues) | Should -Contain 'kotoba-v2'

        # Binding seulement : sans mocks, Get-MediaTranscript irait jusqu'au binaire Purfview.
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { 'whisper.exe' }
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 0
        }
        Mock -ModuleName Tetram.Media.Whisper Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Whisper Show-CommandLine {}
        { Get-MediaTranscript -LiteralPath 'a.mkv' -Model kotoba-v2 -ErrorAction Stop } | Should -Not -Throw
    }

    It 'refuse une langue hors liste' {
        { Get-MediaTranscript -LiteralPath 'a.mkv' -UseLanguage 'French' -ErrorAction Stop } | Should -Throw
    }

    It 'n''accepte aucune entrée pipeline' {
        $meta = Get-Command Get-MediaTranscript
        foreach ($parameter in $meta.Parameters.Values) {
            foreach ($attribute in @($parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })) {
                $attribute.ValueFromPipeline | Should -BeFalse
                $attribute.ValueFromPipelineByPropertyName | Should -BeFalse
            }
        }
    }
}

Describe 'Get-MediaTranscript orchestration' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop
        function New-WhisperTestMedia {
            param(
                [string] $Name = 'Episode.mkv',
                [string] $Folder = 'media'
            )
            $dir = Join-Path $TestDrive $Folder
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $path = Join-Path $dir $Name
            Set-Content -LiteralPath $path -Value 'x'
            (Get-Item -LiteralPath $path).FullName
        }

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
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { 'whisper.exe' }
        Mock -ModuleName Tetram.Media.Whisper Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Whisper Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Whisper Write-DebugLog {}
        Mock -ModuleName Tetram.Media.Whisper Show-CommandLine {}
        $script:SeenArguments = $null
        $script:SeenCalls = $null
    }

    It 'invoque le binaire une seule fois pour un seul média' {
        $media = New-WhisperTestMedia -Name 'a.mkv' -Folder 'once'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -LiteralPath $media
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 1
        $script:SeenArguments[0] | Should -Be $media
        $script:SeenArguments | Should -Not -Contain '--batch_recursive'
        $script:SeenArguments | Should -Contain '--output_format'
        $fmt = [array]::IndexOf(@($script:SeenArguments), '--output_format')
        $script:SeenArguments[$fmt + 1] | Should -Be 'json'
        $ff = [array]::IndexOf(@($script:SeenArguments), '--ff_track')
        $script:SeenArguments[$ff + 1] | Should -Be '1'
    }

    It 'transmet un chemin à crochets tel quel, sans le résoudre en glob' {
        $work = Join-Path $TestDrive 'brackets'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $literal = Join-Path $work 'Episode[1].mkv'
        Set-Content -LiteralPath $literal -Value 'x'
        Set-Content -LiteralPath (Join-Path $work 'Episode1.mkv') -Value 'x'
        $media = (Get-Item -LiteralPath $literal).FullName
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -LiteralPath $literal
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 1
        $script:SeenArguments[0] | Should -Be $media
        $script:SeenArguments[0] | Should -Not -Be (Get-Item -LiteralPath (Join-Path $work 'Episode1.mkv')).FullName
    }

    It 'refuse un masque avant d''invoquer le backend' {
        $work = Join-Path $TestDrive 'mask'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        1..2 | ForEach-Object { Set-Content -LiteralPath (Join-Path $work "f$_.mkv") -Value 'x' }
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'ne doit pas tourner' }
        { Get-MediaTranscript -LiteralPath (Join-Path $work '*.mkv') } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 0
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
    }

    It 'refuse un dossier avant d''invoquer le backend' {
        $dir = Join-Path $TestDrive 'films-dir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'ne doit pas tourner' }
        { Get-MediaTranscript -LiteralPath $dir } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 0
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
    }

    It 'refuse un fichier-liste avant d''invoquer le backend' {
        $lst = Join-Path $TestDrive 'lot.lst'
        Set-Content -LiteralPath $lst -Value 'D:\Films\a.mkv'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'ne doit pas tourner' }
        { Get-MediaTranscript -LiteralPath $lst } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 0
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
    }

    It 'ne throw pas et journalise si le binaire est introuvable' {
        $media = New-WhisperTestMedia -Name 'a.mkv' -Folder 'missing-exe'
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { throw 'faster-whisper-xxl introuvable (test)' }
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'ne doit pas tourner' }
        { Get-MediaTranscript -LiteralPath $media } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 0
    }

    It 'journalise un code de sortie non nul sans lever et sans publier de JSON Tetram' {
        $work = Join-Path $TestDrive 'exit-nonzero'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 1
        }
        { Get-MediaTranscript -LiteralPath $media } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File).Count | Should -Be 0
    }

    It 'ne récupère pas le crash 0xC0000409 pour <Model>' -TestCases @(
        @{ Model = 'large-v2' }
        @{ Model = 'kotoba-v2' }
    ) {
        param($Model)
        $work = Join-Path $TestDrive "crash-other-$Model"
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value $script:RecoverableNativeJson
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Get-MediaTranscript -LiteralPath $media -Model $Model -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-InfoLog -Times 0
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File).Count | Should -Be 0
    }

    It 'ne récupère pas <Model> pour un autre code non nul que 0xC0000409' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $work = Join-Path $TestDrive "other-crash-$Model"
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value $script:RecoverableNativeJson
            $State['ExitCode'] = -1073741819
        }
        { Get-MediaTranscript -LiteralPath $media -Model $Model -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-InfoLog -Times 0
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File).Count | Should -Be 0
    }

    It 'échoue si <Model> crashe en 0xC0000409 sans JSON natif et nettoie le temporaire' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $work = Join-Path $TestDrive "crash-no-json-$Model"
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Get-MediaTranscript -LiteralPath $media -Model $Model -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-InfoLog -Times 0
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File).Count | Should -Be 0
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        Test-Path -LiteralPath $script:SeenArguments[$outIndex + 1] | Should -BeFalse
    }

    It 'échoue si <Model> crashe en 0xC0000409 avec plusieurs JSON natifs' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $work = Join-Path $TestDrive "crash-ambiguous-$Model"
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            $outDir = $Arguments[$outIndex + 1]
            Set-Content -LiteralPath (Join-Path $outDir 'Episode.ja.json') -Value $script:RecoverableNativeJson
            Set-Content -LiteralPath (Join-Path $outDir 'Other.en.json') -Value '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"y"}]}'
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Get-MediaTranscript -LiteralPath $media -Model $Model -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-InfoLog -Times 0
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File).Count | Should -Be 0
    }

    It 'échoue si <Model> crashe en 0xC0000409 avec un JSON natif tronqué et nettoie le temporaire' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $work = Join-Path $TestDrive "crash-truncated-$Model"
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0'
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Get-MediaTranscript -LiteralPath $media -Model $Model -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-InfoLog -Times 0
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File).Count | Should -Be 0
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        Test-Path -LiteralPath $script:SeenArguments[$outIndex + 1] | Should -BeFalse
    }

    It 'échoue si <Model> crashe en 0xC0000409 avec un JSON sans segments exploitable' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $work = Join-Path $TestDrive "crash-no-segments-$Model"
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja"}'
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Get-MediaTranscript -LiteralPath $media -Model $Model -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-InfoLog -Times 0
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File).Count | Should -Be 0
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
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value $script:RecoverableNativeJson
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        { Get-MediaTranscript -LiteralPath $media -Model $Model } | Should -Not -Throw
        $dest = Join-Path $work "Episode.track 1.ja.$Model.json"
        Test-Path -LiteralPath $dest | Should -BeTrue
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 0
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-InfoLog -Times 1 -ParameterFilter {
            $Force -and
            $Text -match 'faster-whisper-xxl' -and
            $Text -match "\(modèle $([regex]::Escape($Model))\)" -and
            $Text -match '-1073740791' -and
            $Text -match '0xC0000409' -and
            $Text -match 'JSON natif exploitable et normalisation Tetram terminée malgré le crash'
        }
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
        $parsed.engine | Should -Be 'faster-whisper'
        $parsed.model | Should -Be $Model
        $parsed.language | Should -Be 'ja'
        $parsed.languageSource | Should -Be 'detected'
        $parsed.audioTrack | Should -Be 1
        $parsed.segments.Count | Should -Be 1
        $parsed.segments[0].start | Should -Be 1.25
        $parsed.segments[0].end | Should -Be 2.50
        $parsed.segments[0].text | Should -Be 'テスト'
        $parsed.segments[0].PSObject.Properties['id'] | Should -BeNullOrEmpty
        $parsed.segments[0].words[0].text | Should -Be 'テスト'
        $parsed.segments[0].words[0].probability | Should -Be 0.95
        $parsed.segments[0].diagnostics.temperature | Should -Be 0.0
        $parsed.segments[0].diagnostics.avg_logprob | Should -Be -0.2
        $parsed.segments[0].diagnostics.compression_ratio | Should -Be 1.1
        $parsed.segments[0].diagnostics.no_speech_prob | Should -Be 0.0
        $parsed.segments[0].diagnostics.tokens | Should -Be @(1, 2, 3)
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        Test-Path -LiteralPath $script:SeenArguments[$outIndex + 1] | Should -BeFalse
    }

    It 'force la langue sur une récupération <Model> comme sur le chemin de succès' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $work = Join-Path $TestDrive "crash-forced-lang-$Model"
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value $script:RecoverableNativeJson
            $State['ExitCode'] = $script:PurfviewCrashExitCode
        }
        Get-MediaTranscript -LiteralPath $media -Model $Model -UseLanguage ja
        $dest = Join-Path $work "Episode.track 1.ja.$Model.json"
        Test-Path -LiteralPath $dest | Should -BeTrue
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
        $parsed.language | Should -Be 'ja'
        $parsed.languageSource | Should -Be 'forced'
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 0
    }

    It 'sous -WhatIf, n''applique aucune récupération <Model>' -TestCases @(
        @{ Model = 'large-v3-turbo' }
        @{ Model = 'large-v3' }
    ) {
        param($Model)
        $work = Join-Path $TestDrive "whatif-crash-$Model"
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        $existing = Join-Path $work 'keep.ja.json'
        Set-Content -LiteralPath $existing -Value '{"language":"ja","segments":[]}'
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { 'X:\binaire-absent-xyz.exe' }
        Get-MediaTranscript -LiteralPath $media -Model $Model -UseLanguage ja -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Whisper Show-CommandLine -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 0
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-InfoLog -Times 0
        Test-Path -LiteralPath $existing | Should -BeTrue
        @(Get-ChildItem -LiteralPath $work -Filter '*.track *.json' -File).Count | Should -Be 0
    }

    It 'journalise une exception d''exécution sans lever' {
        $media = New-WhisperTestMedia -Name 'a.mkv' -Folder 'invoke-throw'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'accès refusé' }
        { Get-MediaTranscript -LiteralPath $media } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
    }

    It 'ne throw pas et journalise si un chemin contient des caractères invalides' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'accès refusé' }
        $illegal = 'D:\foo' + [char]0 + 'bar.mkv'
        { Get-MediaTranscript -LiteralPath $illegal } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
    }

    It 'n''émet rien dans le pipeline' {
        $media = New-WhisperTestMedia -Name 'a.mkv' -Folder 'no-pipeline'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 0
        }
        $out = Get-MediaTranscript -LiteralPath $media
        $out | Should -BeNullOrEmpty
    }

    It 'sous -WhatIf, affiche la commande et ne crée ni ne supprime aucun fichier' {
        $work = Join-Path $TestDrive 'whatif'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        $existing = Join-Path $work 'keep.ja.json'
        Set-Content -LiteralPath $existing -Value '{"language":"ja","segments":[]}'
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { 'X:\binaire-absent-xyz.exe' }
        Mock -ModuleName Tetram.Media.Whisper Show-CommandLine {
            param($Exe, $Arguments)
            $script:SeenArguments = $Arguments
        }
        Get-MediaTranscript -LiteralPath $media -Model large-v3 -UseLanguage ja -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Whisper Show-CommandLine -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 0
        Test-Path -LiteralPath $existing | Should -BeTrue
        @(Get-ChildItem -LiteralPath $work -Filter '*.track *.json' -File).Count | Should -Be 0
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        $outDir = $script:SeenArguments[$outIndex + 1]
        $outDir | Should -Not -Be 'source'
        Test-Path -LiteralPath $outDir | Should -BeFalse
    }

    It 'écrit le JSON Tetram canonique et supprime le JSON natif' {
        $work = Join-Path $TestDrive 'success'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            $outDir = $Arguments[$outIndex + 1]
            Set-Content -LiteralPath (Join-Path $outDir 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -LiteralPath $media -Model large-v3 -UseLanguage ja
        $dest = Join-Path $work 'Episode.track 1.ja.large-v3.json'
        Test-Path -LiteralPath $dest | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $work 'Episode.ja.json') | Should -BeFalse
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        $outDir = $script:SeenArguments[$outIndex + 1]
        $outDir | Should -Not -Be 'source'
        $gotTemp = [IO.Path]::GetFullPath((Split-Path -Parent $outDir)).TrimEnd('\', '/')
        $wantTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
        $gotTemp | Should -Be $wantTemp
        Test-Path -LiteralPath $outDir | Should -BeFalse
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
        $parsed.engine | Should -Be 'faster-whisper'
        $parsed.model | Should -Be 'large-v3'
        $parsed.language | Should -Be 'ja'
        $parsed.languageSource | Should -Be 'forced'
        $parsed.audioTrack | Should -Be 1
        $out = Get-MediaTranscript -LiteralPath $media -Model large-v3 -UseLanguage ja
        $out | Should -BeNullOrEmpty
    }

    It 'remplace un sidecar déjà présent sans sauter l''invocation' {
        $work = Join-Path $TestDrive 'overwrite'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        $dest = Join-Path $work 'Episode.track 1.ja.large-v3.json'
        Set-Content -LiteralPath $dest -Value 'ancien'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":3.0,"end":4.0,"text":"nouveau"}]}'
            $State['ExitCode'] = 0
        }
        { Get-MediaTranscript -LiteralPath $media -Model large-v3 -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 1
        $raw = Get-Content -LiteralPath $dest -Raw -Encoding UTF8
        $raw | Should -Not -Be 'ancien'
        $parsed = ConvertFrom-Json -InputObject $raw
        $parsed.segments[0].text | Should -Be 'nouveau'
        $parsed.engine | Should -Be 'faster-whisper'
    }

    It 'propage -AudioTrack 2 jusqu''à --ff_track, audioTrack et le nom du sidecar' {
        $work = Join-Path $TestDrive 'track2'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -LiteralPath $media -AudioTrack 2 -Model large-v3 -UseLanguage ja
        $ff = [array]::IndexOf(@($script:SeenArguments), '--ff_track')
        $script:SeenArguments[$ff + 1] | Should -Be '2'
        $dest = Join-Path $work 'Episode.track 2.ja.large-v3.json'
        Test-Path -LiteralPath $dest | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $work 'Episode.track 1.ja.large-v3.json') | Should -BeFalse
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
        $parsed.audioTrack | Should -Be 2
    }

    It 'journalise et ne publie pas si le JSON natif est ambigu' {
        $work = Join-Path $TestDrive 'ambiguous'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            $outDir = $Arguments[$outIndex + 1]
            Set-Content -LiteralPath (Join-Path $outDir 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            Set-Content -LiteralPath (Join-Path $outDir 'Other.en.json') -Value '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"y"}]}'
            $State['ExitCode'] = 0
        }
        { Get-MediaTranscript -LiteralPath $media -Model large-v3 -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'nomme le sidecar kotoba-v2 avec le nom canonique du modèle' {
        $work = Join-Path $TestDrive 'kotoba'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -LiteralPath $media -Model kotoba-v2 -UseLanguage ja
        $dest = Join-Path $work 'Episode.track 1.ja.kotoba-v2.json'
        Test-Path -LiteralPath $dest | Should -BeTrue
        $dest | Should -Not -Match 'ctranslate'
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
        $parsed.model | Should -Be 'kotoba-v2'
    }

    It 'invoque une ligne de commande distincte par modèle demandé' {
        $work = Join-Path $TestDrive 'multi-model'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        $script:SeenCalls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenCalls.Add(@($Arguments))
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -LiteralPath $media -Model large-v3, kotoba-v2 -UseLanguage ja
        $script:SeenCalls.Count | Should -Be 2
        $firstModel = [array]::IndexOf(@($script:SeenCalls[0]), '--model')
        $script:SeenCalls[0][$firstModel + 1] | Should -Be 'large-v3'
        $script:SeenCalls[0] | Should -Not -Contain '--condition_on_previous_text'
        $secondModel = [array]::IndexOf(@($script:SeenCalls[1]), '--model')
        $script:SeenCalls[1][$secondModel + 1] | Should -Be 'kotoba-v2'
        $script:SeenCalls[1] | Should -Contain '--condition_on_previous_text'
        Test-Path -LiteralPath (Join-Path $work 'Episode.track 1.ja.large-v3.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $work 'Episode.track 1.ja.kotoba-v2.json') | Should -BeTrue
        $kotoba = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $work 'Episode.track 1.ja.kotoba-v2.json') -Raw -Encoding UTF8)
        $kotoba.model | Should -Be 'kotoba-v2'
    }

    It 'poursuit les modèles suivants si une invocation échoue' {
        $work = Join-Path $TestDrive 'multi-model-fail'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $modelIndex = [array]::IndexOf(@($Arguments), '--model')
            if ($Arguments[$modelIndex + 1] -eq 'large-v3') {
                $State['ExitCode'] = 1
                return
            }
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value '{"language":"ja","segments":[{"start":1.0,"end":2.0,"text":"x"}]}'
            $State['ExitCode'] = 0
        }
        { Get-MediaTranscript -LiteralPath $media -Model large-v3, kotoba-v2 -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 2
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        Test-Path -LiteralPath (Join-Path $work 'Episode.track 1.ja.large-v3.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $work 'Episode.track 1.ja.kotoba-v2.json') | Should -BeTrue
    }

    It 'sous -WhatIf, affiche une commande par modèle sans créer de fichier' {
        $work = Join-Path $TestDrive 'whatif-multi'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        $script:SeenCalls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { 'X:\binaire-absent-xyz.exe' }
        Mock -ModuleName Tetram.Media.Whisper Show-CommandLine {
            param($Exe, $Arguments)
            $script:SeenCalls.Add(@($Arguments))
        }
        Get-MediaTranscript -LiteralPath $media -Model large-v3, kotoba-v2 -UseLanguage ja -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Whisper Show-CommandLine -Times 2
        $script:SeenCalls.Count | Should -Be 2
        @(Get-ChildItem -LiteralPath $work -Filter '*.track *.json' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        foreach ($args in $script:SeenCalls) {
            $outIndex = [array]::IndexOf(@($args), '--output_dir')
            Test-Path -LiteralPath $args[$outIndex + 1] | Should -BeFalse
        }
    }

    It 'reprend la langue détectée du JSON natif sans -UseLanguage' {
        $work = Join-Path $TestDrive 'detected'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.en.json') -Value '{"language":"en","segments":[{"start":1.0,"end":2.0,"text":"hi"}]}'
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -LiteralPath $media -Model large-v3
        $dest = Join-Path $work 'Episode.track 1.en.large-v3.json'
        Test-Path -LiteralPath $dest | Should -BeTrue
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
        $parsed.language | Should -Be 'en'
        $parsed.languageSource | Should -Be 'detected'
    }

    It 'ne laisse pas de JSON Tetram partiel si le JSON natif est invalide' {
        $work = Join-Path $TestDrive 'invalid'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $media = Join-Path $work 'Episode.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $outIndex = [array]::IndexOf(@($Arguments), '--output_dir')
            Set-Content -LiteralPath (Join-Path $Arguments[$outIndex + 1] 'Episode.ja.json') -Value 'not-json'
            $State['ExitCode'] = 0
        }
        { Get-MediaTranscript -LiteralPath $media -Model large-v3 -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        @(Get-ChildItem -LiteralPath $work -Filter '*.json' -File).Count | Should -Be 0
        $outIndex = [array]::IndexOf(@($script:SeenArguments), '--output_dir')
        Test-Path -LiteralPath $script:SeenArguments[$outIndex + 1] | Should -BeFalse
    }
}

Describe 'Get-MediaTranscript bout en bout' -Tag 'Integration' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootWhisper -Force -ErrorAction Stop
        $script:PurfviewRoot = Join-Path $script:ModuleRootWhisper 'Purfview-Whisper-Faster'
        $script:RealExe = Join-Path $script:PurfviewRoot 'faster-whisper-xxl.exe'
        $script:RealFfmpeg = Join-Path $script:PurfviewRoot 'ffmpeg.exe'
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Whisper' -Force -ErrorAction SilentlyContinue
    }

    It 'produit un JSON Tetram à côté de la source' {
        if (-not (Test-Path -LiteralPath $script:RealExe -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'distribution Purfview absente'
            return
        }

        $work = Join-Path $TestDrive 'integration'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $wav = Join-Path $work 'sample.wav'
        & $script:RealFfmpeg -f lavfi -i 'sine=frequency=440:duration=3' -y $wav 2>&1 | Out-Null

        Get-MediaTranscript -LiteralPath $wav -UseLanguage en

        $dest = Join-Path $work 'sample.track 1.en.large-v2.json'
        Test-Path -LiteralPath $dest | Should -BeTrue
        @(Get-ChildItem -LiteralPath $work -Filter '*.srt' -File).Count | Should -Be 0
        $native = @(Get-ChildItem -LiteralPath $work -Filter 'sample.en.json' -File)
        $native.Count | Should -Be 0
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
        $parsed.engine | Should -Be 'faster-whisper'
        $parsed.model | Should -Be 'large-v2'
        $parsed.language | Should -Be 'en'
        $parsed.languageSource | Should -Be 'forced'
        $parsed.audioTrack | Should -Be 1
        $parsed.PSObject.Properties['segments'] | Should -Not -BeNullOrEmpty
    }
}
