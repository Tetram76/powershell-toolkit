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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('PSPath')]
        [string] $LiteralPath,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $AudioTrack = 1,

        [ValidateSet('large-v2', 'large-v3-turbo', 'large-v3', 'kotoba-v2')]
        [string[]] $Model = 'large-v2',

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
        $mediaPath = Resolve-WhisperMediaFile -LiteralPath $LiteralPath
        $exe = Get-WhisperPath -OverridePath $WhisperPath

        foreach ($currentModel in @($Model)) {
            # WhatIf : montrer l'intention sans créer l'espace temporaire d'exécution.
            if ($WhatIfPreference) {
                $outputDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            }
            else {
                $outputDir = New-WhisperTempDirectory
            }

            $whisperArgs = Get-WhisperArguments -Source $mediaPath -Model $currentModel -UseLanguage $UseLanguage -OutputDir $outputDir -AudioTrack $AudioTrack
            Write-DebugLog -Text ($whisperArgs -join ' ')

            try {
                $state = @{ ExitCode = $null }
                Invoke-Whisper -Exe $exe -Arguments $whisperArgs -Cmdlet $PSCmdlet -State $state

                # ExitCode nul = ShouldProcess a refusé (WhatIf), ce n'est pas un échec. Un code non nul en est un ;
                # l'inverse n'est pas vrai, le binaire sortant en 0 même sans média trouvé.
                # Purfview r245.4 : large-v3 et large-v3-turbo écrivent le JSON natif, puis meurent
                # en STATUS_STACK_BUFFER_OVERRUN (0xC0000409 / -1073740791) au post-traitement.
                $recoverablePurfviewCrash = $state['ExitCode'] -eq -1073740791 -and $currentModel -in @('large-v3', 'large-v3-turbo')
                if ($null -ne $state['ExitCode'] -and $state['ExitCode'] -ne 0 -and -not $recoverablePurfviewCrash) {
                    Write-ErrorLog -Text "faster-whisper-xxl a échoué (code $( $state['ExitCode'] )) sur '$mediaPath' (modèle $currentModel)."
                    continue
                }

                if ($null -eq $state['ExitCode']) {
                    continue
                }

                $nativeJsons = @(Get-WhisperNativeJsonFromOutputDir -OutputDir $outputDir)
                if ($nativeJsons.Count -eq 0) {
                    Write-ErrorLog -Text "Aucun JSON natif produit par faster-whisper-xxl pour '$mediaPath' (modèle $currentModel)."
                    continue
                }
                if ($nativeJsons.Count -gt 1) {
                    Write-ErrorLog -Text "Résultat natif ambigu pour '$mediaPath' (modèle $currentModel) : $($nativeJsons.Count) JSON dans le dossier de sortie."
                    continue
                }

                Convert-WhisperNativeToTetram -NativeJsonPath $nativeJsons[0] -MediaPath $mediaPath -Model $currentModel -UseLanguage $UseLanguage -AudioTrack $AudioTrack

                if ($recoverablePurfviewCrash) {
                    Write-InfoLog -Force -Text "faster-whisper-xxl s'est terminé avec le code -1073740791 (0xC0000409) sur '$mediaPath' (modèle $currentModel) ; JSON natif exploitable et normalisation Tetram terminée malgré le crash."
                }
            }
            catch {
                Write-ErrorLog -Text $_.Exception.Message
            }
            finally {
                Remove-WhisperTempDirectory -Path $outputDir
            }
        }
    }
    catch {
        Write-ErrorLog -Text $_.Exception.Message
        return
    }
}

Export-ModuleMember -Function Get-MediaTranscript
