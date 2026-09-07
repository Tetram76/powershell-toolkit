# Étendre la suite autour de Tetram.Media.Repair.psm1 (Get-MkvInterleaveRepairCommand / Invoke-MkvRepair).
#
# RepoRoot depuis tests/<Module> : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Reencode') ; mocks -ModuleName Tetram.Media.Repair
# Get-TetramMkvMergeInfo / Invoke-TetramMkvRepairFile : InModuleScope 'Tetram.Media.Repair'
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

        @(
            "`$exitCode = $ExitCode"
            "`$writeOutput = `$$hasOutput"
            "`$flag = '$flagLiteral'"
            "`$text = '$outputLiteral'"
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
            'for ($i = 0; $i -lt $all.Count; $i++) {'
            '    if ($all[$i] -eq $flag -and ($i + 1) -lt $all.Count) {'
            '        if ($writeOutput) {'
            '            [System.IO.File]::WriteAllText([string]$all[$i + 1], $text)'
            '        }'
            '        break'
            '    }'
            '}'
            'exit $exitCode'
        ) -join [Environment]::NewLine |
            Set-Content -LiteralPath $Path -Encoding utf8
    }

    function script:Invoke-RepairFileUnderTest {
        param(
            [Parameter(Mandatory)] [string] $Path,
            [switch] $PassThru
        )

        InModuleScope 'Tetram.Media.Repair' -Parameters @{
            Path     = $Path
            PassThru = [bool] $PassThru
        } {
            param($Path, $PassThru)

            Invoke-TetramMkvRepairFile -Path $Path -MkvMerge 'mkvmerge.exe' -PassThru:$PassThru
        }
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
}

Describe 'ConvertFrom-TetramExtendedLengthPath / ConvertTo-TetramExtendedLengthPath' {
    It 'retire le préfixe \\?\ et \\?\UNC\' {
        InModuleScope 'Tetram.Media.Repair' {
            ConvertFrom-TetramExtendedLengthPath -Path '\\?\C:\Media\film.mkv' |
                Should -BeExactly 'C:\Media\film.mkv'
            ConvertFrom-TetramExtendedLengthPath -Path '\\?\UNC\server\share\film.mkv' |
                Should -BeExactly '\\server\share\film.mkv'
            ConvertFrom-TetramExtendedLengthPath -Path 'C:\Media\film.mkv' |
                Should -BeExactly 'C:\Media\film.mkv'
        }
    }

    It 'préfixe seulement au-delà du seuil, et laisse un chemin déjà étendu' {
        InModuleScope 'Tetram.Media.Repair' {
            $short = 'C:\Windows'
            ConvertTo-TetramExtendedLengthPath -Path $short -Threshold 160 |
                Should -BeExactly ([System.IO.Path]::GetFullPath($short))
            ConvertTo-TetramExtendedLengthPath -Path $short -Threshold 1 |
                Should -BeExactly ('\\?\' + [System.IO.Path]::GetFullPath($short))
            ConvertTo-TetramExtendedLengthPath -Path '\\?\C:\already' -Threshold 1 |
                Should -BeExactly '\\?\C:\already'
        }
    }
}

Describe 'Get-TetramMkvMergeInfo' {
    It 'lit le JSON redirigé quand mkvmerge rend 0 ou 1' {
        $tool = Join-Path $TestDrive 'mkvmerge-ok.ps1'
        New-FakeToolScript -Path $tool -ExitCode 1 -Flag '--redirect-output' -OutputText '{"ok":true}'

        $info = InModuleScope 'Tetram.Media.Repair' -Parameters @{ Tool = $tool } {
            param($Tool)
            Get-TetramMkvMergeInfo -MkvMerge $Tool -Path 'ignored.mkv'
        }

        $info.ok | Should -BeTrue
    }

    It 'lève quand mkvmerge -J rend un code >= 2' {
        $tool = Join-Path $TestDrive 'mkvmerge-fail.ps1'
        New-FakeToolScript -Path $tool -ExitCode 2 -Flag '--redirect-output'

        InModuleScope 'Tetram.Media.Repair' -Parameters @{ Tool = $tool } {
            param($Tool)
            { Get-TetramMkvMergeInfo -MkvMerge $Tool -Path 'ignored.mkv' } |
                Should -Throw '*mkvmerge -J a échoué*'
        }
    }
}

Describe 'Get-MkvInterleaveRepairCommand' {
    BeforeEach {
        Mock -ModuleName Tetram.Media.Repair Get-TetramMkvMergeInfo {
            $script:mkvInfo
        }
    }

    It 'refuse un fichier absent avant d''appeler mkvmerge -J' {
        { Get-MkvInterleaveRepairCommand -Path (Join-Path $TestDrive 'missing.mkv') } |
            Should -Throw '*Fichier introuvable*'
        Should -Invoke -ModuleName Tetram.Media.Repair Get-TetramMkvMergeInfo -Times 0
    }

    It 'refuse une sortie identique à la source' {
        $mkv = Join-Path $TestDrive 'same.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        { Get-MkvInterleaveRepairCommand -Path $mkv -OutputPath $mkv } |
            Should -Throw '*ne peut pas être le fichier source*'
        Should -Invoke -ModuleName Tetram.Media.Repair Get-TetramMkvMergeInfo -Times 0
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
        $cmd.ToolInputPath | Should -Match '^[\\][\\][?][\\]'
        $cmd.ToolOutputPath | Should -Match '^[\\][\\][?][\\]'
        $cmd.Executable | Should -Match '^[\\][\\][?][\\]'
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
        $cmd.Executable | Should -BeExactly 'mkvmerge.exe'
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

Describe 'Invoke-MkvRepair' {
    It 'n''appelle pas la réparation sous -WhatIf' {
        $mkv = Join-Path $TestDrive 'whatif.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        Mock -ModuleName Tetram.Media.Repair Invoke-TetramMkvRepairFile { throw 'ne doit pas tourner' }

        { Invoke-MkvRepair -Path $mkv -WhatIf } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Repair Invoke-TetramMkvRepairFile -Times 0
    }

    It 'délègue un fichier au réparateur interne' {
        $mkv = Join-Path $TestDrive 'one.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        Mock -ModuleName Tetram.Media.Repair Invoke-TetramMkvRepairFile {}

        Invoke-MkvRepair -Path $mkv
        Should -Invoke -ModuleName Tetram.Media.Repair Invoke-TetramMkvRepairFile -Times 1 -ParameterFilter {
            $Path -eq $mkv
        }
    }

    It 'lève si le dossier n''existe pas' {
        { Invoke-MkvRepair -Folder (Join-Path $TestDrive 'missing-dir') } |
            Should -Throw '*Dossier introuvable*'
    }

    It 'ne traite pas un dossier sans mkv writable' {
        Mock -ModuleName Tetram.Media.Repair Invoke-TetramMkvRepairFile { throw 'ne doit pas tourner' }
        $folder = Join-Path $TestDrive 'nowrite'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $mp4 = Join-Path $folder 'clip.mp4'
        $ro = Join-Path $folder 'locked.mkv'
        Set-Content -LiteralPath $mp4 -Value 'fake'
        Set-Content -LiteralPath $ro -Value 'fake'
        [System.IO.File]::SetAttributes($ro, [System.IO.FileAttributes]::ReadOnly)
        try {
            Invoke-MkvRepair -Folder $folder
            Should -Invoke -ModuleName Tetram.Media.Repair Invoke-TetramMkvRepairFile -Times 0
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
        Mock -ModuleName Tetram.Media.Repair Invoke-TetramMkvRepairFile {}

        Invoke-MkvRepair -Folder $TestDrive
        Should -Invoke -ModuleName Tetram.Media.Repair Invoke-TetramMkvRepairFile -Times 1 -ParameterFilter {
            $Path -eq (Get-Item -LiteralPath $rootMkv).FullName
        }

        Invoke-MkvRepair -Folder $TestDrive -Recurse
        Should -Invoke -ModuleName Tetram.Media.Repair Invoke-TetramMkvRepairFile -Times 2
        Should -Invoke -ModuleName Tetram.Media.Repair Invoke-TetramMkvRepairFile -Times 1 -ParameterFilter {
            $Path -eq (Get-Item -LiteralPath $nestedMkv).FullName
        }
    }
}

Describe 'Invoke-TetramMkvRepairFile' {
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

    It 'conserve le source si mkvmerge échoue' {
        $src = Join-Path $TestDrive 'keep.mkv'
        $out = Join-Path $TestDrive 'keep.repaired.mkv'
        $tool = Join-Path $TestDrive 'mkvmerge-fail-run.ps1'
        Set-Content -LiteralPath $src -Value 'original' -NoNewline
        New-FakeToolScript -Path $tool -ExitCode 1
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

        { Invoke-RepairFileUnderTest -Path $src } | Should -Throw "*mkvmerge a échoué*"
        Get-Content -LiteralPath $src -Raw | Should -BeExactly 'original'
        Test-Path -LiteralPath $out | Should -BeFalse
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
}
