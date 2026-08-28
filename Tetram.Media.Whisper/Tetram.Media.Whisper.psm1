Set-StrictMode -Version 3.0

Import-Module -Name (Join-Path $PSScriptRoot '..' 'Tetram.Common') -Force

# Résolu ici et pas dans Private/Whisper.ps1 : $PSScriptRoot y désignerait le sous-dossier Private.
$script:WhisperRoot = Join-Path $PSScriptRoot 'Purfview-Whisper-Faster'

# Dot-source plutôt que NestedModules : les fonctions de Tetram.Common du scope parent restent visibles.
. (Join-Path $PSScriptRoot 'Private' 'Whisper.ps1')
. (Join-Path $PSScriptRoot 'Private' 'Transcript.ps1')

function Get-MediaTranscript {
    <#
.EXTERNALHELP Tetram.Media.Whisper-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Path')]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory, Position = 0)]
        [Parameter(ParameterSetName = 'Mixed', Mandatory)]
        [SupportsWildcards()]
        [string[]] $Path,

        [Parameter(ParameterSetName = 'LiteralPath', Mandatory)]
        [Parameter(ParameterSetName = 'Mixed', Mandatory)]
        [Alias('PSPath')]
        [string[]] $LiteralPath,

        [ValidateSet('large-v2', 'large-v3-turbo', 'large-v3', 'kotoba-v2')]
        [string] $Model = 'large-v2',

        [ValidateSet(
                'af', 'am', 'ar', 'as', 'az', 'ba', 'be', 'bg', 'bn', 'bo', 'br', 'bs', 'ca', 'cs', 'cy', 'da',
                'de', 'el', 'en', 'es', 'et', 'eu', 'fa', 'fi', 'fo', 'fr', 'gl', 'gu', 'ha', 'haw', 'he', 'hi',
                'hr', 'ht', 'hu', 'hy', 'id', 'is', 'it', 'ja', 'jw', 'ka', 'kk', 'km', 'kn', 'ko', 'la', 'lb',
                'ln', 'lo', 'lt', 'lv', 'mg', 'mi', 'mk', 'ml', 'mn', 'mr', 'ms', 'mt', 'my', 'ne', 'nl', 'nn',
                'no', 'oc', 'pa', 'pl', 'ps', 'pt', 'ro', 'ru', 'sa', 'sd', 'si', 'sk', 'sl', 'sn', 'so', 'sq',
                'sr', 'su', 'sv', 'sw', 'ta', 'te', 'tg', 'th', 'tk', 'tl', 'tr', 'tt', 'uk', 'ur', 'uz', 'vi',
                'yi', 'yo', 'yue', 'zh'
        )]
        [string] $UseLanguage,

        [string] $WhisperPath
    )

    # Contrat public : aucune exception vers l'appelant.
    try {
        $exe = Get-WhisperPath -OverridePath $WhisperPath

        $sources = @(Resolve-WhisperSource -Path $Path -LiteralPath $LiteralPath)
        if ($sources.Count -eq 0) {
            # Atteignable seulement si toutes les entrées étaient des motifs résolus à vide : le binding
            # garantit au moins une source. Évite d'invoquer le binaire sans source.
            Write-InfoLog -Text 'Aucune source à transcrire.' -Force
            return
        }

        $whisperArgs = Get-WhisperArguments -Source $sources -Model $Model -UseLanguage $UseLanguage
        Write-DebugLog -Text ($whisperArgs -join ' ')

        $snapshot = Get-WhisperJsonSnapshot -Source $sources
        try {
            $state = @{ ExitCode = $null }
            Invoke-Whisper -Exe $exe -Arguments $whisperArgs -Cmdlet $PSCmdlet -State $state

            # ExitCode nul = ShouldProcess a refusé (WhatIf), ce n'est pas un échec. Un code non nul en est un ;
            # l'inverse n'est pas vrai, le binaire sortant en 0 même sans média trouvé.
            if ($null -ne $state['ExitCode'] -and $state['ExitCode'] -ne 0) {
                Write-ErrorLog -Text "faster-whisper-xxl a échoué (code $( $state['ExitCode'] )) sur '$( $sources[0] )'."
                return
            }

            if ($null -eq $state['ExitCode']) {
                return
            }

            $nativeJsons = @(Get-WhisperNewJsonFile -Source $sources -Before $snapshot)
            if ($nativeJsons.Count -eq 0) {
                Write-ErrorLog -Text "Aucun JSON natif produit par faster-whisper-xxl pour '$( $sources[0] )'."
                return
            }

            foreach ($native in $nativeJsons) {
                try {
                    Convert-WhisperNativeToTetram -NativeJsonPath $native -Model $Model -UseLanguage $UseLanguage
                }
                catch {
                    Write-ErrorLog -Text $_.Exception.Message
                }
            }
        }
        finally {
            # Snapshot : seuls les JSON apparus pendant cet appel sont des artefacts, y compris si la normalisation a échoué.
            Remove-WhisperNativeJson -Path @(Get-WhisperNewJsonFile -Source $sources -Before $snapshot)
        }
    }
    catch {
        Write-ErrorLog -Text $_.Exception.Message
        return
    }
}

Export-ModuleMember -Function Get-MediaTranscript
