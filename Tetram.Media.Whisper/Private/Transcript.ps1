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

function New-WhisperTempDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    # Stop : un échec New-Item est non terminant par défaut ; renvoyer le GUID sans dossier
    # ferait passer un --output_dir inexistant à whisper.
    $created = New-Item -ItemType Directory -Path $dir -Force -Confirm:$false -WhatIf:$false -ErrorAction Stop
    return $created.FullName
}

function Remove-WhisperTempDirectory {
    [CmdletBinding()]
    param(
        [string] $Path
    )

    # GUID interne TEMP : pas un ShouldProcess utilisateur.
    if (-not $Path) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Remove-Item -LiteralPath $Path -Recurse -Force -Confirm:$false -WhatIf:$false -ErrorAction SilentlyContinue
}

function Get-WhisperNativeJsonFromOutputDir {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $OutputDir
    )

    if ([string]::IsNullOrWhiteSpace($OutputDir) -or -not (Test-Path -LiteralPath $OutputDir -PathType Container)) {
        return @()
    }

    $results = [System.Collections.Generic.List[string]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $OutputDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        if ((Test-WhisperNativeJsonName -FileName $file.Name) -and -not $results.Contains($file.FullName)) {
            $results.Add($file.FullName)
        }
    }
    return @($results)
}

function Add-WhisperTranscriptDirectoryMatch {
    param(
        [string] $FilePath,
        [string] $MediaBase,
        [System.Collections.Generic.List[string]] $Results
    )

    if ([string]::IsNullOrWhiteSpace($FilePath)) { return }
    if ([IO.Path]::GetExtension($FilePath).Equals('.json', [StringComparison]::OrdinalIgnoreCase)) { return }
    $stem = [IO.Path]::GetFileNameWithoutExtension($FilePath)
    if (-not $stem.Equals($MediaBase, [StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $dir = [IO.Path]::GetDirectoryName($FilePath)
    if ([string]::IsNullOrWhiteSpace($dir)) {
        $dir = (Get-Location).Path
    }
    if (-not $Results.Contains($dir)) {
        $Results.Add($dir)
    }
}

function Resolve-WhisperTranscriptDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $MediaBase,
        [string[]] $Source
    )

    $results = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in @($Source)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }

        $ext = [IO.Path]::GetExtension($entry)
        if ($ext -in @('.lst', '.m3u', '.m3u8', '.txt') -and (Test-Path -LiteralPath $entry -PathType Leaf)) {
            foreach ($line in @(Get-Content -LiteralPath $entry)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $found = Resolve-WhisperTranscriptDirectory -MediaBase $MediaBase -Source @($line.Trim())
                if (-not [string]::IsNullOrWhiteSpace($found) -and -not $results.Contains($found)) {
                    $results.Add($found)
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
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                continue
            }
            $filter = [IO.Path]::GetFileName($entry)
            foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter $filter -File -Recurse -ErrorAction SilentlyContinue)) {
                Add-WhisperTranscriptDirectoryMatch -FilePath $file.FullName -MediaBase $MediaBase -Results $results
            }
            continue
        }

        if (Test-Path -LiteralPath $entry -PathType Container -ErrorAction SilentlyContinue) {
            foreach ($file in @(Get-ChildItem -LiteralPath $entry -File -Recurse -ErrorAction SilentlyContinue)) {
                Add-WhisperTranscriptDirectoryMatch -FilePath $file.FullName -MediaBase $MediaBase -Results $results
            }
            continue
        }

        # Fichier explicite : parse du chemin, sans exiger l'existence.
        Add-WhisperTranscriptDirectoryMatch -FilePath $entry -MediaBase $MediaBase -Results $results
    }

    if ($results.Count -eq 0) {
        return [string]::Empty
    }
    return $results[0]
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
    $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.tmp')

    try {
        [IO.File]::WriteAllText($temp, $json, $utf8)
        Move-Item -LiteralPath $temp -Destination $Path -Force -ErrorAction Stop
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
        [string[]] $Source,
        [string] $UseLanguage,
        [int] $AudioTrack = 1
    )

    $raw = Get-Content -LiteralPath $NativeJsonPath -Raw -Encoding UTF8
    $transcript = ConvertFrom-WhisperTranscript -InputObject $raw -Model $Model -UseLanguage $UseLanguage -AudioTrack $AudioTrack
    $mediaBase = Get-WhisperMediaBaseName -NativeJsonPath $NativeJsonPath -Language $transcript.language
    $directory = Resolve-WhisperTranscriptDirectory -MediaBase $mediaBase -Source $Source
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "Impossible de rattacher le JSON natif '$NativeJsonPath' à une source média."
    }
    $dest = Get-TetramTranscriptPath -Directory $directory -MediaBase $mediaBase -Language $transcript.language -Model $Model -AudioTrack $AudioTrack
    Write-TetramTranscript -Transcript $transcript -Path $dest
}
