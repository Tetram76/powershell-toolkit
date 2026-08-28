Set-StrictMode -Version 3.0

function Get-TetramTranscriptPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [string] $MediaBase,
        [Parameter(Mandatory)] [string] $Language,
        [Parameter(Mandatory)] [string] $Model,
        [int] $AudioTrack = 1
    )

    Join-Path $Directory "$MediaBase.track $AudioTrack.$Language.$Model.json"
}

function Get-WhisperMediaBaseName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $NativeJsonPath,
        [Parameter(Mandatory)] [string] $Language
    )

    $name = [IO.Path]::GetFileNameWithoutExtension($NativeJsonPath)
    $suffix = ".$Language"
    if ($name.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)) {
        return $name.Substring(0, $name.Length - $suffix.Length)
    }

    return $name
}

function Test-WhisperNativeJsonName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $FileName,
        [string] $Stem
    )

    # Le sidecar Tetram (`.track N.`) ne doit jamais être pris pour un artefact natif.
    if ($FileName -match '\.track \d+\.') {
        return $false
    }

    if (-not $FileName.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($Stem)) {
        return [bool]($FileName -match '^.+\.[A-Za-z]{2,3}\.json$')
    }

    $escaped = [regex]::Escape($Stem)
    if ($FileName -match ('^' + $escaped + '\.[A-Za-z]{2,3}\.json$')) {
        return $true
    }

    return $FileName.Equals("$Stem.json", [StringComparison]::OrdinalIgnoreCase)
}

function Get-WhisperNativeJsonCandidate {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string[]] $Source
    )

    $results = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in @($Source)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }

        $ext = [IO.Path]::GetExtension($entry)
        if ($ext -in @('.lst', '.m3u', '.m3u8', '.txt') -and (Test-Path -LiteralPath $entry -PathType Leaf)) {
            foreach ($line in @(Get-Content -LiteralPath $entry)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                foreach ($found in @(Get-WhisperNativeJsonCandidate -Source @($line.Trim()))) {
                    if (-not $results.Contains($found)) {
                        $results.Add($found)
                    }
                }
            }
            continue
        }

        $isGlob = -not $entry.StartsWith('\\?\') -and ($entry.Contains('*') -or $entry.Contains('?'))
        if ($isGlob) {
            $dir = [IO.Path]::GetDirectoryName($entry)
            if ([string]::IsNullOrWhiteSpace($dir)) {
                $dir = (Get-Location).Path
            }
            Add-WhisperNativeJsonFromDirectory -Directory $dir -Recurse $true -Results $results
            continue
        }

        if (Test-Path -LiteralPath $entry -PathType Container -ErrorAction SilentlyContinue) {
            Add-WhisperNativeJsonFromDirectory -Directory $entry -Recurse $true -Results $results
            continue
        }

        $dir = [IO.Path]::GetDirectoryName($entry)
        if ([string]::IsNullOrWhiteSpace($dir)) {
            $dir = (Get-Location).Path
        }
        $stem = [IO.Path]::GetFileNameWithoutExtension($entry)
        Add-WhisperNativeJsonFromDirectory -Directory $dir -Recurse $false -Stem $stem -Results $results
    }

    return @($results)
}

function Add-WhisperNativeJsonFromDirectory {
    param(
        [string] $Directory,
        [bool] $Recurse,
        [string] $Stem,
        [AllowEmptyCollection()]
        [Parameter(Mandatory)] [System.Collections.Generic.List[string]] $Results
    )

    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return
    }

    $childArgs = @{
        LiteralPath = $Directory
        Filter      = '*.json'
        File        = $true
        ErrorAction = 'SilentlyContinue'
    }
    if ($Recurse) {
        $childArgs['Recurse'] = $true
    }

    foreach ($file in @(Get-ChildItem @childArgs)) {
        $ok = if ([string]::IsNullOrWhiteSpace($Stem)) {
            Test-WhisperNativeJsonName -FileName $file.Name
        }
        else {
            Test-WhisperNativeJsonName -FileName $file.Name -Stem $Stem
        }
        if ($ok -and -not $Results.Contains($file.FullName)) {
            $Results.Add($file.FullName)
        }
    }
}

function Get-WhisperJsonSnapshot {
    [CmdletBinding()]
    param(
        [string[]] $Source
    )

    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in @(Get-WhisperNativeJsonCandidate -Source $Source)) {
        [void]$set.Add($path)
    }
    # Virgule unaire : un HashSet vide s'énumère sinon en rien, et un HashSet à un
    # élément redeviendrait une string — .Contains n'aurait plus la sémantique d'ensemble.
    return , $set
}

function Get-WhisperNewJsonFile {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string[]] $Source,
        [AllowEmptyCollection()]
        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]] $Before
    )

    foreach ($path in @(Get-WhisperNativeJsonCandidate -Source $Source)) {
        if (-not $Before.Contains($path)) {
            $path
        }
    }
}

function ConvertFrom-WhisperTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)] [string] $Model,
        [string] $UseLanguage,
        [int] $AudioTrack = 1
    )

    $whisper = if ($InputObject -is [string]) {
        ConvertFrom-Json -InputObject $InputObject -ErrorAction Stop
    }
    else {
        $InputObject
    }

    if ($null -eq $whisper) {
        throw "Le JSON natif Whisper n'a pas de collection segments exploitable."
    }

    $segmentsProp = $whisper.PSObject.Properties['segments']
    if ($null -eq $segmentsProp -or $null -eq $segmentsProp.Value) {
        throw "Le JSON natif Whisper n'a pas de collection segments exploitable."
    }

    $language = $null
    $languageSource = $null
    if (-not [string]::IsNullOrWhiteSpace($UseLanguage)) {
        $language = $UseLanguage
        $languageSource = 'forced'
    }
    else {
        $langProp = $whisper.PSObject.Properties['language']
        if ($null -eq $langProp -or [string]::IsNullOrWhiteSpace([string]$langProp.Value)) {
            throw "Le JSON natif Whisper n'a pas de langue exploitable."
        }
        $language = [string]$langProp.Value
        $languageSource = 'detected'
    }

    $segments = [System.Collections.Generic.List[object]]::new()
    foreach ($segment in @($segmentsProp.Value)) {
        if ($null -eq $segment) {
            throw "Le JSON natif Whisper n'a pas de collection segments exploitable."
        }

        $startProp = $segment.PSObject.Properties['start']
        $endProp = $segment.PSObject.Properties['end']
        $textProp = $segment.PSObject.Properties['text']
        if ($null -eq $startProp -or $null -eq $endProp -or $null -eq $textProp) {
            throw "Le JSON natif Whisper n'a pas de collection segments exploitable."
        }

        $item = [ordered]@{
            start = $startProp.Value
            end   = $endProp.Value
            text  = $textProp.Value
        }

        $wordsProp = $segment.PSObject.Properties['words']
        if ($null -ne $wordsProp -and $null -ne $wordsProp.Value) {
            $words = [System.Collections.Generic.List[object]]::new()
            foreach ($word in @($wordsProp.Value)) {
                if ($null -eq $word) { continue }

                $w = [ordered]@{}
                $textWord = $word.PSObject.Properties['text']
                $nativeWord = $word.PSObject.Properties['word']
                if ($null -ne $textWord -and $null -ne $textWord.Value) {
                    $w['text'] = $textWord.Value
                }
                elseif ($null -ne $nativeWord -and $null -ne $nativeWord.Value) {
                    $w['text'] = $nativeWord.Value
                }

                foreach ($name in @('start', 'end', 'probability')) {
                    $p = $word.PSObject.Properties[$name]
                    if ($null -ne $p -and $null -ne $p.Value) {
                        $w[$name] = $p.Value
                    }
                }

                if ($w.Count -gt 0) {
                    $words.Add([pscustomobject]$w)
                }
            }

            if ($words.Count -gt 0) {
                $item['words'] = [object[]]$words.ToArray()
            }
        }

        $diagnostics = [ordered]@{}
        foreach ($name in @('temperature', 'avg_logprob', 'compression_ratio', 'no_speech_prob')) {
            $p = $segment.PSObject.Properties[$name]
            if ($null -ne $p -and $null -ne $p.Value) {
                $diagnostics[$name] = $p.Value
            }
        }

        $tokensProp = $segment.PSObject.Properties['tokens']
        if ($null -ne $tokensProp -and $null -ne $tokensProp.Value) {
            $tokens = @($tokensProp.Value)
            if ($tokens.Count -gt 0) {
                $diagnostics['tokens'] = $tokens
            }
        }

        if ($diagnostics.Count -gt 0) {
            $item['diagnostics'] = [pscustomobject]$diagnostics
        }

        $segments.Add([pscustomobject]$item)
    }

    return [pscustomobject][ordered]@{
        engine         = 'faster-whisper'
        model          = $Model
        language       = $language
        languageSource = $languageSource
        audioTrack     = $AudioTrack
        segments       = [object[]]$segments.ToArray()
    }
}

function Write-TetramTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Transcript,
        [Parameter(Mandatory)] [string] $Path
    )

    $json = ConvertTo-Json -InputObject $Transcript -Depth 8
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $directory = [IO.Path]::GetDirectoryName($Path)
    $temp = Join-Path $directory ([guid]::NewGuid().ToString() + '.tmp')

    try {
        [IO.File]::WriteAllText($temp, $json, $utf8)
        Move-Item -LiteralPath $temp -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force -Confirm:$false -WhatIf:$false -ErrorAction SilentlyContinue
        }
    }
}

function Convert-WhisperNativeToTetram {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $NativeJsonPath,
        [Parameter(Mandatory)] [string] $Model,
        [string] $UseLanguage,
        [int] $AudioTrack = 1
    )

    $raw = Get-Content -LiteralPath $NativeJsonPath -Raw -Encoding UTF8
    $transcript = ConvertFrom-WhisperTranscript -InputObject $raw -Model $Model -UseLanguage $UseLanguage -AudioTrack $AudioTrack
    $directory = [IO.Path]::GetDirectoryName($NativeJsonPath)
    $mediaBase = Get-WhisperMediaBaseName -NativeJsonPath $NativeJsonPath -Language $transcript.language
    $dest = Get-TetramTranscriptPath -Directory $directory -MediaBase $mediaBase -Language $transcript.language -Model $Model -AudioTrack $AudioTrack
    Write-TetramTranscript -Transcript $transcript -Path $dest
}

function Remove-WhisperNativeJson {
    [CmdletBinding()]
    param(
        [string[]] $Path
    )

    foreach ($item in @($Path)) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        if (Test-Path -LiteralPath $item -PathType Leaf) {
            Remove-Item -LiteralPath $item -Force -Confirm:$false -WhatIf:$false -ErrorAction SilentlyContinue
        }
    }
}
