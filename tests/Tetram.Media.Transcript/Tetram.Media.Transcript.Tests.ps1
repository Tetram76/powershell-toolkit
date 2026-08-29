# Étendre la suite autour du module SUD Tetram.Media.Transcript.
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Manifeste : Tetram.Media.Transcript/Tetram.Media.Transcript.psd1 — Test-ModuleManifest puis Import-Module -Force
# Orchestration : mocks Invoke-TranscriptBackend / Publish-TetramTranscript / Write-*Log.
# Les helpers Whisper/Sherpa ne doivent pas exister avant le chargement paresseux du backend.
# Le vrai binaire n'est appelé que sous le tag Integration.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranscript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ModuleRootTranscript = Join-Path $script:RepoRootTranscript 'Tetram.Media.Transcript'
    $script:ManifestTranscript = Join-Path $script:ModuleRootTranscript 'Tetram.Media.Transcript.psd1'
}

Describe 'Tetram.Media.Transcript manifest' {
    It 'passe Test-ModuleManifest' {
        { Test-ModuleManifest -Path $script:ManifestTranscript -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'Tetram.Media.Transcript exports' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
    }

    It 'exporte uniquement Get-MediaTranscript' {
        $names = @(Get-Command -Module 'Tetram.Media.Transcript' | Select-Object -ExpandProperty Name | Sort-Object)
        $names | Should -Be @('Get-MediaTranscript')
    }
}

Describe 'Get-MediaTranscript binding' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
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

        # Binding seulement : le backend est mocké pour ne pas entrer dans un moteur.
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend { $null }
        Mock -ModuleName Tetram.Media.Transcript Write-ErrorLog {}
        { Get-MediaTranscript -LiteralPath 'a.mkv' -Model kotoba-v2 -ErrorAction Stop } | Should -Not -Throw
    }

    It 'accepte reazon-k2-v2 comme modèle' {
        $validate = (Get-Command Get-MediaTranscript).Parameters['Model'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        @($validate.ValidValues) | Should -Contain 'reazon-k2-v2'

        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend { $null }
        Mock -ModuleName Tetram.Media.Transcript Write-ErrorLog {}
        { Get-MediaTranscript -LiteralPath 'a.mkv' -Model reazon-k2-v2 -ErrorAction Stop } | Should -Not -Throw
    }

    It 'accepte <Model> comme modèle Sherpa' -TestCases @(
        @{ Model = 'parakeet-0.6b-ja' }
        @{ Model = 'sensevoice-small' }
    ) {
        param($Model)
        $validate = (Get-Command Get-MediaTranscript).Parameters['Model'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        @($validate.ValidValues) | Should -Contain $Model

        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend { $null }
        Mock -ModuleName Tetram.Media.Transcript Write-ErrorLog {}
        { Get-MediaTranscript -LiteralPath 'a.mkv' -Model $Model -ErrorAction Stop } | Should -Not -Throw
    }

    It 'n''expose plus -WhisperPath' {
        (Get-Command Get-MediaTranscript).Parameters.ContainsKey('WhisperPath') | Should -BeFalse
    }

    It 'n''expose pas de paramètre public spécifique à Sherpa' {
        $names = @((Get-Command Get-MediaTranscript).Parameters.Keys)
        $names | Should -Not -Contain 'SherpaOnnxPath'
        $names | Should -Not -Contain 'SherpaPath'
        $names | Should -Not -Contain 'Engine'
        $names | Should -Not -Contain 'Vad'
        $names | Should -Not -Contain 'SherpaModelType'
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
        Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop
        function New-TranscriptTestMedia {
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
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName Tetram.Media.Transcript Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Transcript Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Transcript Write-DebugLog {}
        Mock -ModuleName Tetram.Media.Transcript Publish-TetramTranscript {}
        $script:SeenBackend = [System.Collections.Generic.List[hashtable]]::new()
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend {
            param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, $WhatIf, $Result)
            $script:SeenBackend.Add(@{
                    MediaPath   = $MediaPath
                    Model       = $Model
                    AudioTrack  = $AudioTrack
                    UseLanguage = $UseLanguage
                    WhatIf      = [bool]$WhatIf
                    Bound       = @($PSBoundParameters.Keys)
                })
            [void]$Result.Transcripts.Add([pscustomobject]@{
                    language   = 'ja'
                    model      = $Model
                    audioTrack = $AudioTrack
                    segments   = @()
                })
        }
    }

    It 'appelle le backend une fois puis publie le transcript canonique' {
        $media = New-TranscriptTestMedia -Name 'a.mkv' -Folder 'once'
        Get-MediaTranscript -LiteralPath $media
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 1
        $script:SeenBackend.Count | Should -Be 1
        $script:SeenBackend[0].MediaPath | Should -Be $media
        $script:SeenBackend[0].Model | Should -Be 'large-v2'
        $script:SeenBackend[0].AudioTrack | Should -Be 1
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 1 -ParameterFilter {
            $MediaPath -eq $media -and $Transcript.model -eq 'large-v2' -and $Transcript.language -eq 'ja'
        }
    }

    It 'transmet un chemin à crochets tel quel, sans le résoudre en glob' {
        $work = Join-Path $TestDrive 'brackets'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $literal = Join-Path $work 'Episode[1].mkv'
        Set-Content -LiteralPath $literal -Value 'x'
        Set-Content -LiteralPath (Join-Path $work 'Episode1.mkv') -Value 'x'
        $media = (Get-Item -LiteralPath $literal).FullName
        Get-MediaTranscript -LiteralPath $literal
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 1
        $script:SeenBackend[0].MediaPath | Should -Be $media
        $script:SeenBackend[0].MediaPath | Should -Not -Be (Get-Item -LiteralPath (Join-Path $work 'Episode1.mkv')).FullName
    }

    It 'refuse un masque avant d''appeler le backend' {
        $work = Join-Path $TestDrive 'mask'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        1..2 | ForEach-Object { Set-Content -LiteralPath (Join-Path $work "f$_.mkv") -Value 'x' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend { throw 'ne doit pas tourner' }
        { Get-MediaTranscript -LiteralPath (Join-Path $work '*.mkv') } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-ErrorLog -Times 1
    }

    It 'refuse un dossier avant d''appeler le backend' {
        $dir = Join-Path $TestDrive 'films-dir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend { throw 'ne doit pas tourner' }
        { Get-MediaTranscript -LiteralPath $dir } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-ErrorLog -Times 1
    }

    It 'passe un fichier-liste au backend : la contrainte liste n''est pas dans l''orchestrateur' {
        $lst = Join-Path $TestDrive 'lot.lst'
        Set-Content -LiteralPath $lst -Value (Join-Path 'Films' 'a.mkv')
        Get-MediaTranscript -LiteralPath $lst
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 1
        $script:SeenBackend[0].MediaPath | Should -Be (Get-Item -LiteralPath $lst).FullName
    }

    It 'ne throw pas et journalise si le backend échoue, sans publier' {
        $media = New-TranscriptTestMedia -Name 'a.mkv' -Folder 'backend-throw'
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend { throw 'échec moteur' }
        { Get-MediaTranscript -LiteralPath $media } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 0
    }

    It 'ne throw pas et journalise si un chemin contient des caractères invalides' {
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend { throw 'ne doit pas tourner' }
        $illegal = 'D:\foo' + [char]0 + 'bar.mkv'
        { Get-MediaTranscript -LiteralPath $illegal } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 0
    }

    It 'n''émet rien dans le pipeline' {
        $media = New-TranscriptTestMedia -Name 'a.mkv' -Folder 'no-pipeline'
        $out = Get-MediaTranscript -LiteralPath $media
        $out | Should -BeNullOrEmpty
    }

    It 'n''appelle pas Publish si le backend ne dépose aucun transcript' {
        $media = New-TranscriptTestMedia -Name 'a.mkv' -Folder 'null-backend'
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend { }
        Get-MediaTranscript -LiteralPath $media
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 1
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 0
    }

    It 'sous -WhatIf, transmet WhatIf au backend et ne publie pas si le backend est muet' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'whatif'
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend {
            param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, $WhatIf, $Result)
            $script:SeenBackend.Add(@{ WhatIf = [bool]$WhatIf; Model = $Model })
        }
        Get-MediaTranscript -LiteralPath $media -Model large-v3 -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 1
        $script:SeenBackend[0].WhatIf | Should -BeTrue
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-ErrorLog -Times 0
    }

    It 'transmet -AudioTrack et -UseLanguage au backend' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'track2'
        Get-MediaTranscript -LiteralPath $media -AudioTrack 2 -Model large-v3 -UseLanguage ja
        $script:SeenBackend[0].AudioTrack | Should -Be 2
        $script:SeenBackend[0].UseLanguage | Should -Be 'ja'
        $script:SeenBackend[0].Model | Should -Be 'large-v3'
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 1 -ParameterFilter {
            $Transcript.audioTrack -eq 2 -and $Transcript.model -eq 'large-v3'
        }
    }

    It 'ne transmet aucun chemin d''exécutable au backend' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'no-exe-path'
        Get-MediaTranscript -LiteralPath $media -Model large-v3
        $script:SeenBackend[0].Bound | Should -Not -Contain 'WhisperPath'
        $script:SeenBackend[0].Bound | Should -Not -Contain 'SherpaOnnxPath'
        (Get-Command Get-MediaTranscript).Parameters.ContainsKey('WhisperPath') | Should -BeFalse
    }

    It 'publie chaque transcript explicitement déposé, notamment Silero puis TEN' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'multi-transcript'
        $script:PublishedModels = [System.Collections.Generic.List[string]]::new()
        $script:PublishedVads = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Tetram.Media.Transcript Publish-TetramTranscript {
            param($Transcript, $MediaPath)
            $script:PublishedModels.Add([string]$Transcript.model)
            $script:PublishedVads.Add([string]$Transcript.vad)
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend {
            param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, $WhatIf, $Result)
            foreach ($vad in @('silero', 'ten')) {
                [void]$Result.Transcripts.Add([pscustomobject]@{
                        language   = 'ja'
                        model      = 'reazon-k2-v2'
                        vad        = $vad
                        audioTrack = 1
                        segments   = @()
                    })
            }
        }
        Get-MediaTranscript -LiteralPath $media -Model reazon-k2-v2 -UseLanguage ja
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 1
        $script:PublishedModels | Should -Be @('reazon-k2-v2', 'reazon-k2-v2')
        $script:PublishedVads | Should -Be @('silero', 'ten')
    }

    It 'ignore une sortie parasite du success stream et publie uniquement Result.Transcripts' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'parasite-stream'
        $script:Published = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName Tetram.Media.Transcript Publish-TetramTranscript {
            param($Transcript, $MediaPath)
            # Rejoue l'accès métier : une chaîne de progression n'a pas .language.
            $script:Published.Add([pscustomobject]@{
                    language = $Transcript.language
                    model    = $Transcript.model
                })
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend {
            param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, $WhatIf, $Result)
            'Progress 47%'
            [void]$Result.Transcripts.Add([pscustomobject]@{
                    language   = 'ja'
                    model      = $Model
                    audioTrack = $AudioTrack
                    segments   = @()
                })
        }
        { Get-MediaTranscript -LiteralPath $media } | Should -Not -Throw
        $script:Published.Count | Should -Be 1
        $script:Published[0].language | Should -Be 'ja'
        $script:Published[0].model | Should -Be 'large-v2'
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 1 -ParameterFilter {
            $Transcript -isnot [string] -and $Transcript.language -eq 'ja'
        }
    }

    It 'ne publie pas un transcript déjà déposé si l''invocation backend échoue ensuite' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'partial-then-throw'
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend {
            param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, $WhatIf, $Result)
            [void]$Result.Transcripts.Add([pscustomobject]@{
                    language   = 'ja'
                    model      = $Model
                    vad        = 'silero'
                    audioTrack = 1
                    segments   = @()
                })
            throw 'échec TEN'
        }
        { Get-MediaTranscript -LiteralPath $media -Model reazon-k2-v2 } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 0
    }

    It 'appelle le backend une fois par modèle et publie chaque transcript' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'multi-model'
        Get-MediaTranscript -LiteralPath $media -Model large-v3, kotoba-v2 -UseLanguage ja
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 2
        $script:SeenBackend.Count | Should -Be 2
        $script:SeenBackend[0].Model | Should -Be 'large-v3'
        $script:SeenBackend[1].Model | Should -Be 'kotoba-v2'
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 2
    }

    It 'poursuit les modèles suivants si un backend échoue' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'multi-model-fail'
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend {
            param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, $WhatIf, $Result)
            if ($Model -eq 'large-v3') {
                throw 'échec moteur'
            }
            [void]$Result.Transcripts.Add([pscustomobject]@{
                    language   = 'ja'
                    model      = $Model
                    audioTrack = 1
                    segments   = @()
                })
        }
        { Get-MediaTranscript -LiteralPath $media -Model large-v3, kotoba-v2 -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 2
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 1 -ParameterFilter {
            $Transcript.model -eq 'kotoba-v2'
        }
    }

    It 'sous -WhatIf, appelle le backend une fois par modèle sans publier' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'whatif-multi'
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend {
            param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, $WhatIf, $Result)
            $script:SeenBackend.Add(@{ Model = $Model; WhatIf = [bool]$WhatIf })
        }
        Get-MediaTranscript -LiteralPath $media -Model large-v3, kotoba-v2 -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 2
        $script:SeenBackend.Count | Should -Be 2
        $script:SeenBackend[0].WhatIf | Should -BeTrue
        $script:SeenBackend[1].WhatIf | Should -BeTrue
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 0
    }

    It 'appelle le backend une fois par modèle même si les moteurs diffèrent' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'multi-engine'
        Get-MediaTranscript -LiteralPath $media -Model large-v3, reazon-k2-v2 -UseLanguage ja
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 2
        $script:SeenBackend[0].Model | Should -Be 'large-v3'
        $script:SeenBackend[1].Model | Should -Be 'reazon-k2-v2'
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 2
    }

    It 'invoque les modèles Sherpa dans l''ordre demandé' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'multi-sherpa-order'
        Get-MediaTranscript -LiteralPath $media -Model large-v2, reazon-k2-v2, parakeet-0.6b-ja, sensevoice-small
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 4
        $script:SeenBackend.Count | Should -Be 4
        $script:SeenBackend[0].Model | Should -Be 'large-v2'
        $script:SeenBackend[1].Model | Should -Be 'reazon-k2-v2'
        $script:SeenBackend[2].Model | Should -Be 'parakeet-0.6b-ja'
        $script:SeenBackend[3].Model | Should -Be 'sensevoice-small'
    }

    It 'poursuit un modèle Sherpa si un modèle Whisper échoue' {
        $media = New-TranscriptTestMedia -Name 'Episode.mkv' -Folder 'multi-engine-fail'
        Mock -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend {
            param($MediaPath, $Model, $Cmdlet, $AudioTrack, $UseLanguage, $WhatIf, $Result)
            if ($Model -eq 'large-v3') {
                throw 'échec whisper'
            }
            [void]$Result.Transcripts.Add([pscustomobject]@{
                    language   = 'ja'
                    model      = $Model
                    audioTrack = 1
                    segments   = @()
                })
        }
        { Get-MediaTranscript -LiteralPath $media -Model large-v3, reazon-k2-v2 -UseLanguage ja } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-TranscriptBackend -Times 2
        Should -Invoke -ModuleName Tetram.Media.Transcript Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Transcript Publish-TetramTranscript -Times 1 -ParameterFilter {
            $Transcript.model -eq 'reazon-k2-v2'
        }
    }
}

Describe 'Get-MediaTranscript bout en bout' -Tag 'Integration' {
    BeforeAll {
        Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop
        $script:PurfviewRoot = Join-Path $script:ModuleRootTranscript 'Purfview-Whisper-Faster'
        $script:RealExe = Join-Path $script:PurfviewRoot 'faster-whisper-xxl.exe'
        $script:RealFfmpeg = Join-Path $script:PurfviewRoot 'ffmpeg.exe'
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
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
