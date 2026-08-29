Set-StrictMode -Version 3.0

function Invoke-SherpaOnnxTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)] $Result,
        [int] $AudioTrack = 1,
        [string] $UseLanguage,
        [switch] $WhatIf
    )

    Assert-SherpaOnnxLanguage -UseLanguage $UseLanguage -Model $Model

    $vadExe = Get-SherpaOnnxNativeExecutable -Name 'sherpa-onnx-vad'
    $offlineExe = Get-SherpaOnnxNativeExecutable -Name 'sherpa-onnx-offline'
    $modelFiles = Get-SherpaOnnxModelFiles -Model $Model
    $sileroVad = Get-SherpaOnnxVadModelPath -Exe $vadExe -FileName 'silero_vad.onnx'
    $tenVad = Get-SherpaOnnxVadModelPath -Exe $vadExe -FileName 'ten-vad.onnx'
    $asrArgs = Get-SherpaOnnxAsrArguments -Model $Model -ModelFiles $modelFiles

    # Chemins figés avant ShouldProcess : WhatIf n'exécute pas le VAD pour découvrir les chunks.
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $wav = Join-Path $tempDir 'audio.wav'
    $sileroSpeech = Join-Path $tempDir 'vad-silero-speech.wav'
    $tenSpeech = Join-Path $tempDir 'vad-ten-speech.wav'
    $ffmpegArgs = Get-SherpaOnnxFfmpegArguments -MediaPath $MediaPath -AudioTrack $AudioTrack -OutputPath $wav
    $sileroVadArgs = Get-SherpaOnnxVadArguments -SileroVadModel $sileroVad -WavPath $wav -SpeechWavPath $sileroSpeech
    $tenVadArgs = Get-SherpaOnnxVadArguments -TenVadModel $tenVad -WavPath $wav -SpeechWavPath $tenSpeech

    $vadNoPath = 'silero-vad-model', 'ten-vad-model', 'num-threads', 'vad-num-threads'
    $asrNoPath = 'tokens', 'encoder', 'decoder', 'joiner', 'nemo-ctc-model', 'sense-voice-model', 'num-threads'
    Show-CommandLine -Exe (Get-FFmpegPath) -Arguments $ffmpegArgs -NoPathDetectionParameters 'map', 'ac', 'c:a', 'hide_banner'
    Show-CommandLine -Exe $vadExe -Arguments $sileroVadArgs -NoPathDetectionParameters $vadNoPath
    Show-CommandLine -Exe $vadExe -Arguments $tenVadArgs -NoPathDetectionParameters $vadNoPath
    Write-DebugLog -Text 'découpage des chunks + sherpa-onnx-offline dépendent du résultat VAD'

    if (-not $Cmdlet.ShouldProcess($MediaPath, 'sherpa-onnx-vad + sherpa-onnx-offline')) {
        return
    }
    if ($WhatIf) {
        return
    }

    try {
        $timelineOffset = Get-SherpaOnnxTimelineOffset -MediaPath $MediaPath -AudioTrack $AudioTrack
        [void](New-SherpaOnnxTempDirectory -Path $tempDir)
        ConvertTo-SherpaOnnxWav -MediaPath $MediaPath -AudioTrack $AudioTrack -OutputPath $wav

        foreach ($run in @(
                [pscustomobject]@{ Vad = 'silero'; Arguments = $sileroVadArgs }
                [pscustomobject]@{ Vad = 'ten'; Arguments = $tenVadArgs }
            )) {
            $vadState = @{ ExitCode = $null; Stdout = $null; Stderr = $null }
            Invoke-SherpaOnnx -Exe $vadExe -Arguments $run.Arguments -State $vadState
            if ($null -eq $vadState['ExitCode']) {
                return
            }
            if ($vadState['ExitCode'] -ne 0) {
                throw "sherpa-onnx-vad a échoué (code $($vadState['ExitCode'])) sur '$MediaPath' (modèle $Model, vad $($run.Vad))."
            }

            $intervals = @(ConvertFrom-SherpaOnnxVadStdout -Stdout ([string]$vadState['Stdout']))
            if ($intervals.Count -eq 0) {
                throw "Aucun intervalle VAD exploitable produit par sherpa-onnx-vad pour '$MediaPath' (modèle $Model, vad $($run.Vad))."
            }

            $chunkDir = Join-Path $tempDir $run.Vad
            $chunkPaths = [System.Collections.Generic.List[string]]::new()
            for ($i = 0; $i -lt $intervals.Count; $i++) {
                $chunk = Join-Path $chunkDir ('chunk-{0:D4}.wav' -f ($i + 1))
                New-SherpaOnnxChunkWav -MasterWav $wav -Start $intervals[$i].start -End $intervals[$i].end -OutputPath $chunk
                $chunkPaths.Add($chunk)
            }

            $asrResults = [System.Collections.Generic.List[object]]::new()
            $batches = Split-SherpaOnnxChunkBatches -ChunkPaths @($chunkPaths.ToArray())
            foreach ($batch in $batches) {
                $batchPaths = [string[]]@($batch)
                $offlineArgs = Get-SherpaOnnxOfflineArguments -AsrArguments $asrArgs -ChunkPaths $batchPaths
                Show-CommandLine -Exe $offlineExe -Arguments $offlineArgs -NoPathDetectionParameters $asrNoPath
                $asrState = @{ ExitCode = $null; Stdout = $null; Stderr = $null }
                Invoke-SherpaOnnx -Exe $offlineExe -Arguments $offlineArgs -State $asrState
                if ($null -eq $asrState['ExitCode']) {
                    return
                }
                if ($asrState['ExitCode'] -ne 0) {
                    throw "sherpa-onnx-offline a échoué (code $($asrState['ExitCode'])) sur '$MediaPath' (modèle $Model, vad $($run.Vad))."
                }
                foreach ($row in @(ConvertFrom-SherpaOnnxOfflineStdout -Stdout ([string]$asrState['Stdout']) -ExpectedCount $batchPaths.Count)) {
                    $asrResults.Add($row)
                }
            }

            $transcript = ConvertFrom-SherpaOnnxTranscript `
                -Intervals $intervals `
                -AsrResults @($asrResults.ToArray()) `
                -Model $Model `
                -Vad $run.Vad `
                -UseLanguage $UseLanguage `
                -AudioTrack $AudioTrack `
                -TimelineOffset $timelineOffset
            [void]$Result.Transcripts.Add($transcript)
        }
    }
    finally {
        Remove-SherpaOnnxTempDirectory -Path $tempDir
    }
}
