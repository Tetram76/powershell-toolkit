Set-StrictMode -Version 3.0

@(
    'Tetram.Common'
) | ForEach-Object {
    Import-Module -Name (Join-Path $PSScriptRoot '..' $_) -Force
}

# ---------------------------------------------------------------------------
# Helpers privés
# ---------------------------------------------------------------------------

function ConvertFrom-TetramExtendedLengthPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if ($Path.StartsWith(
        '\\?\UNC\',
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        return '\\' + $Path.Substring(8)
    }

    if ($Path.StartsWith(
        '\\?\',
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        return $Path.Substring(4)
    }

    return $Path
}


function ConvertTo-TetramExtendedLengthPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [int] $Threshold = 160
    )

    if ($Path.StartsWith(
        '\\?\',
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        return $Path
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if ($fullPath.Length -le $Threshold) {
        return $fullPath
    }

    if ($fullPath.StartsWith('\\')) {
        return '\\?\UNC\' + $fullPath.Substring(2)
    }

    return '\\?\' + $fullPath
}


function Get-TetramOptionalPropertyValue {
    param(
        [Parameter(Mandatory)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $property = $InputObject.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}


function ConvertTo-TetramMkvDate {
    param(
        [Parameter(Mandatory)]
        [object] $Value
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture

    if ($Value -is [datetimeoffset]) {
        return $Value.ToUniversalTime().ToString(
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            $culture
        )
    }

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString(
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            $culture
        )
    }

    $text = [string] $Value
    $parsed = [datetimeoffset]::MinValue

    $styles =
        [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
        [System.Globalization.DateTimeStyles]::AdjustToUniversal

    if (
        [datetimeoffset]::TryParse(
            $text,
            $culture,
            $styles,
            [ref] $parsed
        )
    ) {
        return $parsed.ToString(
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            $culture
        )
    }

    throw "Date Matroska non reconnue : '$text'"
}

function Get-TetramMkvMergeInfo {
    param(
        [Parameter(Mandatory)]
        [string] $MkvMerge,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $tempFile = [System.IO.Path]::GetTempFileName()

    try {
        & $MkvMerge `
            --output-charset UTF-8 `
            --redirect-output $tempFile `
            -J $Path

        $exitCode = $LASTEXITCODE

        if ($exitCode -ge 2) {
            throw "mkvmerge -J a échoué avec le code $exitCode."
        }

        $json = Get-Content `
            -LiteralPath $tempFile `
            -Raw `
            -Encoding UTF8

        return $json | ConvertFrom-Json
    }
    finally {
        Remove-Item `
            -LiteralPath $tempFile `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

function ConvertTo-TetramPowerShellLiteral {
    param(
        [AllowEmptyString()]
        [string] $Value
    )

    return "'" + $Value.Replace("'", "''") + "'"
}


function Wait-TetramFileReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateRange(1, 300)]
        [int] $TimeoutSeconds = 30,

        [ValidateRange(10, 5000)]
        [int] $RetryIntervalMilliseconds = 200
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    do {
        if ([System.IO.File]::Exists($Path)) {
            try {
                $stream = [System.IO.File]::Open(
                    $Path,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::ReadWrite,
                    [System.IO.FileShare]::None
                )

                $stream.Dispose()
                return
            }
            catch [System.IO.IOException] {
                # Le fichier n'est pas encore disponible en exclusivité.
            }
            catch [System.UnauthorizedAccessException] {
                # Certains partages réseau peuvent répondre temporairement ainsi.
            }
        }

        Start-Sleep -Milliseconds $RetryIntervalMilliseconds
    }
    while ([DateTime]::UtcNow -lt $deadline)

    throw "Le fichier n'est pas devenu disponible dans le délai imparti : $Path"
}


function Move-TetramItemWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [string] $Destination,

        [ValidateRange(1, 300)]
        [int] $TimeoutSeconds = 30,

        [ValidateRange(10, 5000)]
        [int] $RetryIntervalMilliseconds = 200
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    do {
        try {
            Move-Item `
                -LiteralPath $LiteralPath `
                -Destination $Destination `
                -Force `
                -ErrorAction Stop

            return
        }
        catch [System.IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) {
                throw
            }
        }
        catch [System.UnauthorizedAccessException] {
            if ([DateTime]::UtcNow -ge $deadline) {
                throw
            }
        }

        Start-Sleep -Milliseconds $RetryIntervalMilliseconds
    }
    while ($true)
}


function Invoke-TetramMkvRepairFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $MkvMerge,

        [ValidateRange(1, 32767)]
        [int] $ExtendedPathThreshold = 160,

        [ValidateRange(1, 300)]
        [int] $FileReadyTimeoutSeconds = 30,

        [ValidateRange(10, 5000)]
        [int] $RetryIntervalMilliseconds = 200,

        [switch] $PassThru
    )

    $command =
        Get-MkvInterleaveRepairCommand `
            -Path $Path `
            -MkvMerge $MkvMerge `
            -ExtendedPathThreshold $ExtendedPathThreshold

	# Show-CommandLine $command.Executable $command.arguments

    & $command.Executable $command.arguments

    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw (
            "mkvmerge a échoué avec le code de sortie $exitCode. " +
            "Le fichier source n'a pas été remplacé : $Path"
        )
    }

    if (-not [System.IO.File]::Exists($command.ToolOutputPath)) {
        throw (
            "mkvmerge s'est terminé sans erreur, mais le fichier de sortie " +
            "n'existe pas : $($command.OutputPath)"
        )
    }

    Wait-TetramFileReady `
        -Path $command.ToolOutputPath `
        -TimeoutSeconds $FileReadyTimeoutSeconds `
        -RetryIntervalMilliseconds $RetryIntervalMilliseconds

    Move-TetramItemWithRetry `
        -LiteralPath $command.ToolOutputPath `
        -Destination $command.ToolInputPath `
        -TimeoutSeconds $FileReadyTimeoutSeconds `
        -RetryIntervalMilliseconds $RetryIntervalMilliseconds

    if ($PassThru) {
        Get-Item -LiteralPath $command.ToolInputPath
    }
}


# ---------------------------------------------------------------------------
# API publique
# ---------------------------------------------------------------------------

function Get-MkvInterleaveRepairCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [string] $OutputPath,

        [string] $MkvMerge = 'mkvmerge.exe',

        [ValidateRange(1, 32767)]
        [int] $ExtendedPathThreshold = 160
    )

    # -----------------------------------------------------------------------
    # Normalisation des chemins
    # -----------------------------------------------------------------------

    $normalInputPath =
        ConvertFrom-TetramExtendedLengthPath -Path $Path

    $fullInputPath =
        [System.IO.Path]::GetFullPath($normalInputPath)

    $toolInputPath =
        ConvertTo-TetramExtendedLengthPath `
            -Path $fullInputPath `
            -Threshold $ExtendedPathThreshold

    if (-not [System.IO.File]::Exists($toolInputPath)) {
        throw "Fichier introuvable : $Path"
    }


    # -----------------------------------------------------------------------
    # Nom du fichier de sortie
    # -----------------------------------------------------------------------

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $directory =
            [System.IO.Path]::GetDirectoryName($fullInputPath)

        $leaf =
            [System.IO.Path]::GetFileName($fullInputPath)

        if (
            $leaf.EndsWith(
                '.mkv',
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            $leaf =
                $leaf.Substring(0, $leaf.Length - 4) +
                '.repaired.mkv'
        }
        else {
            $leaf += '.repaired.mkv'
        }

        $fullOutputPath =
            [System.IO.Path]::Combine(
                $directory,
                $leaf
            )
    }
    else {
        $normalOutputPath =
            ConvertFrom-TetramExtendedLengthPath -Path $OutputPath

        $fullOutputPath =
            [System.IO.Path]::GetFullPath($normalOutputPath)
    }

    $toolOutputPath =
        ConvertTo-TetramExtendedLengthPath `
            -Path $fullOutputPath `
            -Threshold $ExtendedPathThreshold

    if (
        [System.StringComparer]::OrdinalIgnoreCase.Equals(
            $toolInputPath,
            $toolOutputPath
        )
    ) {
        throw 'Le fichier de sortie ne peut pas être le fichier source.'
    }


    # -----------------------------------------------------------------------
    # Exécutable mkvmerge
    # -----------------------------------------------------------------------

    $toolMkvMerge = $MkvMerge

    if ([System.IO.Path]::IsPathRooted($MkvMerge)) {
        $toolMkvMerge =
            ConvertTo-TetramExtendedLengthPath `
                -Path $MkvMerge `
                -Threshold $ExtendedPathThreshold
    }


    # -----------------------------------------------------------------------
    # Identification Matroska
    # -----------------------------------------------------------------------

    $info = Get-TetramMkvMergeInfo `
		-MkvMerge $toolMkvMerge `
		-Path $toolInputPath

    # -----------------------------------------------------------------------
    # Vérification du conteneur
    # -----------------------------------------------------------------------

    $container =
        Get-TetramOptionalPropertyValue `
            -InputObject $info `
            -Name 'container'

    if ($null -eq $container) {
        throw 'mkvmerge n''a retourné aucune information de conteneur.'
    }

    $recognized =
        Get-TetramOptionalPropertyValue `
            -InputObject $container `
            -Name 'recognized'

    $supported =
        Get-TetramOptionalPropertyValue `
            -InputObject $container `
            -Name 'supported'

    $containerType =
        Get-TetramOptionalPropertyValue `
            -InputObject $container `
            -Name 'type'

    if ($recognized -ne $true -or $supported -ne $true) {
        throw 'Conteneur non reconnu ou non supporté par mkvmerge.'
    }

    if (
        $null -eq $containerType -or
        [string] $containerType -notmatch 'Matroska'
    ) {
        throw 'Cette fonction est destinée aux fichiers Matroska.'
    }


    # -----------------------------------------------------------------------
    # Pistes
    # -----------------------------------------------------------------------

    $tracksValue =
        Get-TetramOptionalPropertyValue `
            -InputObject $info `
            -Name 'tracks'

    $tracks = @($tracksValue)

    if ($tracks.Count -eq 0) {
        throw 'Aucune piste trouvée dans le fichier.'
    }

    $avTracks = @(
        $tracks |
            Where-Object {
                $_.type -in 'video', 'audio'
            }
    )

    if ($avTracks.Count -eq 0) {
        throw 'Aucune piste vidéo ou audio trouvée.'
    }

    $otherTracks = @(
        $tracks |
            Where-Object {
                $_.type -notin 'video', 'audio'
            }
    )


    # -----------------------------------------------------------------------
    # Organisation des readers
    # -----------------------------------------------------------------------

    $carrier = $avTracks[0]
    $sourceIdByTrackId = @{}

    $sourceIdByTrackId[[int] $carrier.id] = 0

    for ($i = 1; $i -lt $avTracks.Count; $i++) {
        $trackId = [int] $avTracks[$i].id
        $sourceIdByTrackId[$trackId] = $i
    }

    foreach ($track in $otherTracks) {
        $trackId = [int] $track.id
        $sourceIdByTrackId[$trackId] = 0
    }


    # -----------------------------------------------------------------------
    # Ordre original des pistes
    # -----------------------------------------------------------------------

    $trackOrder = @(
        foreach ($track in $tracks) {
            $trackId = [int] $track.id
            $sourceId = $sourceIdByTrackId[$trackId]

            '{0}:{1}' -f $sourceId, $trackId
        }
    ) -join ','


    # -----------------------------------------------------------------------
    # Construction des arguments
    # -----------------------------------------------------------------------

    $arguments =
        [System.Collections.Generic.List[string]]::new()

    [void] $arguments.Add('-o')
    [void] $arguments.Add($toolOutputPath)


    # -----------------------------------------------------------------------
    # Propriétés du segment
    # -----------------------------------------------------------------------

    $containerProperties =
        Get-TetramOptionalPropertyValue `
            -InputObject $container `
            -Name 'properties'

    if ($null -ne $containerProperties) {

        # ----- SegmentUID --------------------------------------------------

        $segmentUid =
            Get-TetramOptionalPropertyValue `
                -InputObject $containerProperties `
                -Name 'segment_uid'

        if ($null -ne $segmentUid) {
            [void] $arguments.Add('--segment-uid')
            [void] $arguments.Add([string] $segmentUid)
        }


        # ----- Title -------------------------------------------------------

        $title =
            Get-TetramOptionalPropertyValue `
                -InputObject $containerProperties `
                -Name 'title'

        if ($null -ne $title) {
            [void] $arguments.Add('--title')
            [void] $arguments.Add([string] $title)
        }


        # ----- TimestampScale ---------------------------------------------

        $timestampScale =
            Get-TetramOptionalPropertyValue `
                -InputObject $containerProperties `
                -Name 'timestamp_scale'

        if ($null -ne $timestampScale) {
            $timestampScaleText =
                [System.Convert]::ToString(
                    $timestampScale,
                    [System.Globalization.CultureInfo]::InvariantCulture
                )

            [void] $arguments.Add('--timestamp-scale')
            [void] $arguments.Add($timestampScaleText)
        }


        # ----- DateUTC -----------------------------------------------------

        $dateUtc =
            Get-TetramOptionalPropertyValue `
                -InputObject $containerProperties `
                -Name 'date_utc'

        if ($null -ne $dateUtc) {
            $dateText =
                ConvertTo-TetramMkvDate -Value $dateUtc

            [void] $arguments.Add('--date')
            [void] $arguments.Add($dateText)
        }


        # ----- PreviousSegmentUID -----------------------------------------

        $previousSegmentUid =
            Get-TetramOptionalPropertyValue `
                -InputObject $containerProperties `
                -Name 'previous_segment_uid'

        if ($null -ne $previousSegmentUid) {
            [void] $arguments.Add('--link-to-previous')
            [void] $arguments.Add([string] $previousSegmentUid)
        }


        # ----- NextSegmentUID ---------------------------------------------

        $nextSegmentUid =
            Get-TetramOptionalPropertyValue `
                -InputObject $containerProperties `
                -Name 'next_segment_uid'

        if ($null -ne $nextSegmentUid) {
            [void] $arguments.Add('--link-to-next')
            [void] $arguments.Add([string] $nextSegmentUid)
        }
    }


    # -----------------------------------------------------------------------
    # Ordre des pistes
    # -----------------------------------------------------------------------

    [void] $arguments.Add('--track-order')
    [void] $arguments.Add($trackOrder)


    # -----------------------------------------------------------------------
    # Reader #0 : carrier
    # -----------------------------------------------------------------------

    if ($carrier.type -eq 'video') {
        [void] $arguments.Add('--video-tracks')
        [void] $arguments.Add([string] $carrier.id)
        [void] $arguments.Add('-A')
    }
    else {
        [void] $arguments.Add('--audio-tracks')
        [void] $arguments.Add([string] $carrier.id)
        [void] $arguments.Add('-D')
    }

    $carrierTagIds =
        [System.Collections.Generic.List[int]]::new()

    [void] $carrierTagIds.Add(
        [int] $carrier.id
    )

    foreach ($track in $otherTracks) {
        [void] $carrierTagIds.Add(
            [int] $track.id
        )
    }

    if ($carrierTagIds.Count -gt 0) {
        [void] $arguments.Add('--track-tags')
        [void] $arguments.Add(
            ($carrierTagIds.ToArray() -join ',')
        )
    }

    [void] $arguments.Add($toolInputPath)


    # -----------------------------------------------------------------------
    # Readers indépendants des autres pistes A/V
    # -----------------------------------------------------------------------

    for ($i = 1; $i -lt $avTracks.Count; $i++) {
        $track = $avTracks[$i]

        if ($track.type -eq 'video') {
            [void] $arguments.Add('--video-tracks')
            [void] $arguments.Add([string] $track.id)
            [void] $arguments.Add('-A')
        }
        else {
            [void] $arguments.Add('--audio-tracks')
            [void] $arguments.Add([string] $track.id)
            [void] $arguments.Add('-D')
        }

        [void] $arguments.Add('-S')
        [void] $arguments.Add('-B')
        [void] $arguments.Add('-M')
        [void] $arguments.Add('--no-chapters')
        [void] $arguments.Add('--no-global-tags')

        [void] $arguments.Add('--track-tags')
        [void] $arguments.Add([string] $track.id)

        [void] $arguments.Add($toolInputPath)
    }


    # -----------------------------------------------------------------------
    # Représentation PowerShell copiable
    # -----------------------------------------------------------------------

    $commandLine =
        '& ' +
        (ConvertTo-TetramPowerShellLiteral $toolMkvMerge) +
        ' ' +
        (
            (
                $arguments |
                    ForEach-Object {
                        ConvertTo-TetramPowerShellLiteral $_
                    }
            ) -join ' '
        )


    # -----------------------------------------------------------------------
    # Résultat
    # -----------------------------------------------------------------------

    [pscustomobject] @{
        InputPath      = $fullInputPath
        OutputPath     = $fullOutputPath

        ToolInputPath  = $toolInputPath
        ToolOutputPath = $toolOutputPath

        Executable     = $toolMkvMerge
        Arguments      = $arguments.ToArray()
        CommandLine    = $commandLine

        Tracks         = @(
            $tracks |
                Select-Object id, type, codec
        )
    }
}


function Invoke-MkvRepair {
    [CmdletBinding(
        DefaultParameterSetName = 'File',
        SupportsShouldProcess
    )]
    param(
        [Parameter(
            Mandatory,
            Position = 0,
            ParameterSetName = 'File'
        )]
        [string] $Path,

        [Parameter(
            Mandatory,
            ParameterSetName = 'Folder'
        )]
        [string] $Folder,

        [Parameter(
            ParameterSetName = 'Folder'
        )]
        [switch] $Recurse,

        [string] $MkvMerge = 'mkvmerge.exe',

        [ValidateRange(1, 32767)]
        [int] $ExtendedPathThreshold = 160,

        [ValidateRange(1, 300)]
        [int] $FileReadyTimeoutSeconds = 30,

        [ValidateRange(10, 5000)]
        [int] $RetryIntervalMilliseconds = 200,

        [switch] $PassThru
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if ($PSCmdlet.ShouldProcess(
            $Path,
            'Réparer l''interleaving MKV et remplacer le fichier source'
        )) {
            Invoke-TetramMkvRepairFile `
                -Path $Path `
                -MkvMerge $MkvMerge `
                -ExtendedPathThreshold $ExtendedPathThreshold `
                -FileReadyTimeoutSeconds $FileReadyTimeoutSeconds `
                -RetryIntervalMilliseconds $RetryIntervalMilliseconds `
                -PassThru:$PassThru
        }

        return
    }


    # -----------------------------------------------------------------------
    # Mode dossier
    # -----------------------------------------------------------------------

    $normalFolderPath =
        ConvertFrom-TetramExtendedLengthPath -Path $Folder

    $fullFolderPath =
        [System.IO.Path]::GetFullPath($normalFolderPath)

    $toolFolderPath =
        ConvertTo-TetramExtendedLengthPath `
            -Path $fullFolderPath `
            -Threshold $ExtendedPathThreshold

    if (-not [System.IO.Directory]::Exists($toolFolderPath)) {
        throw "Dossier introuvable : $Folder"
    }

    $getChildItemArgs = @{
        LiteralPath = $toolFolderPath
        Filter      = '*.mkv'
        File        = $true
        Recurse     = $Recurse
    }

    # La liste est entièrement matérialisée avant la première réparation.
    # Les fichiers .repaired.mkv créés pendant le traitement ne peuvent donc
    # pas être ajoutés dynamiquement à cette liste.
    $files = @(
        Get-ChildItem @getChildItemArgs |
            Where-Object {
                -not $_.IsReadOnly
            } |
            ForEach-Object {
                $_.FullName
            }
    )

    $count = $files.Count

    if ($count -eq 0) {
        return
    }

    $progressId = 0
    $activity = 'Réparation des fichiers MKV'

    try {
        for ($i = 0; $i -lt $count; $i++) {
            $file = $files[$i]

            Write-Progress `
                -Id $progressId `
                -Activity $activity `
                -Status ('{0}/{1}' -f ($i + 1), $count) `
                -CurrentOperation $file `
                -PercentComplete (($i / $count) * 100)

            if ($PSCmdlet.ShouldProcess(
                $file,
                'Réparer l''interleaving MKV et remplacer le fichier source'
            )) {
                Invoke-TetramMkvRepairFile `
                    -Path $file `
                    -MkvMerge $MkvMerge `
                    -ExtendedPathThreshold $ExtendedPathThreshold `
                    -FileReadyTimeoutSeconds $FileReadyTimeoutSeconds `
                    -RetryIntervalMilliseconds $RetryIntervalMilliseconds `
                    -PassThru:$PassThru
            }
        }
    }
    finally {
        Write-Progress `
            -Id $progressId `
            -Activity $activity `
            -Completed
    }
}
