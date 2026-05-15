BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootCommon = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ManifestPathCommon = Join-Path $script:RepoRootCommon 'Utils/Tetram.Common.psd1'
    Import-Module -Name $script:ManifestPathCommon -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'Tetram.Common' -Force -ErrorAction SilentlyContinue
}

Describe 'Tetram.Common manifest' {

    It 'passes Test-ModuleManifest resolved from repo root (tests/Utils => two parents)' {

        $manifestPath = Join-Path $script:RepoRootCommon 'Utils/Tetram.Common.psd1'
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
}
