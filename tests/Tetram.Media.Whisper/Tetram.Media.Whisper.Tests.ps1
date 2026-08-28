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
        # N'invoque jamais la cmdlet sans lier -Path ni -LiteralPath : PowerShell ne lèverait pas
        # d'erreur de binding mais déclencherait son prompt interactif natif pour le paramètre
        # obligatoire manquant, qui bloque en console réelle (seul un hôte non interactif comme la CI
        # échoue immédiatement). On vérifie donc l'obligation via les métadonnées des jeux de paramètres.
        $meta = Get-Command Get-MediaTranscript
        foreach ($setName in @($meta.ParameterSets | Select-Object -ExpandProperty Name)) {
            $set = $meta.ParameterSets | Where-Object Name -EQ $setName
            $sourceParams = @($set.Parameters | Where-Object { $_.Name -in @('Path', 'LiteralPath') -and $_.IsMandatory })
            $sourceParams.Count | Should -BeGreaterThan 0 -Because "le jeu '$setName' doit exiger Path ou LiteralPath"
        }
    }

    It 'refuse un format hors liste' {
        { Get-MediaTranscript -Path 'a.mkv' -Format 'docx' -ErrorAction Stop } | Should -Throw
    }

    It 'refuse un modèle hors liste' {
        { Get-MediaTranscript -Path 'a.mkv' -Model 'tiny' -ErrorAction Stop } | Should -Throw
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
        { Get-MediaTranscript -Path 'a.mkv' -Model kotoba-v2 -ErrorAction Stop } | Should -Not -Throw
    }

    It 'refuse une langue hors liste' {
        { Get-MediaTranscript -Path 'a.mkv' -UseLanguage 'French' -ErrorAction Stop } | Should -Throw
    }

    It 'expose trois jeux de paramètres dont Path par défaut' {
        $meta = Get-Command Get-MediaTranscript
        $meta.DefaultParameterSet | Should -Be 'Path'
        @($meta.ParameterSets | Select-Object -ExpandProperty Name | Sort-Object) | Should -Be @('LiteralPath', 'Mixed', 'Path')
    }

    It 'rend -Path positionnel dans Path et nommé dans Mixed' {
        $meta = Get-Command Get-MediaTranscript
        $inPath = ($meta.ParameterSets | Where-Object Name -EQ 'Path').Parameters | Where-Object Name -EQ 'Path'
        $inMixed = ($meta.ParameterSets | Where-Object Name -EQ 'Mixed').Parameters | Where-Object Name -EQ 'Path'
        $inPath.Position | Should -Be 0
        $inMixed.Position | Should -Be ([int]::MinValue)
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
    }

    It 'invoque le binaire une seule fois pour tout le lot' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -Path @('D:\a.mkv', 'D:\b.mkv')
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 1
        $script:SeenArguments[0] | Should -Be 'D:\a.mkv'
        $script:SeenArguments[1] | Should -Be 'D:\b.mkv'
    }

    It 'concatène -Path puis -LiteralPath dans le jeu Mixed' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $script:SeenArguments = $Arguments
            $State['ExitCode'] = 0
        }
        Get-MediaTranscript -Path 'D:\Films\*.mkv' -LiteralPath 'D:\Films\film[1].mkv'
        $script:SeenArguments[0] | Should -Be 'D:\Films\*.mkv'
        # LiteralPath n'est pas glob-échappé : whisper teste l'existence avant de globaliser, et
        # film[[]1].mkv ne serait pas trouvé (décision Task 6 / spec, pas ConvertTo-GlobLiteral).
        $script:SeenArguments[1] | Should -Be 'D:\Films\film[1].mkv'
    }

    It 'ne lance rien et journalise si toutes les entrées résolvent à vide' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'ne doit pas tourner' }
        Get-MediaTranscript -Path (Join-Path $TestDrive 'rien[9].mkv')
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 0
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-InfoLog -Times 1
    }

    It 'ne throw pas et journalise si le binaire est introuvable' {
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { throw 'faster-whisper-xxl introuvable (test)' }
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'ne doit pas tourner' }
        { Get-MediaTranscript -Path 'D:\a.mkv' } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 0
    }

    It 'journalise un code de sortie non nul sans lever' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 1
        }
        { Get-MediaTranscript -Path 'D:\a.mkv' } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
    }

    It 'journalise une exception d''exécution sans lever' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'accès refusé' }
        { Get-MediaTranscript -Path 'D:\a.mkv' } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
    }

    It 'ne throw pas et journalise si un chemin contient des caractères invalides' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper { throw 'accès refusé' }
        $illegal = 'D:\foo' + [char]0 + 'bar.mkv'
        { Get-MediaTranscript -LiteralPath $illegal } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 1
    }

    It 'transmet une source inexistante sans erreur' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 0
        }
        { Get-MediaTranscript -Path (Join-Path $TestDrive 'absent.mkv') } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 0
        Should -Invoke -ModuleName Tetram.Media.Whisper Invoke-Whisper -Times 1
    }

    It 'n''émet rien dans le pipeline' {
        Mock -ModuleName Tetram.Media.Whisper Invoke-Whisper {
            param($Exe, $Arguments, $Cmdlet, $State)
            $State['ExitCode'] = 0
        }
        $out = Get-MediaTranscript -Path 'D:\a.mkv'
        $out | Should -BeNullOrEmpty
    }

    It 'sous -WhatIf, affiche la commande et ne lance pas le binaire' {
        # Invoke-Whisper n'est volontairement pas mocké : avec un exe inexistant, toute exécution réelle
        # lèverait et déclencherait Write-ErrorLog.
        Mock -ModuleName Tetram.Media.Whisper Get-WhisperPath { 'X:\binaire-absent-xyz.exe' }
        Get-MediaTranscript -Path 'D:\a.mkv' -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Whisper Show-CommandLine -Times 1
        Should -Invoke -ModuleName Tetram.Media.Whisper Write-ErrorLog -Times 0
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

    It 'produit un .srt à côté de la source' {
        if (-not (Test-Path -LiteralPath $script:RealExe -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'distribution Purfview absente'
            return
        }

        $work = Join-Path $TestDrive 'integration'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $wav = Join-Path $work 'sample.wav'
        & $script:RealFfmpeg -f lavfi -i 'sine=frequency=440:duration=3' -y $wav 2>&1 | Out-Null

        Get-MediaTranscript -Path $wav -UseLanguage en

        @(Get-ChildItem -LiteralPath $work -Filter '*.srt').Count | Should -BeGreaterThan 0
    }
}
