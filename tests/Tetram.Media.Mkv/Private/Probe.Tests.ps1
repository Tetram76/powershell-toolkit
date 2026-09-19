# Étendre la suite autour du SUD Probe.ps1 (packets ffprobe PTS/pos + intégrité A/V).
#
# RepoRoot (trois `..`) : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Mkv') ; InModuleScope 'Tetram.Media.Mkv' { … }
# Mocks : -ModuleName Tetram.Media.Remux (Probe.ps1 est dot-sourcé dans ce nested ; un mock sur le parent Mkv n'intercepte pas Get-FFprobeJson).

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootProbe = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRootProbe 'Tetram.Media.Mkv') -Force -ErrorAction Stop

    function script:New-IntegrityPacket {
        param(
            $PtsTime,
            $Pos,
            $Size = 1000,
            $StreamIndex = $null
        )

        [pscustomobject]@{
            PtsTime     = $PtsTime
            Pos         = $Pos
            Size        = $Size
            StreamIndex = $StreamIndex
        }
    }

    function script:New-CfrPackets {
        param(
            [int] $Count,
            [double] $Fps,
            [double] $StartPts = 0,
            [long] $StartPos = 0,
            [long] $PosStep = 2000,
            [long] $Size = 1000,
            $StreamIndex = $null
        )

        $dt = 1.0 / $Fps
        $packets = @()
        for ($i = 0; $i -lt $Count; $i++)
        {
            $packets += New-IntegrityPacket `
                -PtsTime ($StartPts + $i * $dt) `
                -Pos ($StartPos + $i * $PosStep) `
                -Size $Size `
                -StreamIndex $StreamIndex
        }
        @($packets)
    }

    function script:New-StreamMap {
        param(
            [Parameter(Mandatory)] [string] $StreamType,
            [Parameter(Mandatory)] [int] $SourceRelativeIndex,
            [Parameter(Mandatory)] [int] $OutputRelativeIndex
        )

        [pscustomobject]@{
            StreamType          = $StreamType
            StreamSpecifierType = $(if ($StreamType -eq 'video') { 'v' } else { 'a' })
            SourceRelativeIndex = $SourceRelativeIndex
            OutputRelativeIndex = $OutputRelativeIndex
        }
    }

    function script:New-ProbeStream {
        param(
            [Parameter(Mandatory)] [string] $CodecType,
            [string] $CodecName,
            $Duration,
            $StartTime,
            [string] $DurationTag,
            $Index
        )

        $stream = @{ codec_type = $CodecType }
        if ($PSBoundParameters.ContainsKey('Index')) {
            $stream['index'] = $Index
        }
        if ($PSBoundParameters.ContainsKey('CodecName')) {
            $stream['codec_name'] = $CodecName
        }
        if ($PSBoundParameters.ContainsKey('Duration')) {
            $stream['duration'] = [string]$Duration
        }
        if ($PSBoundParameters.ContainsKey('StartTime')) {
            $stream['start_time'] = [string]$StartTime
        }
        if ($PSBoundParameters.ContainsKey('DurationTag')) {
            $stream['tags'] = @{ DURATION = $DurationTag }
        }
        $stream
    }

    function script:New-MediaProbe {
        param(
            $FormatDuration,
            $FormatStartTime,
            [object[]] $Streams = @()
        )

        $probe = @{
            streams = @($Streams)
            format  = @{}
        }
        if ($PSBoundParameters.ContainsKey('FormatDuration')) {
            $probe['format']['duration'] = [string]$FormatDuration
        }
        if ($PSBoundParameters.ContainsKey('FormatStartTime')) {
            $probe['format']['start_time'] = [string]$FormatStartTime
        }
        for ($i = 0; $i -lt @($probe['streams']).Count; $i++)
        {
            $stream = @($probe['streams'])[$i]
            if ($stream -is [hashtable] -and -not $stream.ContainsKey('index'))
            {
                $stream['index'] = $i
            }
        }
        $probe
    }

    function script:Invoke-IntegrityCheck {
        param(
            [Parameter(Mandatory)] [hashtable] $SourceProbe,
            [Parameter(Mandatory)] [hashtable] $TempProbe,
            [object[]] $StreamMaps = @((New-StreamMap -StreamType 'video' -SourceRelativeIndex 0 -OutputRelativeIndex 0))
        )

        $script:TempProbe = $TempProbe

        $bound = @{
            SourceProbe = $SourceProbe
            SourceFile  = $script:SourceFile
            TempFile    = $script:TempFile
            StreamMaps  = @($StreamMaps)
        }

        InModuleScope 'Tetram.Media.Mkv' -Parameters $bound {
            param(
                $SourceProbe,
                $SourceFile,
                $TempFile,
                $StreamMaps
            )

            Test-EncodedFileIntegrity `
                -FFPROBE 'ffprobe' `
                -SourceProbe $SourceProbe `
                -SourceFile $SourceFile `
                -TempFile $TempFile `
                -StreamMaps $StreamMaps
        }
    }

    function script:Set-DefaultPacketSamples {
        param(
            [double] $SourceSpan = 100,
            [double] $OutputSpan = 100,
            [double] $SourceFps = 25,
            [double] $OutputFps = 25,
            [double] $SourceAudioFps = 50,
            [double] $OutputAudioFps = 50,
            [double] $SourceStart = 0,
            [double] $OutputStart = 0,
            [double] $SourceAudioOffset = 0,
            [double] $OutputAudioOffset = 0
        )

        $script:PacketSampleTable = @{
            SourceVideoStart = New-CfrPackets -Count 32 -Fps $SourceFps -StartPts $SourceStart -StartPos 1000 -StreamIndex 0
            SourceVideoTail  = New-CfrPackets -Count 32 -Fps $SourceFps -StartPts ($SourceStart + $SourceSpan - 31.0 / $SourceFps) -StartPos 8000000 -StreamIndex 0
            OutputVideoStart = New-CfrPackets -Count 32 -Fps $OutputFps -StartPts $OutputStart -StartPos 5000000 -StreamIndex 0
            OutputVideoTail  = New-CfrPackets -Count 32 -Fps $OutputFps -StartPts ($OutputStart + $OutputSpan - 31.0 / $OutputFps) -StartPos 8100000 -StreamIndex 0
            SourceAudioStart = New-CfrPackets -Count 32 -Fps $SourceAudioFps -StartPts ($SourceStart + $SourceAudioOffset) -StartPos 1200 -Size 1536 -StreamIndex 1
            SourceAudioTail  = New-CfrPackets -Count 32 -Fps $SourceAudioFps -StartPts ($SourceStart + $SourceAudioOffset + $SourceSpan - 31.0 / $SourceAudioFps) -StartPos 8050000 -Size 1536 -StreamIndex 1
            OutputAudioStart = New-CfrPackets -Count 32 -Fps $OutputAudioFps -StartPts ($OutputStart + $OutputAudioOffset) -StartPos 5150000 -Size 1536 -StreamIndex 1
            OutputAudioTail  = New-CfrPackets -Count 32 -Fps $OutputAudioFps -StartPts ($OutputStart + $OutputAudioOffset + $OutputSpan - 31.0 / $OutputAudioFps) -StartPos 8150000 -Size 1536 -StreamIndex 1
            SourceAudio2Start = $null
            SourceAudio2Tail  = $null
            OutputAudio2Start = $null
            OutputAudio2Tail  = $null
            SourcePeek        = $null
            OutputPeek        = $null
        }
    }

    function script:Get-MixedFilePackets {
        param(
            $Video,
            $Audio,
            $Audio2
        )

        $mixed = @()
        foreach ($packet in @($Video))
        {
            $mixed += $packet
        }
        foreach ($packet in @($Audio))
        {
            $mixed += $packet
        }
        foreach ($packet in @($Audio2))
        {
            $mixed += $packet
        }
        return @($mixed)
    }

    function script:Get-PacketSampleMaxPts {
        param($Packets)

        $maxPts = $null
        foreach ($packet in @($Packets))
        {
            if ($null -eq $packet -or $null -eq $packet.PtsTime)
            {
                continue
            }
            if ($null -eq $maxPts -or [double]$packet.PtsTime -gt [double]$maxPts)
            {
                $maxPts = [double]$packet.PtsTime
            }
        }
        return $maxPts
    }

    function script:Resolve-PacketSample {
        param(
            [string] $File,
            [string] $StreamSpecifier,
            [string] $ReadIntervals
        )

        $isSource = $File -eq $script:SourceFile
        $isStart = $ReadIntervals -like '%+*'
        $windowStart = $null
        $windowEnd = $null
        $anchor = $null
        if ($ReadIntervals -match '^%\+(.+)$')
        {
            $windowStart = 0.0
            $windowEnd = [double]$Matches[1]
            $anchor = $windowEnd / 2.0
        }
        elseif ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
        {
            $windowStart = [double]$Matches[1]
            $windowEnd = [double]$Matches[2]
            $anchor = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
        }

        $videoStart = if ($isSource) { $script:PacketSampleTable.SourceVideoStart } else { $script:PacketSampleTable.OutputVideoStart }
        $videoTail = if ($isSource) { $script:PacketSampleTable.SourceVideoTail } else { $script:PacketSampleTable.OutputVideoTail }
        $audioStart = if ($isSource) { $script:PacketSampleTable.SourceAudioStart } else { $script:PacketSampleTable.OutputAudioStart }
        $audioTail = if ($isSource) { $script:PacketSampleTable.SourceAudioTail } else { $script:PacketSampleTable.OutputAudioTail }
        $audio2Start = if ($isSource) { $script:PacketSampleTable.SourceAudio2Start } else { $script:PacketSampleTable.OutputAudio2Start }
        $audio2Tail = if ($isSource) { $script:PacketSampleTable.SourceAudio2Tail } else { $script:PacketSampleTable.OutputAudio2Tail }

        if ([string]::IsNullOrWhiteSpace($StreamSpecifier))
        {
            if ($isStart)
            {
                return Get-MixedFilePackets -Video $videoStart -Audio $audioStart -Audio2 $audio2Start
            }

            if ($null -ne $windowStart)
            {
                $maxTailPts = Get-PacketSampleMaxPts -Packets $videoTail
                $span = $windowEnd - $windowStart
                if ($span -ge 9.0 -and $null -ne $maxTailPts -and $windowStart -ge ($maxTailPts - 0.05))
                {
                    $peek = if ($isSource) { $script:PacketSampleTable.SourcePeek } else { $script:PacketSampleTable.OutputPeek }
                    if ($null -eq $peek)
                    {
                        return ,([object[]]@())
                    }
                    return @($peek)
                }
            }

            return Get-MixedFilePackets -Video $videoTail -Audio $audioTail -Audio2 $audio2Tail
        }

        $pick = {
            param($StartPackets, $TailPackets, $Pos, $Size, $Index)
            if ($isStart) { return $StartPackets }
            if ($null -ne $anchor) {
                return @((New-IntegrityPacket -PtsTime $anchor -Pos $Pos -Size $Size -StreamIndex $Index))
            }
            return $TailPackets
        }

        if ($StreamSpecifier -like 'v:*')
        {
            return & $pick $videoStart $videoTail 5000000 1000 0
        }
        if ($StreamSpecifier -eq 'a:1')
        {
            $start2 = if ($null -ne $audio2Start) { $audio2Start } else { $audioStart }
            $tail2 = if ($null -ne $audio2Tail) { $audio2Tail } else { $audioTail }
            return & $pick $start2 $tail2 5200000 1536 2
        }
        return & $pick $audioStart $audioTail 5150000 1536 1
    }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Mkv' -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-IntegrityPacket — parsing' {
    It 'accepte un JSON packet normal' {
        $packet = InModuleScope 'Tetram.Media.Mkv' {
            ConvertTo-IntegrityPacket -Packet @{ pts_time = '1.25'; pos = '4096'; size = '512' }
        }
        $packet.PtsTime | Should -Be 1.25
        $packet.Pos | Should -Be 4096
        $packet.Size | Should -Be 512
        $packet.StreamIndex | Should -BeNullOrEmpty
    }

    It 'conserve stream_index quand il est présent' {
        $packet = InModuleScope 'Tetram.Media.Mkv' {
            ConvertTo-IntegrityPacket -Packet @{ pts_time = '0.04'; pos = '10'; size = '10'; stream_index = '2' }
        }
        $packet.StreamIndex | Should -Be 2
    }

    It 'traite pts_time absent comme indisponible' {
        $packet = InModuleScope 'Tetram.Media.Mkv' {
            ConvertTo-IntegrityPacket -Packet @{ pos = '10'; size = '10' }
        }
        $packet.PtsTime | Should -BeNullOrEmpty
    }

    It 'traite pos absent comme indisponible' {
        $packet = InModuleScope 'Tetram.Media.Mkv' {
            ConvertTo-IntegrityPacket -Packet @{ pts_time = '0.1'; size = '10' }
        }
        $packet.Pos | Should -BeNullOrEmpty
    }

    It 'traite pos = N/A comme indisponible' {
        $packet = InModuleScope 'Tetram.Media.Mkv' {
            ConvertTo-IntegrityPacket -Packet @{ pts_time = '0.1'; pos = 'N/A'; size = '10' }
        }
        $packet.Pos | Should -BeNullOrEmpty
    }

    It 'ne traite pas pos = -1 comme une position' {
        $packet = InModuleScope 'Tetram.Media.Mkv' {
            ConvertTo-IntegrityPacket -Packet @{ pts_time = '0.1'; pos = -1; size = '10' }
        }
        $packet.Pos | Should -BeNullOrEmpty
    }

    It 'traite size absent comme indisponible' {
        $packet = InModuleScope 'Tetram.Media.Mkv' {
            ConvertTo-IntegrityPacket -Packet @{ pts_time = '0.1'; pos = '10' }
        }
        $packet.Size | Should -BeNullOrEmpty
    }

    It 'parse pts_time avec InvariantCulture même en culture française' {
        $packet = InModuleScope 'Tetram.Media.Mkv' {
            $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo('fr-FR')
                ConvertTo-IntegrityPacket -Packet @{ pts_time = '0.04'; pos = '10'; size = '10' }
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
            }
        }
        $packet.PtsTime | Should -Be 0.04
    }

    It 'ignore packet.duration si elle est présente' {
        $packet = InModuleScope 'Tetram.Media.Mkv' {
            ConvertTo-IntegrityPacket -Packet @{ pts_time = '0.04'; pos = '10'; size = '10'; duration = '999'; duration_time = '999' }
        }
        $packet.PSObject.Properties.Name | Should -Not -Contain 'Duration'
        $packet.PtsTime | Should -Be 0.04
    }
}

Describe 'Get-IntegrityPacketWindow — ffprobe' {
    function script:New-FakeFfprobeScript {
        param(
            [Parameter(Mandatory)] [string] $Path,
            [int] $ExitCode = 0,
            [string] $Stdout = '',
            [string] $ArgumentRecord
        )

        $stdoutLiteral = $Stdout.Replace("'", "''")
        $recordLiteral = if ($PSBoundParameters.ContainsKey('ArgumentRecord')) {
            $ArgumentRecord.Replace("'", "''")
        }
        else {
            ''
        }
        $recordArguments = $PSBoundParameters.ContainsKey('ArgumentRecord')
        @(
            "`$exitCode = $ExitCode"
            "`$stdout = '$stdoutLiteral'"
            "`$recordArguments = `$$recordArguments"
            "`$argumentRecord = '$recordLiteral'"
            '$all = @()'
            'foreach ($item in $args) {'
            '    if ($item -is [System.Array]) {'
            '        foreach ($nested in $item) { $all += $nested }'
            '    }'
            '    else { $all += $item }'
            '}'
            'if ($recordArguments) { [System.IO.File]::WriteAllLines($argumentRecord, [string[]]$all) }'
            'if (-not [string]::IsNullOrEmpty($stdout)) { Write-Output $stdout }'
            'exit $exitCode'
        ) -join [Environment]::NewLine |
            Set-Content -LiteralPath $Path -Encoding utf8
    }

    It 'retourne null si ffprobe échoue' {
        $ffprobe = Join-Path $TestDrive 'ffprobe-fail.ps1'
        New-FakeFfprobeScript -Path $ffprobe -ExitCode 1
        $media = Join-Path $TestDrive 'media.mkv'
        Set-Content -LiteralPath $media -Value 'x'

        $result = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ FFPROBE = $ffprobe; File = $media } {
            param($FFPROBE, $File)
            Get-IntegrityPacketWindow -FFPROBE $FFPROBE -File $File -ReadIntervals '%+5'
        }

        $result | Should -BeNullOrEmpty
    }

    It 'retourne null si le JSON est invalide' {
        $ffprobe = Join-Path $TestDrive 'ffprobe-badjson.ps1'
        New-FakeFfprobeScript -Path $ffprobe -Stdout 'not-json'
        $media = Join-Path $TestDrive 'media.mkv'
        Set-Content -LiteralPath $media -Value 'x'

        $result = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ FFPROBE = $ffprobe; File = $media } {
            param($FFPROBE, $File)
            Get-IntegrityPacketWindow -FFPROBE $FFPROBE -File $File -ReadIntervals '%+5'
        }

        $result | Should -BeNullOrEmpty
    }

    It 'demande stream_index,pts_time,pos,size et jamais duration, sans -select_streams' {
        $argsFile = Join-Path $TestDrive 'ffprobe-args.txt'
        $ffprobe = Join-Path $TestDrive 'ffprobe-args.ps1'
        New-FakeFfprobeScript `
            -Path $ffprobe `
            -Stdout '{"packets":[{"stream_index":"1","pts_time":"0.04","pos":"100","size":"50"}]}' `
            -ArgumentRecord $argsFile
        $media = Join-Path $TestDrive 'media.mkv'
        Set-Content -LiteralPath $media -Value 'x'

        $packets = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ FFPROBE = $ffprobe; File = $media } {
            param($FFPROBE, $File)
            Get-IntegrityPacketWindow -FFPROBE $FFPROBE -File $File -ReadIntervals '%+5'
        }

        $packets.Count | Should -Be 1
        $packets[0].PtsTime | Should -Be 0.04
        $packets[0].StreamIndex | Should -Be 1
        $argLine = (Get-Content -LiteralPath $argsFile) -join ' '
        $argLine | Should -Not -Match '-select_streams'
        $argLine | Should -Match '-read_intervals'
        $argLine | Should -Match 'packet=stream_index,pts_time,pos,size'
        $argLine | Should -Not -Match 'duration'
    }

    It 'omet -select_streams pour une sonde fichier' {
        $argsFile = Join-Path $TestDrive 'ffprobe-file-args.txt'
        $ffprobe = Join-Path $TestDrive 'ffprobe-file-args.ps1'
        New-FakeFfprobeScript `
            -Path $ffprobe `
            -Stdout '{"packets":[{"stream_index":"0","pts_time":"0.04","pos":"100","size":"50"}]}' `
            -ArgumentRecord $argsFile
        $media = Join-Path $TestDrive 'media.mkv'
        Set-Content -LiteralPath $media -Value 'x'

        $null = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ FFPROBE = $ffprobe; File = $media } {
            param($FFPROBE, $File)
            Get-IntegrityPacketWindow -FFPROBE $FFPROBE -File $File -ReadIntervals '%+5'
        }

        $argLine = (Get-Content -LiteralPath $argsFile) -join ' '
        $argLine | Should -Not -Match '-select_streams'
        $argLine | Should -Match '-read_intervals'
    }

    It 'conserve -select_streams uniquement pour le fallback d''interleave ciblé' {
        $argsFile = Join-Path $TestDrive 'ffprobe-targeted-args.txt'
        $ffprobe = Join-Path $TestDrive 'ffprobe-targeted-args.ps1'
        New-FakeFfprobeScript `
            -Path $ffprobe `
            -Stdout '{"packets":[{"stream_index":"1","pts_time":"50","pos":"100","size":"50"}]}' `
            -ArgumentRecord $argsFile
        $media = Join-Path $TestDrive 'media.mkv'
        Set-Content -LiteralPath $media -Value 'x'

        $null = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ FFPROBE = $ffprobe; File = $media } {
            param($FFPROBE, $File)
            Get-IntegrityTargetedInterleavePackets -FFPROBE $FFPROBE -File $File -StreamSpecifier 'a:0' -ReadIntervals '45%55'
        }

        $argLine = (Get-Content -LiteralPath $argsFile) -join ' '
        $argLine | Should -Match '-select_streams'
        $argLine | Should -Match 'a:0'
        $argLine | Should -Match '-read_intervals'
        $argLine | Should -Match '45%55'
    }

    It 'préserve un tableau vide distinct de null quand packets est []' {
        $ffprobe = Join-Path $TestDrive 'ffprobe-empty.ps1'
        New-FakeFfprobeScript -Path $ffprobe -Stdout '{"packets":[]}'
        $media = Join-Path $TestDrive 'media.mkv'
        Set-Content -LiteralPath $media -Value 'x'

        $result = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ FFPROBE = $ffprobe; File = $media } {
            param($FFPROBE, $File)
            Get-IntegrityPacketWindow -FFPROBE $FFPROBE -File $File -ReadIntervals '%+5'
        }

        $null -eq $result | Should -BeFalse
        @($result).Count | Should -Be 0
    }

    It 'préserve un tableau vide distinct de null quand la clé packets est absente' {
        $ffprobe = Join-Path $TestDrive 'ffprobe-nopackets.ps1'
        New-FakeFfprobeScript -Path $ffprobe -Stdout '{}'
        $media = Join-Path $TestDrive 'media.mkv'
        Set-Content -LiteralPath $media -Value 'x'

        $result = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ FFPROBE = $ffprobe; File = $media } {
            param($FFPROBE, $File)
            Get-IntegrityPacketWindow -FFPROBE $FFPROBE -File $File -ReadIntervals '%+5'
        }

        $null -eq $result | Should -BeFalse
        @($result).Count | Should -Be 0
    }
}

Describe 'Get-IntegrityUnknownDetail' {
    It 'mappe no-end-packet-near-hint sur le même message que no-end-pts' {
        $fromHint = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityUnknownDetail -Integrity ([pscustomobject]@{
                    Reason               = 'no-end-packet-near-hint'
                    Method               = 'timestamp-span'
                    Side                 = 'source'
                    StreamType           = 'video'
                    SourceRelativeIndex  = 0
                    OutputRelativeIndex  = 0
                })
        }
        $fromPts = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityUnknownDetail -Integrity ([pscustomobject]@{
                    Reason               = 'no-end-pts'
                    Method               = 'timestamp-span'
                    Side                 = 'source'
                    StreamType           = 'video'
                    SourceRelativeIndex  = 0
                    OutputRelativeIndex  = 0
                })
        }
        $fromHint | Should -Be 'source 0:v:0 has no usable end PTS'
        $fromPts | Should -Be $fromHint
    }
}

Describe 'ConvertTo-IntegrityInvariantNumberString' {
    It 'n''émet pas de notation scientifique pour une petite valeur' {
        $text = InModuleScope 'Tetram.Media.Mkv' {
            ConvertTo-IntegrityInvariantNumberString -Value 0.000001
        }
        $text | Should -Be '0.000001'
        $text | Should -Not -Match '[eE]'
    }

    It 'reste parsable pour zéro et pour une cadence 25 fps' {
        $zero = InModuleScope 'Tetram.Media.Mkv' { ConvertTo-IntegrityInvariantNumberString -Value 0 }
        $cadence = InModuleScope 'Tetram.Media.Mkv' { ConvertTo-IntegrityInvariantNumberString -Value 0.04 }
        $zero | Should -Be '0'
        $cadence | Should -Be '0.04'
    }
}

Describe 'Get-IntegrityRelativeOffsetUnknownReason' {
    It 'signale no-start-cadence quand les PTS existent sans cadence' {
        $usable = [pscustomobject]@{ FirstPtsTime = 0.0; StartCadence = 0.04 }
        $noCadence = [pscustomobject]@{ FirstPtsTime = 0.1; StartCadence = $null }
        $reason = InModuleScope 'Tetram.Media.Mkv' -Parameters @{
            Usable = $usable
            NoCadence = $noCadence
        } {
            param($Usable, $NoCadence)
            Get-IntegrityRelativeOffsetUnknownReason `
                -SourceProfile $NoCadence `
                -OutputProfile $Usable `
                -SourceReference $Usable `
                -OutputReference $Usable
        }
        $reason | Should -Be 'no-start-cadence'
    }

    It 'signale no-start-pts quand un FirstPtsTime manque' {
        $usable = [pscustomobject]@{ FirstPtsTime = 0.0; StartCadence = 0.04 }
        $noPts = [pscustomobject]@{ FirstPtsTime = $null; StartCadence = 0.04 }
        $reason = InModuleScope 'Tetram.Media.Mkv' -Parameters @{
            Usable = $usable
            NoPts = $noPts
        } {
            param($Usable, $NoPts)
            Get-IntegrityRelativeOffsetUnknownReason `
                -SourceProfile $Usable `
                -OutputProfile $Usable `
                -SourceReference $NoPts `
                -OutputReference $Usable
        }
        $reason | Should -Be 'no-start-pts'
    }
}

Describe 'Get-IntegrityMedianPositivePtsDelta' {
    It 'calcule 0.04 pour une cadence 25 fps' {
        $packets = @(
            (New-IntegrityPacket -PtsTime 0.00 -Pos 0)
            (New-IntegrityPacket -PtsTime 0.04 -Pos 1)
            (New-IntegrityPacket -PtsTime 0.08 -Pos 2)
            (New-IntegrityPacket -PtsTime 0.12 -Pos 3)
        )
        $median = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Packets = $packets } {
            param($Packets)
            Get-IntegrityMedianPositivePtsDelta -Packets $Packets
        }
        [math]::Abs($median - 0.04) | Should -BeLessThan 1e-9
    }

    It 'n''utilise pas un gap isolé comme cadence' {
        $packets = @(
            (New-IntegrityPacket -PtsTime 0.00 -Pos 0)
            (New-IntegrityPacket -PtsTime 0.04 -Pos 1)
            (New-IntegrityPacket -PtsTime 0.08 -Pos 2)
            (New-IntegrityPacket -PtsTime 5.00 -Pos 3)
            (New-IntegrityPacket -PtsTime 5.04 -Pos 4)
        )
        $median = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Packets = $packets } {
            param($Packets)
            Get-IntegrityMedianPositivePtsDelta -Packets $Packets
        }
        [math]::Abs($median - 0.04) | Should -BeLessThan 1e-9
        $median | Should -BeLessThan 1
    }

    It 'ignore les doublons de PTS' {
        $packets = @(
            (New-IntegrityPacket -PtsTime 0.00 -Pos 0)
            (New-IntegrityPacket -PtsTime 0.00 -Pos 1)
            (New-IntegrityPacket -PtsTime 0.04 -Pos 2)
            (New-IntegrityPacket -PtsTime 0.08 -Pos 3)
        )
        $median = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Packets = $packets } {
            param($Packets)
            Get-IntegrityMedianPositivePtsDelta -Packets $Packets
        }
        [math]::Abs($median - 0.04) | Should -BeLessThan 1e-9
    }

    It 'trie des PTS présentés hors ordre de démux' {
        $packets = @(
            (New-IntegrityPacket -PtsTime 0.08 -Pos 0)
            (New-IntegrityPacket -PtsTime 0.00 -Pos 1)
            (New-IntegrityPacket -PtsTime 0.12 -Pos 2)
            (New-IntegrityPacket -PtsTime 0.04 -Pos 3)
        )
        $median = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Packets = $packets } {
            param($Packets)
            Get-IntegrityMedianPositivePtsDelta -Packets $Packets
        }
        [math]::Abs($median - 0.04) | Should -BeLessThan 1e-9
    }

    It 'retourne null pour un seul PTS' {
        $median = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Packets = @((New-IntegrityPacket -PtsTime 0.00 -Pos 0)) } {
            param($Packets)
            Get-IntegrityMedianPositivePtsDelta -Packets $Packets
        }
        $median | Should -BeNullOrEmpty
    }

    It 'retourne null sans PTS' {
        $median = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityMedianPositivePtsDelta -Packets @()
        }
        $median | Should -BeNullOrEmpty
    }

    It 'reste robuste en VFR' {
        $packets = @(
            (New-IntegrityPacket -PtsTime 0.00 -Pos 0)
            (New-IntegrityPacket -PtsTime 0.04 -Pos 1)
            (New-IntegrityPacket -PtsTime 0.10 -Pos 2)
            (New-IntegrityPacket -PtsTime 0.14 -Pos 3)
        )
        $median = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Packets = $packets } {
            param($Packets)
            Get-IntegrityMedianPositivePtsDelta -Packets $Packets
        }
        [math]::Abs($median - 0.04) | Should -BeLessThan 1e-9
    }

    It 'couvre 24/60/1 fps et une cadence audio' {
        foreach ($fps in @([double]24, [double]60, [double]1, [double](48000.0 / 1024.0)))
        {
            $packets = New-CfrPackets -Count 8 -Fps $fps
            $median = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Packets = $packets } {
                param($Packets)
                Get-IntegrityMedianPositivePtsDelta -Packets $Packets
            }
            [math]::Abs($median - (1.0 / $fps)) | Should -BeLessThan 1e-9
        }
    }
}

Describe 'Get-IntegrityTailSeekHint' {
    It 'préfère stream.start_time + stream.duration' {
        $hint = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityTailSeekHint `
                -Probe @{ format = @{ start_time = '1'; duration = '50' } } `
                -Stream @{ index = 0; start_time = '-0.04'; duration = '100' }
        }
        $hint | Should -Be 99.96
    }

    It 'utilise format.start_time + format.duration sinon' {
        $hint = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityTailSeekHint `
                -Probe @{ format = @{ start_time = '1.5'; duration = '10' } } `
                -Stream @{ index = 0 }
        }
        $hint | Should -Be 11.5
    }

    It 'accepte un start_time positif et un média plus court que 10 s' {
        $hint = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityTailSeekHint `
                -Probe @{ format = @{ duration = '4' } } `
                -Stream @{ index = 0; duration = '3' }
        }
        $hint | Should -Be 3
    }

    It 'retourne null sans aucune metadata exploitable' {
        $hint = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityTailSeekHint -Probe @{ format = @{} } -Stream @{ index = 0 }
        }
        $hint | Should -BeNullOrEmpty
    }

    It 'ignore une duration nulle ou négative' {
        $hint = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityTailSeekHint `
                -Probe @{ format = @{ duration = '0' } } `
                -Stream @{ index = 0; duration = '-1' }
        }
        $hint | Should -BeNullOrEmpty
    }
}

Describe 'Get-IntegrityTailReadInterval' {
    It 'ferme la fenêtre à (hint-10)%(hint+5)' {
        $interval = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityTailReadInterval -Hint 100.24
        }
        $interval | Should -Be '90.24%105.24'
    }

    It 'borne un hint court à 0%(hint+5)' {
        $interval = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityTailReadInterval -Hint 4
        }
        $interval | Should -Be '0%9'
    }
}

Describe 'Get-IntegrityTailGuardInterval' {
    It 'ouvre une guard (hint+5)%(hint+15)' {
        $interval = InModuleScope 'Tetram.Media.Mkv' {
            Get-IntegrityTailGuardInterval -Hint 80
        }
        $interval | Should -Be '85%95'
    }
}

Describe 'Get-IntegrityPacketsForAbsoluteStream' {
    It 'conserve les packets non indexés (mocks unitaires) et ignore les non indexés d''un échantillon mixte' {
        $unindexed = @(
            (New-IntegrityPacket -PtsTime 0 -Pos 1 -Size 10)
            (New-IntegrityPacket -PtsTime 0.04 -Pos 2 -Size 10)
        )
        $kept = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Packets = $unindexed } {
            param($Packets)
            Get-IntegrityPacketsForAbsoluteStream -Packets $Packets -AbsoluteStreamIndex 0
        }
        @($kept).Count | Should -Be 2

        $mixed = @(
            (New-IntegrityPacket -PtsTime 0 -Pos 1 -Size 10)
            (New-IntegrityPacket -PtsTime 0.02 -Pos 2 -Size 10 -StreamIndex 1)
            (New-IntegrityPacket -PtsTime 0.04 -Pos 3 -Size 10 -StreamIndex 0)
        )
        $selected = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Packets = $mixed } {
            param($Packets)
            Get-IntegrityPacketsForAbsoluteStream -Packets $Packets -AbsoluteStreamIndex 0
        }
        @($selected).Count | Should -Be 1
        $selected[0].PtsTime | Should -Be 0.04
    }

    It 'filtre par stream_index quand il est présent' {
        $packets = @(
            (New-IntegrityPacket -PtsTime 0 -Pos 1 -Size 10 -StreamIndex 0)
            (New-IntegrityPacket -PtsTime 0.02 -Pos 2 -Size 10 -StreamIndex 1)
            (New-IntegrityPacket -PtsTime 0.04 -Pos 3 -Size 10 -StreamIndex 0)
        )
        $selected = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Packets = $packets } {
            param($Packets)
            Get-IntegrityPacketsForAbsoluteStream -Packets $Packets -AbsoluteStreamIndex 0
        }
        @($selected).Count | Should -Be 2
        $selected[0].PtsTime | Should -Be 0
        $selected[1].PtsTime | Should -Be 0.04
    }
}

Describe 'Get-IntegrityTemporalProfile' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'x'
        $script:SampleCalls = @()
    }

    It 'construit un profil normal utilisable' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 32 -Fps 25
            }
            if ($ReadIntervals -eq '105.24%115.24') {
                return ,([object[]]@())
            }
            return New-CfrPackets -Count 32 -Fps 25 -StartPts 99.0
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '100.24' } } `
                -Stream @{ index = 0; duration = '100.24'; start_time = '0' }
        }

        $profile.IsUsable | Should -BeTrue
        $profile.FirstPtsTime | Should -Be 0
        $profile.LastPtsTime | Should -Be (99.0 + 31.0 / 25)
        [math]::Abs($profile.StartCadence - 0.04) | Should -BeLessThan 1e-9
        [math]::Abs($profile.Cadence - 0.04) | Should -BeLessThan 1e-9
        $script:SampleCalls[0] | Should -Be '%+5'
        $script:SampleCalls[1] | Should -Be '90.24%105.24'
        $script:SampleCalls[2] | Should -Be '105.24%115.24'
    }

    It 'reste utilisable avec des timestamps négatifs' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25 -StartPts -0.08
            }
            if ($ReadIntervals -match '^([0-9eE.+-]+)%' -and [double]$Matches[1] -ge 100) {
                return ,([object[]]@())
            }
            return New-CfrPackets -Count 8 -Fps 25 -StartPts 99.84
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '100' } } `
                -Stream @{ index = 0; start_time = '-0.08'; duration = '100' }
        }

        $profile.IsUsable | Should -BeTrue
        $profile.FirstPtsTime | Should -Be -0.08
        $profile.SpanSeconds | Should -BeGreaterThan 99
    }

    It 'ignore packet.duration absente' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            @(
                (New-IntegrityPacket -PtsTime 0.00 -Pos 1)
                (New-IntegrityPacket -PtsTime 0.04 -Pos 2)
                (New-IntegrityPacket -PtsTime 0.08 -Pos 3)
            )
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '20' } } `
                -Stream @{ index = 0; duration = '20' }
        }

        $profile.StartCadence | Should -Be 0.04
    }

    It 'devient unknown sans hint de fin et ne scanne pas tout le fichier' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            return New-CfrPackets -Count 8 -Fps 25
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{} } `
                -Stream @{ index = 0 }
        }

        $profile.IsUsable | Should -BeFalse
        $profile.UnknownReason | Should -Be 'no-tail-seek-hint'
        $script:SampleCalls.Count | Should -Be 1
        $script:SampleCalls[0] | Should -Be '%+5'
    }

    It 'signale tail-probe-failed si la sonde de fin échoue' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25
            }
            return $null
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '100' } } `
                -Stream @{ index = 0; duration = '100' }
        }

        $profile.IsUsable | Should -BeFalse
        $profile.UnknownReason | Should -Be 'tail-probe-failed'
    }

    It 'signale no-end-pts si la fin n''a pas de PTS' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25
            }
            return @((New-IntegrityPacket -PtsTime $null -Pos 1))
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '100' } } `
                -Stream @{ index = 0; duration = '100' }
        }

        $profile.UnknownReason | Should -Be 'no-end-packet-near-hint'
        $profile.IsUsable | Should -BeFalse
    }

    It 'signale no-end-packet-near-hint si la sonde de fin réussit sans packet' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25
            }
            return ,@()
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '100' } } `
                -Stream @{ index = 0; duration = '100' }
        }

        $profile.IsUsable | Should -BeFalse
        $profile.UnknownReason | Should -Be 'no-end-packet-near-hint'
    }

    It 'recule de 10 s sur un hint légèrement sous-estimé' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25
            }
            return New-CfrPackets -Count 8 -Fps 25 -StartPts 85.0
        }

        $null = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '95' } } `
                -Stream @{ index = 0; duration = '95'; start_time = '0' }
        }

        $script:SampleCalls[1] | Should -Be '85%100'
    }

    It 'recule de 10 s sur un hint légèrement surestimé' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25
            }
            return New-CfrPackets -Count 8 -Fps 25 -StartPts 95.0
        }

        $null = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '105' } } `
                -Stream @{ index = 0; duration = '105'; start_time = '0' }
        }

        $script:SampleCalls[1] | Should -Be '95%110'
    }

    It 'reste utilisable si le seek de fin retombe avant la cible, sans rescan' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25
            }
            return New-CfrPackets -Count 8 -Fps 25 -StartPts 80.0
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '100' } } `
                -Stream @{ index = 0; duration = '100'; start_time = '0' }
        }

        $profile.IsUsable | Should -BeFalse
        $profile.UnknownReason | Should -Be 'no-end-packet-near-hint'
        $script:SampleCalls | Should -Contain '90%105'
        $script:SampleCalls | Should -Not -Contain '70%85'
        foreach ($call in $script:SampleCalls)
        {
            $call | Should -Not -Match '^[0-9eE.+-]+%$'
        }
    }

    It 'signale tail-hint-underestimates-stream si le peek voit des packets au-delà du hint' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25
            }
            if ($ReadIntervals -eq '90%105') {
                return New-CfrPackets -Count 8 -Fps 25 -StartPts 99.72
            }
            return New-CfrPackets -Count 8 -Fps 25 -StartPts 105.04
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '100' } } `
                -Stream @{ index = 0; duration = '100'; start_time = '0' }
        }

        $profile.IsUsable | Should -BeFalse
        $profile.UnknownReason | Should -Be 'tail-hint-underestimates-stream'
        $script:SampleCalls | Should -Contain '105%115'
    }

    It 'reste utilisable si le peek au-delà du hint est vide' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25
            }
            if ($ReadIntervals -eq '90%105') {
                return New-CfrPackets -Count 8 -Fps 25 -StartPts 99.72
            }
            return ,([object[]]@())
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '100' } } `
                -Stream @{ index = 0; duration = '100'; start_time = '0' }
        }

        $profile.IsUsable | Should -BeTrue
        $profile.LastPtsTime | Should -Be (99.72 + 7.0 / 25)
    }

    It 'cherche localement une piste dont start_time dépasse l''échantillon fichier' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25 -StreamIndex 0
            }
            if ($ReadIntervals -eq '75%85') {
                return New-CfrPackets -Count 8 -Fps 25 -StartPts 80 -StreamIndex 1
            }
            if ($ReadIntervals -eq '90%105') {
                return New-CfrPackets -Count 8 -Fps 25 -StartPts 90 -StreamIndex 1
            }
            return ,([object[]]@())
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '100' } } `
                -Stream @{ index = 1; start_time = '80'; duration = '20' }
        }

        $profile.IsUsable | Should -BeTrue
        $profile.FirstPtsTime | Should -Be 80
        $script:SampleCalls | Should -Contain '75%85'
    }

    It 'signale no-start-cadence s''il n''y a pas assez de PTS distincts' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            if ($ReadIntervals -eq '%+5') {
                return @((New-IntegrityPacket -PtsTime 0 -Pos 1 -Size 10))
            }
            return New-CfrPackets -Count 8 -Fps 25 -StartPts 90
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '100' } } `
                -Stream @{ index = 0; duration = '100' }
        }

        $profile.IsUsable | Should -BeFalse
        $profile.UnknownReason | Should -Be 'no-start-cadence'
    }

    It 'localise un stream à 1200 s via start_time sans scanner depuis 0' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25 -StreamIndex 0
            }
            if ($ReadIntervals -eq '1195%1205') {
                return New-CfrPackets -Count 8 -Fps 25 -StartPts 1200 -StreamIndex 1
            }
            if ($ReadIntervals -eq '1210%1225') {
                return New-CfrPackets -Count 8 -Fps 25 -StartPts 1218 -StreamIndex 1
            }
            return ,([object[]]@())
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            throw 'fallback ciblé interdit sur le chemin temporel'
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '1220' } } `
                -Stream @{ index = 1; start_time = '1200'; duration = '20' }
        }

        $profile.IsUsable | Should -BeTrue
        $profile.FirstPtsTime | Should -Be 1200
        $script:SampleCalls | Should -Contain '1195%1205'
        $script:SampleCalls | Should -Not -Contain '0%1200'
        foreach ($call in $script:SampleCalls)
        {
            $call | Should -Not -Match '%\+#\d+$'
            $call | Should -Not -Match '^[0-9eE.+-]+%$'
        }
    }

    It 'signale no-start-seek-hint sans start_time pour un stream absent du début' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            return New-CfrPackets -Count 8 -Fps 25 -StreamIndex 0
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ start_time = '0'; duration = '1220' } } `
                -Stream @{ index = 1 }
        }

        $profile.IsUsable | Should -BeFalse
        $profile.UnknownReason | Should -Be 'no-start-seek-hint'
        $script:SampleCalls.Count | Should -Be 1
        $script:SampleCalls[0] | Should -Be '%+5'
    }

    It 'devient unknown si duration est nulle et n''émet pas 0%' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            return New-CfrPackets -Count 8 -Fps 25
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '0' } } `
                -Stream @{ index = 0; duration = '0' }
        }

        $profile.IsUsable | Should -BeFalse
        $profile.UnknownReason | Should -Be 'no-tail-seek-hint'
        $script:SampleCalls.Count | Should -Be 1
        $script:SampleCalls[0] | Should -Be '%+5'
        $script:SampleCalls | Should -Not -Contain '0%'
    }

    It 'sonde un média court avec une fenêtre tail fermée depuis 0' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:SampleCalls += $ReadIntervals
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 8 -Fps 25
            }
            if ($ReadIntervals -eq '9%19') {
                return ,([object[]]@())
            }
            return New-CfrPackets -Count 8 -Fps 25 -StartPts 3.0
        }

        $profile = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            Get-IntegrityTemporalProfile `
                -FFPROBE 'ffprobe' `
                -File $File `
                -Probe @{ format = @{ duration = '4' } } `
                -Stream @{ index = 0; duration = '4'; start_time = '0' }
        }

        $profile.IsUsable | Should -BeTrue
        $script:SampleCalls[1] | Should -Be '0%9'
        $script:SampleCalls[2] | Should -Be '9%19'
    }

    It 'partage une fenêtre cache entre plusieurs streams du même intervalle' {
        $script:WindowCalls = 0
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $script:WindowCalls++
            $script:SampleCalls += $ReadIntervals
            @(
                (New-IntegrityPacket -PtsTime 95 -Pos 1 -Size 10 -StreamIndex 0)
                (New-IntegrityPacket -PtsTime 95 -Pos 2 -Size 10 -StreamIndex 1)
                (New-IntegrityPacket -PtsTime 95 -Pos 3 -Size 10 -StreamIndex 2)
                (New-IntegrityPacket -PtsTime 95 -Pos 4 -Size 10 -StreamIndex 3)
            )
        }

        $count = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ File = $script:SourceFile } {
            param($File)
            $cache = @{}
            foreach ($index in 0..3)
            {
                $null = Get-CachedIntegrityPacketWindow `
                    -Cache $cache `
                    -FFPROBE 'ffprobe' `
                    -File $File `
                    -ReadIntervals '90%105'
                $null = Get-IntegrityPacketsForAbsoluteStream `
                    -Packets (Get-CachedIntegrityPacketWindow `
                        -Cache $cache `
                        -FFPROBE 'ffprobe' `
                        -File $File `
                        -ReadIntervals '90%105') `
                    -AbsoluteStreamIndex $index
            }
            $cache.Count
        }

        $script:WindowCalls | Should -Be 1
        $count | Should -Be 1
    }
}

Describe 'Test-EncodedFileIntegrity — span / offset / mapping' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        $script:PacketSampleCalls = @()
        Set-DefaultPacketSamples
        Mock -ModuleName Tetram.Media.Remux Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($File, $ReadIntervals)
            $script:PacketSampleCalls += [pscustomobject]@{
                File = $File
                Spec = ''
                Interval = $ReadIntervals
            }
            Resolve-PacketSample -File $File -StreamSpecifier '' -ReadIntervals $ReadIntervals
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            param($File, $StreamSpecifier, $ReadIntervals)
            $script:PacketSampleCalls += [pscustomobject]@{
                File = $File
                Spec = $StreamSpecifier
                Interval = $ReadIntervals
            }
            Resolve-PacketSample -File $File -StreamSpecifier $StreamSpecifier -ReadIntervals $ReadIntervals
        }
    }

    It 'passe un réencodage normal de même span' {
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 0)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'complete'
    }

    It 'accepte une translation globale des PTS' {
        Set-DefaultPacketSamples -SourceStart 10 -OutputStart 0
        $source = New-MediaProbe -FormatDuration 100.24 -FormatStartTime 10 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 10)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'ok'
    }

    It 'accepte l''asymétrie de metadata duration tant que les PTS existent' {
        Set-DefaultPacketSamples
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 0)
        )
        $temp = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video')
        )
        $temp['format']['duration'] = '100.24'

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'ok'
    }

    It 'accepte l''inverse metadata absente côté source' {
        $source = New-MediaProbe -Streams @(
            (New-ProbeStream -CodecType 'video')
        )
        $source['format']['duration'] = '100.24'
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'ok'
    }

    It 'mismatch si la sortie est tronquée de 2 s' {
        Set-DefaultPacketSamples -OutputSpan 98
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
        )
        $temp = New-MediaProbe -FormatDuration 98.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 98.24)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'timestamp-span'
        $result.Diff | Should -BeGreaterThan $result.Tolerance
    }

    It 'mismatch si la sortie est tronquée de 10 s' {
        Set-DefaultPacketSamples -OutputSpan 90
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
        )
        $temp = New-MediaProbe -FormatDuration 90.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 90.24)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'timestamp-span'
        [math]::Round($result.Diff, 3) | Should -Be 10
    }

    It 'mismatch si la sortie est significativement plus longue' {
        Set-DefaultPacketSamples -OutputSpan 110
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
        )
        $temp = New-MediaProbe -FormatDuration 110.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 110.24)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'timestamp-span'
    }

    It 'passe un span identique 24 fps vers 25 fps (tolérance 2×(Qs+Qo))' {
        Set-DefaultPacketSamples -SourceFps 24 -OutputFps 25
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 0)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'ok'
    }

    It 'accepte un écart de span inférieur à 2×(Qs+Qo) malgré des cadences différentes' {
        # 2×(1/24+1/25) ≈ 0.163 ; 2×max(Qs,Qo) ≈ 0.083. Diff=0.12 ne passe que la somme.
        Set-DefaultPacketSamples -SourceFps 24 -OutputFps 25 -OutputSpan 99.88
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 0)
        )
        $temp = New-MediaProbe -FormatDuration 99.88 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 99.88 -StartTime 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'ok'
    }

    It 'mismatch si l''écart de span dépasse 2×(Qs+Qo) avec cadences différentes' {
        Set-DefaultPacketSamples -SourceFps 24 -OutputFps 25 -OutputSpan 99
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 0)
        )
        $temp = New-MediaProbe -FormatDuration 99.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 99.24 -StartTime 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'timestamp-span'
        $result.Diff | Should -BeGreaterThan $result.Tolerance
        $result.Tolerance | Should -BeGreaterThan (2.0 * (1.0 / 24))
        $result.Tolerance | Should -BeGreaterThan (2.0 * (1.0 / 25))
        [math]::Abs($result.Tolerance - (2.0 * ((1.0 / 24) + (1.0 / 25)))) | Should -BeLessThan 1e-9
    }

    It 'mismatch si un flux mappé est absent de la sortie' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
            (New-ProbeStream -CodecType 'audio' -Duration 100)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )
        $maps = @(
            (New-StreamMap -StreamType 'video' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
            (New-StreamMap -StreamType 'audio' -SourceRelativeIndex 2 -OutputRelativeIndex 1)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -StreamMaps $maps

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'stream-missing'
        $result.SourceRelativeIndex | Should -Be 2
        $result.OutputRelativeIndex | Should -Be 1
    }

    It 'mismatch probe si la sortie ne peut pas être sondée' {
        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson { $null }
        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe @{ format = @{}; streams = @() }

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'probe'
        $result.Reason | Should -Be 'output-probe-failed'
    }

    It 'passe des offsets relatifs conservés et une translation globale' {
        Set-DefaultPacketSamples -SourceStart 5 -OutputStart 0 -SourceAudioOffset 0.1 -OutputAudioOffset 0.1
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 5)
            (New-ProbeStream -CodecType 'audio' -Duration 100.24 -StartTime 5.1)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24 -StartTime 0)
            (New-ProbeStream -CodecType 'audio' -Duration 100.24 -StartTime 0.1)
        )
        $maps = @(
            (New-StreamMap -StreamType 'video' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
            (New-StreamMap -StreamType 'audio' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -StreamMaps $maps

        $result.Status | Should -Be 'ok'
    }

    It 'mismatch si l''audio est décalé de 500 ms' {
        Set-DefaultPacketSamples -OutputAudioOffset 0.5
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'audio' -Duration 100.24)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'audio' -Duration 100.24)
        )
        $maps = @(
            (New-StreamMap -StreamType 'video' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
            (New-StreamMap -StreamType 'audio' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -StreamMaps $maps

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'relative-offset'
        $result.Diff | Should -BeGreaterThan 0.4
    }

    It 'mismatch si seule la seconde piste audio est décalée' {
        $script:PacketSampleTable = @{
            SourceVideoStart = New-CfrPackets -Count 32 -Fps 25 -StreamIndex 0
            SourceVideoTail  = New-CfrPackets -Count 32 -Fps 25 -StartPts 99.0 -StreamIndex 0
            OutputVideoStart = New-CfrPackets -Count 32 -Fps 25 -StreamIndex 0
            OutputVideoTail  = New-CfrPackets -Count 32 -Fps 25 -StartPts 99.0 -StreamIndex 0
            SourceAudioStart = New-CfrPackets -Count 32 -Fps 50 -StreamIndex 1
            SourceAudioTail  = New-CfrPackets -Count 32 -Fps 50 -StartPts 99.0 -StreamIndex 1
            OutputAudioStart = New-CfrPackets -Count 32 -Fps 50 -StreamIndex 1
            OutputAudioTail  = New-CfrPackets -Count 32 -Fps 50 -StartPts 99.0 -StreamIndex 1
            SourceAudio2Start = New-CfrPackets -Count 32 -Fps 50 -StreamIndex 2
            SourceAudio2Tail  = New-CfrPackets -Count 32 -Fps 50 -StartPts 99.0 -StreamIndex 2
            OutputAudio2Start = New-CfrPackets -Count 32 -Fps 50 -StartPts 0.5 -StreamIndex 2
            OutputAudio2Tail  = New-CfrPackets -Count 32 -Fps 50 -StartPts 99.5 -StreamIndex 2
            SourcePeek = $null
            OutputPeek = $null
        }

        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'audio' -Duration 100.24)
            (New-ProbeStream -CodecType 'audio' -Duration 100.24)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'audio' -Duration 100.24)
            (New-ProbeStream -CodecType 'audio' -Duration 100.24)
        )
        $maps = @(
            (New-StreamMap -StreamType 'video' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
            (New-StreamMap -StreamType 'audio' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
            (New-StreamMap -StreamType 'audio' -SourceRelativeIndex 1 -OutputRelativeIndex 1)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -StreamMaps $maps

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'relative-offset'
        $result.OutputRelativeIndex | Should -Be 1
    }

    It 'unknown si la fin n''est pas localisable, pas mismatch' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 32 -Fps 25
            }
            return @()
        }
        $source = New-MediaProbe -Streams @((New-ProbeStream -CodecType 'video'))
        $temp = New-MediaProbe -Streams @((New-ProbeStream -CodecType 'video'))

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'unknown'
        $result.Method | Should -Be 'timestamp-span'
        $result.Reason | Should -Be 'no-tail-seek-hint'
    }

    It 'accepte une liste de maps A/V vide sans lever' {
        $source = New-MediaProbe -FormatDuration 100 -Streams @((New-ProbeStream -CodecType 'video' -Duration 100))
        $temp = New-MediaProbe -FormatDuration 100 -Streams @((New-ProbeStream -CodecType 'video' -Duration 100))

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -StreamMaps @()

        $result.Status | Should -Be 'ok'
        $result.Method | Should -Be 'complete'
        $result.Reason | Should -Be 'not-applicable'
    }

    It 'rend un unknown de profil source comme un défaut source, pas sortie' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($File, $StreamSpecifier, $ReadIntervals)
            if ($File -eq $script:SourceFile -and $ReadIntervals -ne '%+5') {
                return ,@()
            }
            Resolve-PacketSample -File $File -StreamSpecifier $StreamSpecifier -ReadIntervals $ReadIntervals
        }
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'unknown'
        $result.Reason | Should -Be 'no-end-packet-near-hint'
        $result.Side | Should -Be 'source'
        $msg = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Integrity = $result } {
            param($Integrity)
            Get-IntegrityUnknownMessage -Filename 'film.mkv' -Integrity $Integrity
        }
        $msg | Should -Match 'source 0:v:0 has no usable end PTS'
        $msg | Should -Not -Match 'output 0:v:0 has no usable end PTS'
    }

    It 'conserve l''exemple de message unknown côté sortie' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($File, $StreamSpecifier, $ReadIntervals)
            if ($File -eq $script:TempFile -and $ReadIntervals -ne '%+5') {
                return ,@()
            }
            Resolve-PacketSample -File $File -StreamSpecifier $StreamSpecifier -ReadIntervals $ReadIntervals
        }
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Side | Should -Be 'output'
        $msg = InModuleScope 'Tetram.Media.Mkv' -Parameters @{ Integrity = $result } {
            param($Integrity)
            Get-IntegrityUnknownMessage -Filename 'film.mkv' -Integrity $Integrity
        }
        $msg | Should -Match 'output 0:v:0 has no usable end PTS'
    }

    It 'ne laisse pas un unknown précoce masquer un mismatch ultérieur' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($File, $ReadIntervals)
            if ($File -eq $script:SourceFile)
            {
                $audioStart = New-CfrPackets -Count 32 -Fps 50 -StreamIndex 1
                $audioTail = New-CfrPackets -Count 32 -Fps 50 -StartPts 99.0 -StreamIndex 1
                if ($ReadIntervals -eq '%+5') {
                    $mixedStart = @((New-IntegrityPacket -PtsTime 0 -Pos 1 -StreamIndex 0))
                    foreach ($packet in @($audioStart)) { $mixedStart += $packet }
                    return $mixedStart
                }
                $maxAudio = Get-PacketSampleMaxPts -Packets $audioTail
                if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$') {
                    $windowStart = [double]$Matches[1]
                    $windowEnd = [double]$Matches[2]
                    if (($windowEnd - $windowStart) -ge 9.0 -and $windowStart -ge ($maxAudio - 0.05)) {
                        return ,([object[]]@())
                    }
                }
                return @($audioTail)
            }
            Resolve-PacketSample -File $File -StreamSpecifier '' -ReadIntervals $ReadIntervals
        }
        Set-DefaultPacketSamples -OutputSpan 90
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'audio' -Duration 100.24)
        )
        $temp = New-MediaProbe -FormatDuration 90.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 90.24)
            (New-ProbeStream -CodecType 'audio' -Duration 90.24)
        )
        $maps = @(
            (New-StreamMap -StreamType 'video' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
            (New-StreamMap -StreamType 'audio' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -StreamMaps $maps

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'timestamp-span'
        $result.StreamType | Should -Be 'audio'
    }

    It 'n''appelle aucune sonde packets sans -read_intervals et n''effectue pas de full scan' {
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
        )

        $null = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $script:PacketSampleCalls.Count | Should -BeGreaterThan 0
        foreach ($call in $script:PacketSampleCalls)
        {
            $call.Interval | Should -Not -BeNullOrEmpty
            $call.Interval | Should -Not -Be '%'
            $call.Interval | Should -Not -Match '^[0-9eE.+-]+%$'
            $call.Interval | Should -Not -Match '%\+#\d+$'
        }
        @(
            $script:PacketSampleCalls |
                Where-Object { $_.Interval -eq '%+5' }
        ).Count | Should -BeGreaterThan 0
    }

    It 'mismatch interleave e2e si l''audio est physiquement retardé (~74,1 MiB)' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($File, $StreamSpecifier, $ReadIntervals)
            $isSource = ($File -eq $script:SourceFile)
            if ([string]::IsNullOrWhiteSpace($StreamSpecifier)) {
                if ($isSource) {
                    if ($ReadIntervals -eq '%+5') {
                        return @(
                            (New-CfrPackets -Count 32 -Fps 25 -StartPos 1000 -StreamIndex 0) +
                            (New-CfrPackets -Count 32 -Fps 50 -StartPos 1200 -Size 1536 -StreamIndex 1)
                        )
                    }
                    if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$') {
                        $windowStart = [double]$Matches[1]
                        $windowEnd = [double]$Matches[2]
                        if (($windowEnd - $windowStart) -ge 9.0 -and $windowStart -ge 99.9) {
                            return ,([object[]]@())
                        }
                    }
                    return @(
                        (New-CfrPackets -Count 32 -Fps 25 -StartPts 99.0 -StartPos 8000000 -StreamIndex 0) +
                        (New-CfrPackets -Count 32 -Fps 50 -StartPts 99.0 -StartPos 8050000 -Size 1536 -StreamIndex 1)
                    )
                }
                if ($ReadIntervals -eq '%+5') {
                    return New-CfrPackets -Count 32 -Fps 25 -StartPos 4913010 -StreamIndex 0
                }
                if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$') {
                    $windowStart = [double]$Matches[1]
                    $windowEnd = [double]$Matches[2]
                    if (($windowEnd - $windowStart) -ge 9.0 -and $windowStart -ge 99.9) {
                        return ,([object[]]@())
                    }
                }
                return New-CfrPackets -Count 32 -Fps 25 -StartPts 99.0 -StartPos 70000000 -StreamIndex 0
            }

            if ($StreamSpecifier -like 'a:*') {
                $mid = -0.005
                if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$') {
                    $windowStart = [double]$Matches[1]
                    $windowEnd = [double]$Matches[2]
                    $mid = ($windowStart + $windowEnd) / 2.0
                }
                return @((New-IntegrityPacket -PtsTime $mid -Pos 82615734L -Size 1536 -StreamIndex 1))
            }
            $mid = 0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$') {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = ($windowStart + $windowEnd) / 2.0
            }
            return @((New-IntegrityPacket -PtsTime $mid -Pos 4913010L -Size 200000 -StreamIndex 0))
        }

        $source = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100 -StartTime 0)
            (New-ProbeStream -CodecType 'audio' -Duration 100 -StartTime -0.005)
        )
        $temp = New-MediaProbe -FormatDuration 100 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100 -StartTime 0)
            (New-ProbeStream -CodecType 'audio' -Duration 100 -StartTime -0.005)
        )
        $maps = @(
            (New-StreamMap -StreamType 'video' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
            (New-StreamMap -StreamType 'audio' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp -StreamMaps $maps

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'interleave'
        $result.PhysicalSpreadBytes | Should -BeGreaterThan $result.PhysicalLimitBytes
    }

    It 'unknown (pas mismatch) si la duration source sous-estime le contenu' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            if ($ReadIntervals -eq '%+5') {
                return New-CfrPackets -Count 32 -Fps 25 -StreamIndex 0
            }
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$') {
                $start = [double]$Matches[1]
                $end = [double]$Matches[2]
                $realEnd = 600.04
                if ($start -ge 599.9) {
                    $peekEnd = [math]::Min($end, $realEnd)
                    if ($peekEnd -le $start) {
                        return ,([object[]]@())
                    }
                    return New-CfrPackets -Count 32 -Fps 25 -StartPts ($peekEnd - 31.0 / 25) -StreamIndex 0
                }
                $lastPts = [math]::Min($end, $realEnd)
                return New-CfrPackets -Count 32 -Fps 25 -StartPts ($lastPts - 31.0 / 25) -StreamIndex 0
            }
            return ,([object[]]@())
        }

        $source = New-MediaProbe -FormatDuration 590 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 590 -StartTime 0)
        )
        $temp = New-MediaProbe -FormatDuration 600.04 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 600.04 -StartTime 0)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'unknown'
        $result.Reason | Should -Be 'tail-hint-underestimates-stream'
        $result.Side | Should -Be 'source'
    }
}

Describe 'Test-EncodedFileIntegrity — sous-titres exclus' {
    BeforeEach {
        $script:SourceFile = Join-Path $TestDrive 'source.mkv'
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:SourceFile -Value 'source'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        Set-DefaultPacketSamples
        Mock -ModuleName Tetram.Media.Remux Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Remux Get-FFprobeJson { $script:TempProbe }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($File, $ReadIntervals)
            Resolve-PacketSample -File $File -StreamSpecifier '' -ReadIntervals $ReadIntervals
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            param($File, $StreamSpecifier, $ReadIntervals)
            $StreamSpecifier | Should -Not -Match '^s:'
            Resolve-PacketSample -File $File -StreamSpecifier $StreamSpecifier -ReadIntervals $ReadIntervals
        }
    }

    It 'ignore un SRT plus long que la vidéo' {
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'subtitle' -CodecName 'subrip' -Duration 180)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'subtitle' -CodecName 'subrip' -Duration 180)
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'ok'
    }

    It 'ignore un ASS avec ou sans packet.duration' {
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'subtitle' -CodecName 'ass' -Duration 50)
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'subtitle' -CodecName 'ass')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'ok'
    }

    It 'ignore un PGS sans packet.duration' {
        $source = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'subtitle' -CodecName 'hdmv_pgs_subtitle')
        )
        $temp = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'subtitle' -CodecName 'hdmv_pgs_subtitle')
        )

        $result = Invoke-IntegrityCheck -SourceProbe $source -TempProbe $temp

        $result.Status | Should -Be 'ok'
    }

    It 'n''est pas influencé par l''ajout ou le retrait d''une piste subtitle' {
        $withSub = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
            (New-ProbeStream -CodecType 'subtitle' -CodecName 'subrip' -Duration 12)
        )
        $withoutSub = New-MediaProbe -FormatDuration 100.24 -Streams @(
            (New-ProbeStream -CodecType 'video' -Duration 100.24)
        )

        $kept = Invoke-IntegrityCheck -SourceProbe $withSub -TempProbe $withSub
        $dropped = Invoke-IntegrityCheck -SourceProbe $withSub -TempProbe $withoutSub

        $kept.Status | Should -Be 'ok'
        $dropped.Status | Should -Be 'ok'
    }
}

        function script:New-IntegrityTemporalProfileForTest {
    param(
        [double] $First,
        [double] $Last,
        [double] $Cadence,
        $StartPackets,
        $TailPackets,
        [int] $AbsoluteStreamIndex = 0
    )

    [pscustomobject]@{
        FirstPtsTime        = $First
        LastPtsTime         = $Last
        SpanSeconds         = $Last - $First
        StartCadence        = $Cadence
        EndCadence          = $Cadence
        Cadence             = $Cadence
        StartPackets        = @($StartPackets)
        TailPackets         = @($TailPackets)
        AbsoluteStreamIndex = $AbsoluteStreamIndex
        IsUsable            = $true
        UnknownReason       = $null
    }
}

function script:Invoke-InterleaveUnderTest {
    param(
        $VideoProfile,
        $AudioProfile,
        $SecondAudioProfile
    )

    $maps = @()
    $maps += New-StreamMap -StreamType 'video' -SourceRelativeIndex 0 -OutputRelativeIndex 0
    $maps += New-StreamMap -StreamType 'audio' -SourceRelativeIndex 0 -OutputRelativeIndex 0
    $profiles = @{
        'v:0' = $VideoProfile
        'a:0' = $AudioProfile
    }
    $VideoProfile | Add-Member -NotePropertyName AbsoluteStreamIndex -NotePropertyValue 0 -Force
    $AudioProfile | Add-Member -NotePropertyName AbsoluteStreamIndex -NotePropertyValue 1 -Force
    if ($PSBoundParameters.ContainsKey('SecondAudioProfile'))
    {
        $maps += New-StreamMap -StreamType 'audio' -SourceRelativeIndex 1 -OutputRelativeIndex 1
        $profiles['a:1'] = $SecondAudioProfile
        $SecondAudioProfile | Add-Member -NotePropertyName AbsoluteStreamIndex -NotePropertyValue 2 -Force
    }

    InModuleScope 'Tetram.Media.Mkv' -Parameters @{
        TempFile = $script:TempFile
        Maps = @($maps)
        Profiles = $profiles
    } {
        param($TempFile, $Maps, $Profiles)
        Test-IntegrityOutputInterleave -FFPROBE 'ffprobe' -TempFile $TempFile -StreamMaps $Maps -OutputProfiles $Profiles
    }
}

Describe 'Test-IntegrityOutputInterleave' {
    BeforeEach {
        $script:TempFile = Join-Path $TestDrive 'temp.mkv'
        Set-Content -LiteralPath $script:TempFile -Value 'temp'
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            @(
                (New-IntegrityPacket -PtsTime $mid -Pos 5000000L -Size 1000L -StreamIndex 0)
                (New-IntegrityPacket -PtsTime $mid -Pos 5150000L -Size 1536L -StreamIndex 1)
                (New-IntegrityPacket -PtsTime $mid -Pos 5150000L -Size 1536L -StreamIndex 2)
            )
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            param($StreamSpecifier, $ReadIntervals)
            $script:TargetedCalls += "$StreamSpecifier|$ReadIntervals"
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            $pos = if ($StreamSpecifier -like 'a:*') { 5150000L } else { 5000000L }
            $size = if ($StreamSpecifier -like 'a:*') { 1536L } else { 1000L }
            $index = if ($StreamSpecifier -eq 'a:1') { 2 } elseif ($StreamSpecifier -like 'a:*') { 1 } else { 0 }
            @((New-IntegrityPacket -PtsTime $mid -Pos $pos -Size $size -StreamIndex $index))
        }
        $script:TargetedCalls = @()
    }

    It 'passe un entrelacement sain' {
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5000000 -Size 200000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000000 -Size 200000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5150000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9150000 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'ok'
    }

    It 'mismatch sur la fixture historique ~74,1 MiB' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            @(
                (New-IntegrityPacket -PtsTime $mid -Pos 4913010L -Size 200000L -StreamIndex 0)
                (New-IntegrityPacket -PtsTime $mid -Pos 82615734L -Size 1536L -StreamIndex 1)
            )
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0.000 -Pos 4913010L -Size 200000L)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 4913010L -Size 200000L))
        $audio = New-IntegrityTemporalProfileForTest -First -0.005 -Last 100 -Cadence 0.021 `
            -StartPackets @((New-IntegrityPacket -PtsTime -0.005 -Pos 82615734L -Size 1536L)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 82615734L -Size 1536L))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'interleave'
        $result.PhysicalSpreadBytes | Should -Be 77702724
        $result.PhysicalSpreadBytes | Should -BeGreaterThan $result.PhysicalLimitBytes
    }

    It 'passe quand spread == limit' {
        $limitWithoutPacket = 2 * 5 * 1024 * 1024
        $size = 1000L
        $limit = $limitWithoutPacket + $size
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 10 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 0 -Size $size)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 10 -Pos 0 -Size $size))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 10 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos $limit -Size $size)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 10 -Pos $limit -Size $size))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'ok'
    }

    It 'mismatch quand spread > limit' {
        $limitWithoutPacket = 2 * 5 * 1024 * 1024
        $size = 1000L
        $limit = $limitWithoutPacket + $size
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $mid = 5.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            @(
                (New-IntegrityPacket -PtsTime $mid -Pos 0 -Size $size -StreamIndex 0)
                (New-IntegrityPacket -PtsTime $mid -Pos ($limit + 1) -Size $size -StreamIndex 1)
            )
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 10 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 0 -Size $size)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 10 -Pos 0 -Size $size))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 10 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos ($limit + 1) -Size $size)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 10 -Pos ($limit + 1) -Size $size))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'mismatch'
    }

    It 'unknown si pos = -1' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $mid = 5.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            @(
                (New-IntegrityPacket -PtsTime $mid -Pos $null -Size 1000 -StreamIndex 0)
                (New-IntegrityPacket -PtsTime $mid -Pos 1000 -Size 1000 -StreamIndex 1)
            )
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            return ,@()
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 10 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos $null -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 10 -Pos $null -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 10 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 1000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 10 -Pos 1000 -Size 1000))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'unknown'
        $result.Method | Should -Be 'interleave'
    }

    It 'ne déclare pas un faux mismatch pour un packet hors marge PTS' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($StreamSpecifier)
            if ($StreamSpecifier -eq 'v:0') {
                return @((New-IntegrityPacket -PtsTime 50 -Pos 5000000 -Size 1000))
            }
            return @((New-IntegrityPacket -PtsTime 80 -Pos 82615734L -Size 1536))
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 1000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 2000 -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 1100 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 2100 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Not -Be 'mismatch'
    }

    It 'n''est pas applicable pour un seul stream A/V' {
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 10 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 1 -Size 1)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 10 -Pos 2 -Size 1))
        $maps = @((New-StreamMap -StreamType 'video' -SourceRelativeIndex 0 -OutputRelativeIndex 0))
        $profiles = @{ 'v:0' = $video }

        $result = InModuleScope 'Tetram.Media.Mkv' -Parameters @{
            TempFile = $script:TempFile
            Maps = $maps
            Profiles = $profiles
        } {
            param($TempFile, $Maps, $Profiles)
            Test-IntegrityOutputInterleave -FFPROBE 'ffprobe' -TempFile $TempFile -StreamMaps $Maps -OutputProfiles $Profiles
        }

        $result.Status | Should -Be 'ok'
        $result.Reason | Should -Be 'not-applicable'
    }

    It 'sonde une fenêtre commune par anchor et n''utilise pas le fallback si les streams sont présents' {
        $script:WindowCalls = [System.Collections.Generic.List[string]]::new()
        $script:TargetedCalls = @()
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            [void]$script:WindowCalls.Add($ReadIntervals)
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            @(
                (New-IntegrityPacket -PtsTime $mid -Pos 5000000 -Size 1000 -StreamIndex 0)
                (New-IntegrityPacket -PtsTime $mid -Pos 5150000 -Size 1536 -StreamIndex 1)
            )
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            param($StreamSpecifier, $ReadIntervals)
            $script:TargetedCalls += "$StreamSpecifier|$ReadIntervals"
            return ,@()
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5000000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000000 -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5150000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9150000 -Size 1536))

        $null = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $script:WindowCalls.Count | Should -Be 5
        @($script:TargetedCalls).Count | Should -Be 0
        foreach ($interval in $script:WindowCalls)
        {
            $interval | Should -Match '%'
            $interval | Should -Not -Match '%\+'
            $interval | Should -Not -Match '%\+#\d+$'
        }
    }

    It 'ignore une piste inactive aux anchors hors de sa plage' {
        $script:LateAudioWindows = 0
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($StreamSpecifier, $ReadIntervals)
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            if ($StreamSpecifier -eq 'a:0') {
                $script:LateAudioWindows++
                return @((New-IntegrityPacket -PtsTime $mid -Pos 8000000 -Size 1536))
            }
            return @((New-IntegrityPacket -PtsTime $mid -Pos 5000000 -Size 1000))
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 1000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000 -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 80 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 80 -Pos 1100 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9100 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'ok'
        $script:LateAudioWindows | Should -Be 0
    }

    It 'ignore une piste qui finit plus tôt aux anchors hors de sa plage' {
        $script:EarlyAudioWindows = 0
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($StreamSpecifier, $ReadIntervals)
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            if ($StreamSpecifier -eq 'a:0') {
                $script:EarlyAudioWindows++
                return @((New-IntegrityPacket -PtsTime $mid -Pos 5150000 -Size 1536))
            }
            return @((New-IntegrityPacket -PtsTime $mid -Pos 5000000 -Size 1000))
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5000000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000000 -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 40 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5150000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 40 -Pos 6000000 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'ok'
        $script:EarlyAudioWindows | Should -Be 0
    }

    It 'mesure max(pos)-min(pos) sur trois candidats contemporains' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($StreamSpecifier, $ReadIntervals)
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            $pos = switch ($StreamSpecifier) {
                'a:0' { 5100000L }
                'a:1' { 5150000L }
                default { 5000000L }
            }
            @((New-IntegrityPacket -PtsTime $mid -Pos $pos -Size 1000))
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5000000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000000 -Size 1000))
        $audio0 = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5100000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9100000 -Size 1536))
        $audio1 = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5150000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9150000 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio0 -SecondAudioProfile $audio1

        $result.Status | Should -Be 'ok'
    }

    It 'mismatch si le spread de trois candidats dépasse la limite' {
        $script:FarPos = (2 * 5 * 1024 * 1024) + 1000L + 1
        $size = 1000L
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $mid = 5.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            @(
                (New-IntegrityPacket -PtsTime $mid -Pos 0L -Size 1000 -StreamIndex 0)
                (New-IntegrityPacket -PtsTime $mid -Pos 0L -Size 1000 -StreamIndex 1)
                (New-IntegrityPacket -PtsTime $mid -Pos $script:FarPos -Size 1000 -StreamIndex 2)
            )
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 10 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 0 -Size $size)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 10 -Pos 0 -Size $size))
        $audio0 = New-IntegrityTemporalProfileForTest -First 0 -Last 10 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 1000 -Size $size)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 10 -Pos 1000 -Size $size))
        $audio1 = New-IntegrityTemporalProfileForTest -First 0 -Last 10 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos $script:FarPos -Size $size)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 10 -Pos $script:FarPos -Size $size))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio0 -SecondAudioProfile $audio1

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'interleave'
        $result.PhysicalSpreadBytes | Should -Be $script:FarPos
    }

    It 'unknown (pas mismatch) si un gap PTS entoure un anchor actif' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            @(
                (New-IntegrityPacket -PtsTime 10.0 -Pos 5000000L -Size 1000 -StreamIndex 0)
                (New-IntegrityPacket -PtsTime 10.0 -Pos 5150000L -Size 1000 -StreamIndex 1)
            )
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            @(
                (New-IntegrityPacket -PtsTime 10.0 -Pos 5000000L -Size 1000 -StreamIndex 0)
                (New-IntegrityPacket -PtsTime 10.0 -Pos 5150000L -Size 1000 -StreamIndex 1)
            )
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5000000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000000 -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5150000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9150000 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'unknown'
        $result.Method | Should -Be 'interleave'
        $result.Reason | Should -Be 'no-anchor-candidate'
    }

    It 'unknown si la fenêtre d''anchor réussit sans packet' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            return ,@()
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            return ,@()
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5000000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000000 -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5150000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9150000 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'unknown'
        $result.Reason | Should -Be 'no-anchor-candidate'
    }

    It 'signale anchor-probe-failed si la fenêtre centrale échoue' {
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            return $null
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5000000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000000 -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5150000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9150000 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'unknown'
        $result.Method | Should -Be 'interleave'
        $result.Reason | Should -Be 'anchor-probe-failed'
    }

    It 'mismatch via fallback ciblé quand l''audio actif est absent de la fenêtre commune' {
        $script:TargetedCalls = @()
        $script:FarPos = 5000000L + (2L * 5L * 1024L * 1024L) + 1536L + 1L
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            if ([math]::Abs($mid - 50) -lt 1)
            {
                return @((New-IntegrityPacket -PtsTime $mid -Pos 5000000L -Size 1000 -StreamIndex 0))
            }
            @(
                (New-IntegrityPacket -PtsTime $mid -Pos 5000000L -Size 1000 -StreamIndex 0)
                (New-IntegrityPacket -PtsTime $mid -Pos 5150000L -Size 1536 -StreamIndex 1)
            )
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            param($StreamSpecifier, $ReadIntervals)
            $script:TargetedCalls += "$StreamSpecifier|$ReadIntervals"
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            @((New-IntegrityPacket -PtsTime $mid -Pos $script:FarPos -Size 1536 -StreamIndex 1))
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5000000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000000 -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5150000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9150000 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'interleave'
        $result.AnchorFraction | Should -Be 0.5
        @($script:TargetedCalls | Where-Object { $_ -like 'a:0|*' }).Count | Should -Be 1
    }

    It 'mismatch uniquement à l''anchor <Fraction>' -TestCases @(
        @{ Fraction = 0.25 }
        @{ Fraction = 0.50 }
        @{ Fraction = 0.75 }
        @{ Fraction = 1.00 }
    ) {
        param($Fraction)
        $script:AnchorFraction = $Fraction
        $script:FarPos = 5000000L + (2L * 5L * 1024L * 1024L) + 1536L + 1L
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            $audioPos = 5150000L
            if ([math]::Abs($mid - (100.0 * $script:AnchorFraction)) -lt 1.0)
            {
                $audioPos = $script:FarPos
            }
            @(
                (New-IntegrityPacket -PtsTime $mid -Pos 5000000L -Size 1000 -StreamIndex 0)
                (New-IntegrityPacket -PtsTime $mid -Pos $audioPos -Size 1536 -StreamIndex 1)
            )
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            return ,@()
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5000000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000000 -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5150000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9150000 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'interleave'
        $result.AnchorFraction | Should -Be $Fraction
    }

    It 'ne laisse pas un unknown à 25 % masquer un mismatch à 50 %' {
        $script:FarPos = 5000000L + (2L * 5L * 1024L * 1024L) + 1536L + 1L
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityPacketWindow {
            param($ReadIntervals)
            $mid = 50.0
            if ($ReadIntervals -match '^([0-9eE.+-]+)%([0-9eE.+-]+)$')
            {
                $windowStart = [double]$Matches[1]
                $windowEnd = [double]$Matches[2]
                $mid = if ($windowStart -le 0) { $windowEnd - 5.0 } else { ($windowStart + $windowEnd) / 2.0 }
            }
            if ([math]::Abs($mid - 25) -lt 1)
            {
                return @((New-IntegrityPacket -PtsTime $mid -Pos 5000000L -Size 1000 -StreamIndex 0))
            }
            $audioPos = if ([math]::Abs($mid - 50) -lt 1) { $script:FarPos } else { 5150000L }
            @(
                (New-IntegrityPacket -PtsTime $mid -Pos 5000000L -Size 1000 -StreamIndex 0)
                (New-IntegrityPacket -PtsTime $mid -Pos $audioPos -Size 1536 -StreamIndex 1)
            )
        }
        Mock -ModuleName Tetram.Media.Remux Get-IntegrityTargetedInterleavePackets {
            return ,@()
        }
        $video = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.04 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5000000 -Size 1000)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9000000 -Size 1000))
        $audio = New-IntegrityTemporalProfileForTest -First 0 -Last 100 -Cadence 0.02 `
            -StartPackets @((New-IntegrityPacket -PtsTime 0 -Pos 5150000 -Size 1536)) `
            -TailPackets @((New-IntegrityPacket -PtsTime 100 -Pos 9150000 -Size 1536))

        $result = Invoke-InterleaveUnderTest -VideoProfile $video -AudioProfile $audio

        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'interleave'
        $result.AnchorFraction | Should -Be 0.5
    }
}

Describe 'Intégrité — ffmpeg/ffprobe réels' -Tag 'Integration' {
    BeforeAll {
        $script:HaveMediaTools = $false
        $script:FFmpegPath = $null
        $script:FFprobePath = $null
        try
        {
            $script:FFmpegPath = InModuleScope 'Tetram.Media.Mkv' { Get-FFmpegPath }
            $script:FFprobePath = InModuleScope 'Tetram.Media.Mkv' { Get-FfprobePath }
            $script:HaveMediaTools = (
                $script:FFmpegPath -and (Test-Path -LiteralPath $script:FFmpegPath) -and
                $script:FFprobePath -and (Test-Path -LiteralPath $script:FFprobePath)
            )
        }
        catch
        {
            $script:HaveMediaTools = $false
        }

        $script:AvMaps = @(
            (New-StreamMap -StreamType 'video' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
            (New-StreamMap -StreamType 'audio' -SourceRelativeIndex 0 -OutputRelativeIndex 0)
        )
    }

    function script:Invoke-FFmpegFixture {
        param([Parameter(Mandatory)] [string[]] $Arguments)
        & $script:FFmpegPath @Arguments
        if ($LASTEXITCODE -ne 0)
        {
            throw "ffmpeg a échoué (code $LASTEXITCODE) : $($Arguments -join ' ')"
        }
    }

    function script:New-AvMkv {
        param([Parameter(Mandatory)] [string] $Path, [double] $Duration = 2)
        Invoke-FFmpegFixture -Arguments @(
            '-y', '-hide_banner', '-loglevel', 'error'
            '-f', 'lavfi', '-i', "testsrc=size=320x240:rate=25:duration=$Duration"
            '-f', 'lavfi', '-i', "sine=frequency=1000:sample_rate=48000:duration=$Duration"
            '-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency'
            '-c:a', 'aac', '-ac', '2'
            '-shortest', $Path
        )
    }

    function script:Invoke-RealIntegrity {
        param(
            [Parameter(Mandatory)] [string] $SourceFile,
            [Parameter(Mandatory)] [string] $TempFile,
            $StreamMaps = $script:AvMaps
        )

        InModuleScope 'Tetram.Media.Mkv' -Parameters @{
            FFprobe = $script:FFprobePath
            SourceFile = $SourceFile
            TempFile = $TempFile
            StreamMaps = @($StreamMaps)
        } {
            param($FFprobe, $SourceFile, $TempFile, $StreamMaps)
            $sourceProbe = Get-FFprobeJson -FFPROBE $FFprobe -File $SourceFile
            if ($null -eq $sourceProbe)
            {
                throw "Get-FFprobeJson a renvoyé `$null pour $SourceFile"
            }
            Test-EncodedFileIntegrity `
                -FFPROBE $FFprobe `
                -SourceProbe $sourceProbe `
                -SourceFile $SourceFile `
                -TempFile $TempFile `
                -StreamMaps $StreamMaps
        }
    }

    It 'lit pts_time/pos via une fenêtre fichier bornée, sans -select_streams' {
        if (-not $script:HaveMediaTools)
        {
            Set-ItResult -Skipped -Because 'ffmpeg/ffprobe indisponibles dans cet environnement'
            return
        }

        $mkv = Join-Path $TestDrive 'sample.mkv'
        New-AvMkv -Path $mkv

        $packets = InModuleScope 'Tetram.Media.Mkv' -Parameters @{
            FFprobe = $script:FFprobePath
            File = $mkv
        } {
            param($FFprobe, $File)
            Get-IntegrityPacketWindow -FFPROBE $FFprobe -File $File -ReadIntervals '%+5'
        }

        $packets | Should -Not -BeNullOrEmpty
        $packets.Count | Should -BeGreaterThan 1
        $packets[0].PtsTime | Should -Not -BeNullOrEmpty
        $packets[0].Pos | Should -Not -BeNullOrEmpty
        @($packets | Where-Object { $null -ne $_.PtsTime }).Count | Should -Be $packets.Count
    }

    It 'accepte un remux MKV identique (copie)' {
        if (-not $script:HaveMediaTools)
        {
            Set-ItResult -Skipped -Because 'ffmpeg/ffprobe indisponibles dans cet environnement'
            return
        }

        $source = Join-Path $TestDrive 'source.mkv'
        $copy = Join-Path $TestDrive 'copy.mkv'
        New-AvMkv -Path $source
        Invoke-FFmpegFixture -Arguments @(
            '-y', '-hide_banner', '-loglevel', 'error'
            '-i', $source, '-c', 'copy', $copy
        )

        $result = Invoke-RealIntegrity -SourceFile $source -TempFile $copy
        $result.Status | Should -Be 'ok'
    }

    It 'rejette une sortie volontairement tronquée' {
        if (-not $script:HaveMediaTools)
        {
            Set-ItResult -Skipped -Because 'ffmpeg/ffprobe indisponibles dans cet environnement'
            return
        }

        $source = Join-Path $TestDrive 'full.mkv'
        $trunc = Join-Path $TestDrive 'trunc.mkv'
        New-AvMkv -Path $source -Duration 4
        Invoke-FFmpegFixture -Arguments @(
            '-y', '-hide_banner', '-loglevel', 'error'
            '-i', $source, '-t', '1', '-c', 'copy', $trunc
        )

        $result = Invoke-RealIntegrity -SourceFile $source -TempFile $trunc
        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'timestamp-span'
    }

    It 'rejette un décalage audio volontaire' {
        if (-not $script:HaveMediaTools)
        {
            Set-ItResult -Skipped -Because 'ffmpeg/ffprobe indisponibles dans cet environnement'
            return
        }

        $source = Join-Path $TestDrive 'sync.mkv'
        $shifted = Join-Path $TestDrive 'shifted.mkv'
        New-AvMkv -Path $source
        Invoke-FFmpegFixture -Arguments @(
            '-y', '-hide_banner', '-loglevel', 'error'
            '-i', $source
            '-itsoffset', '0.5'
            '-i', $source
            '-map', '0:v:0', '-map', '1:a:0'
            '-c', 'copy', $shifted
        )

        $result = Invoke-RealIntegrity -SourceFile $source -TempFile $shifted
        $result.Status | Should -Be 'mismatch'
        $result.Method | Should -Be 'relative-offset'
    }

    It 'ignore les sous-titres même présents dans le conteneur' {
        if (-not $script:HaveMediaTools)
        {
            Set-ItResult -Skipped -Because 'ffmpeg/ffprobe indisponibles dans cet environnement'
            return
        }

        $source = Join-Path $TestDrive 'plain.mkv'
        $withSubs = Join-Path $TestDrive 'with-subs.mkv'
        $srt = Join-Path $TestDrive 'cue.srt'
        New-AvMkv -Path $source
        @'
1
00:00:00,000 --> 00:00:01,500
hello
'@ | Set-Content -LiteralPath $srt -Encoding utf8
        Invoke-FFmpegFixture -Arguments @(
            '-y', '-hide_banner', '-loglevel', 'error'
            '-i', $source, '-i', $srt
            '-map', '0:v:0', '-map', '0:a:0', '-map', '1:0'
            '-c', 'copy', '-c:s', 'srt', $withSubs
        )

        $result = Invoke-RealIntegrity -SourceFile $source -TempFile $withSubs
        $result.Status | Should -Be 'ok'
    }

    It 'accepte un remux MP4 H.264/AAC vers MKV' {
        if (-not $script:HaveMediaTools)
        {
            Set-ItResult -Skipped -Because 'ffmpeg/ffprobe indisponibles dans cet environnement'
            return
        }

        $mp4 = Join-Path $TestDrive 'source.mp4'
        $mkv = Join-Path $TestDrive 'from-mp4.mkv'
        Invoke-FFmpegFixture -Arguments @(
            '-y', '-hide_banner', '-loglevel', 'error'
            '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25:duration=2'
            '-f', 'lavfi', '-i', 'sine=frequency=1000:sample_rate=48000:duration=2'
            '-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency'
            '-c:a', 'aac', '-ac', '2'
            '-shortest', $mp4
        )
        Invoke-FFmpegFixture -Arguments @(
            '-y', '-hide_banner', '-loglevel', 'error'
            '-i', $mp4, '-c', 'copy', $mkv
        )

        $result = Invoke-RealIntegrity -SourceFile $mp4 -TempFile $mkv
        $result.Status | Should -Be 'ok'
    }

    It 'accepte une translation globale des timestamps' {
        if (-not $script:HaveMediaTools)
        {
            Set-ItResult -Skipped -Because 'ffmpeg/ffprobe indisponibles dans cet environnement'
            return
        }

        $source = Join-Path $TestDrive 'sync-src.mkv'
        $shifted = Join-Path $TestDrive 'global-shift.mkv'
        New-AvMkv -Path $source
        Invoke-FFmpegFixture -Arguments @(
            '-y', '-hide_banner', '-loglevel', 'error'
            '-itsoffset', '1'
            '-i', $source
            '-c', 'copy', $shifted
        )

        $result = Invoke-RealIntegrity -SourceFile $source -TempFile $shifted
        $result.Status | Should -Be 'ok'
    }
}
