# Étendre la suite autour de Invoke.ps1 (args d'extraction split).
#
# RepoRoot : (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module Tetram.Media.Streams.psd1 ; InModuleScope ; Get-SplitExtractArguments

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams') -Force -ErrorAction Stop
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

Describe 'Invoke-StreamsFFmpeg' {
    It 'retourne $null sous WhatIf sans appeler ffmpeg' {
        InModuleScope 'Tetram.Media.Streams' {
            Mock Show-CommandLine {}
            Mock Invoke-FFmpeg { throw 'ne doit pas tourner' }
            $cmd = [pscustomobject]@{}
            $cmd | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { $false }
            Invoke-StreamsFFmpeg -Cmdlet $cmd -Exe 'ffmpeg' -Arguments @('-y', 'out') -TargetLabel 'out' | Should -BeNullOrEmpty
            Should -Invoke Show-CommandLine -Times 1
            Should -Invoke Invoke-FFmpeg -Times 0
        }
    }
    It 'retourne $null si Confirm refuse (indistinguable de WhatIf pour l''appelant)' {
        InModuleScope 'Tetram.Media.Streams' {
            Mock Show-CommandLine {}
            Mock Invoke-FFmpeg { throw 'ne doit pas tourner' }
            $cmd = [pscustomobject]@{}
            $cmd | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { $false }
            Invoke-StreamsFFmpeg -Cmdlet $cmd -Exe 'ffmpeg' -Arguments @('-y', 'out') -TargetLabel 'out' | Should -Be $null
            Should -Invoke Invoke-FFmpeg -Times 0
        }
    }
    It 'appelle ffmpeg et retourne true si le code de sortie est 0' {
        InModuleScope 'Tetram.Media.Streams' {
            Mock Show-CommandLine {}
            Mock Invoke-FFmpeg { 0 }
            $cmd = [pscustomobject]@{}
            $cmd | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { $true }
            Invoke-StreamsFFmpeg -Cmdlet $cmd -Exe 'ffmpeg' -Arguments @('-y', 'out') -TargetLabel 'out' | Should -BeTrue
            Should -Invoke Invoke-FFmpeg -Times 1
        }
    }
    It 'retourne false si ffmpeg renvoie un code non nul' {
        InModuleScope 'Tetram.Media.Streams' {
            Mock Show-CommandLine {}
            Mock Invoke-FFmpeg { 1 }
            $cmd = [pscustomobject]@{}
            $cmd | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { $true }
            Invoke-StreamsFFmpeg -Cmdlet $cmd -Exe 'ffmpeg' -Arguments @('-y', 'out') -TargetLabel 'out' | Should -BeFalse
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
