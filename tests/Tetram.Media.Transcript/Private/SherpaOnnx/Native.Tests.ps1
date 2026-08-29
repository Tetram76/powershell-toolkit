# Étendre la suite autour de la résolution/exécution native Sherpa (vad + offline).
#
# Tout passe par InModuleScope 'Tetram.Media.Transcript' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.
# Get-SherpaOnnxNativeExecutable n'appelle aucun binaire. Invoke-SherpaOnnx s'exerce via un mock
# ou un stand-in pwsh, jamais via sherpa-onnx-vad.exe / sherpa-onnx-offline.exe.

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

Describe 'Get-SherpaOnnxNativeExecutable' {
    It 'prend <Name>.exe dans le dossier du module quand il existe' -TestCases @(
        @{ Name = 'sherpa-onnx-vad' }
        @{ Name = 'sherpa-onnx-offline' }
    ) {
        param($Name)
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive"; Name = $Name } {
            param($Work, $Name)
            $fakeRoot = Join-Path $Work $Name
            New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
            $exe = Join-Path $fakeRoot "$Name.exe"
            Set-Content -LiteralPath $exe -Value 'stub'
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $fakeRoot
                Get-SherpaOnnxNativeExecutable -Name $Name | Should -Be $exe
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'retourne l''override quand c''est un fichier' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $exe = Join-Path $Work 'ailleurs.exe'
            Set-Content -LiteralPath $exe -Value 'stub'
            Get-SherpaOnnxNativeExecutable -Name 'sherpa-onnx-vad' -OverridePath $exe | Should -Be $exe
        }
    }

    It 'rejette un override qui est un dossier' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $dir = Join-Path $Work 'dossier-exe'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            { Get-SherpaOnnxNativeExecutable -Name 'sherpa-onnx-offline' -OverridePath $dir } |
                Should -Throw '*pas un dossier*'
        }
    }

    It 'rejette un override inexistant' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            { Get-SherpaOnnxNativeExecutable -Name 'sherpa-onnx-vad' -OverridePath (Join-Path $Work 'absent.exe') } |
                Should -Throw '*inexistant*'
        }
    }

    It 'n''utilise pas sherpa-onnx-vad-with-offline-asr.exe comme substitut de <Name>' -TestCases @(
        @{ Name = 'sherpa-onnx-vad' }
        @{ Name = 'sherpa-onnx-offline' }
    ) {
        param($Name)
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive"; Name = $Name } {
            param($Work, $Name)
            $fakeRoot = Join-Path $Work "combined-$Name"
            New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fakeRoot 'sherpa-onnx-vad-with-offline-asr.exe') -Value 'stub'
            Mock Get-Command { $null } -ParameterFilter { $Name -eq $Name }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $fakeRoot
                { Get-SherpaOnnxNativeExecutable -Name $Name } | Should -Throw "*$Name*"
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'échoue avec un message qui indique où poser <Name>' -TestCases @(
        @{ Name = 'sherpa-onnx-vad' }
        @{ Name = 'sherpa-onnx-offline' }
    ) {
        param($Name)
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive"; Name = $Name } {
            param($Work, $Name)
            Mock Get-Command { $null } -ParameterFilter { $Name -eq $Name }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = Join-Path $Work "vide-$Name"
                { Get-SherpaOnnxNativeExecutable -Name $Name } | Should -Throw '*SherpaOnnx*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }
}

Describe 'Invoke-SherpaOnnx' {
    It 'ne fusionne pas stderr dans stdout et conserve stderr à part' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $helper = Join-Path $Work 'emit-streams.ps1'
            Set-Content -LiteralPath $helper -Value @'
$out = [System.Text.Encoding]::UTF8.GetBytes("0.080 -- 1.320")
[Console]::OpenStandardOutput().Write($out, 0, $out.Length)
$err = [System.Text.Encoding]::UTF8.GetBytes("Creating recognizer ...")
[Console]::OpenStandardError().Write($err, 0, $err.Length)
'@
            $state = @{ ExitCode = $null; Stdout = $null; Stderr = $null }
            Invoke-SherpaOnnx -Exe (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', $helper) -State $state
            $state['ExitCode'] | Should -Be 0
            $state['Stdout'] | Should -Match '0\.080 -- 1\.320'
            $state['Stdout'] | Should -Not -Match 'Creating recognizer'
            $state['Stderr'] | Should -Match 'Creating recognizer'
        }
    }

    It 'décode stdout en UTF-8 même si la console n''est pas UTF-8' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $helper = Join-Path $Work 'emit-utf8.ps1'
            Set-Content -LiteralPath $helper -Value @'
$bytes = [System.Text.Encoding]::UTF8.GetBytes("こんにちは")
[Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)
'@
            $saved = [Console]::OutputEncoding
            try {
                [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437)
                $state = @{ ExitCode = $null; Stdout = $null; Stderr = $null }
                Invoke-SherpaOnnx -Exe (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', $helper) -State $state
                $state['ExitCode'] | Should -Be 0
                $state['Stdout'] | Should -Match 'こんにちは'
            }
            finally {
                [Console]::OutputEncoding = $saved
            }
        }
    }
}
