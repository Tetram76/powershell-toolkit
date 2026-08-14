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

Describe 'Remove-StreamsTempIfPresent' {
    It 'supprime le GUID même si ShouldProcess refuse (Confirm No to All)' {
        InModuleScope 'Tetram.Media.Streams' {
            $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.mkv')
            Set-Content -LiteralPath $temp -Value 'leftover'
            try {
                Remove-StreamsTempIfPresent -TempPath $temp
                Test-Path -LiteralPath $temp | Should -BeFalse
            }
            finally {
                if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -Confirm:$false -WhatIf:$false }
            }
        }
    }
    It 'supprime le GUID même si WhatIfPreference est hérité' {
        InModuleScope 'Tetram.Media.Streams' {
            $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.mkv')
            Set-Content -LiteralPath $temp -Value 'leftover'
            try {
                $WhatIfPreference = 'Continue'
                Remove-StreamsTempIfPresent -TempPath $temp
                Test-Path -LiteralPath $temp | Should -BeFalse
            }
            finally {
                if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -Confirm:$false -WhatIf:$false }
            }
        }
    }
}

Describe 'Get-StreamsUniqueTempPath' {
    It 'utilise TEMP + GUID + extension finale (comme Reencode)' {
        InModuleScope 'Tetram.Media.Streams' {
            $final = Join-Path $TestDrive 'film.fra.srt'
            $temp = Get-StreamsUniqueTempPath -FinalPath $final
            [IO.Path]::GetExtension($temp) | Should -Be '.srt'
            $gotDir = [IO.Path]::GetFullPath((Split-Path -Parent $temp)).TrimEnd('\', '/')
            $wantDir = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
            $gotDir | Should -Be $wantDir
            [IO.Path]::GetFileNameWithoutExtension($temp) | Should -Match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            [IO.Path]::GetFileName($temp) | Should -Not -Match 'film'
        }
    }
}
