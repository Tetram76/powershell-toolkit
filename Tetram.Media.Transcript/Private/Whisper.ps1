Set-StrictMode -Version 3.0

# Dot-source depuis Private/ : $PSScriptRoot n'est pas la racine du module.
$script:WhisperRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Purfview-Whisper-Faster'

function Get-WhisperArguments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] [string] $OutputDir,
        [int] $AudioTrack = 1,
        [string] $UseLanguage
    )

    $whisperArgs = @(
        $Source
        '--output_dir', $OutputDir
        '--output_format', 'json'
        '--check_files'
        '--model', $Model
        '--ff_track', "$AudioTrack"
    )

    if (-not [string]::IsNullOrWhiteSpace($UseLanguage)) {
        $whisperArgs += @('--language', $UseLanguage)
    }

    $whisperArgs += @(
        '--postfix'
        '--print_progress'
        '--task', 'transcribe'
        # Lot sans opérateur : le beep de fin du binaire n'a rien à signaler.
        '--beep_off'
    )

    # kotoba-v2 (CTranslate2 custom) plante en 0xC0000005 avec les défauts Purfview ; ces flags
    # sont ceux qui ont été validés empiriquement. Ne pas les appliquer aux modèles Whisper.
    if ($Model -eq 'kotoba-v2') {
        $whisperArgs += @(
            '--condition_on_previous_text', 'False'
            '-prompt', 'None'
            '--word_timestamps', 'False'
            '--chunk_length', '15'
            '--compute_type', 'float16'
        )
    }

    return $whisperArgs
}

function Get-WhisperPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $OverridePath
    )

    if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
        if (Test-Path -LiteralPath $OverridePath -PathType Leaf) {
            return $OverridePath
        }
        if (Test-Path -LiteralPath $OverridePath) {
            throw "WhisperPath doit désigner un exécutable, pas un dossier : '$OverridePath'"
        }
        throw "WhisperPath inexistant : '$OverridePath'"
    }

    $default = Join-Path $script:WhisperRoot 'faster-whisper-xxl.exe'
    if (Test-Path -LiteralPath $default -PathType Leaf) {
        return $default
    }

    # -CommandType Application : une fonction/alias de même nom dans la session primerait sinon sur
    # l'exécutable du PATH (vérifié empiriquement), avec une Source vide ou trompeuse.
    $fromPath = Get-Command -Name 'faster-whisper-xxl' -CommandType Application -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    throw "faster-whisper-xxl introuvable : posez la distribution Purfview dans '$script:WhisperRoot'."
}

function Invoke-Whisper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)] [hashtable] $State
    )

    # Résultat déposé dans $State et non retourné : une valeur de retour forcerait l'appelant à capturer
    # la sortie de la fonction, donc celle du binaire, et étoufferait --print_progress.
    $State['ExitCode'] = $null

    # Avant ShouldProcess : sous -WhatIf, la ligne prévue reste visible.
    Show-CommandLine -Exe $Exe -Arguments $Arguments -NoPathDetectionParameters 'output_format', 'model', 'task', 'language', 'ff_track'

    if (-not $Cmdlet.ShouldProcess($Arguments[0], 'faster-whisper-xxl')) {
        return
    }

    # & + splat, sans redirection : les frontières d'arguments sont conservées et le binaire écrit
    # directement sur la console.
    & $Exe @Arguments
    $State['ExitCode'] = $LASTEXITCODE
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

function Convert-WhisperNativeToTetram {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $NativeJsonPath,
        [Parameter(Mandatory)] [string] $Model,
        [string] $UseLanguage,
        [int] $AudioTrack = 1
    )

    $raw = Get-Content -LiteralPath $NativeJsonPath -Raw -Encoding UTF8
    return ConvertFrom-WhisperTranscript -InputObject $raw -Model $Model -UseLanguage $UseLanguage -AudioTrack $AudioTrack
}

function Invoke-WhisperTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)] $Result,
        [int] $AudioTrack = 1,
        [string] $UseLanguage,
        [string] $WhisperPath,
        [switch] $WhatIf
    )

    # Purfview lit ces extensions comme une liste de médias, pas comme une source unique.
    $ext = [IO.Path]::GetExtension($MediaPath)
    if ($ext -in @('.lst', '.m3u', '.m3u8', '.txt')) {
        throw "LiteralPath ne doit pas être un fichier-liste : '$MediaPath'"
    }

    $exe = Get-WhisperPath -OverridePath $WhisperPath

    if ($WhatIf) {
        $outputDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    }
    else {
        $outputDir = New-WhisperTempDirectory
    }

    $whisperArgs = Get-WhisperArguments -Source $MediaPath -Model $Model -UseLanguage $UseLanguage -OutputDir $outputDir -AudioTrack $AudioTrack
    Write-DebugLog -Text ($whisperArgs -join ' ')

    try {
        $state = @{ ExitCode = $null }
        Invoke-Whisper -Exe $exe -Arguments $whisperArgs -Cmdlet $Cmdlet -State $state

        # Purfview r245.4 : large-v3 et large-v3-turbo écrivent le JSON natif, puis meurent
        # en STATUS_STACK_BUFFER_OVERRUN (0xC0000409 / -1073740791) au post-traitement.
        $recoverablePurfviewCrash = $state['ExitCode'] -eq -1073740791 -and $Model -in @('large-v3', 'large-v3-turbo')
        if ($null -ne $state['ExitCode'] -and $state['ExitCode'] -ne 0 -and -not $recoverablePurfviewCrash) {
            throw "faster-whisper-xxl a échoué (code $($state['ExitCode'])) sur '$MediaPath' (modèle $Model)."
        }

        if ($null -eq $state['ExitCode']) {
            return
        }

        $nativeJsons = @(Get-WhisperNativeJsonFromOutputDir -OutputDir $outputDir)
        if ($nativeJsons.Count -eq 0) {
            throw "Aucun JSON natif produit par faster-whisper-xxl pour '$MediaPath' (modèle $Model)."
        }
        if ($nativeJsons.Count -gt 1) {
            throw "Résultat natif ambigu pour '$MediaPath' (modèle $Model) : $($nativeJsons.Count) JSON dans le dossier de sortie."
        }

        $transcript = Convert-WhisperNativeToTetram -NativeJsonPath $nativeJsons[0] -Model $Model -UseLanguage $UseLanguage -AudioTrack $AudioTrack

        if ($recoverablePurfviewCrash) {
            Write-InfoLog -Force -Text "faster-whisper-xxl s'est terminé avec le code -1073740791 (0xC0000409) sur '$MediaPath' (modèle $Model) ; JSON natif exploitable et normalisation Tetram terminée malgré le crash."
        }

        [void]$Result.Transcripts.Add($transcript)
    }
    finally {
        Remove-WhisperTempDirectory -Path $outputDir
    }
}

function Invoke-ProviderTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MediaPath,
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)] $Result,
        [int] $AudioTrack = 1,
        [string] $UseLanguage,
        [switch] $WhatIf
    )

    Invoke-WhisperTranscript -MediaPath $MediaPath -Model $Model -Cmdlet $Cmdlet -AudioTrack $AudioTrack -UseLanguage $UseLanguage -Result $Result -WhatIf:$WhatIf
}
