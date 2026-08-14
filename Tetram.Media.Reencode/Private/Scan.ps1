using namespace System
using namespace System.IO

Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# Scan.psm1 — parcours du filesystem et orchestration par fichier/liste
# Sous-module privé de Tetram.Media.Reencode (chargé via NestedModules).
# Pas d'Export-ModuleMember : les fonctions restent dans le scope du module.
# -----------------------------------------------------------------------------

function Invoke-PathScan
{
    param(
        [ValidateScript({ Test-Path $_ }, ErrorMessage = "{0} is not a valid path")]
        [string] $Path = "",
        [switch] $Recurse,
        [switch] $SubPath,
        [hashtable] $State,
        [hashtable] $Config,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )

    $LiteralPath = $Path
    if ($SubPath)
    {
        $LiteralPath = [Management.Automation.WildcardPattern]::Unescape($LiteralPath)
    }

    if (-not [File]::Exists($LiteralPath))
    {
        if (-not $SubPath)
        {
            Write-InfoLog "Scanning '$LiteralPath' $( $Recurse ? 'recursively' : '' )..."
        }
        if ($Recurse)
        {
            Get-SortedFileList (Get-ChildItem -Path $LiteralPath -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ine "Plex Versions" -and $_.Name -ine ".deletedByTMM" }) $Config.Sort |
                    ForEach-Object {
                        $NotReadOnly = ($_.Attributes -band [FileAttributes]::ReadOnly) -ne [FileAttributes]::ReadOnly
                        if ($NotReadOnly -or $Config.ScanReadOnlyDirectory)
                        {
                            Invoke-PathScan -Path ([Management.Automation.WildcardPattern]::Escape($_.FullName)) -Recurse -SubPath -State $State -Config $Config -Cmdlet $Cmdlet
                        }
                    }
        }
    }

    if ([Directory]::Exists($LiteralPath) -and -not $LiteralPath.EndsWith('*'))
    {
        if ((Get-ChildItem -LiteralPath $LiteralPath -Include $Config.InputMasks -Force | Select-Object -First 1 | Measure-Object).Count -eq 0)
        {
            return
        }
        $LiteralPath = [Management.Automation.WildcardPattern]::Escape($LiteralPath) + '\*'
    }

    Get-SortedFileList (Get-ChildItem -Path $LiteralPath -File -Attributes !ReadOnly -Include $Config.InputMasks -Force -ErrorAction SilentlyContinue) $Config.Sort |
            ForEach-Object {
                if (-not ([string]$_.FullName).Contains('-trailer.', [StringComparison]::InvariantCultureIgnoreCase))
                {
                    Invoke-ReencodeFile -Filename $_.FullName -State $State -Config $Config -Cmdlet $Cmdlet
                }
            }
}

function Invoke-PathList
{
    param(
        [string[]] $Paths,
        [hashtable] $State,
        [hashtable] $Config,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )

    foreach ($PathItem in $Paths)
    {
        $DoRecurse = ([string]$PathItem).StartsWith('+')
        $p = ([string]$PathItem).Substring(($DoRecurse ? 1 : 0))
        Invoke-PathScan -Path $p -Recurse:($Config.Recurse -or $DoRecurse) -State $State -Config $Config -Cmdlet $Cmdlet
    }
}

function Invoke-FileList
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string] $ListFile,
        [hashtable] $State,
        [hashtable] $Config,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )

    Write-InfoLog -Color Blue "Using file list in '$ListFile'..."
    $ListContent = Get-Content $ListFile

    $ListContent | ForEach-Object {
        $currentLine = [string]$_
        $DoRecurse = $currentLine.StartsWith('+')
        $p = $currentLine.Substring(($DoRecurse ? 1 : 0))
        Invoke-PathScan -Path $p -Recurse:($Config.Recurse -or $DoRecurse) -State $State -Config $Config -Cmdlet $Cmdlet

        if ($Config.UpdateList)
        {
            if ( $Cmdlet.ShouldProcess($ListFile, "Remove processed entry"))
            {
                $NewListContent = Get-Content $ListFile | Where-Object { [string]$_ -ne $currentLine }
                Set-Content $ListFile -Value $NewListContent
            }
        }
    }
}
