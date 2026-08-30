Set-StrictMode -Version 3.0

Import-Module -Name (Join-Path $PSScriptRoot '..' 'Tetram.Common') -Force

# Dot-source plutôt que NestedModules : les fonctions de Tetram.Common du scope parent restent visibles.
. (Join-Path $PSScriptRoot 'Private' 'Transcript.ps1')

function Get-MediaTranscript {
    <#
.EXTERNALHELP Tetram.Media.Transcript-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('PSPath')]
        [string] $LiteralPath,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $AudioTrack = 1,

        [ValidateSet('large-v2', 'large-v3-turbo', 'large-v3', 'kotoba-v2', 'reazon-k2-v2', 'parakeet-0.6b-ja', 'sensevoice-small')]
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
        [string] $UseLanguage
    )

    # Contrat public : aucune exception vers l'appelant.
    $publishedPaths = [System.Collections.Generic.List[string]]::new()
    try {
        $mediaPath = Resolve-TranscriptMediaFile -LiteralPath $LiteralPath

        foreach ($currentModel in @($Model)) {
            try {
                $result = @{
                    Transcripts = [System.Collections.Generic.List[object]]::new()
                }
                Invoke-TranscriptBackend `
                    -MediaPath $mediaPath `
                    -Model $currentModel `
                    -AudioTrack $AudioTrack `
                    -UseLanguage $UseLanguage `
                    -Cmdlet $PSCmdlet `
                    -Result $result `
                    -WhatIf:$WhatIfPreference
                foreach ($transcript in $result.Transcripts) {
                    Publish-TetramTranscript -Transcript $transcript -MediaPath $mediaPath
                    [void]$publishedPaths.Add((Get-TetramTranscriptDest -Transcript $transcript -MediaPath $mediaPath))
                }
            }
            catch {
                Write-ErrorLog -Text $_.Exception.Message
            }
        }

        foreach ($path in $publishedPaths) {
            Write-InfoLog -Force -Text $path
        }
    }
    catch {
        Write-ErrorLog -Text $_.Exception.Message
        return
    }
}

Export-ModuleMember -Function Get-MediaTranscript
