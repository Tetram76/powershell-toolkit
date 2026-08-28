Set-StrictMode -Version 3.0

function Get-WhisperArguments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] [string] $OutputDir,
        [int] $AudioTrack = 1,
        [string] $UseLanguage
    )

    $whisperArgs = @(
        $Source
        '--output_dir', $OutputDir
        '--output_format', 'json'
        '--check_files'
        '--model', $Model
        '--ff_track', "$AudioTrack"
    )

    if (-not [string]::IsNullOrWhiteSpace($UseLanguage)) {
        $whisperArgs += @('--language', $UseLanguage)
    }

    $whisperArgs += @(
        '--postfix'
        '--print_progress'
        '--task', 'transcribe'
        # Lot sans opérateur : le beep de fin du binaire n'a rien à signaler.
        '--beep_off'
    )

    # kotoba-v2 (CTranslate2 custom) plante en 0xC0000005 avec les défauts Purfview ; ces flags
    # sont ceux qui ont été validés empiriquement. Ne pas les appliquer aux modèles Whisper.
    if ($Model -eq 'kotoba-v2') {
        $whisperArgs += @(
            '--condition_on_previous_text', 'False'
            '-prompt', 'None'
            '--word_timestamps', 'False'
            '--chunk_length', '15'
            '--compute_type', 'float16'
        )
    }

    return $whisperArgs
}

function Resolve-WhisperMediaFile {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $LiteralPath
    )

    # -LiteralPath : * / ? / [ ne sont pas des globs. Purfview les traiterait comme un lot.
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

    # Purfview lit ces extensions comme une liste de médias, pas comme une source unique.
    $ext = $item.Extension
    if ($ext -in @('.lst', '.m3u', '.m3u8', '.txt')) {
        throw "LiteralPath ne doit pas être un fichier-liste : '$LiteralPath'"
    }

    return $item.FullName
}

function Get-WhisperPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $OverridePath
    )

    if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
        if (Test-Path -LiteralPath $OverridePath -PathType Leaf) {
            return $OverridePath
        }
        if (Test-Path -LiteralPath $OverridePath) {
            throw "WhisperPath doit désigner un exécutable, pas un dossier : '$OverridePath'"
        }
        throw "WhisperPath inexistant : '$OverridePath'"
    }

    $default = Join-Path $script:WhisperRoot 'faster-whisper-xxl.exe'
    if (Test-Path -LiteralPath $default -PathType Leaf) {
        return $default
    }

    # -CommandType Application : une fonction/alias de même nom dans la session primerait sinon sur
    # l'exécutable du PATH (vérifié empiriquement), avec une Source vide ou trompeuse.
    $fromPath = Get-Command -Name 'faster-whisper-xxl' -CommandType Application -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    throw "faster-whisper-xxl introuvable : posez la distribution Purfview dans '$script:WhisperRoot', ou fournissez -WhisperPath."
}

function Invoke-Whisper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)] [hashtable] $State
    )

    # Résultat déposé dans $State et non retourné : une valeur de retour forcerait l'appelant à capturer
    # la sortie de la fonction, donc celle du binaire, et étoufferait --print_progress.
    $State['ExitCode'] = $null

    # Avant ShouldProcess : sous -WhatIf, la ligne prévue reste visible.
    Show-CommandLine -Exe $Exe -Arguments $Arguments -NoPathDetectionParameters 'output_format', 'model', 'task', 'language', 'ff_track'

    if (-not $Cmdlet.ShouldProcess($Arguments[0], 'faster-whisper-xxl')) {
        return
    }

    # & + splat, sans redirection : les frontières d'arguments sont conservées et le binaire écrit
    # directement sur la console.
    & $Exe @Arguments
    $State['ExitCode'] = $LASTEXITCODE
}
