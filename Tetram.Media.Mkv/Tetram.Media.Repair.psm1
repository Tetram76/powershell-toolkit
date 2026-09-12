Set-StrictMode -Version 3.0

@(
    'Tetram.Common'
) | ForEach-Object {
    Import-Module -Name (Join-Path $PSScriptRoot '..' $_) -Force
}

# ---------------------------------------------------------------------------
# Helpers privés
# ---------------------------------------------------------------------------

function Format-RepairSourceHeader {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SourcePath
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return $null
    }

    "Fichier source '$SourcePath'"
}

function Get-RepairDiagnosticLines {
    param(
        [AllowNull()]
        [string] $Message
    )

    $text = [string] $Message
    if ($text.Length -eq 0) {
        return [string[]] @()
    }

    # Split explicite : -split PowerShell drop les vides de fin et laisserait
    # un CR si on ne cassait que sur LF. Les lignes vides du split ne doivent
    # pas devenir des Write-* sans texte.
    return [string[]] @(
        foreach ($line in [regex]::Split($text, '\r\n|\n|\r')) {
            if ($line.Length -gt 0) {
                $line
            }
        }
    )
}

function Write-RepairDiagnostic {
    [CmdletBinding()]
    param(
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Diagnostics,

        [ValidateSet('Warning', 'Error')]
        [string] $HeaderSeverity
    )

    $items = @(
        foreach ($item in @($Diagnostics)) {
            if ($null -ne $item) {
                $item
            }
        }
    )

    $forceHeader = $PSBoundParameters.ContainsKey('HeaderSeverity')
    if ($items.Count -eq 0 -and -not $forceHeader) {
        return
    }

    $hasError = $false
    if ($forceHeader) {
        $hasError = $HeaderSeverity -eq 'Error'
    }
    else {
        foreach ($item in $items) {
            if ([string] (Get-OptionalPropertyValue -InputObject $item -Name 'Severity') -eq 'Error') {
                $hasError = $true
                break
            }
        }
    }

    $header = Format-RepairSourceHeader -SourcePath $SourcePath
    if ($null -ne $header) {
        if ($hasError) {
            Write-Error -Message $header -ErrorAction Continue
        }
        else {
            Write-Warning -Message $header
        }
    }

    foreach ($item in $items) {
        $isError = [string] (Get-OptionalPropertyValue -InputObject $item -Name 'Severity') -eq 'Error'
        $message = [string] (Get-OptionalPropertyValue -InputObject $item -Name 'Message')
        foreach ($line in (Get-RepairDiagnosticLines -Message $message)) {
            if ($isError) {
                Write-Error -Message $line -ErrorAction Continue
            }
            else {
                Write-Warning -Message $line
            }
        }
    }
}

function Get-RepairDisplayDiagnostics {
    param(
        [AllowEmptyCollection()]
        [object[]] $Diagnostics,

        [string] $ExceptionMessage,

        [switch] $HideExceptionMessage
    )

    $items = @(
        foreach ($item in @($Diagnostics)) {
            if ($null -ne $item) {
                $item
            }
        }
    )

    if (-not $HideExceptionMessage -or [string]::IsNullOrWhiteSpace($ExceptionMessage) -or $items.Count -eq 0) {
        return $items
    }

    $lastErrorIndex = -1
    for ($i = 0; $i -lt $items.Count; $i++) {
        if ([string] (Get-OptionalPropertyValue -InputObject $items[$i] -Name 'Severity') -eq 'Error') {
            $lastErrorIndex = $i
        }
    }

    if ($lastErrorIndex -lt 0) {
        return $items
    }

    $lastMessage = [string] (Get-OptionalPropertyValue -InputObject $items[$lastErrorIndex] -Name 'Message')
    if ($lastMessage -ne $ExceptionMessage) {
        return $items
    }

    $kept = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $items.Count; $i++) {
        if ($i -ne $lastErrorIndex) {
            $kept.Add($items[$i])
        }
    }

    return @($kept)
}

function Write-RepairFailedDiagnostic {
    param(
        [string] $SourcePath,

        [AllowEmptyCollection()]
        [object[]] $Diagnostics,

        [string] $ExceptionMessage,

        [switch] $HideExceptionMessage
    )

    $original = @(
        foreach ($item in @($Diagnostics)) {
            if ($null -ne $item) {
                $item
            }
        }
    )
    $display = @(
        Get-RepairDisplayDiagnostics `
            -Diagnostics $original `
            -ExceptionMessage $ExceptionMessage `
            -HideExceptionMessage:$HideExceptionMessage
    )
    $omitted = $HideExceptionMessage -and $original.Count -gt $display.Count

    if ($display.Count -eq 0 -and -not $omitted) {
        return
    }

    if ($omitted) {
        Write-RepairDiagnostic -SourcePath $SourcePath -Diagnostics $display -HeaderSeverity Error
        return
    }

    Write-RepairDiagnostic -SourcePath $SourcePath -Diagnostics $display
}

$script:RepairExceptionKeyDiagnostics = 'Tetram.Media.Repair.Diagnostics'
$script:RepairExceptionKeyTempPath = 'Tetram.Media.Repair.TempPath'
$script:RepairExceptionKeySeverity = 'Tetram.Media.Repair.Severity'
$script:RepairExceptionKeyBlocked = 'Tetram.Media.Repair.OperationBlocked'

function Add-RepairExceptionData {
    param(
        [Parameter(Mandatory)]
        [System.Exception] $Exception,

        [object[]] $Diagnostics,

        [string] $TempPath,

        [string] $Severity,

        [switch] $OperationBlocked
    )

    if ($PSBoundParameters.ContainsKey('Diagnostics') -and -not $Exception.Data.Contains($script:RepairExceptionKeyDiagnostics)) {
        $Exception.Data[$script:RepairExceptionKeyDiagnostics] = @($Diagnostics)
    }

    if ($PSBoundParameters.ContainsKey('TempPath') -and -not $Exception.Data.Contains($script:RepairExceptionKeyTempPath)) {
        $Exception.Data[$script:RepairExceptionKeyTempPath] = $TempPath
    }

    if ($PSBoundParameters.ContainsKey('Severity') -and -not $Exception.Data.Contains($script:RepairExceptionKeySeverity)) {
        $Exception.Data[$script:RepairExceptionKeySeverity] = $Severity
    }

    if ($OperationBlocked -and -not $Exception.Data.Contains($script:RepairExceptionKeyBlocked)) {
        $Exception.Data[$script:RepairExceptionKeyBlocked] = $true
    }
}

function Get-RepairExceptionData {
    param(
        [Parameter(Mandatory)]
        [System.Exception] $Exception
    )

    $diagnostics = $null
    $tempPath = $null
    $severity = $null
    $blocked = $null

    $current = $Exception
    while ($null -ne $current) {
        if ($null -eq $diagnostics -and $current.Data.Contains($script:RepairExceptionKeyDiagnostics)) {
            $diagnostics = $current.Data[$script:RepairExceptionKeyDiagnostics]
        }

        if ($null -eq $tempPath -and $current.Data.Contains($script:RepairExceptionKeyTempPath)) {
            $tempPath = $current.Data[$script:RepairExceptionKeyTempPath]
        }

        if ($null -eq $severity -and $current.Data.Contains($script:RepairExceptionKeySeverity)) {
            $severity = $current.Data[$script:RepairExceptionKeySeverity]
        }

        if ($null -eq $blocked -and $current.Data.Contains($script:RepairExceptionKeyBlocked)) {
            $blocked = $current.Data[$script:RepairExceptionKeyBlocked]
        }

        $current = $current.InnerException
    }

    [pscustomobject]@{
        Diagnostics      = $diagnostics
        TempPath         = $tempPath
        Severity         = $severity
        OperationBlocked = $blocked
    }
}

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

# Get-MkvMergeCapturedDiagnostics ne reconnaît que les préfixes anglais
# Warning:/Error: ; sans --ui-language, un mkvmerge localisé les traduit
# (Erreur : / Avertissement :). MKVToolNix n'a pas de locale en_US : l'anglais
# est la langue source. --ui-language en_US fait échouer l'outil avant toute
# identification, avec un message localisé que le parser Warning:/Error: ignore.
function Get-MkvMergeMessageCaptureArguments {
    param(
        [Parameter(Mandatory)]
        [string] $LogPath
    )

    @(
        '--ui-language', 'en',
        '--output-charset', 'UTF-8',
        '--redirect-output', $LogPath
    )
}

function New-MkvMergeDiagnosticCounts {
    param(
        [int] $WarningCount = 0,
        [int] $ErrorCount = 0
    )

    [pscustomobject]@{
        WarningCount = $WarningCount
        ErrorCount   = $ErrorCount
    }
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

function New-RepairDiagnosticItem {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Warning', 'Error')]
        [string] $Severity,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message
    )

    [pscustomobject]@{
        Severity = $Severity
        Message  = $Message
    }
}

function New-RepairDiagnosticSet {
    param(
        [System.Collections.IEnumerable] $Items
    )

    $list = [System.Collections.Generic.List[object]]::new()
    $warningCount = 0
    $errorCount = 0
    foreach ($item in @($Items)) {
        if ($null -eq $item) {
            continue
        }

        $list.Add($item)
        if ([string] $item.Severity -eq 'Error') {
            $errorCount++
        }
        else {
            $warningCount++
        }
    }

    [pscustomobject]@{
        Items        = $list.ToArray()
        WarningCount = $warningCount
        ErrorCount   = $errorCount
    }
}

function Get-MkvMergeIdentificationDiagnostics {
    param(
        [Parameter(Mandatory)]
        [object] $Info
    )

    $items = [System.Collections.Generic.List[object]]::new()

    $warnings = Get-OptionalPropertyValue -InputObject $Info -Name 'warnings'
    foreach ($message in (Get-MkvMergeJsonDiagnosticMessageList -Value $warnings)) {
        $items.Add((New-RepairDiagnosticItem -Severity Warning -Message $message))
    }

    $errors = Get-OptionalPropertyValue -InputObject $Info -Name 'errors'
    foreach ($message in (Get-MkvMergeJsonDiagnosticMessageList -Value $errors)) {
        $items.Add((New-RepairDiagnosticItem -Severity Error -Message $message))
    }

    New-RepairDiagnosticSet -Items $items
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
            $diagnosticSet = if ($null -ne $info) {
                Get-MkvMergeIdentificationDiagnostics -Info $info
            }
            else {
                Get-MkvMergeCapturedDiagnostics -LogPath $tempFile
            }

            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in @($diagnosticSet.Items)) {
                $items.Add($item)
            }

            # JSON parsable sans warnings/errors : ne pas dumper le document.
            # Le brut n'est qu'un dernier recours si rien n'a été classifié.
            if (
                $items.Count -eq 0 -and
                $null -eq $info -and
                -not [string]::IsNullOrWhiteSpace($raw)
            ) {
                $items.Add(
                    (New-RepairDiagnosticItem -Severity Error -Message $raw.TrimEnd())
                )
            }

            $exception = [System.InvalidOperationException]::new(
                "mkvmerge -J a échoué avec le code $exitCode."
            )
            Add-RepairExceptionData -Exception $exception -Diagnostics $items.ToArray()
            throw $exception
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

function Get-MkvMergeCapturedDiagnostics {
    param(
        [string] $LogPath
    )

    $items = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($LogPath) -or -not [System.IO.File]::Exists($LogPath)) {
        return (New-RepairDiagnosticSet -Items $items)
    }

    $logText = Get-Content -LiteralPath $LogPath -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($logText)) {
        return (New-RepairDiagnosticSet -Items $items)
    }

    # Parcours unique : l'ordre Warning:/Error: de mkvmerge doit être conservé.
    foreach ($line in @($logText -split '[\r\n]+')) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed.StartsWith('Warning:')) {
            $items.Add(
                (New-RepairDiagnosticItem -Severity Warning -Message ($trimmed.Substring('Warning:'.Length).TrimStart()))
            )
            continue
        }

        if ($trimmed.StartsWith('Error:')) {
            $items.Add(
                (New-RepairDiagnosticItem -Severity Error -Message ($trimmed.Substring('Error:'.Length).TrimStart()))
            )
        }
    }

    New-RepairDiagnosticSet -Items $items
}

function Invoke-MkvMergeRemux {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Executable,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Arguments,

        [Parameter(Mandatory)]
        [string] $LogPath
    )

    $mkvmergeArguments = @(
        (Get-MkvMergeMessageCaptureArguments -LogPath $LogPath)
        '--quiet'
    ) + @($Arguments)

    try {
        & $Executable $mkvmergeArguments > $null
        $exitCode = $LASTEXITCODE
        $captured = Get-MkvMergeCapturedDiagnostics -LogPath $LogPath
        [pscustomobject]@{
            ExitCode     = $exitCode
            Diagnostics  = @($captured.Items)
            WarningCount = $captured.WarningCount
            ErrorCount   = $captured.ErrorCount
        }
    }
    catch {
        $captured = Get-MkvMergeCapturedDiagnostics -LogPath $LogPath
        if (@($captured.Items).Count -gt 0) {
            Add-RepairExceptionData -Exception $_.Exception -Diagnostics @($captured.Items)
        }

        throw
    }
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


function New-RepairFileResult {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'WarningKept', 'Failed')]
        [string] $Outcome,

        $PassThru = $null,

        $ErrorRecord = $null
    )

    [pscustomobject]@{
        Outcome     = $Outcome
        PassThru    = $PassThru
        ErrorRecord = $ErrorRecord
    }
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

        [switch] $PassThru,

        [switch] $ForceReplaceOnWarning,

        # L'appelant qui ThrowTerminatingError omet le dernier Error du bloc
        # s'il recopie Exception.Message : l'hôte réécrit ce texte à la terminaison.
        [switch] $HideExceptionMessage
    )

    # Le défaut public du builder est un voisin {basename}.repaired.mkv : mkvmerge -o
    # l'écraserait, et en -Folder ce nom est déjà dans la liste matérialisée.
    $sourcePathForDisplay = $Path
    $command = $null
    $replaced = $false
    $mkvmergeLogPath = $null
    $originalCreationTime = $null
    $originalLastWriteTime = $null
    $originalLastAccessTime = $null

    try {
        $normalPath = ConvertFrom-ExtendedLengthPath -Path $Path
        $fullPath = [System.IO.Path]::GetFullPath($normalPath)
        $sourcePathForDisplay = $fullPath
        $directory = [System.IO.Path]::GetDirectoryName($fullPath)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
        $uniqueOutputPath = Join-Path $directory (
            '{0}.{1}.mkv' -f $baseName, [guid]::NewGuid().ToString('N')
        )

        $command =
            New-MkvInterleaveRepairCommand `
                -Path $Path `
                -OutputPath $uniqueOutputPath `
                -MkvMerge $MkvMerge `
                -ExtendedPathThreshold $ExtendedPathThreshold

        # Après le builder : un fichier absent lève « Fichier introuvable »
        # plutôt qu'un Get-Item non terminant puis StrictMode sur CreationTime.
        # Même contrat qu'Invoke-ReencodeFile : un remplacement in-place ne doit
        # pas faire passer le fichier pour « nouveau » auprès des backups / bibliothèques.
        $sourceFile = Get-Item -LiteralPath $fullPath -ErrorAction Stop
        $originalCreationTime = $sourceFile.CreationTime
        $originalLastWriteTime = $sourceFile.LastWriteTime
        $originalLastAccessTime = $sourceFile.LastAccessTime

        # Show-CommandLine $command.Executable $command.arguments

        # --quiet : la progression mkvmerge utilise un CR sans LF et collerait
        # les Warning: au milieu d'une ligne Progress. Absent de -J (pas de barre).
        $mkvmergeLogPath = [System.IO.Path]::GetTempFileName()
        $remux = Invoke-MkvMergeRemux `
            -Executable $command.Executable `
            -Arguments $command.Arguments `
            -LogPath $mkvmergeLogPath

        $exitCode = $remux.ExitCode

        # Code 1 : mux avec avertissements. Par défaut on conserve la source.
        # -ForceReplaceOnWarning rejoint le chemin code 0 seulement s'il n'y a
        # aucun diagnostic Error: : une erreur native reste non remplaçable,
        # sans transformer ce code 1 en exception (ContinueOnError inchangé).
        if ($exitCode -eq 1) {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in @($remux.Diagnostics)) {
                $items.Add($item)
            }

            $keepSource = -not $ForceReplaceOnWarning -or $remux.ErrorCount -gt 0
            if ($keepSource) {
                if ($remux.WarningCount -eq 0) {
                    $items.Add(
                        (New-RepairDiagnosticItem -Severity Warning -Message "mkvmerge a émis des avertissements (code 1). Le fichier source n'a pas été remplacé.")
                    )
                }
                else {
                    $items.Add(
                        (New-RepairDiagnosticItem -Severity Warning -Message "Le fichier source n'a pas été remplacé.")
                    )
                }

                Write-RepairDiagnostic -SourcePath $sourcePathForDisplay -Diagnostics $items.ToArray()
                return (New-RepairFileResult -Outcome WarningKept)
            }

            if ($remux.WarningCount -eq 0) {
                $items.Add(
                    (New-RepairDiagnosticItem -Severity Warning -Message "mkvmerge a émis des avertissements (code 1). Le remplacement est poursuivi parce que -ForceReplaceOnWarning est actif.")
                )
            }

            if ($items.Count -gt 0) {
                Write-RepairDiagnostic -SourcePath $sourcePathForDisplay -Diagnostics $items.ToArray()
            }
        }
        elseif ($exitCode -ne 0) {
            $exception = [System.InvalidOperationException]::new(
                "mkvmerge a échoué avec le code de sortie $exitCode. Le fichier source n'a pas été remplacé."
            )
            Write-RepairFailedDiagnostic `
                -SourcePath $sourcePathForDisplay `
                -Diagnostics @($remux.Diagnostics) `
                -ExceptionMessage $exception.Message `
                -HideExceptionMessage:$HideExceptionMessage
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'Tetram.Media.Repair.MkvMergeFailed',
                [System.Management.Automation.ErrorCategory]::InvalidResult,
                $sourcePathForDisplay
            )
            return (New-RepairFileResult -Outcome Failed -ErrorRecord $errorRecord)
        }

        if (-not [System.IO.File]::Exists($command.ToolOutputPath)) {
            $exception = [System.InvalidOperationException]::new(
                "mkvmerge s'est terminé sans erreur, mais le fichier de sortie n'existe pas : $($command.OutputPath)"
            )
            Write-RepairFailedDiagnostic `
                -SourcePath $sourcePathForDisplay `
                -Diagnostics @(
                    (New-RepairDiagnosticItem -Severity Error -Message $exception.Message)
                ) `
                -ExceptionMessage $exception.Message `
                -HideExceptionMessage:$HideExceptionMessage
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'Tetram.Media.Repair.OutputMissing',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $sourcePathForDisplay
            )
            return (New-RepairFileResult -Outcome Failed -ErrorRecord $errorRecord)
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

        $replacedFile = Get-Item -LiteralPath $command.ToolInputPath -ErrorAction Stop
        $replacedFile.CreationTime = $originalCreationTime
        $replacedFile.LastWriteTime = $originalLastWriteTime
        $replacedFile.LastAccessTime = $originalLastAccessTime

        $replaced = $true

        $passThruItem = $null
        if ($PassThru) {
            $passThruItem = Get-Item -LiteralPath $command.ToolInputPath -ErrorAction Stop
        }

        return (New-RepairFileResult -Outcome Success -PassThru $passThruItem)
    }
    catch {
        if ($_.Exception -is [System.Management.Automation.ActionPreferenceStopException] -or
            $_.Exception -is [System.Management.Automation.PipelineStoppedException]) {
            throw
        }

        $errorRecord = $_
        $data = Get-RepairExceptionData -Exception $_.Exception
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @($data.Diagnostics)) {
            if ($null -ne $item) {
                $items.Add($item)
            }
        }

        $message = [string] $_.Exception.Message
        $alreadyPresent = $false
        foreach ($item in $items) {
            if ([string] $item.Message -eq $message) {
                $alreadyPresent = $true
                break
            }
        }

        if (-not $alreadyPresent -and -not [string]::IsNullOrWhiteSpace($message)) {
            $severity = 'Error'
            if ([string] $data.Severity -eq 'Warning') {
                $severity = 'Warning'
            }

            $items.Add((New-RepairDiagnosticItem -Severity $severity -Message $message))
        }

        if ($items.Count -gt 0) {
            Write-RepairFailedDiagnostic `
                -SourcePath $sourcePathForDisplay `
                -Diagnostics $items.ToArray() `
                -ExceptionMessage $message `
                -HideExceptionMessage:$HideExceptionMessage
        }

        return (New-RepairFileResult -Outcome Failed -ErrorRecord $errorRecord)
    }
    finally {
        if (
            -not [string]::IsNullOrWhiteSpace($mkvmergeLogPath) -and
            [System.IO.File]::Exists($mkvmergeLogPath)
        ) {
            Remove-Item -LiteralPath $mkvmergeLogPath -Force -ErrorAction SilentlyContinue
        }

        # Temporaire unique à côté de la source : un échec après le mux
        # laisserait un *.mkv qu'un prochain -Folder reprendrait.
        if (-not $replaced -and $null -ne $command) {
            $tempPath = $command.ToolOutputPath
            if (
                -not [string]::IsNullOrWhiteSpace($tempPath) -and
                [System.IO.File]::Exists($tempPath)
            ) {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}


# ---------------------------------------------------------------------------
# API publique
# ---------------------------------------------------------------------------

function New-MkvInterleaveRepairCommand {
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

    $sourcePathForDisplay = $Path
    try {
        $sourcePathForDisplay = [System.IO.Path]::GetFullPath(
            (ConvertFrom-ExtendedLengthPath -Path $Path)
        )
    }
    catch {
        $sourcePathForDisplay = $Path
    }

    try {
        New-MkvInterleaveRepairCommand `
            -Path $Path `
            -OutputPath $OutputPath `
            -MkvMerge $MkvMerge `
            -ExtendedPathThreshold $ExtendedPathThreshold
    }
    catch {
        $data = Get-RepairExceptionData -Exception $_.Exception
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @($data.Diagnostics)) {
            if ($null -ne $item) {
                $items.Add($item)
            }
        }

        $message = [string] $_.Exception.Message
        $alreadyPresent = $false
        foreach ($item in $items) {
            if ([string] $item.Message -eq $message) {
                $alreadyPresent = $true
                break
            }
        }

        if (-not $alreadyPresent -and -not [string]::IsNullOrWhiteSpace($message)) {
            $items.Add((New-RepairDiagnosticItem -Severity Error -Message $message))
        }

        if ($items.Count -gt 0) {
            Write-RepairDiagnostic -SourcePath $sourcePathForDisplay -Diagnostics $items.ToArray()
        }

        throw
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

        [switch] $ForceReplaceOnWarning,

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
        $processTarget = Format-RepairSourceHeader -SourcePath $Path
        if ([string]::IsNullOrWhiteSpace($processTarget)) {
            $processTarget = $Path
        }

        if ($PSCmdlet.ShouldProcess($processTarget, 'Réparer l''interleaving MKV et remplacer le fichier source')) {
            $result = Invoke-MkvRepairFile `
                -Path $Path `
                -MkvMerge $MkvMerge `
                -ExtendedPathThreshold $ExtendedPathThreshold `
                -FileReadyTimeoutSeconds $FileReadyTimeoutSeconds `
                -RetryIntervalMilliseconds $RetryIntervalMilliseconds `
                -PassThru:$PassThru `
                -ForceReplaceOnWarning:$ForceReplaceOnWarning `
                -HideExceptionMessage

            if ($PassThru -and $null -ne $result -and $result.Outcome -eq 'Success' -and $null -ne $result.PassThru) {
                $result.PassThru
            }

            if ($null -ne $result -and $result.Outcome -eq 'Failed' -and $null -ne $result.ErrorRecord) {
                $PSCmdlet.ThrowTerminatingError($result.ErrorRecord)
            }
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
            ForEach-Object {
                # Scan via le chemin outil (\\?\) ; libellé ShouldProcess / RepairFile
                # : chemin logique, identique à l'en-tête des diagnostics.
                [System.IO.Path]::GetFullPath((ConvertFrom-ExtendedLengthPath -Path $_.FullName))
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

            $processTarget = Format-RepairSourceHeader -SourcePath $file
            if ([string]::IsNullOrWhiteSpace($processTarget)) {
                $processTarget = $file
            }

            Write-Progress `
                -Id $progressId `
                -Activity $activity `
                -Status ('{0}/{1}' -f ($i + 1), $count) `
                -CurrentOperation $processTarget `
                -PercentComplete (($i / $count) * 100)

            if ($PSCmdlet.ShouldProcess($processTarget, 'Réparer l''interleaving MKV et remplacer le fichier source')) {
                $result = Invoke-MkvRepairFile `
                    -Path $file `
                    -MkvMerge $MkvMerge `
                    -ExtendedPathThreshold $ExtendedPathThreshold `
                    -FileReadyTimeoutSeconds $FileReadyTimeoutSeconds `
                    -RetryIntervalMilliseconds $RetryIntervalMilliseconds `
                    -PassThru:$PassThru `
                    -ForceReplaceOnWarning:$ForceReplaceOnWarning `
                    -HideExceptionMessage:(-not $ContinueOnError)

                if ($PassThru -and $null -ne $result -and $result.Outcome -eq 'Success' -and $null -ne $result.PassThru) {
                    $result.PassThru
                }

                if ($null -ne $result -and $result.Outcome -eq 'Failed') {
                    if ($ContinueOnError) {
                        continue
                    }

                    if ($null -ne $result.ErrorRecord) {
                        $PSCmdlet.ThrowTerminatingError($result.ErrorRecord)
                    }
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
