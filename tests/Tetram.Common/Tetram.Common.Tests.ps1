BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootCommon = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ManifestPathCommon = Join-Path $script:RepoRootCommon 'Tetram.Common' 'Tetram.Common.psd1'
    Import-Module -Name (Join-Path $script:RepoRootCommon 'Tetram.Common') -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Common' -Force -ErrorAction SilentlyContinue
}

Describe 'Tetram.Common manifest' {

    It 'passes Test-ModuleManifest resolved from repo root (tests/Tetram.Common => two parents)' {

        $manifestPath = Join-Path $script:RepoRootCommon 'Tetram.Common' 'Tetram.Common.psd1'
        { Test-ModuleManifest -Path $manifestPath } | Should -Not -Throw
    }
}

Describe 'Tetram.Common exports' {

    It 'Registers every FunctionsToExport from the manifest' {

        $names = @(Import-PowerShellDataFile -LiteralPath $script:ManifestPathCommon).FunctionsToExport

        foreach ($name in $names) {
            $cmd = Get-Command -Name $name -Module 'Tetram.Common' -ErrorAction Ignore
            $cmd | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Format-FileSize (invariant culture)' {

    It 'formats correctly for <Caption>' -TestCases @(
        @{ Caption = 'negative small'; Size = [long]-500; Expected = '-500.00 B' }

        @{ Caption = 'under 1 kB threshold'; Size = [long]500; Expected = '500.00 B' }

        @{ Caption = 'boundary not promoted to kB'; Size = [long]1024; Expected = '1024.00 B' }

        @{ Caption = 'just above 1 KB'; Size = [long]2048; Expected = '2.00 kB' }

        @{ Caption = 'just above 1 MB'; Size = [long]1048577; Expected = '1.00 MB' }

    ) {
        param([string]$Caption, [long]$Size, [string]$Expected)

        $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
        $thread = [System.Threading.Thread]::CurrentThread
        $previousCulture = $thread.CurrentCulture
        $previousUICulture = $thread.CurrentUICulture

        try {
            $thread.CurrentCulture = $invariantCulture
            $thread.CurrentUICulture = $invariantCulture
            $formatted = Format-FileSize -Size $Size
        }
        finally {
            $thread.CurrentCulture = $previousCulture
            $thread.CurrentUICulture = $previousUICulture
        }

        $formatted | Should -BeExactly $Expected
    }
}

Describe 'Format-Duration' {

    It 'throws when TimeSpan binds as $null via Mandatory semantics' {

        { Format-Duration -TimeSpan $null } | Should -Throw
    }

    It 'formats sub-day durations as hh:mm:ss' {

        Format-Duration -TimeSpan ([TimeSpan]::FromSeconds(3661)) |
            Should -BeExactly '1:01:01'
    }

    It 'formats multi-day durations with dot-separated day prefix' {

        Format-Duration -TimeSpan (New-TimeSpan -Days 2 -Hours 3 -Minutes 4 -Seconds 5) |
            Should -BeExactly '2.03:04:05'
    }

    It 'shows zero span using the sub-day pattern' {

        Format-Duration -TimeSpan ([TimeSpan]::Zero) |
            Should -BeExactly '0:00:00'
    }
}

Describe 'Show-CommandLine (-PassThru)' {

    It 'returns exe line followed by indented switch/value pairs without requiring console rendering' {

        $lines = Show-CommandLine -Exe 'ffmpeg' -Arguments '-i', 'input.mkv' -PassThru
        $lines | Should -HaveCount 2
        $lines[0] | Should -BeExactly 'ffmpeg'

        $lines[1] | Should -BeExactly '    -i input.mkv'
    }

    It 'ne fusionne pas le token suivant avec un parametre deja de forme nom=valeur' {

        $lines = Show-CommandLine -Exe 'sherpa-onnx' -Arguments '--num-threads=1', 'audio.wav' -PassThru
        $lines | Should -HaveCount 3
        $lines[0] | Should -BeExactly 'sherpa-onnx'
        $lines[1] | Should -BeExactly '    --num-threads=1'
        $lines[2] | Should -BeExactly '    audio.wav'
    }
}

Describe 'Write-InfoWarning' {

    It 'est exporté par Tetram.Common' {
        $cmd = Get-Command -Name Write-InfoWarning -Module 'Tetram.Common' -ErrorAction Ignore
        $cmd | Should -Not -BeNullOrEmpty
    }

    It 'exige le paramètre Text' {
        { Write-InfoWarning } | Should -Throw
    }

    It 'délègue à Write-InfoLog en jaune avec -Force' {
        InModuleScope Tetram.Common {
            Mock Write-InfoLog {}

            Write-InfoWarning -Text 'test' -Force

            Should -Invoke Write-InfoLog -Times 1 -ParameterFilter {
                $Text -eq 'test' -and
                $Color -eq [System.ConsoleColor]::Yellow -and
                $Force
            }
        }
    }

    It 'ne force pas l''affichage lorsque -Force est absent' {
        InModuleScope Tetram.Common {
            Mock Write-InfoLog {}

            Write-InfoWarning -Text 'quiet'

            Should -Invoke Write-InfoLog -Times 1 -ParameterFilter {
                $Text -eq 'quiet' -and
                $Color -eq [System.ConsoleColor]::Yellow -and
                -not $Force
            }
        }
    }

    It 'n''écrit aucun objet dans le pipeline' {
        InModuleScope Tetram.Common {
            Mock Write-InfoLog {}

            $output = Write-InfoWarning -Text 'no pipeline' -Force
            $output | Should -BeNullOrEmpty
        }
    }
}

Describe 'Test-PowerShellSpecificPath' {

    It 'reconnaît les crochets et l''échappement backtick' {
        Test-PowerShellSpecificPath -Path 'D:\Films\film[1].mkv' | Should -BeTrue
        Test-PowerShellSpecificPath -Path 'D:\Films\film`*.mkv' | Should -BeTrue
    }

    It 'reconnaît un PSDrive nommé' {
        Test-PowerShellSpecificPath -Path 'Temp:\a.mkv' | Should -BeTrue
    }

    It 'laisse passer un chemin, un masque, une lettre de lecteur ou un UNC' {
        Test-PowerShellSpecificPath -Path 'D:\Films\a.mkv' | Should -BeFalse
        Test-PowerShellSpecificPath -Path 'D:\Films\*.mkv' | Should -BeFalse
        Test-PowerShellSpecificPath -Path '.\a?.mkv' | Should -BeFalse
        Test-PowerShellSpecificPath -Path '\\nas\films\a.mkv' | Should -BeFalse
    }
}
