Set-StrictMode -Version 3.0

function Get-WhisperArguments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string[]] $Source,
        [Parameter(Mandatory)] [string[]] $Format,
        [Parameter(Mandatory)] [string] $Model,
        [string] $UseLanguage
    )

    # Chaque source est un argument nu (pas de préfixe file_list=).
    $whisperArgs = @($Source)

    $whisperArgs += @(
        '--batch_recursive'
        '--output_dir', 'source'
        '--output_format'
    )
    $whisperArgs += $Format
    $whisperArgs += @(
        '--check_files'
        '--model', $Model
        '--ff_track', '1'
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

    return $whisperArgs
}

function Resolve-WhisperSource {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string[]] $Path,
        [string[]] $LiteralPath
    )

    $sources = @()

    foreach ($entry in @($Path)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }

        if (Test-PowerShellSpecificPath -Path $entry) {
            # WildcardPattern lit [x] comme une classe de caractères (un seul caractère du jeu), pas comme
            # des crochets littéraux : sans cet échappement, un fichier réellement nommé "a[1].mkv" est
            # invisible à Resolve-Path -Path (vérifié empiriquement, contrairement à -LiteralPath).
            $pattern = $entry -replace '(?<!`)([\[\]])', '`$1'

            # Une résolution vide ne se rabat pas sur le littéral : ce serait inventer une interprétation
            # que l'appelant n'a pas demandée, et faire signaler par whisper un fichier jamais désigné.
            foreach ($resolved in @(Resolve-Path -Path $pattern -ErrorAction SilentlyContinue)) {
                $sources += $resolved.ProviderPath
            }
            continue
        }

        # * / ? sont déjà le glob de whisper : on ne résout pas et on n'absolutise pas.
        $sources += $entry
    }

    foreach ($entry in @($LiteralPath)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $sources += $entry
    }

    return $sources
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

    $fromPath = Get-Command -Name 'faster-whisper-xxl' -ErrorAction SilentlyContinue
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
    Show-CommandLine -Exe $Exe -Arguments $Arguments -NoPathDetectionParameters 'output_dir', 'output_format', 'model', 'task', 'language', 'ff_track'

    if (-not $Cmdlet.ShouldProcess($Arguments[0], 'faster-whisper-xxl')) {
        return
    }

    # & + splat, sans redirection : les frontières d'arguments sont conservées et le binaire écrit
    # directement sur la console.
    & $Exe @Arguments
    $State['ExitCode'] = $LASTEXITCODE
}
