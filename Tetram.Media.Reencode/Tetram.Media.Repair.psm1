Set-StrictMode -Version 3.0

@(
    'Tetram.Common'
) | ForEach-Object {
    Import-Module -Name (Join-Path $PSScriptRoot '..' $_) -Force
}

# ---------------------------------------------------------------------------
# Helpers privés
# ---------------------------------------------------------------------------

function Get-OptionalPropertyValue {
    param(
        [Parameter(Mandatory)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $Name
    )

    # ConvertFrom-Json -AsHashtable : OrderedHashtable, les clés ne sont pas
    # des NoteProperties (PSObject.Properties['container'] est null).
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in @($InputObject.Keys)) {
            if ($key -eq $Name) {
                return $InputObject[$key]
            }
        }

        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}


function ConvertTo-MkvDate {
    param(
        [Parameter(Mandatory)]
        [object] $Value
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture

    if ($Value -is [datetimeoffset]) {
        return $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $culture)
    }

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $culture)
    }

    $text = [string] $Value
    $parsed = [datetimeoffset]::MinValue

    $styles =
        [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
        [System.Globalization.DateTimeStyles]::AdjustToUniversal

    if ([datetimeoffset]::TryParse($text, $culture, $styles, [ref] $parsed)) {
        return $parsed.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $culture)
    }

    throw "Date Matroska non reconnue : '$text'"
}

function Get-DefaultMkvMergeExecutable {
    return $IsWindows ? 'mkvmerge.exe' : 'mkvmerge' 
}

# Write-MkvMergeCapturedDiagnostics ne reconnaît que les préfixes anglais
# Warning:/Error: ; sans --ui-language, un mkvmerge localisé les traduit.
function Get-MkvMergeMessageCaptureArguments {
    param(
        [Parameter(Mandatory)]
        [string] $LogPath
    )

    @(
        '--ui-language', 'en_US',
        '--output-charset', 'UTF-8',
        '--redirect-output', $LogPath
    )
}

function Get-MkvMergeJsonDiagnosticMessageList {
    param($Value)

    # List plutôt que @() : un tableau vide renvoyé par une fonction PowerShell
    # s'effondre en $null, et foreach ($x in $null) est inoffensif mais
    # foreach ($x in 'text') énumère les caractères.
    $messages = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Value) {
        return $messages
    }

    if ($Value -is [string]) {
        $messages.Add($Value)
        return $messages
    }

    foreach ($item in $Value) {
        if ($null -eq $item) {
            continue
        }

        $messages.Add([string] $item)
    }

    return $messages
}

function Write-MkvMergeIdentificationDiagnostics {
    param(
        [Parameter(Mandatory)]
        [object] $Info
    )

    $warnings = Get-OptionalPropertyValue -InputObject $Info -Name 'warnings'
    foreach ($message in (Get-MkvMergeJsonDiagnosticMessageList -Value $warnings)) {
        Write-Warning $message
    }

    $errors = Get-OptionalPropertyValue -InputObject $Info -Name 'errors'
    foreach ($message in (Get-MkvMergeJsonDiagnosticMessageList -Value $errors)) {
        Write-Error -Message $message -ErrorAction Continue
    }
}

function Get-MkvMergeInfo {
    param(
        [Parameter(Mandatory)]
        [string] $MkvMerge,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $tempFile = [System.IO.Path]::GetTempFileName()

    try {
        & $MkvMerge @(
            (Get-MkvMergeMessageCaptureArguments -LogPath $tempFile)
            '-J'
            $Path
        )

        $exitCode = $LASTEXITCODE
        $raw = Get-Content -LiteralPath $tempFile -Raw -Encoding UTF8

        $info = $null
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            try {
                $info = $raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            }
            catch {
                # ConvertFrom-Json ne doit pas devenir l'exception visible du code >= 2.
                $info = $null
            }
        }

        # Code 0/1 : le JSON d'identification peut déjà porter des warnings
        # repris au remux ; on ne les rejoue pas ici pour éviter le double affichage.
        if ($exitCode -ge 2) {
            if ($null -ne $info) {
                Write-MkvMergeIdentificationDiagnostics -Info $info
            }
            else {
                $null = Write-MkvMergeCapturedDiagnostics -LogPath $tempFile
            }

            throw "mkvmerge -J a échoué avec le code $exitCode."
        }

        if ($null -eq $info) {
            return $raw | ConvertFrom-Json -AsHashtable
        }

        return $info
    }
    finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Write-MkvMergeCapturedDiagnostics {
    param(
        [string] $LogPath
    )

    $warningCount = 0
    if ([string]::IsNullOrWhiteSpace($LogPath) -or -not [System.IO.File]::Exists($LogPath)) {
        return $warningCount
    }

    $logText = Get-Content -LiteralPath $LogPath -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($logText)) {
        return $warningCount
    }

    # Parcours unique : l'ordre Warning:/Error: de mkvmerge doit être conservé.
    foreach ($line in @($logText -split '[\r\n]+')) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed.StartsWith('Warning:')) {
            Write-Warning ($trimmed.Substring('Warning:'.Length).TrimStart())
            $warningCount++
            continue
        }

        if ($trimmed.StartsWith('Error:')) {
            Write-Error -Message ($trimmed.Substring('Error:'.Length).TrimStart()) -ErrorAction Continue
        }
    }

    return $warningCount
}


function Wait-FileReady {
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


function Move-ItemWithRetry {
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


function Invoke-MkvRepairFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $MkvMerge,

        [ValidateRange(1, 32767)]
        [int] $ExtendedPathThreshold = 250,

        [ValidateRange(1, 300)]
        [int] $FileReadyTimeoutSeconds = 30,

        [ValidateRange(10, 5000)]
        [int] $RetryIntervalMilliseconds = 200,

        [switch] $PassThru
    )

    # Le défaut public du builder est un voisin {basename}.repaired.mkv : mkvmerge -o
    # l'écraserait, et en -Folder ce nom est déjà dans la liste matérialisée.
    $normalPath = ConvertFrom-ExtendedLengthPath -Path $Path
    $fullPath = [System.IO.Path]::GetFullPath($normalPath)
    $directory = [System.IO.Path]::GetDirectoryName($fullPath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
    $uniqueOutputPath = Join-Path $directory (
        '{0}.{1}.mkv' -f $baseName, [guid]::NewGuid().ToString('N')
    )

    # Même contrat qu'Invoke-ReencodeFile : un remplacement in-place ne doit
    # pas faire passer le fichier pour « nouveau » auprès des backups / bibliothèques.
    $sourceFile = Get-Item -LiteralPath $fullPath
    $originalCreationTime = $sourceFile.CreationTime
    $originalLastWriteTime = $sourceFile.LastWriteTime
    $originalLastAccessTime = $sourceFile.LastAccessTime

    $command = $null
    $replaced = $false
    $mkvmergeLogPath = $null
    try {
        $command =
            Get-MkvInterleaveRepairCommand `
                -Path $Path `
                -OutputPath $uniqueOutputPath `
                -MkvMerge $MkvMerge `
                -ExtendedPathThreshold $ExtendedPathThreshold

        # Show-CommandLine $command.Executable $command.arguments

        # --quiet : la progression mkvmerge utilise un CR sans LF et collerait
        # les Warning: au milieu d'une ligne Progress. Absent de -J (pas de barre).
        $mkvmergeLogPath = [System.IO.Path]::GetTempFileName()
        $mkvmergeArguments = @(
            (Get-MkvMergeMessageCaptureArguments -LogPath $mkvmergeLogPath)
            '--quiet'
        ) + @($command.Arguments)

        & $command.Executable $mkvmergeArguments > $null

        $exitCode = $LASTEXITCODE

        # Code 1 : mkvmerge a muxé avec avertissements ; le fichier produit n'est
        # pas assez fiable pour remplacer la source, mais ce n'est pas bloquant.
        if ($exitCode -eq 1) {
            $warningCount = Write-MkvMergeCapturedDiagnostics -LogPath $mkvmergeLogPath
            if ($warningCount -eq 0) {
                Write-Warning "mkvmerge a émis des avertissements (code 1). Le fichier source n'a pas été remplacé : $Path"
            }
            else {
                Write-Warning "Le fichier source n'a pas été remplacé : $Path"
            }

            return
        }

        if ($exitCode -ne 0) {
            $null = Write-MkvMergeCapturedDiagnostics -LogPath $mkvmergeLogPath
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

        Wait-FileReady `
            -Path $command.ToolOutputPath `
            -TimeoutSeconds $FileReadyTimeoutSeconds `
            -RetryIntervalMilliseconds $RetryIntervalMilliseconds

        Move-ItemWithRetry `
            -LiteralPath $command.ToolOutputPath `
            -Destination $command.ToolInputPath `
            -TimeoutSeconds $FileReadyTimeoutSeconds `
            -RetryIntervalMilliseconds $RetryIntervalMilliseconds

        $replacedFile = Get-Item -LiteralPath $command.ToolInputPath
        $replacedFile.CreationTime = $originalCreationTime
        $replacedFile.LastWriteTime = $originalLastWriteTime
        $replacedFile.LastAccessTime = $originalLastAccessTime

        $replaced = $true

        if ($PassThru) {
            Get-Item -LiteralPath $command.ToolInputPath
        }
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($mkvmergeLogPath)) {
            Remove-Item -LiteralPath $mkvmergeLogPath -Force -ErrorAction SilentlyContinue
        }

        # Temporaire unique à côté de la source : un échec après le mux
        # laisserait un *.mkv qu'un prochain -Folder reprendrait.
        if (-not $replaced -and $null -ne $command) {
            $tempPath = $command.ToolOutputPath
            if (-not [string]::IsNullOrWhiteSpace($tempPath)) {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
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

        [string] $MkvMerge = (Get-DefaultMkvMergeExecutable),

        [ValidateRange(1, 32767)]
        [int] $ExtendedPathThreshold = 250
    )

    # -----------------------------------------------------------------------
    # Normalisation des chemins
    # -----------------------------------------------------------------------

    $normalInputPath = ConvertFrom-ExtendedLengthPath -Path $Path

    $fullInputPath = [System.IO.Path]::GetFullPath($normalInputPath)

    $toolInputPath = ConvertTo-ExtendedLengthPath -Path $fullInputPath -Threshold $ExtendedPathThreshold

    if (-not [System.IO.File]::Exists($toolInputPath)) {
        throw "Fichier introuvable : $Path"
    }


    # -----------------------------------------------------------------------
    # Nom du fichier de sortie
    # -----------------------------------------------------------------------

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $directory = [System.IO.Path]::GetDirectoryName($fullInputPath)
        $leaf = [System.IO.Path]::GetFileName($fullInputPath)

        if ($leaf.EndsWith('.mkv', [System.StringComparison]::OrdinalIgnoreCase)) {
            $leaf = $leaf.Substring(0, $leaf.Length - 4) + '.repaired.mkv'
        }
        else {
            $leaf += '.repaired.mkv'
        }    
        $fullOutputPath = [System.IO.Path]::Combine($directory, $leaf)
    }
    else {
        $fullOutputPath = [System.IO.Path]::GetFullPath(
            (ConvertFrom-ExtendedLengthPath -Path $OutputPath)
        )
    }

    $toolOutputPath = ConvertTo-ExtendedLengthPath -Path $fullOutputPath -Threshold $ExtendedPathThreshold

    if (Test-SameFilesystemPath -LiteralPath $fullInputPath -ReferenceLiteralPath $fullOutputPath) {
        throw 'Le fichier de sortie ne peut pas être le fichier source.'
    }


    # -----------------------------------------------------------------------
    # Exécutable mkvmerge
    # -----------------------------------------------------------------------

    $toolMkvMerge = $MkvMerge

    if ([System.IO.Path]::IsPathRooted($MkvMerge)) {
        $toolMkvMerge = ConvertTo-ExtendedLengthPath -Path $MkvMerge -Threshold $ExtendedPathThreshold
    }

    # -----------------------------------------------------------------------
    # Identification Matroska
    # -----------------------------------------------------------------------

    $info = Get-MkvMergeInfo -MkvMerge $toolMkvMerge -Path $toolInputPath

    # -----------------------------------------------------------------------
    # Vérification du conteneur
    # -----------------------------------------------------------------------

    $container = Get-OptionalPropertyValue -InputObject $info -Name 'container'

    if ($null -eq $container) {
        throw 'mkvmerge n''a retourné aucune information de conteneur.'
    }

    $recognized = Get-OptionalPropertyValue -InputObject $container -Name 'recognized'

    $supported = Get-OptionalPropertyValue -InputObject $container -Name 'supported'

    $containerType = Get-OptionalPropertyValue -InputObject $container -Name 'type'

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

    $tracksValue = Get-OptionalPropertyValue -InputObject $info -Name 'tracks'

    $tracks = @($tracksValue)

    if ($tracks.Count -eq 0) {
        throw 'Aucune piste trouvée dans le fichier.'
    }

    $avTracks = @(
        $tracks | Where-Object { $_.type -in 'video', 'audio' }
    )

    if ($avTracks.Count -eq 0) {
        throw 'Aucune piste vidéo ou audio trouvée.'
    }

    $otherTracks = @(
        $tracks | Where-Object { $_.type -notin 'video', 'audio' }
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

    $arguments = @(
        '-o', $toolOutputPath
    )

    # -----------------------------------------------------------------------
    # Propriétés du segment
    # -----------------------------------------------------------------------

    $containerProperties = Get-OptionalPropertyValue -InputObject $container -Name 'properties'

    if ($null -ne $containerProperties) {

        # ----- SegmentUID --------------------------------------------------

        $segmentUid = Get-OptionalPropertyValue -InputObject $containerProperties -Name 'segment_uid'

        if ($null -ne $segmentUid) {
            $arguments += @( 
                '--segment-uid', [string] $segmentUid
            )
        }


        # ----- Title -------------------------------------------------------

        $title = Get-OptionalPropertyValue -InputObject $containerProperties -Name 'title'

        if ($null -ne $title) {
            $arguments += @( 
                '--title', [string] $title
            )
        }


        # ----- TimestampScale ---------------------------------------------

        $timestampScale = Get-OptionalPropertyValue -InputObject $containerProperties -Name 'timestamp_scale'

        if ($null -ne $timestampScale) {
            $timestampScaleText = [System.Convert]::ToString($timestampScale, [System.Globalization.CultureInfo]::InvariantCulture)

            $arguments += @( 
                '--timestamp-scale', $timestampScaleText
            )
        }


        # ----- DateUTC -----------------------------------------------------

        $dateUtc = Get-OptionalPropertyValue -InputObject $containerProperties -Name 'date_utc'

        if ($null -ne $dateUtc) {
            $dateText = ConvertTo-MkvDate -Value $dateUtc

            $arguments += @( 
                '--date', $dateText
            )
        }


        # ----- PreviousSegmentUID -----------------------------------------

        $previousSegmentUid = Get-OptionalPropertyValue -InputObject $containerProperties -Name 'previous_segment_uid'

        if ($null -ne $previousSegmentUid) {
            $arguments += @( 
                '--link-to-previous', [string] $previousSegmentUid
            )
        }


        # ----- NextSegmentUID ---------------------------------------------

        $nextSegmentUid = Get-OptionalPropertyValue -InputObject $containerProperties -Name 'next_segment_uid'

        if ($null -ne $nextSegmentUid) {
            $arguments += @( 
                '--link-to-next', [string] $nextSegmentUid
            )
        }
    }


    # -----------------------------------------------------------------------
    # Ordre des pistes
    # -----------------------------------------------------------------------

    $arguments += @( 
        '--track-order', $trackOrder
    )


    # -----------------------------------------------------------------------
    # Reader #0 : carrier
    # -----------------------------------------------------------------------

    if ($carrier.type -eq 'video') {
        $arguments += @( 
            '--video-tracks', [string] $carrier.id, '-A'
        )
    }
    else {
        $arguments += @( 
            '--audio-tracks', [string] $carrier.id, '-D'
        )
    }

    $carrierTagIds = @( 
        [int] $carrier.id
    )

    foreach ($track in $otherTracks) {
        $carrierTagIds += [int] $track.id
    }

    if ($carrierTagIds.Count -gt 0) {
        $arguments += @( 
            '--track-tags', ($carrierTagIds -join ',')
        )
    }

    $arguments += @( 
        $toolInputPath
    )

    # -----------------------------------------------------------------------
    # Readers indépendants des autres pistes A/V
    # -----------------------------------------------------------------------

    for ($i = 1; $i -lt $avTracks.Count; $i++) {
        $track = $avTracks[$i]

        if ($track.type -eq 'video') {
            $arguments += @( 
                '--video-tracks', [string] $track.id, '-A'
            )
        }
        else {
            $arguments += @( 
                '--audio-tracks', [string] $track.id, '-D'
            )
        }

        $arguments += @(
            '-S', '-B', '-M', '--no-chapters', '--no-global-tags'
            '--track-tags', [string] $track.id
            $toolInputPath
        )
    }


    # -----------------------------------------------------------------------
    # Représentation PowerShell copiable
    # -----------------------------------------------------------------------

    $commandLine =
        '& ' +
        (ConvertTo-PowerShellLiteral $toolMkvMerge) +
        ' ' +
        (($arguments | ForEach-Object { ConvertTo-PowerShellLiteral $_ }) -join ' ')

    # -----------------------------------------------------------------------
    # Résultat
    # -----------------------------------------------------------------------

    [pscustomobject] @{
        InputPath      = $fullInputPath
        OutputPath     = $fullOutputPath

        ToolInputPath  = $toolInputPath
        ToolOutputPath = $toolOutputPath

        Executable     = $toolMkvMerge
        Arguments      = $arguments
        CommandLine    = $commandLine

        Tracks         = @($tracks | Select-Object id, type, codec)
    }
}


function Invoke-MkvRepair {
    [CmdletBinding(DefaultParameterSetName = 'File', SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'File')] 
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Folder')] 
        [string] $Folder,

        [Parameter(ParameterSetName = 'Folder')] 
        [switch] $Recurse,

        [Parameter(ParameterSetName = 'Folder')]
        [switch] $ContinueOnError,

        [string] $MkvMerge = (Get-DefaultMkvMergeExecutable),

        [ValidateRange(1, 32767)]
        [int] $ExtendedPathThreshold = 250,

        [ValidateRange(1, 300)]
        [int] $FileReadyTimeoutSeconds = 30,

        [ValidateRange(10, 5000)]
        [int] $RetryIntervalMilliseconds = 200,

        [switch] $PassThru
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if ($PSCmdlet.ShouldProcess($Path, 'Réparer l''interleaving MKV et remplacer le fichier source')) {
            Invoke-MkvRepairFile `
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

    $normalFolderPath = ConvertFrom-ExtendedLengthPath -Path $Folder

    $fullFolderPath = [System.IO.Path]::GetFullPath($normalFolderPath)

    $toolFolderPath = ConvertTo-ExtendedLengthPath -Path $fullFolderPath -Threshold $ExtendedPathThreshold

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
    # Les temporaires créés pendant le traitement ne peuvent donc pas être
    # ajoutés dynamiquement à cette liste.
    $files = @(
        Get-ChildItem @getChildItemArgs |
            Where-Object {-not $_.IsReadOnly} |
            ForEach-Object { $_.FullName }
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

            if ($PSCmdlet.ShouldProcess($file, 'Réparer l''interleaving MKV et remplacer le fichier source')) {
                try {
                    Invoke-MkvRepairFile `
                        -Path $file `
                        -MkvMerge $MkvMerge `
                        -ExtendedPathThreshold $ExtendedPathThreshold `
                        -FileReadyTimeoutSeconds $FileReadyTimeoutSeconds `
                        -RetryIntervalMilliseconds $RetryIntervalMilliseconds `
                        -PassThru:$PassThru
                }
                catch {
                    if ($ContinueOnError) {
                        Write-Error -ErrorRecord $_ -ErrorAction Continue
                        continue
                    }

                    throw
                }
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
