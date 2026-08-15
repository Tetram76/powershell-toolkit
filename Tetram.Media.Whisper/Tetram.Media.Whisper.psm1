Set-StrictMode -Version 3.0

Import-Module -Name (Join-Path $PSScriptRoot '..' 'Tetram.Common') -Force

# Résolu ici et pas dans Private/Whisper.ps1 : $PSScriptRoot y désignerait le sous-dossier Private.
$script:WhisperRoot = Join-Path $PSScriptRoot 'Purfview-Whisper-Faster'

# Dot-source plutôt que NestedModules : les fonctions de Tetram.Common du scope parent restent visibles.
. (Join-Path $PSScriptRoot 'Private' 'Whisper.ps1')

function Get-MediaTranscript {
    [CmdletBinding()]
    param()
}

Export-ModuleMember -Function Get-MediaTranscript
