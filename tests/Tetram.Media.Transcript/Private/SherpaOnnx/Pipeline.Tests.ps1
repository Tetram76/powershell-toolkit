# Étendre la suite autour de l'orchestration Sherpa (modèle × Silero/TEN).
#
# Tout passe par InModuleScope 'Tetram.Media.Transcript' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Les binaires natifs sont mockés. Les tests vérifient les interactions, pas chaque combinaison déjà
# couverte dans Model/Vad/Asr/Normalize.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranscript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
    $script:ModuleRootTranscript = Join-Path $script:RepoRootTranscript 'Tetram.Media.Transcript'
    Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop

    $module = Get-Module -Name 'Tetram.Media.Transcript'
    . $module {
        . (Join-Path $script:TranscriptPrivateRoot 'SherpaOnnx.ps1')
    }

    $script:FakeCmdlet = [PSCustomObject]@{}
    $script:FakeCmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $true }

    function New-SherpaTestResult {
        @{
            Transcripts = [System.Collections.Generic.List[object]]::new()
        }
    }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-SherpaOnnxTranscript' {
    BeforeEach {
        Mock -ModuleName Tetram.Media.Transcript Write-DebugLog {}
        Mock -ModuleName Tetram.Media.Transcript Show-CommandLine {}
        $script:FakeSherpaDir = Join-Path $TestDrive 'sherpa-dist'
        New-Item -ItemType Directory -Path $script:FakeSherpaDir -Force | Out-Null
        $script:FakeVadExe = Join-Path $script:FakeSherpaDir 'sherpa-onnx-vad.exe'
        $script:FakeOfflineExe = Join-Path $script:FakeSherpaDir 'sherpa-onnx-offline.exe'
        Set-Content -LiteralPath $script:FakeVadExe -Value 'stub'
        Set-Content -LiteralPath $script:FakeOfflineExe -Value 'stub'
        Set-Content -LiteralPath (Join-Path $script:FakeSherpaDir 'silero_vad.onnx') -Value 'stub'
        Set-Content -LiteralPath (Join-Path $script:FakeSherpaDir 'ten-vad.onnx') -Value 'stub'
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxNativeExecutable {
            param($Name)
            if ($Name -eq 'sherpa-onnx-vad') { return $script:FakeVadExe }
            return $script:FakeOfflineExe
        }
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxModelFiles {
            [pscustomobject]@{
                Tokens  = 'tokens.txt'
                Encoder = 'encoder.onnx'
                Decoder = 'decoder.onnx'
                Joiner  = 'joiner.onnx'
            }
        }
        Mock -ModuleName Tetram.Media.Transcript Get-FFmpegPath { 'ffmpeg.exe' }
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxTimelineOffset { 0 }
        $script:SeenFfmpeg = [System.Collections.Generic.List[object]]::new()
        $script:SeenSherpaCalls = [System.Collections.Generic.List[object]]::new()
        $script:SeenWav = $null
    }

    It 'enchaîne VAD puis ASR offline sur des chunks du WAV maître, Silero puis TEN' {
        $media = Join-Path $TestDrive 'track.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg {
            param($Arguments)
            $script:SeenFfmpeg.Add([string[]]@($Arguments))
            $out = $Arguments[-1]
            if ($Arguments -contains '-map') {
                $script:SeenWav = $out
            }
            $parent = Split-Path -Parent $out
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Set-Content -LiteralPath $out -Value 'RIFF'
            return 0
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx {
            param($Exe, $Arguments, $State)
            $script:SeenSherpaCalls.Add([pscustomobject]@{
                    Exe       = $Exe
                    Arguments = [string[]]@($Arguments)
                })
            $State['ExitCode'] = 0
            if ($Exe -eq $script:FakeVadExe) {
                $State['Stdout'] = ''
                $State['Stderr'] = "VadModelConfig(...)`n0.080 -- 1.320`n2.560 -- 4.800`nSaved to speech.wav"
            }
            else {
                $State['Stdout'] = @(
                    '{"text":"こんにちは","tokens":["こん"],"timestamps":[0.00]}'
                    '{"text":"どうしたの","tokens":["どう"],"timestamps":[0.08]}'
                ) -join "`n"
            }
        }

        $result = New-SherpaTestResult
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
            Result = $result
        } {
            param($Media, $Cmdlet, $Result)
            Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -AudioTrack 2 -Cmdlet $Cmdlet -Result $Result
        }

        $script:SeenSherpaCalls.Count | Should -Be 4
        $script:SeenSherpaCalls[0].Exe | Should -Be $script:FakeVadExe
        $script:SeenSherpaCalls[1].Exe | Should -Be $script:FakeOfflineExe
        $script:SeenSherpaCalls[2].Exe | Should -Be $script:FakeVadExe
        $script:SeenSherpaCalls[3].Exe | Should -Be $script:FakeOfflineExe
        ($script:SeenSherpaCalls[0].Arguments -join ' ') | Should -Match 'silero-vad-model'
        ($script:SeenSherpaCalls[0].Arguments -join ' ') | Should -Not -Match 'tokens'
        ($script:SeenSherpaCalls[1].Arguments -join ' ') | Should -Match 'encoder='
        ($script:SeenSherpaCalls[1].Arguments -join ' ') | Should -Not -Match 'silero-vad'
        ($script:SeenSherpaCalls[1].Arguments -join ' ') | Should -Not -Match 'num-threads'
        $script:SeenSherpaCalls[1].Arguments[-2] | Should -Match 'chunk-'
        $script:SeenSherpaCalls[1].Arguments[-1] | Should -Match 'chunk-'

        $chunkCalls = @($script:SeenFfmpeg | Where-Object { $_ -contains '-af' })
        $chunkCalls.Count | Should -BeGreaterThan 0
        foreach ($call in $chunkCalls) {
            $call[-1] | Should -Not -Match 'speech\.wav'
            ($call -join ' ') | Should -Match ([regex]::Escape($script:SeenWav))
        }

        $got = @($result.Transcripts)
        $got.Count | Should -Be 2
        $got[0].engine | Should -Be 'sherpa-onnx'
        $got[0].model | Should -Be 'reazon-k2-v2'
        $got[0].vad | Should -Be 'silero'
        $got[0].audioTrack | Should -Be 2
        $got[0].segments[0].text | Should -Be 'こんにちは'
        $got[0].segments[0].diagnostics.tokens | Should -Be @('こん')
        $got[0].segments[0].diagnostics.timestamps | Should -Be @(0.08)
        $got[1].vad | Should -Be 'ten'
        $got[1].segments[1].text | Should -Be 'どうしたの'
        Test-Path -LiteralPath $script:SeenWav | Should -BeFalse
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
            $result = @{ Transcripts = [System.Collections.Generic.List[object]]::new() }
            { Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -UseLanguage 'en' -Cmdlet $Cmdlet -Result $result } |
                Should -Throw '*incompatible*'
        }
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-FFmpeg -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx -Times 0
    }

    It 'sous -WhatIf n''exécute aucun binaire ni ne crée de TEMP' {
        $media = Join-Path $TestDrive 'whatif.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg { throw 'ne doit pas tourner' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx { throw 'ne doit pas tourner' }
        $result = New-SherpaTestResult
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
            Result = $result
        } {
            param($Media, $Cmdlet, $Result)
            Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet -Result $Result -WhatIf
        }
        $result.Transcripts | Should -HaveCount 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-FFmpeg -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Get-SherpaOnnxTimelineOffset -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Show-CommandLine -Times 3
    }

    It 'n''appelle ni ffprobe ni FFmpeg si ShouldProcess refuse' {
        $media = Join-Path $TestDrive 'confirm.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        $cmdlet = [PSCustomObject]@{}
        $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $false }
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg { throw 'ne doit pas tourner' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx { throw 'ne doit pas tourner' }
        $result = New-SherpaTestResult
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $cmdlet
            Result = $result
        } {
            param($Media, $Cmdlet, $Result)
            Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet -Result $Result
        }
        $result.Transcripts | Should -HaveCount 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Get-SherpaOnnxTimelineOffset -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-FFmpeg -Times 0
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx -Times 0
    }

    It 'applique l''offset de piste aux segments et aux timestamps token' {
        $media = Join-Path $TestDrive 'offset.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxTimelineOffset { 10 }
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg {
            param($Arguments)
            $out = $Arguments[-1]
            $parent = Split-Path -Parent $out
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Set-Content -LiteralPath $out -Value 'RIFF'
            return 0
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx {
            param($Exe, $Arguments, $State)
            $State['ExitCode'] = 0
            if ($Exe -eq $script:FakeVadExe) {
                $State['Stdout'] = ''
                $State['Stderr'] = '0.080 -- 1.320'
            }
            else {
                $State['Stdout'] = '{"text":"こんにちは","tokens":["こん"],"timestamps":[0.16]}'
            }
        }
        $result = New-SherpaTestResult
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
            Result = $result
        } {
            param($Media, $Cmdlet, $Result)
            Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet -Result $Result
        }
        $got = @($result.Transcripts)
        $got.Count | Should -Be 2
        foreach ($transcript in $got) {
            $transcript.segments[0].start | Should -Be 10.08
            $transcript.segments[0].end | Should -Be 11.32
            $transcript.segments[0].diagnostics.timestamps | Should -Be @(10.24)
        }
    }

    It 'un batch offline tardif en échec n''ajoute aucun transcript' {
        $media = Join-Path $TestDrive 'batch-fail.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg {
            param($Arguments)
            $out = $Arguments[-1]
            $parent = Split-Path -Parent $out
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Set-Content -LiteralPath $out -Value 'RIFF'
            return 0
        }
        $result = New-SherpaTestResult
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
            Result = $result
        } {
            param($Media, $Cmdlet, $Result)
            $script:SherpaOnnxOfflineBatchSize = 1
            $script:OfflineHits = 0
            Mock Invoke-SherpaOnnx {
                param($Exe, $Arguments, $State)
                if ($Exe -like '*sherpa-onnx-vad.exe') {
                    $State['ExitCode'] = 0
                    $State['Stdout'] = ''
                    $State['Stderr'] = "0.080 -- 1.320`n2.560 -- 4.800"
                    return
                }
                $script:OfflineHits++
                if ($script:OfflineHits -ge 2) {
                    $State['ExitCode'] = 2
                    $State['Stdout'] = ''
                    return
                }
                $State['ExitCode'] = 0
                $State['Stdout'] = '{"text":"こんにちは","tokens":["こん"],"timestamps":[0.00]}'
            }
            { Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet -Result $Result } |
                Should -Throw '*sherpa-onnx-offline a échoué (code 2)*'
        }
        $result.Transcripts | Should -HaveCount 0
    }

    It 'lève si l''exécutable VAD est introuvable' {
        $media = Join-Path $TestDrive 'no-exe.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxNativeExecutable { throw 'sherpa-onnx-vad introuvable (test)' }
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg { throw 'ne doit pas tourner' }
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            $result = @{ Transcripts = [System.Collections.Generic.List[object]]::new() }
            { Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet -Result $result } |
                Should -Throw '*sherpa-onnx-vad*'
        }
        Should -Invoke -ModuleName Tetram.Media.Transcript Invoke-FFmpeg -Times 0
    }

    It 'prépare un WAV commun et deux VAD pour <Model>' -TestCases @(
        @{
            Model          = 'reazon-k2-v2'
            LanguageSource = 'model'
            RequiredAsr    = @('--encoder=', '--decoder=', '--joiner=')
            ForbiddenAsr   = @('nemo-ctc-model', 'sense-voice')
        }
        @{
            Model          = 'parakeet-0.6b-ja'
            LanguageSource = 'model'
            RequiredAsr    = @('--nemo-ctc-model=')
            ForbiddenAsr   = @('--encoder=', '--decoder=', '--joiner=', 'sense-voice')
        }
        @{
            Model          = 'sensevoice-small'
            LanguageSource = 'forced'
            RequiredAsr    = @('--sense-voice-model=', '--sense-voice-language=ja')
            ForbiddenAsr   = @('--encoder=', '--decoder=', '--joiner=', 'nemo-ctc-model')
        }
    ) {
        param($Model, $LanguageSource, $RequiredAsr, $ForbiddenAsr)
        $media = Join-Path $TestDrive "dual-vad-$Model.mkv"
        Set-Content -LiteralPath $media -Value 'x'
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxModelFiles {
            param($Model)
            switch ($Model) {
                'parakeet-0.6b-ja' {
                    [pscustomobject]@{ Tokens = 'tokens.txt'; NemoCtcModel = 'model.int8.onnx' }
                }
                'sensevoice-small' {
                    [pscustomobject]@{ Tokens = 'tokens.txt'; SenseVoiceModel = 'model.int8.onnx' }
                }
                default {
                    [pscustomobject]@{
                        Tokens  = 'tokens.txt'
                        Encoder = 'encoder.onnx'
                        Decoder = 'decoder.onnx'
                        Joiner  = 'joiner.onnx'
                    }
                }
            }
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg {
            param($Arguments)
            $out = $Arguments[-1]
            $parent = Split-Path -Parent $out
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Set-Content -LiteralPath $out -Value 'RIFF'
            return 0
        }
        Mock -ModuleName Tetram.Media.Transcript Invoke-SherpaOnnx {
            param($Exe, $Arguments, $State)
            $script:SeenSherpaCalls.Add([pscustomobject]@{
                    Exe       = $Exe
                    Arguments = [string[]]@($Arguments)
                })
            $State['ExitCode'] = 0
            if ($Exe -eq $script:FakeVadExe) {
                $State['Stdout'] = ''
                $State['Stderr'] = '0.080 -- 1.320'
            }
            else {
                $State['Stdout'] = '{"text":"こんにちは","tokens":["こん"],"timestamps":[0.00]}'
            }
        }

        $result = New-SherpaTestResult
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
            Result = $result
            Model  = $Model
        } {
            param($Media, $Cmdlet, $Result, $Model)
            Invoke-SherpaOnnxTranscript -MediaPath $Media -Model $Model -Cmdlet $Cmdlet -Result $Result
        }

        $offline = @($script:SeenSherpaCalls | Where-Object { $_.Exe -eq $script:FakeOfflineExe })
        $offline.Count | Should -Be 2
        foreach ($call in $offline) {
            $joined = $call.Arguments -join ' '
            $joined | Should -Not -Match '--num-threads'
            $joined | Should -Not -Match 'silero-vad'
            $joined | Should -Not -Match 'ten-vad'
            foreach ($flag in $RequiredAsr) {
                $joined | Should -Match ([regex]::Escape($flag))
            }
            foreach ($flag in $ForbiddenAsr) {
                $joined | Should -Not -Match ([regex]::Escape($flag))
            }
        }
        $got = @($result.Transcripts)
        $got.Count | Should -Be 2
        $got[0].model | Should -Be $Model
        $got[0].vad | Should -Be 'silero'
        $got[0].language | Should -Be 'ja'
        $got[0].languageSource | Should -Be $LanguageSource
        $got[0].segments[0].diagnostics.tokens | Should -Be @('こん')
        $got[0].segments[0].PSObject.Properties.Name | Should -Not -Contain 'words'
        $got[1].vad | Should -Be 'ten'
        $got[1].languageSource | Should -Be $LanguageSource
    }

    It 'lève si ten-vad.onnx est absent à côté du VAD' {
        $media = Join-Path $TestDrive 'no-ten.mkv'
        Set-Content -LiteralPath $media -Value 'x'
        $dir = Join-Path $TestDrive 'exe-sans-ten'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $vad = Join-Path $dir 'sherpa-onnx-vad.exe'
        Set-Content -LiteralPath $vad -Value 'stub'
        Set-Content -LiteralPath (Join-Path $dir 'silero_vad.onnx') -Value 'stub'
        Mock -ModuleName Tetram.Media.Transcript Get-SherpaOnnxNativeExecutable { $vad }
        Mock -ModuleName Tetram.Media.Transcript Invoke-FFmpeg { throw 'ne doit pas tourner' }
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Media  = $media
            Cmdlet = $script:FakeCmdlet
        } {
            param($Media, $Cmdlet)
            $result = @{ Transcripts = [System.Collections.Generic.List[object]]::new() }
            { Invoke-SherpaOnnxTranscript -MediaPath $Media -Model 'reazon-k2-v2' -Cmdlet $Cmdlet -Result $result } |
                Should -Throw '*ten-vad.onnx*'
        }
    }
}

Describe 'Invoke-ProviderTranscript (Sherpa)' {
    It 'est le point d''entrée commun du backend Sherpa' {
        InModuleScope 'Tetram.Media.Transcript' {
            (Get-Command Invoke-ProviderTranscript).Name | Should -Be 'Invoke-ProviderTranscript'
        }
    }
}
