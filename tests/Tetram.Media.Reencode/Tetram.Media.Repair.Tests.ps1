# Étendre la suite autour de Tetram.Media.Repair.psm1 (Get-MkvInterleaveRepairCommand / Invoke-MkvRepair).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode') ; mocks -ModuleName Tetram.Media.Repair
# Get-MkvMergeInfo / Invoke-MkvRepairFile : InModuleScope 'Tetram.Media.Repair'
# Fichiers factices sous $TestDrive ; mkvmerge simulé par un .ps1 (pas de binaire réel).

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootRepair = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootRepair 'Tetram.Media.Reencode') -Force -ErrorAction Stop

    function script:New-MkvTrack {
        param(
            [Parameter(Mandatory)] [int] $Id,
            [Parameter(Mandatory)] [string] $Type,
            [string] $Codec = 'X'
        )

        [pscustomobject]@{
            id    = $Id
            type  = $Type
            codec = $Codec
        }
    }

    function script:New-MkvMergeInfo {
        param(
            [object[]] $Tracks = @(),
            [string] $ContainerType = 'Matroska',
            [bool] $Recognized = $true,
            [bool] $Supported = $true,
            [object] $Properties
        )

        $container = [pscustomobject]@{
            recognized = $Recognized
            supported  = $Supported
            type       = $ContainerType
        }

        if ($PSBoundParameters.ContainsKey('Properties')) {
            $container | Add-Member -NotePropertyName properties -NotePropertyValue $Properties
        }

        [pscustomobject]@{
            container = $container
            tracks    = $Tracks
        }
    }

    function script:New-FakeToolScript {
        param(
            [Parameter(Mandatory)] [string] $Path,
            [int] $ExitCode = 0,
            [string] $OutputText,
            [string] $StdoutText,
            [Alias('MuxDiagnostics', 'UnstructuredRedirectText')]
            [string] $RedirectOutputText,
            [string] $IdentificationJson,
            [string] $RedirectPathRecord,
            [string] $ArgumentRecord,
            [string] $Flag = '-o'
        )

        $flagLiteral = $Flag.Replace("'", "''")
        $hasOutput = $PSBoundParameters.ContainsKey('OutputText')
        $outputLiteral = if ($hasOutput) {
            $OutputText.Replace("'", "''")
        }
        else {
            ''
        }
        $hasStdout = $PSBoundParameters.ContainsKey('StdoutText')
        $stdoutLiteral = if ($hasStdout) {
            $StdoutText.Replace("'", "''")
        }
        else {
            ''
        }
        $hasRedirect = $PSBoundParameters.ContainsKey('RedirectOutputText')
        $redirectLiteral = if ($hasRedirect) {
            $RedirectOutputText.Replace("'", "''")
        }
        else {
            ''
        }
        $hasIdentification = $PSBoundParameters.ContainsKey('IdentificationJson')
        $identificationB64 = if ($hasIdentification) {
            [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($IdentificationJson))
        }
        else {
            ''
        }
        $hasRedirectRecord = $PSBoundParameters.ContainsKey('RedirectPathRecord')
        $redirectRecordLiteral = if ($hasRedirectRecord) {
            $RedirectPathRecord.Replace("'", "''")
        }
        else {
            ''
        }
        $hasArgumentRecord = $PSBoundParameters.ContainsKey('ArgumentRecord')
        $argumentRecordLiteral = if ($hasArgumentRecord) {
            $ArgumentRecord.Replace("'", "''")
        }
        else {
            ''
        }

        @(
            "`$exitCode = $ExitCode"
            "`$writeOutput = `$$hasOutput"
            "`$writeStdout = `$$hasStdout"
            "`$writeRedirect = `$$hasRedirect"
            "`$writeIdentification = `$$hasIdentification"
            "`$recordRedirect = `$$hasRedirectRecord"
            "`$recordArguments = `$$hasArgumentRecord"
            "`$flag = '$flagLiteral'"
            "`$text = '$outputLiteral'"
            "`$stdout = '$stdoutLiteral'"
            "`$redirect = '$redirectLiteral'"
            "`$identificationB64 = '$identificationB64'"
            "`$redirectRecord = '$redirectRecordLiteral'"
            "`$argumentRecord = '$argumentRecordLiteral'"
            # `& $exe $argumentArray` passe le tableau comme un seul $args[0] ; on aplatit.
            '$all = [System.Collections.Generic.List[object]]::new()'
            'foreach ($item in $args) {'
            '    if ($item -is [System.Array]) {'
            '        foreach ($nested in $item) { [void]$all.Add($nested) }'
            '    }'
            '    else {'
            '        [void]$all.Add($item)'
            '    }'
            '}'
            'if ($writeStdout) { Write-Output $stdout }'
            '$isIdentify = $false'
            'foreach ($item in $all) {'
            '    if ([string]$item -eq ''-J'') { $isIdentify = $true }'
            '}'
            # Plusieurs flags possibles : -o (sortie MKV) et --redirect-output (journal mkvmerge).
            # -J écrit un document JSON : ne pas le confondre avec le journal texte du remux.
            'for ($i = 0; $i -lt $all.Count; $i++) {'
            '    if ($writeIdentification -and $isIdentify -and $all[$i] -eq ''--redirect-output'' -and ($i + 1) -lt $all.Count) {'
            '        $identBytes = [byte[]]::new(0)'
            '        if (-not [string]::IsNullOrEmpty($identificationB64)) {'
            '            $identBytes = [Convert]::FromBase64String($identificationB64)'
            '        }'
            '        [System.IO.File]::WriteAllBytes([string]$all[$i + 1], $identBytes)'
            '    }'
            '    elseif ($writeOutput -and $all[$i] -eq $flag -and ($i + 1) -lt $all.Count) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], $text)'
            '    }'
            '    if ($writeRedirect -and $all[$i] -eq ''--redirect-output'' -and ($i + 1) -lt $all.Count) {'
            '        if (-not ($writeIdentification -and $isIdentify)) {'
            '            [System.IO.File]::WriteAllText([string]$all[$i + 1], $redirect)'
            '        }'
            '    }'
            '    if ($recordRedirect -and $all[$i] -eq ''--redirect-output'' -and ($i + 1) -lt $all.Count) {'
            '        [System.IO.File]::WriteAllText($redirectRecord, [string]$all[$i + 1])'
            '    }'
            '}'
            'if ($recordArguments) {'
            '    [System.IO.File]::WriteAllLines($argumentRecord, [string[]]$all)'
            '}'
            'exit $exitCode'
        ) -join [Environment]::NewLine |
            Set-Content -LiteralPath $Path -Encoding utf8
    }

    function script:Invoke-RepairFileUnderTest {
        param(
            [Parameter(Mandatory)] [string] $Path,
            [string] $MkvMerge = 'mkvmerge.exe',
            [switch] $PassThru
        )

        $state = @{
            Path     = $Path
            MkvMerge = $MkvMerge
            PassThru = [bool] $PassThru
            Warnings = @()
            Output   = $null
        }

        try {
            InModuleScope 'Tetram.Media.Repair' -Parameters @{ State = $state } {
                param($State)

                $warningMessages = $null
                try {
                    $State.Output = Invoke-MkvRepairFile `
                        -Path $State.Path `
                        -MkvMerge $State.MkvMerge `
                        -PassThru:$State.PassThru `
                        -WarningAction SilentlyContinue `
                        -WarningVariable warningMessages
                }
                finally {
                    $State.Warnings = @($warningMessages)
                }
            }
        }
        finally {
            $script:LastRepairWarnings = $state.Warnings
        }

        if ($null -ne $state.Output) {
            $state.Output
        }
    }

    function script:New-MkvMergeMuxLog {
        param(
            [Parameter(Mandatory)]
            [string[]] $WarningLine
        )

        # mkvmerge écrit Progress avec un CR seul, puis colle le warning sans LF.
        $glued = 'Progress: 42%' + [char]13 + $WarningLine[0]
        if ($WarningLine.Count -eq 1) {
            return $glued
        }

        return @(
            $glued
            $WarningLine[1..($WarningLine.Count - 1)]
        ) -join "`n"
    }

    function script:Get-DiagnosticSequence {
        param($Records)

        foreach ($item in @($Records)) {
            if ($item -is [System.Management.Automation.WarningRecord]) {
                [pscustomobject]@{ Kind = 'Warning'; Text = [string]$item.Message }
                continue
            }

            if ($item -is [System.Management.Automation.ErrorRecord]) {
                [pscustomobject]@{ Kind = 'Error'; Text = [string]$item.Exception.Message }
            }
        }
    }

    function script:Get-NativeDiagnosticSequence {
        param(
            $Records,
            [string[]] $Text
        )

        $wanted = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Text))
        @(
            Get-DiagnosticSequence -Records $Records |
                Where-Object { $wanted.Contains([string]$_.Text) }
        )
    }

    function script:Invoke-MkvMergeInfoCapturingDiagnostics {
        param(
            [Parameter(Mandatory)] [string] $MkvMerge,
            [string] $Path = 'ignored.mkv'
        )

        $state = @{
            MkvMerge  = $MkvMerge
            Path      = $Path
            Records   = [System.Collections.Generic.List[object]]::new()
            Exception = $null
            Output    = @()
        }

        InModuleScope 'Tetram.Media.Repair' -Parameters @{ State = $state } {
            param($State)

            try {
                Get-MkvMergeInfo -MkvMerge $State.MkvMerge -Path $State.Path -WarningAction Continue -ErrorAction Continue 2>&1 3>&1 |
                    ForEach-Object { [void]$State.Records.Add($_) }
            }
            catch {
                $State.Exception = $_
                [void]$State.Records.Add($_)
            }
        }

        $state.Output = @(
            $state.Records | Where-Object {
                $_ -isnot [System.Management.Automation.WarningRecord] -and
                $_ -isnot [System.Management.Automation.ErrorRecord]
            }
        )
        $state
    }

    function script:Assert-MkvMergeJFailedException {
        param(
            $Exception,
            [Parameter(Mandatory)] [string] $Path,
            [int] $ExitCode = 2
        )

        $Exception | Should -Not -BeNullOrEmpty
        $message = [string]$Exception.Exception.Message
        $message | Should -Match 'mkvmerge -J'
        $message | Should -Match "code $ExitCode"
        $message | Should -Match ([regex]::Escape($Path))
    }

    function script:New-FakeMkvMergeWithIdentificationFailure {
        param(
            [Parameter(Mandatory)] [string] $Path,
            [Parameter(Mandatory)] [string] $FailFileName,
            [Parameter(Mandatory)] [string] $FailJson,
            [Parameter(Mandatory)] [string] $OkJson
        )

        $failLiteral = $FailFileName.Replace("'", "''")
        $failB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($FailJson))
        $okB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($OkJson))

        @(
            "`$failName = '$failLiteral'"
            "`$failB64 = '$failB64'"
            "`$okB64 = '$okB64'"
            '$all = [System.Collections.Generic.List[object]]::new()'
            'foreach ($item in $args) {'
            '    if ($item -is [System.Array]) {'
            '        foreach ($nested in $item) { [void]$all.Add($nested) }'
            '    }'
            '    else { [void]$all.Add($item) }'
            '}'
            '$isFail = $false'
            '$isIdentify = $false'
            'foreach ($item in $all) {'
            '    if ([string]$item -like ("*{0}" -f $failName)) { $isFail = $true }'
            '    if ([string]$item -eq ''-J'') { $isIdentify = $true }'
            '}'
            'for ($i = 0; $i -lt $all.Count; $i++) {'
            '    if ($all[$i] -eq ''--redirect-output'' -and ($i + 1) -lt $all.Count -and $isIdentify) {'
            '        $payload = if ($isFail) { $failB64 } else { $okB64 }'
            '        [System.IO.File]::WriteAllBytes([string]$all[$i + 1], [Convert]::FromBase64String($payload))'
            '    }'
            '    if ($all[$i] -eq ''-o'' -and ($i + 1) -lt $all.Count -and -not $isFail) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], ''repaired-ok'')'
            '    }'
            '}'
            'if ($isIdentify -and $isFail) { exit 2 } else { exit 0 }'
        ) -join [Environment]::NewLine |
            Set-Content -LiteralPath $Path -Encoding utf8
    }

    # 2>&1 3>&1 dans le même appel : l'ordre des WarningRecord/ErrorRecord
    # est celui des Write-Warning / Write-Error, pas un regroupement a posteriori.
    function script:Invoke-RepairFileCapturingDiagnostics {
        param(
            [Parameter(Mandatory)] [string] $Path,
            [string] $MkvMerge = 'mkvmerge.exe',
            [switch] $PassThru
        )

        $state = @{
            Path      = $Path
            MkvMerge  = $MkvMerge
            PassThru  = [bool] $PassThru
            Records   = [System.Collections.Generic.List[object]]::new()
            Threw     = $false
            Exception = $null
        }

        InModuleScope 'Tetram.Media.Repair' -Parameters @{ State = $state } {
            param($State)

            try {
                Invoke-MkvRepairFile `
                    -Path $State.Path `
                    -MkvMerge $State.MkvMerge `
                    -PassThru:$State.PassThru `
                    -WarningAction Continue `
                    -ErrorAction Continue `
                    2>&1 3>&1 |
                    ForEach-Object {
                        [void]$State.Records.Add($_)
                    }
            }
            catch {
                $State.Threw = $true
                $State.Exception = $_
                [void]$State.Records.Add($_)
            }
        }

        $script:LastRepairRecords = $state.Records
        $script:LastRepairThrew = $state.Threw
        $script:LastRepairException = $state.Exception
        $state
    }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Reencode' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-MkvInterleaveRepairCommand - surface publique' {
    It 'exige -Path en position 0 et n''expose pas ShouldProcess' {
        $meta = Get-Command Get-MkvInterleaveRepairCommand
        $meta.Parameters['Path'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -ExpandProperty Position |
            Should -Contain 0
        $meta.Parameters['Path'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -ExpandProperty Mandatory |
            Should -Contain $true
        $meta.Parameters.ContainsKey('WhatIf') | Should -BeFalse
        $meta.Parameters.ContainsKey('Confirm') | Should -BeFalse
    }
}

Describe 'Invoke-MkvRepair - surface publique' {
    It 'expose File par défaut et Folder, avec ShouldProcess' {
        $meta = Get-Command Invoke-MkvRepair
        $meta.DefaultParameterSet | Should -Be 'File'
        @($meta.ParameterSets | Select-Object -ExpandProperty Name | Sort-Object) | Should -Be @('File', 'Folder')
        $meta.Parameters['Path'].ParameterSets['File'].IsMandatory | Should -BeTrue
        $meta.Parameters['Folder'].ParameterSets['Folder'].IsMandatory | Should -BeTrue
        $meta.Parameters['Recurse'].ParameterSets.ContainsKey('Folder') | Should -BeTrue
        $meta.Parameters['Recurse'].ParameterSets.ContainsKey('File') | Should -BeFalse
        $meta.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        $meta.Parameters.ContainsKey('Confirm') | Should -BeTrue
    }

    It 'expose ContinueOnError uniquement sur le jeu Folder, optionnel' {
        $meta = Get-Command Invoke-MkvRepair
        $meta.Parameters.ContainsKey('ContinueOnError') | Should -BeTrue
        $meta.Parameters['ContinueOnError'].ParameterSets.ContainsKey('Folder') | Should -BeTrue
        $meta.Parameters['ContinueOnError'].ParameterSets.ContainsKey('File') | Should -BeFalse
        $meta.Parameters['ContinueOnError'].ParameterSets['Folder'].IsMandatory | Should -BeFalse
        $meta.DefaultParameterSet | Should -Be 'File'
    }

    It 'refuse -ContinueOnError avec -Path (binding)' {
        $mkv = Join-Path $TestDrive 'binding-continue.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        { Invoke-MkvRepair -Path $mkv -ContinueOnError } | Should -Throw
    }
}

Describe 'Get-DefaultMkvMergeExecutable' {
    It 'donne mkvmerge.exe sous Windows et mkvmerge sinon, et les deux commandes publiques s''en servent' {
        $expected = if ($IsWindows) { 'mkvmerge.exe' } else { 'mkvmerge' }
        InModuleScope 'Tetram.Media.Repair' { Get-DefaultMkvMergeExecutable } |
            Should -BeExactly $expected
        # DefaultValue n'est pas exposé sur le paramètre (expression évaluée à l'appel).
        (Get-Command Get-MkvInterleaveRepairCommand).Definition |
            Should -BeLike '*Get-DefaultMkvMergeExecutable*'
        (Get-Command Invoke-MkvRepair).Definition |
            Should -BeLike '*Get-DefaultMkvMergeExecutable*'
    }
}

Describe 'Get-MkvMergeInfo' {
    It 'lit le JSON redirigé quand mkvmerge rend 0 ou 1' {
        $tool = Join-Path $TestDrive 'mkvmerge-ok.ps1'
        New-FakeToolScript -Path $tool -ExitCode 1 -IdentificationJson '{"ok":true}'

        $info = InModuleScope 'Tetram.Media.Repair' -Parameters @{ Tool = $tool } {
            param($Tool)
            Get-MkvMergeInfo -MkvMerge $Tool -Path 'ignored.mkv'
        }

        $info.ok | Should -BeTrue
    }

    It 'ne rejoue pas les warnings JSON de mkvmerge -J pour un code 0 ou 1' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-code1-warnings.ps1'
        New-FakeToolScript -Path $tool -ExitCode 1 -IdentificationJson '{"ok":true,"warnings":["identification warning on success"],"errors":[]}'

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        $captured.Exception | Should -BeNullOrEmpty
        $native = @(Get-NativeDiagnosticSequence -Records $captured.Records -Text 'identification warning on success')
        $native | Should -HaveCount 0
        $captured.Output.Count | Should -Be 1
        $captured.Output[0].ok | Should -BeTrue
    }

    It 'restitue errors[] du JSON -J puis lève quand mkvmerge rend un code >= 2' {
        $tool = Join-Path $TestDrive 'mkvmerge-fail.ps1'
        $record = Join-Path $TestDrive 'mkvmerge-fail-redirect-path.txt'
        New-FakeToolScript `
            -Path $tool `
            -ExitCode 2 `
            -IdentificationJson '{"errors":["simulated identification failure"],"warnings":[]}' `
            -RedirectPathRecord $record

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $sequence = @(Get-DiagnosticSequence -Records $captured.Records)
        $native = @(Get-NativeDiagnosticSequence -Records $captured.Records -Text 'simulated identification failure')
        $native | Should -HaveCount 1
        $native[0].Kind | Should -Be 'Error'
        @($sequence | Where-Object { $_.Kind -eq 'Error' -and $_.Text -match 'mkvmerge -J a échoué' }) |
            Should -HaveCount 1
        Test-Path -LiteralPath $record | Should -BeTrue
        $logPath = (Get-Content -LiteralPath $record -Raw).Trim()
        $logPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $logPath | Should -BeFalse
    }

    It 'restitue warnings[] puis errors[] dans l''ordre des tableaux JSON' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-warn-then-error.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -IdentificationJson (@'
{
  "warnings": [
    "first identification warning",
    "second identification warning"
  ],
  "errors": [
    "final identification error"
  ]
}
'@)

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(
            Get-NativeDiagnosticSequence -Records $captured.Records -Text @(
                'first identification warning'
                'second identification warning'
                'final identification error'
            )
        )
        @(
            $native | ForEach-Object { '{0} {1}' -f $_.Kind, $_.Text }
        ) | Should -BeExactly @(
            'Warning first identification warning'
            'Warning second identification warning'
            'Error final identification error'
        )
    }

    It 'restitue plusieurs errors[] après le warning, sans en perdre' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-multi-error.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -IdentificationJson (@'
{
  "warnings": [
    "warning before failure"
  ],
  "errors": [
    "first identification error",
    "second identification error"
  ]
}
'@)

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(
            Get-NativeDiagnosticSequence -Records $captured.Records -Text @(
                'warning before failure'
                'first identification error'
                'second identification error'
            )
        )
        @(
            $native | ForEach-Object { '{0} {1}' -f $_.Kind, $_.Text }
        ) | Should -BeExactly @(
            'Warning warning before failure'
            'Error first identification error'
            'Error second identification error'
        )
    }

    It 'conserve l''UTF-8 des warnings et errors JSON' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-utf8.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -IdentificationJson (@'
{
  "warnings": [
    "piste « Français » — durée incohérente"
  ],
  "errors": [
    "échec d'accès au fichier « Français ».mkv"
  ]
}
'@)

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(
            Get-NativeDiagnosticSequence -Records $captured.Records -Text @(
                'piste « Français » — durée incohérente'
                "échec d'accès au fichier « Français ».mkv"
            )
        )
        $native.Count | Should -Be 2
        $native[0].Kind | Should -Be 'Warning'
        $native[0].Text | Should -BeExactly 'piste « Français » — durée incohérente'
        $native[1].Kind | Should -Be 'Error'
        $native[1].Text | Should -BeExactly "échec d'accès au fichier « Français ».mkv"
    }

    It 'lève sans inventer de diagnostic quand warnings[] et errors[] sont vides' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-empty-arrays.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -IdentificationJson '{"warnings":[],"errors":[]}'

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $sequence = @(Get-DiagnosticSequence -Records $captured.Records)
        @($sequence | Where-Object { $_.Kind -eq 'Warning' }) | Should -HaveCount 0
        @($sequence | Where-Object { $_.Kind -eq 'Error' -and $_.Text -notmatch 'mkvmerge -J a échoué' }) |
            Should -HaveCount 0
    }

    It 'traite warnings/errors JSON null comme des collections vides' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-null-arrays.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -IdentificationJson '{"warnings":null,"errors":null}'

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $sequence = @(Get-DiagnosticSequence -Records $captured.Records)
        @($sequence | Where-Object { $_.Kind -eq 'Warning' }) | Should -HaveCount 0
        @($sequence | Where-Object { $_.Kind -eq 'Error' -and $_.Text -notmatch 'mkvmerge -J a échoué' }) |
            Should -HaveCount 0
    }

    It 'accepte un JSON sans propriété warnings sous StrictMode' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-no-warnings.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -IdentificationJson '{"errors":["failure"]}'

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(Get-NativeDiagnosticSequence -Records $captured.Records -Text 'failure')
        $native | Should -HaveCount 1
        $native[0].Kind | Should -Be 'Error'
    }

    It 'accepte un JSON sans propriété errors sous StrictMode' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-no-errors.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -IdentificationJson '{"warnings":["warning"]}'

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(Get-NativeDiagnosticSequence -Records $captured.Records -Text 'warning')
        $native | Should -HaveCount 1
        $native[0].Kind | Should -Be 'Warning'
    }

    It 'ne laisse pas un JSON invalide masquer l''échec mkvmerge -J' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-invalid.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -IdentificationJson '{ invalid json'

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $captured.Exception.Exception.Message | Should -Not -Match 'JSON'
        $native = @(Get-NativeDiagnosticSequence -Records $captured.Records -Text '{ invalid json')
        $native | Should -HaveCount 1
        $native[0].Kind | Should -Be 'Error'
    }

    It 'ne laisse pas une capture vide masquer l''échec mkvmerge -J' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-empty.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $captured.Exception.Exception.Message | Should -Not -Match 'JSON'
        $sequence = @(Get-DiagnosticSequence -Records $captured.Records)
        @($sequence | Where-Object { $_.Kind -eq 'Error' -and $_.Text -notmatch 'mkvmerge -J a échoué' }) |
            Should -HaveCount 0
    }

    It 'rejoue un fallback texte Warning:/Error: seulement si le JSON d''identification est illisible' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-text-fallback.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -MuxDiagnostics "Warning: fallback warning`nError: fallback error"

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(
            Get-NativeDiagnosticSequence -Records $captured.Records -Text @(
                'fallback warning'
                'fallback error'
            )
        )
        @(
            $native | ForEach-Object { '{0} {1}' -f $_.Kind, $_.Text }
        ) | Should -BeExactly @(
            'Warning fallback warning'
            'Error fallback error'
        )
    }

    It 'expose un diagnostic brut non structuré avant l''exception synthétique avec le Path' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-unstructured.ps1'
        $path = 'V:\fake\problem.mkv'
        $rawText = 'some native mkvmerge diagnostic without Error prefix'
        New-FakeToolScript -Path $tool -ExitCode 2 -UnstructuredRedirectText $rawText

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool -Path $path
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path $path
        $native = @(Get-NativeDiagnosticSequence -Records $captured.Records -Text $rawText)
        $native | Should -HaveCount 1
        $native[0].Kind | Should -Be 'Error'

        $sequence = @(Get-DiagnosticSequence -Records $captured.Records)
        $nativeIdx = -1
        $synthIdx = -1
        for ($i = 0; $i -lt $sequence.Count; $i++) {
            if ($nativeIdx -lt 0 -and $sequence[$i].Text -eq $rawText) {
                $nativeIdx = $i
            }
            if ($synthIdx -lt 0 -and $sequence[$i].Text -match 'mkvmerge -J a échoué') {
                $synthIdx = $i
            }
        }
        $nativeIdx | Should -BeGreaterThan -1
        $synthIdx | Should -BeGreaterThan $nativeIdx
    }

    It 'n''affiche pas deux fois un JSON d''identification déjà interprété' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-no-json-dump.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -IdentificationJson '{"warnings":["warning"],"errors":["error"]}'

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(Get-NativeDiagnosticSequence -Records $captured.Records -Text @('warning', 'error'))
        @(
            $native | ForEach-Object { '{0} {1}' -f $_.Kind, $_.Text }
        ) | Should -BeExactly @(
            'Warning warning'
            'Error error'
        )
        $sequence = @(Get-DiagnosticSequence -Records $captured.Records)
        @($sequence | Where-Object { $_.Text -match '"warnings"' -or $_.Text -match '"errors"' }) |
            Should -HaveCount 0
    }

    It 'n''affiche pas deux fois un fallback texte Warning:/Error: déjà interprété' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-no-text-dump.ps1'
        $rawText = "Warning: warning`nError: error"
        New-FakeToolScript -Path $tool -ExitCode 2 -RedirectOutputText $rawText

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(Get-NativeDiagnosticSequence -Records $captured.Records -Text @('warning', 'error'))
        @(
            $native | ForEach-Object { '{0} {1}' -f $_.Kind, $_.Text }
        ) | Should -BeExactly @(
            'Warning warning'
            'Error error'
        )
        $sequence = @(Get-DiagnosticSequence -Records $captured.Records)
        @($sequence | Where-Object { $_.Text -eq $rawText }) | Should -HaveCount 0
    }

    It 'conserve toutes les lignes d''un diagnostic brut multi-ligne, dans l''ordre' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-multiline-raw.ps1'
        $rawText = "first native line`nsecond native line`nthird native line"
        New-FakeToolScript -Path $tool -ExitCode 2 -UnstructuredRedirectText $rawText

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(
            Get-DiagnosticSequence -Records $captured.Records |
                Where-Object { $_.Kind -eq 'Error' -and $_.Text -notmatch 'mkvmerge -J a échoué' }
        )
        $native | Should -HaveCount 1
        $native[0].Text | Should -BeExactly $rawText
        $native[0].Text | Should -Match '(?s)first native line.*second native line.*third native line'
    }

    It 'restitue exactement un diagnostic brut UTF-8 non structuré' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-utf8-raw.ps1'
        $rawText = "échec d'accès à « épisode Français ».mkv — donnée invalide"
        New-FakeToolScript -Path $tool -ExitCode 2 -UnstructuredRedirectText $rawText

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(Get-NativeDiagnosticSequence -Records $captured.Records -Text $rawText)
        $native | Should -HaveCount 1
        $native[0].Kind | Should -Be 'Error'
        $native[0].Text | Should -BeExactly $rawText
    }

    It 'expose le message localisé réel de --ui-language en_US (préfixe Erreur :, pas Error:)' {
        $tool = Join-Path $TestDrive 'mkvmerge-j-erreur-fr.ps1'
        $rawText = "Erreur : Aucune traduction n'est disponible pour «en_US»."
        New-FakeToolScript -Path $tool -ExitCode 2 -UnstructuredRedirectText $rawText

        $captured = Invoke-MkvMergeInfoCapturingDiagnostics -MkvMerge $tool
        Assert-MkvMergeJFailedException -Exception $captured.Exception -Path 'ignored.mkv'
        $native = @(Get-NativeDiagnosticSequence -Records $captured.Records -Text $rawText)
        $native | Should -HaveCount 1
        $native[0].Kind | Should -Be 'Error'
        $native[0].Text | Should -BeExactly $rawText
    }

    It 'force --ui-language en sur mkvmerge -J : MKVToolNix n''a pas de locale en_US' {
        $tool = Join-Path $TestDrive 'mkvmerge-ui-lang.ps1'
        $record = Join-Path $TestDrive 'mkvmerge-j-args.txt'
        New-FakeToolScript `
            -Path $tool `
            -ExitCode 2 `
            -IdentificationJson '{"errors":["simulated identification failure"],"warnings":[]}' `
            -ArgumentRecord $record

        InModuleScope 'Tetram.Media.Repair' -Parameters @{ Tool = $tool } {
            param($Tool)
            { Get-MkvMergeInfo -MkvMerge $Tool -Path 'ignored.mkv' } |
                Should -Throw '*mkvmerge -J a échoué*'
        }

        Test-Path -LiteralPath $record | Should -BeTrue
        $recorded = @(Get-Content -LiteralPath $record)
        $idx = [array]::IndexOf($recorded, '--ui-language')
        $idx | Should -BeGreaterThan -1
        $recorded[$idx + 1] | Should -BeExactly 'en'
        $recorded | Should -Not -Contain 'en_US'
    }
}

Describe 'Get-MkvInterleaveRepairCommand' {
    BeforeEach {
        Mock -ModuleName Tetram.Media.Repair Get-MkvMergeInfo {
            $script:mkvInfo
        }
    }

    It 'refuse un fichier absent avant d''appeler mkvmerge -J' {
        { Get-MkvInterleaveRepairCommand -Path (Join-Path $TestDrive 'missing.mkv') } |
            Should -Throw '*Fichier introuvable*'
        Should -Invoke -ModuleName Tetram.Media.Repair Get-MkvMergeInfo -Times 0
    }

    It 'refuse une sortie identique à la source' {
        $mkv = Join-Path $TestDrive 'same.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        { Get-MkvInterleaveRepairCommand -Path $mkv -OutputPath $mkv } |
            Should -Throw '*ne peut pas être le fichier source*'
        Should -Invoke -ModuleName Tetram.Media.Repair Get-MkvMergeInfo -Times 0
    }

    It 'refuse une sortie identique écrite avec le préfixe \\?\' {
        $mkv = Join-Path $TestDrive 'same-ext.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        $full = [System.IO.Path]::GetFullPath($mkv)
        { Get-MkvInterleaveRepairCommand -Path $mkv -OutputPath ('\\?\' + $full) } |
            Should -Throw '*ne peut pas être le fichier source*'
        Should -Invoke -ModuleName Tetram.Media.Repair Get-MkvMergeInfo -Times 0
    }

    It 'autorise une sortie qui ne diffère que par la casse hors Windows' {
        if ($IsWindows) {
            Set-ItResult -Skipped -Because 'NTFS ne distingue pas deux noms qui ne diffèrent que par la casse'
            return
        }

        $lower = Join-Path $TestDrive 'case.mkv'
        $upper = Join-Path $TestDrive 'CASE.mkv'
        Set-Content -LiteralPath $lower -Value 'fake'
        Set-Content -LiteralPath $upper -Value 'fake'
        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        { Get-MkvInterleaveRepairCommand -Path $lower -OutputPath $upper } |
            Should -Not -Throw
    }

    It 'dérive film.repaired.mkv à côté d''un .mkv, et suffixe sinon' {
        $mkv = Join-Path $TestDrive 'Film.MKV'
        $other = Join-Path $TestDrive 'clip.mp4'
        Set-Content -LiteralPath $mkv -Value 'fake'
        Set-Content -LiteralPath $other -Value 'fake'
        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video -Codec 'V_MPEGH/ISO/HEVC')
        )

        $fromMkv = Get-MkvInterleaveRepairCommand -Path $mkv
        $fromMkv.OutputPath | Should -BeExactly ([System.IO.Path]::GetFullPath((Join-Path $TestDrive 'Film.repaired.mkv')))

        $fromOther = Get-MkvInterleaveRepairCommand -Path $other
        $fromOther.OutputPath | Should -BeExactly ([System.IO.Path]::GetFullPath((Join-Path $TestDrive 'clip.mp4.repaired.mkv')))
    }

    It 'préfixe les chemins outils au-delà du seuil, y compris un mkvmerge encheminé' {
        $mkv = Join-Path $TestDrive 'long.mkv'
        $exe = Join-Path $TestDrive 'mkvmerge.exe'
        Set-Content -LiteralPath $mkv -Value 'fake'
        Set-Content -LiteralPath $exe -Value 'fake'
        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )

        $cmd = Get-MkvInterleaveRepairCommand -Path $mkv -MkvMerge $exe -ExtendedPathThreshold 1
        $fullIn = [System.IO.Path]::GetFullPath($mkv)
        $fullExe = [System.IO.Path]::GetFullPath($exe)
        if ($IsWindows) {
            $cmd.ToolInputPath | Should -Match '^[\\][\\][?][\\]'
            $cmd.ToolOutputPath | Should -Match '^[\\][\\][?][\\]'
            $cmd.Executable | Should -Match '^[\\][\\][?][\\]'
        }
        else {
            $cmd.ToolInputPath | Should -BeExactly $fullIn
            $cmd.Executable | Should -BeExactly $fullExe
            $cmd.ToolInputPath | Should -Not -Match '^[\\][\\][?][\\]'
            $cmd.ToolOutputPath | Should -Not -Match '^[\\][\\][?][\\]'
            $cmd.Executable | Should -Not -Match '^[\\][\\][?][\\]'
        }
        $cmd.InputPath | Should -Not -Match '^[\\][\\][?][\\]'
        $cmd.OutputPath | Should -Not -Match '^[\\][\\][?][\\]'
    }

    It 'lève sur un conteneur non reconnu, non Matroska, sans piste, ou sans A/V' {
        $mkv = Join-Path $TestDrive 'bad.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'

        $script:mkvInfo = New-MkvMergeInfo -Recognized $false -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        { Get-MkvInterleaveRepairCommand -Path $mkv } | Should -Throw '*non reconnu ou non supporté*'

        $script:mkvInfo = New-MkvMergeInfo -ContainerType 'AVI' -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        { Get-MkvInterleaveRepairCommand -Path $mkv } | Should -Throw '*destinée aux fichiers Matroska*'

        $script:mkvInfo = New-MkvMergeInfo -Tracks @()
        { Get-MkvInterleaveRepairCommand -Path $mkv } | Should -Throw '*Aucune piste trouvée*'

        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 2 -Type subtitles -Codec 'S_TEXT/UTF8')
        )
        { Get-MkvInterleaveRepairCommand -Path $mkv } | Should -Throw '*Aucune piste vidéo ou audio*'
    }

    It 'construit des readers séparés pour chaque piste A/V et rattache le reste au carrier' {
        $mkv = Join-Path $TestDrive "it's.mkv"
        Set-Content -LiteralPath $mkv -Value 'fake'
        $fullIn = [System.IO.Path]::GetFullPath($mkv)
        $fullOut = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "it's.repaired.mkv"))
        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video -Codec 'V_MPEGH/ISO/HEVC')
            (New-MkvTrack -Id 1 -Type audio -Codec 'A_EAC3')
            (New-MkvTrack -Id 2 -Type subtitles -Codec 'S_TEXT/UTF8')
        ) -Properties ([pscustomobject]@{
                segment_uid          = 'aabb'
                title                = "It's a film"
                timestamp_scale      = 1000000
                date_utc             = '2020-01-02T03:04:05Z'
                previous_segment_uid = 'prev'
                next_segment_uid     = 'next'
            })

        $cmd = Get-MkvInterleaveRepairCommand -Path $mkv
        $cmd.Arguments | Should -Be @(
            '-o'
            $fullOut
            '--segment-uid'
            'aabb'
            '--title'
            "It's a film"
            '--timestamp-scale'
            '1000000'
            '--date'
            '2020-01-02T03:04:05Z'
            '--link-to-previous'
            'prev'
            '--link-to-next'
            'next'
            '--track-order'
            '0:0,1:1,0:2'
            '--video-tracks'
            '0'
            '-A'
            '--track-tags'
            '0,2'
            $fullIn
            '--audio-tracks'
            '1'
            '-D'
            '-S'
            '-B'
            '-M'
            '--no-chapters'
            '--no-global-tags'
            '--track-tags'
            '1'
            $fullIn
        )
        $cmd.CommandLine | Should -BeLike "*'It''s a film'*"
        $cmd.Tracks.Count | Should -Be 3
        $cmd.Executable | Should -BeExactly $(if ($IsWindows) { 'mkvmerge.exe' } else { 'mkvmerge' })
    }

    It 'utilise --audio-tracks / -D quand le carrier n''est pas une vidéo' {
        $mkv = Join-Path $TestDrive 'audio-first.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        $fullIn = [System.IO.Path]::GetFullPath($mkv)
        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 3 -Type audio -Codec 'A_AAC')
            (New-MkvTrack -Id 4 -Type video -Codec 'V_MPEG4/ISO/AVC')
        )

        $cmd = Get-MkvInterleaveRepairCommand -Path $mkv
        $cmd.Arguments | Should -Be @(
            '-o'
            ([System.IO.Path]::GetFullPath((Join-Path $TestDrive 'audio-first.repaired.mkv')))
            '--track-order'
            '0:3,1:4'
            '--audio-tracks'
            '3'
            '-D'
            '--track-tags'
            '3'
            $fullIn
            '--video-tracks'
            '4'
            '-A'
            '-S'
            '-B'
            '-M'
            '--no-chapters'
            '--no-global-tags'
            '--track-tags'
            '4'
            $fullIn
        )
    }
}

Describe 'Get-MkvInterleaveRepairCommand - JSON hashtable mkvmerge -J' {
    It 'lit container et tracks depuis ConvertFrom-Json -AsHashtable' {
        $mkv = Join-Path $TestDrive 'from-json.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        $tool = Join-Path $TestDrive 'mkvmerge-hashtable.ps1'
        $json = '{"container":{"recognized":true,"supported":true,"type":"Matroska"},"tracks":[{"id":0,"type":"video","codec":"V_MPEGH/ISO/HEVC"}]}'
        New-FakeToolScript -Path $tool -ExitCode 0 -Flag '--redirect-output' -OutputText $json

        $cmd = Get-MkvInterleaveRepairCommand -Path $mkv -MkvMerge $tool

        $cmd.Tracks.Count | Should -Be 1
        $cmd.Tracks[0].id | Should -Be 0
        $cmd.Tracks[0].type | Should -BeExactly 'video'
        $cmd.Arguments | Should -Contain '--video-tracks'
    }
}

Describe 'Invoke-MkvRepair' {
    It 'n''appelle pas la réparation sous -WhatIf' {
        $mkv = Join-Path $TestDrive 'whatif.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        Mock -ModuleName Tetram.Media.Repair Invoke-MkvRepairFile { throw 'ne doit pas tourner' }

        { Invoke-MkvRepair -Path $mkv -WhatIf } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Repair Invoke-MkvRepairFile -Times 0
    }

    It 'délègue un fichier au réparateur interne' {
        $mkv = Join-Path $TestDrive 'one.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        Mock -ModuleName Tetram.Media.Repair Invoke-MkvRepairFile {}

        Invoke-MkvRepair -Path $mkv
        Should -Invoke -ModuleName Tetram.Media.Repair Invoke-MkvRepairFile -Times 1 -ParameterFilter {
            $Path -eq $mkv
        }
    }

    It 'lève si le dossier n''existe pas' {
        { Invoke-MkvRepair -Folder (Join-Path $TestDrive 'missing-dir') } |
            Should -Throw '*Dossier introuvable*'
    }

    It 'ne traite pas un dossier sans mkv writable' {
        Mock -ModuleName Tetram.Media.Repair Invoke-MkvRepairFile { throw 'ne doit pas tourner' }
        $folder = Join-Path $TestDrive 'nowrite'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $mp4 = Join-Path $folder 'clip.mp4'
        $ro = Join-Path $folder 'locked.mkv'
        Set-Content -LiteralPath $mp4 -Value 'fake'
        Set-Content -LiteralPath $ro -Value 'fake'
        [System.IO.File]::SetAttributes($ro, [System.IO.FileAttributes]::ReadOnly)
        try {
            Invoke-MkvRepair -Folder $folder
            Should -Invoke -ModuleName Tetram.Media.Repair Invoke-MkvRepairFile -Times 0
        }
        finally {
            [System.IO.File]::SetAttributes($ro, [System.IO.FileAttributes]::Normal)
        }
    }

    It 'matérialise la liste : sans -Recurse ignore le sous-dossier, avec -Recurse le parcourt' {
        $rootMkv = Join-Path $TestDrive 'root.mkv'
        $sub = Join-Path $TestDrive 'nested'
        New-Item -ItemType Directory -Path $sub | Out-Null
        $nestedMkv = Join-Path $sub 'child.mkv'
        Set-Content -LiteralPath $rootMkv -Value 'fake'
        Set-Content -LiteralPath $nestedMkv -Value 'fake'
        Mock -ModuleName Tetram.Media.Repair Invoke-MkvRepairFile {}

        Invoke-MkvRepair -Folder $TestDrive
        Should -Invoke -ModuleName Tetram.Media.Repair Invoke-MkvRepairFile -Times 1 -ParameterFilter {
            $Path -eq (Get-Item -LiteralPath $rootMkv).FullName
        }

        Invoke-MkvRepair -Folder $TestDrive -Recurse
        Should -Invoke -ModuleName Tetram.Media.Repair Invoke-MkvRepairFile -Times 2
        Should -Invoke -ModuleName Tetram.Media.Repair Invoke-MkvRepairFile -Times 1 -ParameterFilter {
            $Path -eq (Get-Item -LiteralPath $nestedMkv).FullName
        }
    }

    It 'en -Folder conserve un voisin .repaired.mkv et termine le lot' {
        $folder = Join-Path $TestDrive 'lib'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $src = Join-Path $folder 'film.mkv'
        $neighbor = Join-Path $folder 'film.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-folder-temp.ps1'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        Set-Content -LiteralPath $neighbor -Value 'keep-me' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 0 -OutputText 'repaired'
        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        Mock -ModuleName Tetram.Media.Repair Get-MkvMergeInfo {
            $script:mkvInfo
        }

        { Invoke-MkvRepair -Folder $folder -MkvMerge $tool } | Should -Not -Throw
        Test-Path -LiteralPath $src | Should -BeTrue
        Test-Path -LiteralPath $neighbor | Should -BeTrue
        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'repaired'
    }

    It 'en -Folder, un remux code 1 avertit, conserve la source, puis continue avec le fichier suivant' {
        $folder = Join-Path $TestDrive 'warn-then-ok'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $warnSrc = Join-Path $folder 'a-warn.mkv'
        $okSrc = Join-Path $folder 'b-ok.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-folder-warn-then-ok.ps1'
        Set-Content -LiteralPath $warnSrc -Value 'original-warn' -NoNewline
        Set-Content -LiteralPath $okSrc -Value 'original-ok' -NoNewline

        # a-warn.mkv est lexico avant b-ok.mkv : Get-ChildItem les traite dans cet ordre.
        @(
            '$all = [System.Collections.Generic.List[object]]::new()'
            'foreach ($item in $args) {'
            '    if ($item -is [System.Array]) {'
            '        foreach ($nested in $item) { [void]$all.Add($nested) }'
            '    }'
            '    else { [void]$all.Add($item) }'
            '}'
            '$isWarn = $false'
            'foreach ($item in $all) {'
            '    if ([string]$item -like ''*a-warn.mkv'') { $isWarn = $true }'
            '}'
            'for ($i = 0; $i -lt $all.Count; $i++) {'
            '    if ($all[$i] -eq ''--redirect-output'' -and ($i + 1) -lt $all.Count -and $isWarn) {'
            '        $log = ''Progress: 42%'' + [char]13 + ''Warning: The track timestamp scale is invalid'''
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], $log)'
            '    }'
            '    if ($all[$i] -eq ''-o'' -and ($i + 1) -lt $all.Count) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], $(if ($isWarn) { ''doubtful'' } else { ''repaired-ok'' }))'
            '    }'
            '}'
            'if ($isWarn) { exit 1 } else { exit 0 }'
        ) -join [Environment]::NewLine |
            Set-Content -LiteralPath $tool -Encoding utf8

        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        Mock -ModuleName Tetram.Media.Repair Get-MkvMergeInfo {
            $script:mkvInfo
        }

        $warnings = $null
        $passThru = @(
            Invoke-MkvRepair -Folder $folder -MkvMerge $tool -PassThru -WarningVariable warnings -WarningAction SilentlyContinue
        )

        $warningText = @($warnings) -join [Environment]::NewLine
        $warningText | Should -Match 'The track timestamp scale is invalid'
        $warningText | Should -Match 'a-warn\.mkv'
        Get-Content -LiteralPath $warnSrc -Raw | Should -BeExactly 'original-warn'
        Get-Content -LiteralPath $okSrc -Raw | Should -BeExactly 'repaired-ok'
        $passThru.Count | Should -Be 1
        $passThru[0].FullName | Should -BeExactly ([System.IO.Path]::GetFullPath($okSrc))
        @(Get-ChildItem -LiteralPath $folder -Filter '*.mkv').Name |
            Sort-Object |
            Should -Be @('a-warn.mkv', 'b-ok.mkv')
    }

    It 'en -Folder sans -ContinueOnError s''arrête au premier échec réel' {
        $folder = Join-Path $TestDrive 'stop-on-error'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $failSrc = Join-Path $folder 'a-fail.mkv'
        $okSrc = Join-Path $folder 'b-ok.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-folder-stop.ps1'
        Set-Content -LiteralPath $failSrc -Value 'original-fail' -NoNewline
        Set-Content -LiteralPath $okSrc -Value 'original-ok' -NoNewline

        @(
            '$all = [System.Collections.Generic.List[object]]::new()'
            'foreach ($item in $args) {'
            '    if ($item -is [System.Array]) {'
            '        foreach ($nested in $item) { [void]$all.Add($nested) }'
            '    }'
            '    else { [void]$all.Add($item) }'
            '}'
            '$isFail = $false'
            'foreach ($item in $all) {'
            '    if ([string]$item -like ''*a-fail.mkv'') { $isFail = $true }'
            '}'
            'for ($i = 0; $i -lt $all.Count; $i++) {'
            '    if ($all[$i] -eq ''--redirect-output'' -and ($i + 1) -lt $all.Count -and $isFail) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], "Error: simulated failure")'
            '    }'
            '    if ($all[$i] -eq ''-o'' -and ($i + 1) -lt $all.Count -and -not $isFail) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], ''repaired-ok'')'
            '    }'
            '}'
            'if ($isFail) { exit 2 } else { exit 0 }'
        ) -join [Environment]::NewLine |
            Set-Content -LiteralPath $tool -Encoding utf8

        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        Mock -ModuleName Tetram.Media.Repair Get-MkvMergeInfo {
            $script:mkvInfo
        }

        { Invoke-MkvRepair -Folder $folder -MkvMerge $tool } | Should -Throw '*mkvmerge a échoué*'
        Get-Content -LiteralPath $failSrc -Raw | Should -BeExactly 'original-fail'
        Get-Content -LiteralPath $okSrc -Raw | Should -BeExactly 'original-ok'
    }

    It 'en -Folder -ContinueOnError poursuit après un échec réel visible' {
        $folder = Join-Path $TestDrive 'continue-on-error'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $failSrc = Join-Path $folder 'a-fail.mkv'
        $okSrc = Join-Path $folder 'b-ok.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-folder-continue.ps1'
        Set-Content -LiteralPath $failSrc -Value 'original-fail' -NoNewline
        Set-Content -LiteralPath $okSrc -Value 'original-ok' -NoNewline

        @(
            '$all = [System.Collections.Generic.List[object]]::new()'
            'foreach ($item in $args) {'
            '    if ($item -is [System.Array]) {'
            '        foreach ($nested in $item) { [void]$all.Add($nested) }'
            '    }'
            '    else { [void]$all.Add($item) }'
            '}'
            '$isFail = $false'
            'foreach ($item in $all) {'
            '    if ([string]$item -like ''*a-fail.mkv'') { $isFail = $true }'
            '}'
            'for ($i = 0; $i -lt $all.Count; $i++) {'
            '    if ($all[$i] -eq ''--redirect-output'' -and ($i + 1) -lt $all.Count -and $isFail) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], "Error: simulated failure")'
            '    }'
            '    if ($all[$i] -eq ''-o'' -and ($i + 1) -lt $all.Count -and -not $isFail) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], ''repaired-ok'')'
            '    }'
            '}'
            'if ($isFail) { exit 2 } else { exit 0 }'
        ) -join [Environment]::NewLine |
            Set-Content -LiteralPath $tool -Encoding utf8

        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        Mock -ModuleName Tetram.Media.Repair Get-MkvMergeInfo {
            $script:mkvInfo
        }

        $errs = $null
        Invoke-MkvRepair -Folder $folder -MkvMerge $tool -ContinueOnError -ErrorAction Continue -ErrorVariable errs
        ($errs | Out-String) | Should -Match 'simulated failure'
        Get-Content -LiteralPath $failSrc -Raw | Should -BeExactly 'original-fail'
        Get-Content -LiteralPath $okSrc -Raw | Should -BeExactly 'repaired-ok'
    }

    It 'en -Folder -PassThru -ContinueOnError n''émet que les fichiers remplacés' {
        $folder = Join-Path $TestDrive 'passthru-continue'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $ok1 = Join-Path $folder 'a-ok.mkv'
        $failSrc = Join-Path $folder 'b-fail.mkv'
        $ok2 = Join-Path $folder 'c-ok.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-folder-passthru-continue.ps1'
        Set-Content -LiteralPath $ok1 -Value 'original-a' -NoNewline
        Set-Content -LiteralPath $failSrc -Value 'original-b' -NoNewline
        Set-Content -LiteralPath $ok2 -Value 'original-c' -NoNewline

        @(
            '$all = [System.Collections.Generic.List[object]]::new()'
            'foreach ($item in $args) {'
            '    if ($item -is [System.Array]) {'
            '        foreach ($nested in $item) { [void]$all.Add($nested) }'
            '    }'
            '    else { [void]$all.Add($item) }'
            '}'
            '$isFail = $false'
            'foreach ($item in $all) {'
            '    if ([string]$item -like ''*b-fail.mkv'') { $isFail = $true }'
            '}'
            'for ($i = 0; $i -lt $all.Count; $i++) {'
            '    if ($all[$i] -eq ''--redirect-output'' -and ($i + 1) -lt $all.Count -and $isFail) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], "Error: simulated failure")'
            '    }'
            '    if ($all[$i] -eq ''-o'' -and ($i + 1) -lt $all.Count -and -not $isFail) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], ''repaired-ok'')'
            '    }'
            '}'
            'if ($isFail) { exit 2 } else { exit 0 }'
        ) -join [Environment]::NewLine |
            Set-Content -LiteralPath $tool -Encoding utf8

        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        Mock -ModuleName Tetram.Media.Repair Get-MkvMergeInfo {
            $script:mkvInfo
        }

        $passThru = @(
            Invoke-MkvRepair -Folder $folder -MkvMerge $tool -PassThru -ContinueOnError -ErrorAction Continue
        )

        $passThru.Count | Should -Be 2
        $passThru[0].FullName | Should -BeExactly ([System.IO.Path]::GetFullPath($ok1))
        $passThru[1].FullName | Should -BeExactly ([System.IO.Path]::GetFullPath($ok2))
        Get-Content -LiteralPath $failSrc -Raw | Should -BeExactly 'original-b'
    }

    It 'en -Folder, un code 1 continue avec ou sans -ContinueOnError' {
        $folder = Join-Path $TestDrive 'warn-continue-switch'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $warnSrc = Join-Path $folder 'a-warn.mkv'
        $okSrc = Join-Path $folder 'b-ok.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-folder-warn-switch.ps1'
        Set-Content -LiteralPath $warnSrc -Value 'original-warn' -NoNewline
        Set-Content -LiteralPath $okSrc -Value 'original-ok' -NoNewline

        @(
            '$all = [System.Collections.Generic.List[object]]::new()'
            'foreach ($item in $args) {'
            '    if ($item -is [System.Array]) {'
            '        foreach ($nested in $item) { [void]$all.Add($nested) }'
            '    }'
            '    else { [void]$all.Add($item) }'
            '}'
            '$isWarn = $false'
            'foreach ($item in $all) {'
            '    if ([string]$item -like ''*a-warn.mkv'') { $isWarn = $true }'
            '}'
            'for ($i = 0; $i -lt $all.Count; $i++) {'
            '    if ($all[$i] -eq ''--redirect-output'' -and ($i + 1) -lt $all.Count -and $isWarn) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], "Warning: The track timestamp scale is invalid")'
            '    }'
            '    if ($all[$i] -eq ''-o'' -and ($i + 1) -lt $all.Count) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], $(if ($isWarn) { ''doubtful'' } else { ''repaired-ok'' }))'
            '    }'
            '}'
            'if ($isWarn) { exit 1 } else { exit 0 }'
        ) -join [Environment]::NewLine |
            Set-Content -LiteralPath $tool -Encoding utf8

        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        Mock -ModuleName Tetram.Media.Repair Get-MkvMergeInfo {
            $script:mkvInfo
        }

        $cases = @(
            @{ UseContinueOnError = $false }
            @{ UseContinueOnError = $true }
        )
        foreach ($case in $cases) {
            Set-Content -LiteralPath $warnSrc -Value 'original-warn' -NoNewline
            Set-Content -LiteralPath $okSrc -Value 'original-ok' -NoNewline
            $warnings = $null
            $errs = $null
            $invokeParams = @{
                Folder              = $folder
                MkvMerge            = $tool
                PassThru            = $true
                WarningVariable     = 'warnings'
                WarningAction       = 'SilentlyContinue'
                ErrorAction         = 'Continue'
                ErrorVariable       = 'errs'
            }
            if ($case.UseContinueOnError) {
                $invokeParams.ContinueOnError = $true
            }

            $passThru = @(Invoke-MkvRepair @invokeParams)
            ($warnings -join [Environment]::NewLine) | Should -Match 'The track timestamp scale is invalid'
            @($errs) | Should -HaveCount 0
            Get-Content -LiteralPath $warnSrc -Raw | Should -BeExactly 'original-warn'
            Get-Content -LiteralPath $okSrc -Raw | Should -BeExactly 'repaired-ok'
            $passThru.Count | Should -Be 1
        }
    }

    It 'en -Folder, un échec JSON de mkvmerge -J arrête le lot sans -ContinueOnError' {
        $folder = Join-Path $TestDrive 'ident-fail-stop'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $failSrc = Join-Path $folder 'a-ident-fail.mkv'
        $okSrc = Join-Path $folder 'b-ok.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-ident-fail-stop.ps1'
        Set-Content -LiteralPath $failSrc -Value 'original-fail' -NoNewline
        Set-Content -LiteralPath $okSrc -Value 'original-ok' -NoNewline
        New-FakeMkvMergeWithIdentificationFailure `
            -Path $tool `
            -FailFileName 'a-ident-fail.mkv' `
            -FailJson '{"warnings":["warning file 1"],"errors":["identification failure file 1"]}' `
            -OkJson '{"container":{"recognized":true,"supported":true,"type":"Matroska"},"tracks":[{"id":0,"type":"video","codec":"V"}]}'

        $records = [System.Collections.Generic.List[object]]::new()
        $exception = $null
        try {
            Invoke-MkvRepair -Folder $folder -MkvMerge $tool -WarningAction Continue -ErrorAction Continue 2>&1 3>&1 |
                ForEach-Object { [void]$records.Add($_) }
        }
        catch {
            $exception = $_
            [void]$records.Add($_)
        }

        $exception | Should -Not -BeNullOrEmpty
        Assert-MkvMergeJFailedException -Exception $exception -Path $failSrc
        $native = @(
            Get-NativeDiagnosticSequence -Records $records -Text @(
                'warning file 1'
                'identification failure file 1'
            )
        )
        @(
            $native | ForEach-Object { '{0} {1}' -f $_.Kind, $_.Text }
        ) | Should -BeExactly @(
            'Warning warning file 1'
            'Error identification failure file 1'
        )
        Get-Content -LiteralPath $failSrc -Raw | Should -BeExactly 'original-fail'
        Get-Content -LiteralPath $okSrc -Raw | Should -BeExactly 'original-ok'
    }

    It 'en -Folder -ContinueOnError poursuit si l''identification -J échoue' {
        $folder = Join-Path $TestDrive 'ident-fail-continue'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $failSrc = Join-Path $folder 'a-ident-fail.mkv'
        $okSrc = Join-Path $folder 'b-ok.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-ident-fail.ps1'
        Set-Content -LiteralPath $failSrc -Value 'original-fail' -NoNewline
        Set-Content -LiteralPath $okSrc -Value 'original-ok' -NoNewline
        New-FakeMkvMergeWithIdentificationFailure `
            -Path $tool `
            -FailFileName 'a-ident-fail.mkv' `
            -FailJson '{"warnings":["warning file 1"],"errors":["identification failure file 1"]}' `
            -OkJson '{"container":{"recognized":true,"supported":true,"type":"Matroska"},"tracks":[{"id":0,"type":"video","codec":"V"}]}'

        $records = [System.Collections.Generic.List[object]]::new()
        Invoke-MkvRepair -Folder $folder -MkvMerge $tool -ContinueOnError -WarningAction Continue -ErrorAction Continue 2>&1 3>&1 |
            ForEach-Object { [void]$records.Add($_) }

        $native = @(
            Get-NativeDiagnosticSequence -Records $records -Text @(
                'warning file 1'
                'identification failure file 1'
            )
        )
        @(
            $native | ForEach-Object { '{0} {1}' -f $_.Kind, $_.Text }
        ) | Should -BeExactly @(
            'Warning warning file 1'
            'Error identification failure file 1'
        )
        $sequence = @(Get-DiagnosticSequence -Records $records)
        $synthetic = @(
            $sequence | Where-Object { $_.Kind -eq 'Error' -and $_.Text -match 'mkvmerge -J a échoué' }
        )
        $synthetic | Should -HaveCount 1
        $synthetic[0].Text | Should -Match ([regex]::Escape($failSrc))
        Get-Content -LiteralPath $failSrc -Raw | Should -BeExactly 'original-fail'
        Get-Content -LiteralPath $okSrc -Raw | Should -BeExactly 'repaired-ok'
        @(Get-ChildItem -LiteralPath $folder -Filter '*.mkv').Name |
            Sort-Object |
            Should -Be @('a-ident-fail.mkv', 'b-ok.mkv')
    }

    It 'en -Folder, une erreur PowerShell propre au fichier obéit à -ContinueOnError' {
        $folder = Join-Path $TestDrive 'ghost-continue'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $ghostSrc = Join-Path $folder 'a-ghost.mkv'
        $okSrc = Join-Path $folder 'b-ok.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-folder-ghost.ps1'
        Set-Content -LiteralPath $ghostSrc -Value 'original-ghost' -NoNewline
        Set-Content -LiteralPath $okSrc -Value 'original-ok' -NoNewline

        @(
            '$all = [System.Collections.Generic.List[object]]::new()'
            'foreach ($item in $args) {'
            '    if ($item -is [System.Array]) {'
            '        foreach ($nested in $item) { [void]$all.Add($nested) }'
            '    }'
            '    else { [void]$all.Add($item) }'
            '}'
            '$isGhost = $false'
            'foreach ($item in $all) {'
            '    if ([string]$item -like ''*a-ghost.mkv'') { $isGhost = $true }'
            '}'
            'for ($i = 0; $i -lt $all.Count; $i++) {'
            '    if ($all[$i] -eq ''-o'' -and ($i + 1) -lt $all.Count -and -not $isGhost) {'
            '        [System.IO.File]::WriteAllText([string]$all[$i + 1], ''repaired-ok'')'
            '    }'
            '}'
            'exit 0'
        ) -join [Environment]::NewLine |
            Set-Content -LiteralPath $tool -Encoding utf8

        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        Mock -ModuleName Tetram.Media.Repair Get-MkvMergeInfo {
            $script:mkvInfo
        }

        { Invoke-MkvRepair -Folder $folder -MkvMerge $tool } | Should -Throw "*n'existe pas*"
        Get-Content -LiteralPath $okSrc -Raw | Should -BeExactly 'original-ok'

        Set-Content -LiteralPath $okSrc -Value 'original-ok' -NoNewline
        $errs = $null
        Invoke-MkvRepair -Folder $folder -MkvMerge $tool -ContinueOnError -ErrorAction Continue -ErrorVariable errs
        ($errs | Out-String) | Should -Match "n'existe pas"
        Get-Content -LiteralPath $ghostSrc -Raw | Should -BeExactly 'original-ghost'
        Get-Content -LiteralPath $okSrc -Raw | Should -BeExactly 'repaired-ok'
    }
}

Describe 'Invoke-MkvRepairFile' {
    It 'remplace le source par la sortie quand mkvmerge rend 0' {
        $src = Join-Path $TestDrive 'replace.mkv'
        $out = Join-Path $TestDrive 'replace.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-write.ps1'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 0 -OutputText 'repaired'
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        $item = Invoke-RepairFileUnderTest -Path $src -PassThru
        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'repaired'
        Test-Path -LiteralPath $out | Should -BeFalse
        $item.FullName | Should -BeExactly ([System.IO.Path]::GetFullPath($src))
    }

    It 'restitue CreationTime et LastWriteTime du source après le remplacement' {
        $src = Join-Path $TestDrive 'stamps.mkv'
        $out = Join-Path $TestDrive 'stamps.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-stamps.ps1'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        $stamp = [datetime]::new(2020, 6, 15, 12, 0, 0, [System.DateTimeKind]::Utc)
        $before = Get-Item -LiteralPath $src
        $before.CreationTimeUtc = $stamp
        $before.LastWriteTimeUtc = $stamp
        New-FakeToolScript -Path $tool -ExitCode 0 -OutputText 'repaired'
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        Invoke-RepairFileUnderTest -Path $src
        $after = Get-Item -LiteralPath $src
        $after.CreationTimeUtc | Should -Be $stamp
        $after.LastWriteTimeUtc | Should -Be $stamp
        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'repaired'
    }

    It 'ne mélange pas la progression mkvmerge au FileInfo de -PassThru' {
        $src = Join-Path $TestDrive 'passthru.mkv'
        $out = Join-Path $TestDrive 'passthru.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-stdout.ps1'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 0 -OutputText 'repaired' -StdoutText 'Progress: 50%'
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        $output = @(Invoke-RepairFileUnderTest -Path $src -PassThru)

        $output.Count | Should -Be 1
        $output[0] | Should -BeOfType ([System.IO.FileInfo])
        $output[0].FullName | Should -BeExactly ([System.IO.Path]::GetFullPath($src))
    }

    It 'avertit sans exception ni remplacement quand mkvmerge rend 1 sans sortie' {
        $src = Join-Path $TestDrive 'keep.mkv'
        $out = Join-Path $TestDrive 'keep.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-warn-run.ps1'
        $nativeWarning = New-MkvMergeMuxLog -WarningLine 'Warning: No default track for audio'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 1 -RedirectOutputText $nativeWarning
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        $passThru = @(Invoke-RepairFileUnderTest -Path $src -PassThru)
        $passThru | Should -HaveCount 0
        $script:LastRepairWarnings | Should -Not -BeNullOrEmpty
        ($script:LastRepairWarnings -join [Environment]::NewLine) | Should -Match 'No default track for audio'
        ($script:LastRepairWarnings -join [Environment]::NewLine) | Should -Match 'keep\.mkv'
        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'original'
        Test-Path -LiteralPath $out | Should -BeFalse
    }

    It 'avertit et supprime le temporaire quand mkvmerge rend 1 après avoir écrit une sortie' {
        # Un mux « réussi avec warnings » ne doit jamais s'installer : la sortie est douteuse.
        $src = Join-Path $TestDrive 'warn-written.mkv'
        $out = Join-Path $TestDrive 'warn-written.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-warn-written.ps1'
        $nativeWarning = New-MkvMergeMuxLog -WarningLine 'Warning: The track number 2 was not found'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 1 -OutputText 'doubtful' -RedirectOutputText $nativeWarning
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        { Invoke-RepairFileUnderTest -Path $src -PassThru } | Should -Not -Throw
        $script:LastRepairWarnings | Should -Not -BeNullOrEmpty
        ($script:LastRepairWarnings -join [Environment]::NewLine) | Should -Match 'The track number 2 was not found'
        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'original'
        Test-Path -LiteralPath $out | Should -BeFalse
    }

    It 'restitue chaque ligne Warning: de mkvmerge quand le code 1 en produit plusieurs' {
        $src = Join-Path $TestDrive 'multi-warn.mkv'
        $out = Join-Path $TestDrive 'multi-warn.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-multi-warn.ps1'
        $nativeLog = New-MkvMergeMuxLog -WarningLine @(
            'Warning: The track timestamp scale is invalid'
            'Warning: ''Default'' flag is not set on any track'
        )
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 1 -RedirectOutputText $nativeLog
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        Invoke-RepairFileUnderTest -Path $src
        $warningText = $script:LastRepairWarnings -join [Environment]::NewLine
        $warningText | Should -Match 'The track timestamp scale is invalid'
        $warningText | Should -Match "'Default' flag is not set on any track"
        $warningText | Should -Not -Match 'Progress: 42%'
        $script:LastRepairWarnings.Count | Should -Be 3
        @($script:LastRepairWarnings | Where-Object { $_ -match 'multi-warn\.mkv' }).Count |
            Should -Be 1
        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'original'
    }

    It 'supprime le journal temporaire de capture après un code 1' {
        $src = Join-Path $TestDrive 'log-cleanup.mkv'
        $out = Join-Path $TestDrive 'log-cleanup.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-log-cleanup.ps1'
        $record = Join-Path $TestDrive 'redirect-path.txt'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript `
            -Path $tool `
            -ExitCode 1 `
            -RedirectOutputText (New-MkvMergeMuxLog -WarningLine 'Warning: No default track for audio') `
            -RedirectPathRecord $record
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        Invoke-RepairFileUnderTest -Path $src
        Test-Path -LiteralPath $record | Should -BeTrue
        $logPath = (Get-Content -LiteralPath $record -Raw).Trim()
        $logPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $logPath | Should -BeFalse
    }

    It 'conserve le source et lève si mkvmerge rend un code >= 2' {
        $src = Join-Path $TestDrive 'keep-error.mkv'
        $out = Join-Path $TestDrive 'keep-error.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-fail-run.ps1'
        $record = Join-Path $TestDrive 'keep-error-redirect-path.txt'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript `
            -Path $tool `
            -ExitCode 2 `
            -OutputText 'partial' `
            -RedirectOutputText 'Error: simulated failure' `
            -RedirectPathRecord $record
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        $captured = Invoke-RepairFileCapturingDiagnostics -Path $src -PassThru
        $captured.Threw | Should -BeTrue
        $captured.Exception.Exception.Message | Should -Match 'mkvmerge a échoué'
        $sequence = @(Get-DiagnosticSequence -Records $captured.Records)
        @($sequence | Where-Object { $_.Kind -eq 'Error' -and $_.Text -match 'simulated failure' }) |
            Should -HaveCount 1
        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'original'
        Test-Path -LiteralPath $out | Should -BeFalse
        Test-Path -LiteralPath $record | Should -BeTrue
        $logPath = (Get-Content -LiteralPath $record -Raw).Trim()
        $logPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $logPath | Should -BeFalse
    }

    It 'restitue warnings puis erreur dans l''ordre mkvmerge pour un code 2' {
        $src = Join-Path $TestDrive 'warn-then-error.mkv'
        $out = Join-Path $TestDrive 'warn-then-error.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-warn-then-error.ps1'
        $nativeLog = @(
            'Warning: first warning'
            'Warning: second warning'
            'Error: final error'
        ) -join "`n"
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 2 -RedirectOutputText $nativeLog
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        $captured = Invoke-RepairFileCapturingDiagnostics -Path $src
        $captured.Threw | Should -BeTrue
        $sequence = @(Get-DiagnosticSequence -Records $captured.Records)
        $native = @(
            $sequence | Where-Object {
                $_.Text -eq 'first warning' -or
                $_.Text -eq 'second warning' -or
                $_.Text -eq 'final error'
            }
        )
        $native.Count | Should -Be 3
        $native[0].Kind | Should -Be 'Warning'
        $native[0].Text | Should -BeExactly 'first warning'
        $native[1].Kind | Should -Be 'Warning'
        $native[1].Text | Should -BeExactly 'second warning'
        $native[2].Kind | Should -Be 'Error'
        $native[2].Text | Should -BeExactly 'final error'
        @($sequence | Where-Object { $_.Text -eq 'first warning' }) | Should -HaveCount 1
        @($sequence | Where-Object { $_.Text -eq 'second warning' }) | Should -HaveCount 1
        @($sequence | Where-Object { $_.Text -eq 'final error' }) | Should -HaveCount 1
        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'original'
        Test-Path -LiteralPath $out | Should -BeFalse
    }

    It 'restitue un diagnostic mkvmerge UTF-8 sans corruption' {
        $src = Join-Path $TestDrive 'utf8-diag.mkv'
        $out = Join-Path $TestDrive 'utf8-diag.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-utf8-diag.ps1'
        $nativeLog = @(
            'Warning: piste « Français » — durée incohérente'
            "Error: échec d'accès au fichier"
        ) -join "`n"
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 2 -RedirectOutputText $nativeLog
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        $captured = Invoke-RepairFileCapturingDiagnostics -Path $src
        $captured.Threw | Should -BeTrue
        $sequence = @(Get-DiagnosticSequence -Records $captured.Records)
        @($sequence | Where-Object { $_.Kind -eq 'Warning' -and $_.Text -match 'Français' }) |
            Should -HaveCount 1
        @($sequence | Where-Object { $_.Kind -eq 'Error' -and $_.Text -match "échec d'accès au fichier" }) |
            Should -HaveCount 1
        ($sequence | Where-Object { $_.Text -match 'Français' }).Text |
            Should -BeExactly 'piste « Français » — durée incohérente'
    }

    It 'conserve le source si mkvmerge rend 0 sans créer la sortie' {
        $src = Join-Path $TestDrive 'ghost.mkv'
        $out = Join-Path $TestDrive 'ghost.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-ghost.ps1'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 0
        $script:repairCommand = [pscustomobject]@{
            Executable     = $tool
            Arguments      = @('-o', $out, $src)
            ToolOutputPath = $out
            ToolInputPath  = $src
            OutputPath     = $out
        }
        Mock -ModuleName Tetram.Media.Repair Get-MkvInterleaveRepairCommand {
            $script:repairCommand
        }

        { Invoke-RepairFileUnderTest -Path $src } | Should -Throw "*n'existe pas*"
        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'original'
    }

    It 'n''écrase pas un voisin .repaired.mkv déjà présent' {
        $src = Join-Path $TestDrive 'film.mkv'
        $neighbor = Join-Path $TestDrive 'film.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-unique-temp.ps1'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        Set-Content -LiteralPath $neighbor -Value 'keep-me' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 0 -OutputText 'repaired'
        $script:mkvInfo = New-MkvMergeInfo -Tracks @(
            (New-MkvTrack -Id 0 -Type video)
        )
        Mock -ModuleName Tetram.Media.Repair Get-MkvMergeInfo {
            $script:mkvInfo
        }

        Invoke-RepairFileUnderTest -Path $src -MkvMerge $tool

        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'repaired'
        Get-Content -LiteralPath $neighbor -Raw | Should -BeExactly 'keep-me'
        @(Get-ChildItem -LiteralPath $TestDrive -Filter 'film*.mkv').Name |
            Sort-Object |
            Should -Be @('film.mkv', 'film.repaired.mkv')
    }
}
