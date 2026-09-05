Set-StrictMode -Version 3.0

# $PSScriptRoot de ce fichier (Private/), pas celui du psm1 : le dispatcher retrouve les backends.
$script:TranscriptPrivateRoot = $PSScriptRoot

function Resolve-TranscriptMediaFile {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $LiteralPath
    )

    # -LiteralPath : * / ? / [ ne sont pas des globs.
    $item = $null
    try {
        $item = Get-Item -LiteralPath $LiteralPath -ErrorAction Stop
    }
    catch {
        throw "LiteralPath doit désigner un fichier unique existant : '$LiteralPath'"
    }

    if ($item.PSIsContainer) {
        throw "LiteralPath doit désigner un fichier, pas un dossier : '$LiteralPath'"
    }

    return $item.FullName
}

function Get-TetramTranscriptPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [string] $MediaBase,
        [Parameter(Mandatory)] [string] $Language,
        [Parameter(Mandatory)] [string] $Model,
        [int] $AudioTrack = 1,
        [string] $Vad
    )

    $leaf = if ([string]::IsNullOrWhiteSpace($Vad)) {
        "$MediaBase.track $AudioTrack.$Language.$Model.json"
    }
    else {
        "$MediaBase.track $AudioTrack.$Language.$Model.$Vad.json"
    }
    Join-Path $Directory $leaf
}

function Write-TetramTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Transcript,
        [Parameter(Mandatory)] [string] $Path
    )

    $json = ConvertTo-Json -InputObject $Transcript -Depth 8
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    # Même volume que le sidecar : un Move-Item depuis TEMP serait une copie inter-filesystem.
    $destDir = [IO.Path]::GetDirectoryName($Path)
    if ([string]::IsNullOrWhiteSpace($destDir)) {
        $destDir = (Get-Location).Path
    }
    $temp = Join-Path $destDir ([guid]::NewGuid().ToString() + '.tmp')

    try {
        [IO.File]::WriteAllText($temp, $json, $utf8)
        # -Force : une réexécution doit remplacer le sidecar existant ; sans ça Move-Item échoue si $Path est déjà là.
        Move-Item -LiteralPath $temp -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force -Confirm:$false -WhatIf:$false -ErrorAction SilentlyContinue
        }
    }
}

function Get-TetramTranscriptDest {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Transcript,
        [Parameter(Mandatory)] [string] $MediaPath
    )

    $directory = [IO.Path]::GetDirectoryName($MediaPath)
    if ([string]::IsNullOrWhiteSpace($directory)) {
        $directory = (Get-Location).Path
    }
    $mediaBase = [IO.Path]::GetFileNameWithoutExtension($MediaPath)
    $vad = $null
    $vadProp = $Transcript.PSObject.Properties['vad']
    if ($null -ne $vadProp -and -not [string]::IsNullOrWhiteSpace([string]$vadProp.Value)) {
        $vad = [string]$vadProp.Value
    }
    Get-TetramTranscriptPath -Directory $directory -MediaBase $mediaBase -Language $Transcript.language -Model $Transcript.model -AudioTrack $Transcript.audioTrack -Vad $vad
}

function Publish-TetramTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Transcript,
        [Parameter(Mandatory)] [string] $MediaPath
    )

    $dest = Get-TetramTranscriptDest -Transcript $Transcript -MediaPath $MediaPath
    Write-TetramTranscript -Transcript $Transcript -Path $dest
}

function Get-TranscriptEngineName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Model
    )

    switch ($Model) {
        { $_ -in @('large-v2', 'large-v3', 'large-v3-turbo', 'kotoba-v2') } {
            return 'Whisper'
        }
        { $_ -in @('reazon-k2-v2', 'parakeet-0.6b-ja', 'sensevoice-small') } {
            return 'SherpaOnnx'
        }
        default {
            throw "Aucun moteur de transcription pour le modèle '$Model'."
        }
    }
}

function Invoke-TranscriptBackend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)] $Result,
        [int] $AudioTrack = 1,
        [string] $UseLanguage,
        [switch] $WhatIf
    )

    $engine = Get-TranscriptEngineName -Model $Model
    switch ($engine) {
        'Whisper' {
            . (Join-Path $script:TranscriptPrivateRoot 'Whisper.ps1')
        }
        'SherpaOnnx' {
            . (Join-Path $script:TranscriptPrivateRoot 'SherpaOnnx.ps1')
        }
        default {
            throw "Moteur de transcription non implémenté : $engine"
        }
    }

    Invoke-ProviderTranscript `
        -MediaPath $MediaPath `
        -Model $Model `
        -AudioTrack $AudioTrack `
        -UseLanguage $UseLanguage `
        -Cmdlet $Cmdlet `
        -Result $Result `
        -WhatIf:$WhatIf
}
