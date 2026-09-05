Set-StrictMode -Version 3.0

# Dot-source depuis Private/ : $PSScriptRoot n'est pas la racine du module.
$script:SherpaOnnxRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'SherpaOnnx'
$script:SherpaOnnxFfmpegModule = Join-Path (Split-Path -Parent $PSScriptRoot) '..' 'Tetram.Media.FFmpeg'

# Dépendance interne au backend Sherpa : le chemin générique de transcription n'importe pas FFmpeg.
Import-Module -Name $script:SherpaOnnxFfmpegModule -Force

$sherpaPrivate = Join-Path $PSScriptRoot 'SherpaOnnx'
. (Join-Path $sherpaPrivate 'Model.ps1')
. (Join-Path $sherpaPrivate 'Native.ps1')
. (Join-Path $sherpaPrivate 'Audio.ps1')
. (Join-Path $sherpaPrivate 'Vad.ps1')
. (Join-Path $sherpaPrivate 'Asr.ps1')
. (Join-Path $sherpaPrivate 'Normalize.ps1')
. (Join-Path $sherpaPrivate 'Pipeline.ps1')

function Invoke-ProviderTranscript {
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

    Invoke-SherpaOnnxTranscript -MediaPath $MediaPath -Model $Model -Cmdlet $Cmdlet -AudioTrack $AudioTrack -UseLanguage $UseLanguage -Result $Result -WhatIf:$WhatIf
}
