Set-StrictMode -Version 3.0

$script:SherpaOnnxOfflineBatchSize = 32

function Get-SherpaOnnxOfflineArguments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string[]] $AsrArguments,
        [Parameter(Mandatory)] [string[]] $ChunkPaths
    )

    return @($AsrArguments) + @($ChunkPaths)
}

function Get-SherpaOnnxJsonArray {
    param(
        $InputObject,
        [Parameter(Mandatory)] [string] $Name
    )

    $prop = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) {
        return @()
    }
    return @($prop.Value)
}

function Get-SherpaOnnxJsonText {
    param(
        $InputObject,
        [Parameter(Mandatory)] [string] $Name
    )

    $prop = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) {
        return $null
    }
    $text = [string]$prop.Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }
    return $text
}

function ConvertFrom-SherpaOnnxOfflineResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject
    )

    $text = Get-SherpaOnnxJsonText -InputObject $InputObject -Name 'text'
    $tokens = @(Get-SherpaOnnxJsonArray -InputObject $InputObject -Name 'tokens' | ForEach-Object { "$_" })
    $timestamps = @(Get-SherpaOnnxJsonArray -InputObject $InputObject -Name 'timestamps' | ForEach-Object { [double]$_ })
    $durations = @(Get-SherpaOnnxJsonArray -InputObject $InputObject -Name 'durations' | ForEach-Object { [double]$_ })
    $logProbs = @(Get-SherpaOnnxJsonArray -InputObject $InputObject -Name 'ys_log_probs' | ForEach-Object { [double]$_ })

    if ($timestamps.Count -gt 0 -and $timestamps.Count -ne $tokens.Count) {
        throw "JSON Sherpa-ONNX incohérent : tokens.Count=$($tokens.Count) timestamps.Count=$($timestamps.Count)."
    }
    if ($durations.Count -gt 0 -and $durations.Count -ne $tokens.Count) {
        throw "JSON Sherpa-ONNX incohérent : tokens.Count=$($tokens.Count) durations.Count=$($durations.Count)."
    }
    if ($logProbs.Count -gt 0 -and $logProbs.Count -ne $tokens.Count) {
        throw "JSON Sherpa-ONNX incohérent : tokens.Count=$($tokens.Count) ys_log_probs.Count=$($logProbs.Count)."
    }

    return [pscustomobject]@{
        text         = $text
        tokens       = $tokens
        timestamps   = $timestamps
        durations    = $durations
        ys_log_probs = $logProbs
        lang         = (Get-SherpaOnnxJsonText -InputObject $InputObject -Name 'lang')
        emotion      = (Get-SherpaOnnxJsonText -InputObject $InputObject -Name 'emotion')
        event        = (Get-SherpaOnnxJsonText -InputObject $InputObject -Name 'event')
    }
}

function ConvertFrom-SherpaOnnxOfflineStdout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Stdout,
        [Parameter(Mandatory)] [int] $ExpectedCount
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($Stdout -split '\r?\n')) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0) {
            continue
        }
        # Upstream n'écrit que AsJsonString() sur stdout ; une autre ligne est une fuite native, pas un log.
        if (-not $trimmed.StartsWith('{')) {
            throw "Sortie sherpa-onnx-offline inattendue : '$trimmed'."
        }

        try {
            $json = ConvertFrom-Json -InputObject $trimmed -ErrorAction Stop
        }
        catch {
            throw "Sortie sherpa-onnx-offline non JSON : '$trimmed'."
        }
        $results.Add((ConvertFrom-SherpaOnnxOfflineResult -InputObject $json))
    }

    if ($results.Count -ne $ExpectedCount) {
        throw "sherpa-onnx-offline a renvoyé $($results.Count) résultat(s) JSON pour $ExpectedCount chunk(s)."
    }

    return @($results.ToArray())
}

function Split-SherpaOnnxChunkBatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $ChunkPaths,
        [int] $BatchSize = $script:SherpaOnnxOfflineBatchSize
    )

    if ($BatchSize -lt 1) {
        throw "BatchSize Sherpa-ONNX invalide : $BatchSize."
    }

    $batches = [System.Collections.Generic.List[object]]::new()
    $buffer = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @($ChunkPaths)) {
        $buffer.Add($path)
        if ($buffer.Count -ge $BatchSize) {
            $batches.Add([string[]]@($buffer.ToArray()))
            $buffer.Clear()
        }
    }
    if ($buffer.Count -gt 0) {
        $batches.Add([string[]]@($buffer.ToArray()))
    }

    # Virgule unaire : un seul batch ne doit pas se dérouler en N chemins dans l'appelant.
    return , $batches
}
