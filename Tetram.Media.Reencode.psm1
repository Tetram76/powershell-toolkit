using namespace System
using namespace System.Collections.Generic
using namespace System.IO

Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# Chargement des sous-modules privés (dot-source)
#   On dot-source plutôt que de passer par `NestedModules` pour garder un
#   scope unique avec le root : ainsi les sous-modules privés voient à la
#   fois les fonctions exportées par `Tetram.Common`/`VideoUtils`/etc.
#   (chargées en NestedModules), les fonctions du root (`Get-SortedFileList`,
#   `Invoke-ReencodeFile`, `Resolve-UpscaleHeight`...), et la classe locale
#   `[EncodingResult]`.
# -----------------------------------------------------------------------------
$PrivateRoot = Join-Path $PSScriptRoot 'Tetram.Media.Reencode.Private'
. (Join-Path $PrivateRoot 'Probe.ps1')
. (Join-Path $PrivateRoot 'Streams.ps1')
. (Join-Path $PrivateRoot 'EncoderArgs.ps1')
. (Join-Path $PrivateRoot 'NFO.ps1')
. (Join-Path $PrivateRoot 'Scan.ps1')

# -----------------------------------------------------------------------------
# Types et enums
#   Note : la classe `EncodingResult` reste confinée au module racine — elle
#   sert d'API interne pour `Invoke-ReencodeFile`/`Invoke-ReencodeMedia` et ne
#   doit pas traverser la frontière des sous-modules privés.
# -----------------------------------------------------------------------------
class EncodingResult
{
    [long] $OriginalSize = 0
    [long] $ReencodedSize = 0
    [TimeSpan] $Duration = 0
    [TimeSpan] $ElapsedTime = 0
    [int] $Count = 0

    EncodingResult()
    {
    }

    EncodingResult([long] $o, [long] $r)
    {
        $this.OriginalSize = $o;
        $this.ReencodedSize = $r;
        $this.Count = 1
    }

    EncodingResult([long] $o, [long] $r, [TimeSpan] $d, [TimeSpan] $e)
    {
        $this.OriginalSize = $o;
        $this.ReencodedSize = $r;
        $this.Duration = $d;
        $this.ElapsedTime = $e;
        $this.Count = 1
    }

    [void]
    Add([EncodingResult] $Other)
    {
        $this.OriginalSize += $Other.OriginalSize
        $this.ReencodedSize += $Other.ReencodedSize
        $this.Duration += $Other.Duration
        $this.ElapsedTime += $Other.ElapsedTime
        $this.Count += $Other.Count
    }

    [string]
    SizeReport()
    {
        if ($this.Count -eq 0 -or $this.OriginalSize -eq 0 -or $this.ReencodedSize -eq 0)
        {
            return ''
        }
        $saved = $this.OriginalSize - $this.ReencodedSize
        return ("{0} reencoded into {1} ({2:0.00}:1, {3:0.00} %, {4} disk space saved)" -f
        (Format-FileSize -Size $this.OriginalSize),
        (Format-FileSize -Size $this.ReencodedSize),
        ($this.OriginalSize / $this.ReencodedSize),
        ($saved / $this.OriginalSize * 100),
        (Format-FileSize -Size $saved))
    }

    [string]
    TimeReport()
    {
        if ($this.Count -eq 0 -or $this.Duration -eq 0 -or $this.ElapsedTime -eq 0)
        {
            return ''
        }
        return ("{0} reencoded in {1} (Speed: x{2:0.00})" -f
        (Format-Duration -TimeSpan $this.Duration),
        (Format-Duration -TimeSpan $this.ElapsedTime),
        ($this.Duration / $this.ElapsedTime))
    }

    [void]
    WriteReport([ConsoleColor] $Color, [string] $Prefix, [bool] $Force)
    {
        if (-not [string]::IsNullOrWhiteSpace($Prefix))
        {
            if ($this.Count -eq 0)
            {
                Write-InfoLog -Color $Color ("{0}no reencoded file" -f $Prefix) -Force:$Force; return
            }
            Write-InfoLog -Color $Color ($Prefix + "$( $this.Count ) reencoded file(s)") -Force:$Force
        }
        $size = $this.SizeReport(); if ($size)
        {
            Write-InfoLog -Color $Color $size -Force:$Force
        }
        if ($this.Duration -gt 0)
        {
            $time = $this.TimeReport(); if ($time)
            {
                Write-InfoLog -Color $Color $time -Force:$Force
            }
        }
    }
}

enum Upscale
{
    x = -1
    x720p = 720
    x1080p = 1080
    x2160p = 2160
    x4320p = 4320
}

# -----------------------------------------------------------------------------
# Helpers internes au module racine
# -----------------------------------------------------------------------------

# Convertit l'étiquette Upscale (ex: '720p') vers la hauteur cible en pixels.
# Remplace les usages de `[Upscale]::Parse("x$Value").value__` dans les
# sous-modules privés, où l'enum `Upscale` n'est pas accessible (les types
# définis dans un module n'étant pas exportés vers les NestedModules).
function Resolve-UpscaleHeight
{
    param([string] $Value)
    switch ($Value)
    {
        '720p'  { 720 }
        '1080p' { 1080 }
        '2160p' { 2160 }
        '4320p' { 4320 }
        default { -1 }
    }
}

# TODO: converger vers Tetram.Media.FFmpeg\Invoke-FFmpeg
# Conservée ici pour préserver l'ordre de résolution actuel : la version
# locale shadow l'exportée par `Tetram.Media.FFmpeg` (qui n'a pas exactement
# les mêmes paramètres). À unifier dans une future itération.
function Invoke-FFmpeg
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string] $FFMPEG,
        [Parameter(Mandatory)]
        [string] $InputFile,
        [Parameter()]
        [string[]] $DynamicArgs = @(),
        [Parameter()]
        [string] $OutputFile,

        [Parameter(Mandatory)]
        [string] $TargetLabel,

        [Parameter(Mandatory)]
        [hashtable] $State
    )

    [bool]$IsCheckMode = [string]::IsNullOrWhiteSpace($OutputFile)

    $ffmpegArgs = @(
        '-hide_banner'
        '-v', ($IsCheckMode ? 'error' : '+level')
        '-analyzeduration', '200M'
        '-probesize', '200M'
        '-i', $InputFile
    )
    $ffmpegArgs += $DynamicArgs

    if ($IsCheckMode)
    {
        # ensures "null" muxer if not defined yet
        if (-not ($DynamicArgs -match '^-f$' -or $DynamicArgs -match '^null$'))
        {
            $ffmpegArgs += @('-f', 'null')
        }
    }
    else
    {
        $ffmpegArgs += $OutputFile
    }

    $State.Attempts++
    Show-CommandLine $FFMPEG $ffmpegArgs -NoPathDetectionParameters 'metadata*'

    if ( $PSCmdlet.ShouldProcess($TargetLabel, "ffmpeg $( $IsCheckMode ? 'check' : 'run' ) on $TargetLabel"))
    {
        & $FFMPEG $ffmpegArgs
        return $?
    }

    Write-InfoLog -Color Magenta "[WhatIf] Would run ffmpeg ($( $IsCheckMode ? 'check' : 'run' )) on $TargetLabel"
    return $true
}

function Get-SortedFileList
{
    param(
        [Object[]] $Files,
        [string] $Sort
    )

    switch ($Sort)
    {
        'NewestFirst'  {
            $Files | Sort-Object LastWriteTime -Descending
        }
        'OldestFirst'  {
            $Files | Sort-Object LastWriteTime
        }
        'SmallerFirst' {
            $Files | Sort-Object Length
        }
        'LargerFirst'  {
            $Files | Sort-Object Length -Descending
        }
        default        {
            $Files | Sort-Object Name
        }
    }
}

function Initialize-ReencodeState
{
    param(
        [string] $TempPath
    )

    $state = @{
        ErrorLog = 'reencode-errors.log'
        BaseTempFilename = Join-Path $TempPath ([guid]::NewGuid().ToString())
        Attempts = 0
        IntegrityWarningFiles = [List[string]]::new()
        IntegrityFailureFiles = [List[string]]::new()
        SessionResult = [EncodingResult]::new()
    }

    return $state
}

function Write-ErrorLogWithFile
{
    param(
        [string] $Text,
        [string] $ErrorLog
    )
    Write-ErrorLog $Text
    ("{0}: {1}" -f (Get-Date -Format 'u'), $Text) | Out-File -Append -Encoding UTF8 $ErrorLog
}

# -----------------------------------------------------------------------------
# Orchestrateur fichier
#   Utilise la classe [EncodingResult] (locale) et délègue aux fonctions des
#   sous-modules privés (Probe / Streams / EncoderArgs / NFO / Scan) chargés
#   via NestedModules.
# -----------------------------------------------------------------------------

function Invoke-ReencodeFile
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string] $Filename,
        [hashtable] $State,
        [hashtable] $Config,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )
    Write-Verbose "Starting analysis of '$Filename'"

    $OriginalFile = Get-Item -LiteralPath $Filename
    if (-not $OriginalFile)
    {
        Write-ErrorLogWithFile -Text "Can't get access to '$Filename'" -ErrorLog $State.ErrorLog
        return
    }

    $TempFilename = ""

    try
    {
        if ($OriginalFile.IsReadOnly)
        {
            Write-InfoLog "Skip read-only file '$Filename'"
            return
        }
        $OriginalFileSize = $OriginalFile.Length

        $LastWriteTimeFixes = Get-NFOTimestamps -Filename $Filename -Cmdlet $Cmdlet

        $OriginalFileCreationTime = $OriginalFile.CreationTime
        $OriginalFileLastWriteTime = $OriginalFile.LastWriteTime
        $OriginalFileLastAccessTime = $OriginalFile.LastAccessTime

        foreach ($item in $LastWriteTimeFixes.GetEnumerator())
        {
            if ( $Cmdlet.ShouldProcess($item.Key.FullName, "Fix directory times from premiered"))
            {
                $item.Key.CreationTime = $item.Value
                $item.Key.LastWriteTime = $item.Value
            }
        }

        $ffprobeOutput = Get-FFprobeJson -FFPROBE $Config.FFPROBEPath -File $Filename
        if (-not $ffprobeOutput)
        {
            return
        }

        if (-not ($ffprobeOutput.format.Keys -contains "duration") -and -not $Config.ForceRecodeVideo -and -not $Config.Rewrite)
        {
            Write-InfoLog "Skip '$Filename' that does not look like a convertable format"
            return
        }

        if ($Config.CheckOnly)
        {
            $ok = Invoke-FFmpeg -FFMPEG $Config.FFMPEGPath `
                -InputFile $Filename `
                -DynamicArgs @() `
                -TargetLabel $Filename `
                -State $State
            if (-not $ok)
            {
                Write-ErrorLogWithFile -Text "ffmpeg check failed for '$Filename'" -ErrorLog $State.ErrorLog
            }
            return
        }

        $FinalExtension = ($Config.KeepExtension ? $OriginalFile.Extension : $Config.OutputExtension)

        $videoResult = Select-VideoStreams `
            -FfprobeOutput $ffprobeOutput `
            -ForceRecodeVideo $Config.ForceRecodeVideo `
            -VideoCodec $Config.VideoCodec `
            -AllowVideoCodecUpgrade $Config.AllowVideoCodecUpgrade `
            -Deinterlace $Config.Deinterlace `
            -Upscale $Config.Upscale `
            -UpscaleWidth $Config.UpscaleWidth `
            -UpscaleHeight $Config.UpscaleHeight `
            -UpscaleFit $Config.UpscaleFit `
            -ConfigUpscaleWidth $Config.UpscaleWidth `
            -RewriteMode $Config.Rewrite

        $AudioTracks = Select-AudioStreams `
            -FfprobeOutput $ffprobeOutput `
            -FinalExtension $FinalExtension `
            -Quality $Config.Quality `
            -RewriteMode $Config.Rewrite

        $subtitleResult = Select-SubtitleStreams `
            -FfprobeOutput $ffprobeOutput `
            -FinalExtension $FinalExtension `
            -AllowSubTitlesConversion $Config.AllowSubTitlesConversion `
            -RewriteMode $Config.Rewrite `
            -SubTitlesToKeep $Config.SubTitlesToKeep `
            -Filename $Filename `
            -DirectoryName $OriginalFile.DirectoryName

        if ($null -eq $subtitleResult)
        {
            $subtitleStreams = $ffprobeOutput.streams | Where-Object { $_.codec_type -eq 'subtitle' }
            $SubtitleTracks = $subtitleStreams | Select-Object codec_name, tags
            if ($SubtitleTracks -and $FinalExtension -ieq '.mp4' -and -not $Config.AllowSubTitlesConversion)
            {
                Write-InfoLog -Color Yellow "Skip '$Filename' because $FinalExtension format requires subtitles conversion"
            }
            else
            {
                Write-InfoLog -Color Yellow "Skip '$Filename' because ass subtitles cannot be properly converted"
            }
            return
        }

        $AttachmentTracks = Select-AttachmentStreams `
            -FfprobeOutput $ffprobeOutput `
            -HasAssSubtitles $subtitleResult.HasAssSubtitles

        $hasVideoToConvert = @(@($videoResult.VideoTracks) | Where-Object { -not $_.__copy }).Count
        $hasAudioToConvert = @(@($AudioTracks) | Where-Object { -not $_.__copy }).Count
        $hasSubtitlesToConvert = @(@($subtitleResult.SubtitleTracks) | Where-Object { -not $_.__copy }).Count

        $hasTracksDropped = (
        @(@($videoResult.VideoTracks) | Where-Object { -not $_.__copy -and -not $_.__process }).Count -gt 0 -or
                @(@($AudioTracks) | Where-Object { -not $_.__copy -and -not $_.__process }).Count -gt 0 -or
                @(@($subtitleResult.SubtitleTracks) | Where-Object { -not $_.__copy -and -not $_.__process }).Count -gt 0 -or
                @(@($AttachmentTracks) | Where-Object { -not $_.__copy -and -not $_.__process }).Count -gt 0
        )

        if ($Config.Rewrite)
        {
            if (-not $hasTracksDropped)
            {
                Write-InfoLog "No stream filtering needed for '$Filename'"
                return
            }
        }
        else
        {
            if (($hasVideoToConvert -eq 0) -and ($hasAudioToConvert -eq 0) -and ($hasSubtitlesToConvert -eq 0) -and
                    ($OriginalFile.Extension -ieq $FinalExtension) -and -not $hasTracksDropped)
            {
                Write-InfoLog "No reencoding needed for '$Filename'"
                return
            }
        }

        $mediaDuration = ($ffprobeOutput.format.Keys -contains "duration") ? $ffprobeOutput.format.duration : 0

        $NewFilename = $OriginalFile.BaseName + $FinalExtension
        $TempFilename = $State.BaseTempFilename + $FinalExtension
        $NewFilePath = Join-Path -Path $OriginalFile.DirectoryName -ChildPath $NewFilename

        if (([string]$OriginalFile.FullName -ne $NewFilePath) -and [File]::Exists($NewFilePath))
        {
            Write-InfoLog -Color Yellow "Skip '$Filename' to avoid already existing file override" -Force
            return
        }

        Write-InfoLog "Processing '$Filename'..." -Force
        if (Test-Path $TempFilename -PathType Leaf)
        {
            if ( $Cmdlet.ShouldProcess($TempFilename, 'Remove temp file'))
            {
                Remove-Item $TempFilename -Force
            }
        }

        $ffmpegArgs = Get-FFmpegArgs `
            -VideoCodec $Config.VideoCodec `
            -Quality $Config.Quality `
            -Upscale $Config.Upscale `
            -UpscaleWidth $Config.UpscaleWidth `
            -UpscaleHeight $Config.UpscaleHeight `
            -UpscaleFit $Config.UpscaleFit `
            -ConfigUpscaleWidth $Config.UpscaleWidth `
            -ClearStreamsTitle $Config.ClearStreamsTitle `
            -VideoTracks $videoResult.VideoTracks `
            -IsSource10Bit $videoResult.IsSource10Bit `
            -SourceChroma $videoResult.SourceChroma `
            -AudioTracks $AudioTracks `
            -SubtitleTracks $subtitleResult.SubtitleTracks `
            -AttachmentTracks $AttachmentTracks

        $start = Get-Date
        $ok = Invoke-FFmpeg -FFMPEG $Config.FFMPEGPath `
            -InputFile $Filename `
            -DynamicArgs $ffmpegArgs `
            -OutputFile $TempFilename `
            -TargetLabel $Filename `
            -State $State

        if (-not $ok)
        {
            return
        }

        if (-not $WhatIfPreference -and (Test-Path -LiteralPath $TempFilename -PathType Leaf))
        {
            $keptSourceVideoIndices = @(
            $videoResult.VideoTracks |
                    Where-Object { $_.__copy -or $_.__process } |
                    ForEach-Object { [int]$_._index }
            )
            $keptSourceAudioIndices = @(
            $AudioTracks |
                    Where-Object { $_.__copy -or $_.__process } |
                    ForEach-Object { [int]$_._index }
            )

            $integrity = Test-EncodedFileIntegrity `
                -FFPROBE $Config.FFPROBEPath `
                -SourceProbe $ffprobeOutput `
                -SourceFile $Filename `
                -TempFile $TempFilename `
                -KeptSourceVideoIndices $keptSourceVideoIndices `
                -KeptSourceAudioIndices $keptSourceAudioIndices

            switch ($integrity.Status)
            {
                'mismatch' {
                    $msg = "Incomplete encoding for '{0}' [via {1}] - expected {2:0.000}s, got {3:0.000}s (diff {4:0.000}s)" -f `
                        $Filename, $integrity.Method, $integrity.Expected, $integrity.Actual, $integrity.Diff
                    Write-ErrorLogWithFile -Text $msg -ErrorLog $State.ErrorLog
                    [void]$State.IntegrityFailureFiles.Add($Filename)
                    return
                }
                'unknown' {
                    $msg = "Integrity check inconclusive for '$Filename' - no comparable duration method - accepting file"
                    Write-ErrorLogWithFile -Text $msg -ErrorLog $State.ErrorLog
                    [void]$State.IntegrityWarningFiles.Add($Filename)
                }
            }
        }

        if ( $Cmdlet.ShouldProcess($TempFilename, "Move temp over original '$Filename'"))
        {
            Move-Item -Path $TempFilename -Destination $Filename -Force
        }

        $NewFile = Get-Item -LiteralPath $Filename
        if ($NewFile)
        {
            if ( $Cmdlet.ShouldProcess($NewFile.FullName, "Rename to '$NewFilename'"))
            {
                $NewFile = $NewFile | Rename-Item -NewName $NewFilename -Force -PassThru
            }
            if ( $Cmdlet.ShouldProcess($NewFile.FullName, "Restore timestamps"))
            {
                $NewFile.CreationTime = $OriginalFileCreationTime
                $NewFile.LastWriteTime = $OriginalFileLastWriteTime
                $NewFile.LastAccessTime = $OriginalFileLastAccessTime
            }
            foreach ($item in $LastWriteTimeFixes.GetEnumerator())
            {
                if ( $Cmdlet.ShouldProcess($item.Key.FullName, "Fix directory times (post)"))
                {
                    $item.Key.CreationTime = $item.Value
                    $item.Key.LastWriteTime = $item.Value
                }
            }

            $NewFileSize = $NewFile.Length
            $Result = if ($mediaDuration)
            {
                $Duration = [TimeSpan]::FromSeconds([double]::Parse($mediaDuration, [cultureinfo]''))
                [EncodingResult]::new($OriginalFileSize, $NewFileSize, $Duration, (Get-Date) - $start)
            }
            else
            {
                [EncodingResult]::new($OriginalFileSize, $NewFileSize)
            }

            Write-Log -Color Magenta "Successfully reencoded $Filename"
            if ($NewFile.FullName -ne $Filename)
            {
                Write-Log -Color Magenta "                    to $( $NewFile.FullName )"
            }
            $Result.WriteReport('Magenta', '', $true)

            $State.SessionResult.Add($Result)
            if ($State.SessionResult.Count -gt 1)
            {
                $State.SessionResult.WriteReport('DarkMagenta', 'So far, ', $true)
            }
        }
    }
    catch
    {
        Write-ErrorLogWithFile -Text "Error while treating $( $OriginalFile.FullName )" -ErrorLog $State.ErrorLog
        Write-Verbose $_.Exception
        throw
    }
    finally
    {
        if ( [System.IO.File]::Exists($TempFilename))
        {
            if ( $Cmdlet.ShouldProcess($TempFilename, 'Cleanup temp file'))
            {
                Remove-Item $TempFilename -Force
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Fonction publique
# -----------------------------------------------------------------------------
function Invoke-ReencodeMedia
{
    [CmdletBinding(
            PositionalBinding = $false,
            DefaultParametersetName = 'SetExtensionFromPath',
            SupportsShouldProcess = $true,
            ConfirmImpact = 'Medium'
    )]
    param (
        [Parameter(Position = 0, ParameterSetName = 'CheckFromPath')]
        [Parameter(Position = 0, ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(Position = 0, ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(Position = 0, ParameterSetName = 'RewriteFromPath')]
        [string[]] $Path = ".",
        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [switch] $Recurse,

        [Parameter(Mandatory, ParameterSetName = 'CheckFromFile')]
        [Parameter(Mandatory, ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(Mandatory, ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(Mandatory, ParameterSetName = 'RewriteFromFile')]
        [ValidateScript({ [File]::Exists($_) }, ErrorMessage = "{0} is not a valid filename")]
        [string] $ListFile,
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [switch] $UpdateList,

        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [ValidateSet('NewestFirst', 'OldestFirst', 'SmallerFirst', 'LargerFirst')]
        [string] $Sort,

        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [switch] $ScanReadOnlyDirectory,

        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [ValidateNotNullOrEmpty()]
        [string[]] $InputMasks = @('*.mkv', '*.mp4', '*.avi', '*.wmv', '*.mov', '*.flv', '*.mpeg', '*.mpg', '*.heic', '*.ts', '*.webm'),

        [Parameter(Mandatory, ParameterSetName = 'RewriteFromPath')]
        [Parameter(Mandatory, ParameterSetName = 'RewriteFromFile')]
        [switch] $Rewrite,

        [Parameter(Mandatory, ParameterSetName = 'CheckFromPath')]
        [Parameter(Mandatory, ParameterSetName = 'CheckFromFile')]
        [switch] $CheckOnly,

        [Parameter(Mandatory, ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(Mandatory, ParameterSetName = 'KeepExtensionFromFile')]
        [switch] $KeepExtension,

        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [ValidateScript({ $_ -match '^\.[^.\\/:*?"<>|\r\n]+$' }, ErrorMessage = "{0} is not a valid extension with a leading point")]
        [string] $OutputExtension = '.mkv',

        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [ValidateSet('HEVC', 'AV1')]
        [string] $VideoCodec = 'HEVC',

        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [switch] $ClearStreamsTitle,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [switch] $ForceRecodeVideo,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [switch] $AllowVideoCodecUpgrade,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [ValidateSet('Low', 'Medium', 'High')]
        [string] $Quality = 'Medium',
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [ValidateSet('720p', '1080p', '2160p', '4320p')]
        [string] $Upscale,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [ValidateScript({ ($_ -eq -1) -or ($_ -gt 0) })]
        [int] $UpscaleWidth = -1,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath', Mandatory = $false)]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile', Mandatory = $false)]
        [Parameter(ParameterSetName = 'SetExtensionFromPath', Mandatory = $false)]
        [Parameter(ParameterSetName = 'SetExtensionFromFile', Mandatory = $false)]
        [ValidatePattern('^\d+[xX]\d+$')]
        [string] $UpscaleFit,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [switch] $Deinterlace,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [switch] $AllowSubTitlesConversion,
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [string[]] $SubTitlesToKeep = @('fr', 'fre', 'fr-FR', 'en', 'eng', 'en-US', 'en-GB'),

        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [ValidateScript({ [Directory]::Exists($_) }, ErrorMessage = "{0} is not a valid path")]
        [string] $TempPath = $env:TEMP,

        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [ValidateScript({ [System.IO.Directory]::Exists($_) }, ErrorMessage = "{0} is not a valid folder")]
        [string] $FFToolsBase = '.\',

        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [ValidateScript({ [System.IO.File]::Exists($_) }, ErrorMessage = "{0} is not a valid filename")]
        [string] $FFMPEGPath = (Join-Path $FFToolsBase ($IsWindows ? 'ffmpeg.exe'  : 'ffmpeg')),

        [Parameter(ParameterSetName = 'CheckFromPath')]
        [Parameter(ParameterSetName = 'CheckFromFile')]
        [Parameter(ParameterSetName = 'KeepExtensionFromPath')]
        [Parameter(ParameterSetName = 'KeepExtensionFromFile')]
        [Parameter(ParameterSetName = 'SetExtensionFromPath')]
        [Parameter(ParameterSetName = 'SetExtensionFromFile')]
        [Parameter(ParameterSetName = 'RewriteFromPath')]
        [Parameter(ParameterSetName = 'RewriteFromFile')]
        [ValidateScript({ [System.IO.File]::Exists($_) }, ErrorMessage = "{0} is not a valid filename")]
        [string] $FFPROBEPath = (Join-Path $FFToolsBase ($IsWindows ? 'ffprobe.exe' : 'ffprobe'))
    )

    $state = Initialize-ReencodeState -TempPath $TempPath

    $upscaleWidth = $UpscaleWidth
    $upscaleHeight = $null
    if ($UpscaleFit)
    {
        $parts = $UpscaleFit -split '[xX]'
        $upscaleWidth = [int]$parts[0]
        $upscaleHeight = [int]$parts[1]
    }

    $resolvedFFmpegPath = Get-FFmpegPath -OverridePath $FFMPEGPath
    $resolvedFFprobePath = Get-FfprobePath -OverridePath $FFPROBEPath

    $config = @{
    # Parcours / sélection
        Recurse = $Recurse
        Sort = $Sort
        ScanReadOnlyDirectory = $ScanReadOnlyDirectory
        InputMasks = $InputMasks

        # Mode / format cible
        CheckOnly = $CheckOnly
        Rewrite = [bool]$Rewrite
        KeepExtension = [bool]$Rewrite -or [bool]$KeepExtension
        OutputExtension = $OutputExtension

        # Vidéo
        VideoCodec = $VideoCodec
        ForceRecodeVideo = $ForceRecodeVideo
        AllowVideoCodecUpgrade = $AllowVideoCodecUpgrade
        Quality = $Quality
        Deinterlace = $Deinterlace
        Upscale = $Upscale
        UpscaleWidth = $upscaleWidth
        UpscaleHeight = $upscaleHeight
        UpscaleFit = $UpscaleFit

        # Sous-titres / metadata
        AllowSubTitlesConversion = $AllowSubTitlesConversion
        SubTitlesToKeep = $SubTitlesToKeep
        ClearStreamsTitle = $ClearStreamsTitle

        # Liste
        UpdateList = $UpdateList

        # Outils
        FFMPEGPath = $resolvedFFmpegPath
        FFPROBEPath = $resolvedFFprobePath
    }

    try
    {
        if ($ListFile)
        {
            Invoke-FileList -ListFile $ListFile -State $state -Config $config -Cmdlet $PSCmdlet
        }
        else
        {
            Invoke-PathList -Paths $Path -State $state -Config $config -Cmdlet $PSCmdlet
        }
    }
    finally
    {
        $state.SessionResult.WriteReport('Green', 'This session, ', $true)
        Write-InfoLog -Color Green "On $( $state.Attempts ) ffmpeg invocation(s)" -Force

        if ($state.IntegrityFailureFiles.Count -gt 0)
        {
            Write-InfoLog -Color Red ("{0} file(s) rejected by integrity check (originals preserved):" -f $state.IntegrityFailureFiles.Count) -Force
            foreach ($f in $state.IntegrityFailureFiles)
            {
                Write-InfoLog -Color Red "  - $f" -Force
            }
        }
        if ($state.IntegrityWarningFiles.Count -gt 0)
        {
            Write-InfoLog -Color Yellow ("{0} file(s) accepted with integrity warning (duration unverifiable):" -f $state.IntegrityWarningFiles.Count) -Force
            foreach ($f in $state.IntegrityWarningFiles)
            {
                Write-InfoLog -Color Yellow "  - $f" -Force
            }
        }
    }
}

Export-ModuleMember -Function Invoke-ReencodeMedia
