using namespace System
using namespace System.IO

Set-StrictMode -Version 3.0

# -----------------------------------------------------------------------------
# NFO.psm1 — récupération des dates depuis les fichiers NFO (Kodi/TMM)
# Sous-module privé de Tetram.Media.Reencode (chargé via NestedModules).
# Pas d'Export-ModuleMember : la fonction reste dans le scope du module.
# -----------------------------------------------------------------------------

function Get-NFOTimestamps
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string] $Filename,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )

    $LastWriteTimeFixes = @{ }
    $NFOFilename = [Path]::ChangeExtension($Filename, '.nfo')

    if (-not [File]::Exists($NFOFilename))
    {
        return $LastWriteTimeFixes
    }

    $FileDirectory = Get-Item -LiteralPath ([Path]::GetDirectoryName($Filename))
    $xml = Get-Content -LiteralPath $NFOFilename -ErrorAction SilentlyContinue
    $NFO = $null

    if ($xml)
    {
        $NFO = [xml](Select-String -InputObject $xml -Pattern '.*?<([^\?^\!.]*?)>.*?</\1>').Matches.Value
    }

    if ($NFO)
    {
        try
        {
            $DatePremiered = $NFO.SelectSingleNode("./episodedetails") ? $NFO.episodedetails.premiered : $NFO.movie.premiered
            if ($DatePremiered)
            {
                $LastWriteTime = [datetime]::ParseExact($DatePremiered, "yyyy-MM-dd", $null)
                $OriginalFile = Get-Item -LiteralPath $Filename
                if ( $Cmdlet.ShouldProcess($Filename, "Set original file times from premiered=$DatePremiered"))
                {
                    $OriginalFile.CreationTime = $LastWriteTime
                    $OriginalFile.LastWriteTime = $LastWriteTime
                }
                if ($FileDirectory.LastWriteTime -gt $LastWriteTime)
                {
                    $LastWriteTimeFixes[$FileDirectory] = $LastWriteTime
                }
            }
        }
        catch
        {
            Write-DebugLog "get content nfo from $NFOFilename failed"
            Write-DebugLog $_
        }
    }

    $NFOFilesCandidates = @(
        [Path]::Combine($FileDirectory, 'tvshow.nfo')
        [Path]::Combine([Directory]::GetParent($FileDirectory), 'tvshow.nfo')
        [Path]::Combine([Directory]::GetParent([Directory]::GetParent($FileDirectory)), 'tvshow.nfo')
    )

    :NFOLoop foreach ($nfoPath in $NFOFilesCandidates)
    {
        if ( [File]::Exists($nfoPath))
        {
            $n = [xml](Get-Content -LiteralPath $nfoPath -ErrorAction SilentlyContinue)
            if ($n)
            {
                try
                {
                    $DatePremiered = $n.tvshow.premiered
                    if ($DatePremiered)
                    {
                        $LastWriteTimeFixes[(Get-Item -LiteralPath ([Path]::GetDirectoryName($nfoPath)))] =
                        [datetime]::ParseExact($DatePremiered, "yyyy-MM-dd", $null)
                    }
                    break NFOLoop
                }
                catch
                {
                    Write-DebugLog "get content nfo from $nfoPath failed"
                    Write-DebugLog $_
                }
            }
        }
    }

    return $LastWriteTimeFixes
}
