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

function Test-WhisperNativeJsonName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $FileName
    )

    # Dossier GUID dédié à l'exécution : tout JSON y est natif, sauf un sidecar Tetram
    # posé par erreur. Purfview --postfix nomme `stem_lang.json`, pas `stem.lang.json`.
    if ($FileName -match '\.track \d+\.') {
        return $false
    }

    return $FileName.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)
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
    # Même volume que le sidecar : un Move-Item depuis TEMP serait une copie inter-filesystem.
    $destDir = [IO.Path]::GetDirectoryName($Path)
    if ([string]::IsNullOrWhiteSpace($destDir)) {
        $destDir = (Get-Location).Path
    }
    $temp = Join-Path $destDir ([guid]::NewGuid().ToString() + '.tmp')

    try {
        [IO.File]::WriteAllText($temp, $json, $utf8)
        # -Force : une réexécution doit remplacer le sidecar existant ; sans ça Move-Item échoue si $Path est déjà là.
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
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [string] $Model,
        [string] $UseLanguage,
        [int] $AudioTrack = 1
    )

    $raw = Get-Content -LiteralPath $NativeJsonPath -Raw -Encoding UTF8
    $transcript = ConvertFrom-WhisperTranscript -InputObject $raw -Model $Model -UseLanguage $UseLanguage -AudioTrack $AudioTrack
    $directory = [IO.Path]::GetDirectoryName($MediaPath)
    if ([string]::IsNullOrWhiteSpace($directory)) {
        $directory = (Get-Location).Path
    }
    $mediaBase = [IO.Path]::GetFileNameWithoutExtension($MediaPath)
    $dest = Get-TetramTranscriptPath -Directory $directory -MediaBase $mediaBase -Language $transcript.language -Model $Model -AudioTrack $AudioTrack
    Write-TetramTranscript -Transcript $transcript -Path $dest
}
