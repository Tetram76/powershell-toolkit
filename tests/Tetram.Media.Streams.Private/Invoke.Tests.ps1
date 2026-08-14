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
    It 'dump_attachment avant -i pour une pièce jointe, sans -map' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{ Class = 'Attachment'; StreamIndex = 5 }
            $ffmpegArgs = @(Get-SplitExtractArguments -Descriptor $d -MkvPath 'film.mkv' -OutPath 'film.Arial.ttf')
            $ffmpegArgs | Should -Contain '-dump_attachment:5'
            $ffmpegArgs | Should -Not -Contain '-map'
            $iDump = [array]::IndexOf($ffmpegArgs, '-dump_attachment:5')
            $iInput = [array]::IndexOf($ffmpegArgs, '-i')
            $iDump | Should -BeGreaterThan -1
            $iInput | Should -BeGreaterThan $iDump
            $ffmpegArgs[$iDump + 1] | Should -Be 'film.Arial.ttf'
        }
    }

    It 'garde -map 0:idx -c copy hors pièce jointe' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{ Class = 'Subtitle'; StreamIndex = 3 }
            $ffmpegArgs = @(Get-SplitExtractArguments -Descriptor $d -MkvPath 'film.mkv' -OutPath 'film.eng.srt')
            $pair = $false
            for ($i = 0; $i -lt $ffmpegArgs.Count - 1; $i++) {
                if ($ffmpegArgs[$i] -eq '-map' -and $ffmpegArgs[$i + 1] -eq '0:3') { $pair = $true; break }
            }
            $pair | Should -BeTrue
            ($ffmpegArgs -join ' ') | Should -Match '-c copy'
            $ffmpegArgs | Should -Not -Contain '-dump_attachment:3'
        }
    }
}
