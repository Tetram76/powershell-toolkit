Set-StrictMode -Version 3.0

function Get-SherpaOnnxNativeExecutable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('sherpa-onnx-vad', 'sherpa-onnx-offline')]
        [string] $Name,
        [string] $OverridePath
    )

    if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
        if (Test-Path -LiteralPath $OverridePath -PathType Leaf) {
            return $OverridePath
        }
        if (Test-Path -LiteralPath $OverridePath) {
            throw "Le chemin doit désigner un exécutable, pas un dossier : '$OverridePath'"
        }
        throw "Exécutable Sherpa-ONNX inexistant : '$OverridePath'"
    }

    $default = Join-Path $script:SherpaOnnxRoot "$Name.exe"
    if (Test-Path -LiteralPath $default -PathType Leaf) {
        return $default
    }

    # -CommandType Application : une fonction/alias de même nom primerait sinon sur l'exécutable du PATH.
    $fromPath = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    throw "$Name introuvable : posez la distribution dans '$script:SherpaOnnxRoot' (dossier SherpaOnnx du module)."
}

function Invoke-SherpaOnnx {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [hashtable] $State
    )

    $State['ExitCode'] = $null
    $State['Stdout'] = $null
    $State['Stderr'] = $null

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    foreach ($argument in $Arguments) {
        [void]$psi.ArgumentList.Add($argument)
    }

    # Le binaire VAD écrit le japonais en UTF-8 ; & $Exe décode selon [Console]::OutputEncoding (souvent OEM).
    $process = $null
    $savedOutputEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $process = [System.Diagnostics.Process]::Start($psi)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        [void][System.Threading.Tasks.Task]::WaitAll(@($stdoutTask, $stderrTask))
        $process.WaitForExit()
        $State['Stdout'] = $stdoutTask.GetAwaiter().GetResult()
        $State['Stderr'] = $stderrTask.GetAwaiter().GetResult()
        $State['ExitCode'] = $process.ExitCode
    }
    finally {
        [Console]::OutputEncoding = $savedOutputEncoding
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}
