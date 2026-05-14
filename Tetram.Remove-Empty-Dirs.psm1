# Remove-Empty-Dirs.psm1 — PowerShell 7+
Set-StrictMode -Version 3.0

$script:ErrorLog = 'remove-empty-dirs-error.log'

function Test-DirIsEmpty
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Dir
    )
    try
    {
        $item = Get-Item -LiteralPath $Dir -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
        {
            return $false
        }
        $hasAny = Get-ChildItem -LiteralPath $Dir -Force -ErrorAction Stop | Select-Object -First 1
        return -not $hasAny
    }
    catch
    {
        Write-ErrorLog "Failed to inspect '$Dir' — $( $_.Exception.Message )"
        return $false
    }
}

function Remove-Empty-Dirs-Pass
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Root
    )

    $foundEmpty = $false
    Write-InfoLog "Scanning '$Root'..."

    $dirs = Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending

    foreach ($d in $dirs)
    {
        if (Test-DirIsEmpty -Dir $d.FullName)
        {
            $foundEmpty = $true
            if ( $PSCmdlet.ShouldProcess($d.FullName, 'Remove empty directory'))
            {
                try
                {
                    Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop
                    Write-InfoLog -Color Magenta "Deleted empty directory: $( $d.FullName )"
                }
                catch
                {
                    Write-ErrorLog "Unable to delete '$( $d.FullName )': $( $_.Exception.Message )"
                }
            }
            else
            {
                Write-InfoLog -Color Magenta "[WhatIf] Would remove: $( $d.FullName )"
            }
        }
        else
        {
            Write-DebugLog "Not empty (or skipped): $( $d.FullName )"
        }
    }
    return $foundEmpty
}

function Remove-EmptyDirs
{
    <#
.SYNOPSIS
    Supprime les répertoires vides (PS7).
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    param(
        [Parameter(Position = 0)]
        [string] $Path = ".",
        [switch] $DeepScan
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container))
    {
        Write-ErrorLog "The specified path does not exist: '$Path'"
        return
    }

    $pass = 1
    $changed = Remove-Empty-Dirs-Pass -Root $Path

    if ($DeepScan)
    {
        while ($changed)
        {
            $pass++
            Write-InfoLog -Color Yellow "DeepScan: found empties on pass #$( $pass - 1 ). Starting pass #$pass."
            $changed = Remove-Empty-Dirs-Pass -Root $Path
        }
        Write-InfoLog "Completed in $pass pass(es)."
    }
}
Export-ModuleMember -Function Remove-EmptyDirs
