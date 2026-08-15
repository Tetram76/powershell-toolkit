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
    )

    return $whisperArgs
}
