# Étendre la suite autour de Invoke.ps1 (args d'extraction split).
#
# RepoRoot : (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module Tetram.Media.Streams.psd1 ; InModuleScope ; Get-SplitExtractArguments

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams.psd1') -Force -ErrorAction Stop
}
AfterAll { Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue }

Describe 'Get-SplitExtractArguments' {
    It 'émet -map 0:idx -c copy' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{ Class = 'Subtitle'; StreamIndex = 3 }
            $ffmpegArgs = @(Get-SplitExtractArguments -Descriptor $d -MkvPath 'film.mkv' -OutPath 'film.eng.srt')
            $pair = $false
            for ($i = 0; $i -lt $ffmpegArgs.Count - 1; $i++) {
                if ($ffmpegArgs[$i] -eq '-map' -and $ffmpegArgs[$i + 1] -eq '0:3') { $pair = $true; break }
            }
            $pair | Should -BeTrue
            ($ffmpegArgs -join ' ') | Should -Match '-c copy'
        }
    }
}

Describe 'Get-StreamsUniqueTempPath' {
    It 'conserve l''extension sidecar (FFmpeg déduit le muxer de la dernière extension)' {
        InModuleScope 'Tetram.Media.Streams' {
            $final = Join-Path $TestDrive 'film.fra.srt'
            $temp = Get-StreamsUniqueTempPath -FinalPath $final -KeepExtension
            [IO.Path]::GetExtension($temp) | Should -Be '.srt'
            $temp | Should -Match '\.tmp\.srt$'
        }
    }
    It 'ajoute .tmp après le MKV (le muxer est -f matroska)' {
        InModuleScope 'Tetram.Media.Streams' {
            $final = Join-Path $TestDrive 'film.mkv'
            $temp = Get-StreamsUniqueTempPath -FinalPath $final
            $temp | Should -Be ($final + '.tmp')
        }
    }
}
