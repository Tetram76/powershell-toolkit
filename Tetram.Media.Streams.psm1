Set-StrictMode -Version 3.0

$PrivateRoot = Join-Path $PSScriptRoot 'Tetram.Media.Streams.Private'
. (Join-Path $PrivateRoot 'Naming.ps1')
. (Join-Path $PrivateRoot 'CodecMap.ps1')
. (Join-Path $PrivateRoot 'Descriptors.ps1')
. (Join-Path $PrivateRoot 'Matching.ps1')
. (Join-Path $PrivateRoot 'Invoke.ps1')

function Split-MediaStream {
    <#
.EXTERNALHELP Tetram.Media.Streams-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $LiteralPath,
        [ValidateSet('Video', 'Audio', 'Subtitle', 'Attachment', 'Chapter')]
        [string[]] $StreamType,
        [string[]] $Language,
        [switch] $Force
    )
    return
}

function Merge-MediaStream {
    <#
.EXTERNALHELP Tetram.Media.Streams-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $LiteralPath,
        [string] $Destination,
        [switch] $RemoveSidecars,
        [switch] $Force
    )
    return
}

Export-ModuleMember -Function Split-MediaStream, Merge-MediaStream
