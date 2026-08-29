# Étendre la suite autour de la timebase et des artefacts audio Sherpa.
#
# Tout passe par InModuleScope 'Tetram.Media.Transcript' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Les arguments FFmpeg sont testés sans lancer le binaire.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranscript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
    $script:ModuleRootTranscript = Join-Path $script:RepoRootTranscript 'Tetram.Media.Transcript'
    Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop

    $module = Get-Module -Name 'Tetram.Media.Transcript'
    . $module {
        . (Join-Path $script:TranscriptPrivateRoot 'SherpaOnnx.ps1')
    }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SherpaOnnxChunkFfmpegArguments' {
    It 'découpe le WAV maître aux bornes VAD, sans resampling et sans seek avant l''entrée' {
        InModuleScope 'Tetram.Media.Transcript' {
            $master = Join-Path 'tmp' 'audio.wav'
            $chunk = Join-Path 'tmp' 'silero' 'chunk-0001.wav'
            $got = Get-SherpaOnnxChunkFfmpegArguments -MasterWav $master -Start 10.5 -End 12.75 -OutputPath $chunk
            $iAt = [array]::IndexOf(@($got), '-i')
            $iAt | Should -BeGreaterThan -1
            $got[$iAt + 1] | Should -Be $master
            $got | Should -Not -Contain '-ss'
            $got | Should -Not -Contain '-ar'
            $got | Should -Not -Contain '-ac'
            $joined = $got -join ' '
            $joined | Should -Match 'atrim='
            $joined | Should -Match '10\.5'
            $joined | Should -Match '12\.75'
            $joined | Should -Not -Match 'vad-silero-speech'
            $joined | Should -Not -Match 'vad-ten-speech'
            $got[-1] | Should -Be $chunk
        }
    }

    It 'émet les bornes en InvariantCulture et sans cumuler les durées précédentes' {
        InModuleScope 'Tetram.Media.Transcript' {
            $saved = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
                $early = Get-SherpaOnnxChunkFfmpegArguments -MasterWav 'audio.wav' -Start 0.08 -End 1.32 -OutputPath 'chunk-0001.wav'
                $late = Get-SherpaOnnxChunkFfmpegArguments -MasterWav 'audio.wav' -Start 150.5 -End 154.25 -OutputPath 'chunk-0150.wav'
                ($early -join ' ') | Should -Match 'atrim=start=0\.08:end=1\.32'
                ($late -join ' ') | Should -Match 'atrim=start=150\.5:end=154\.25'
                ($late -join ' ') | Should -Not -Match '151\.74'
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $saved
            }
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
