Set-StrictMode -Version 3.0

# Gemini corrompt régulièrement les timestamps SRT : on les ignore toujours
# et on reconstruit depuis la source. Un écart du nombre de cues, lui, n'est
# pas récupérable par position.

function Get-SubtitleNewline {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    if ($Text -match '\r\n') {
        return "`r`n"
    }
    return "`n"
}

function Split-SubtitleLine {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    return [regex]::Split($Text, '\r\n|\n|\r')
}

function ConvertFrom-SrtCueList {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Text,
        [Parameter(Mandatory)][bool] $Strict
    )

    $normalized = ($Text -replace '\r\n', "`n" -replace '\r', "`n").TrimEnd()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return @()
    }

    $blocks = @([regex]::Split($normalized, '\n[ \t]*\n+') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cues = foreach ($block in $blocks) {
        $lines = @($block -split '\n')
        if ($Strict) {
            if ($lines.Count -lt 2) {
                throw 'Un cue SRT source est incomplet (identifiant ou timestamp manquant).'
            }
            $textLines = if ($lines.Count -gt 2) { $lines[2..($lines.Count - 1)] } else { @() }
            [pscustomobject]@{
                Id        = $lines[0]
                Timestamp = $lines[1]
                Text      = $textLines -join "`n"
            }
        }
        else {
            [pscustomobject]@{
                Text = Get-SrtTranslationText -Line $lines
            }
        }
    }
    return @($cues)
}

function Get-SrtTranslationText {
    param([Parameter(Mandatory)][string[]] $Line)

    # Id + ligne avec --> (même timestamp invalide) : le texte utile est en dessous.
    if ($Line.Count -ge 2 -and $Line[1] -match '-->') {
        if ($Line.Count -gt 2) {
            return ($Line[2..($Line.Count - 1)] -join "`n")
        }
        return ''
    }

    return ($Line -join "`n")
}

function Merge-SrtTranslatedSubtitle {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Source,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Translation
    )

    $sourceCues = @(ConvertFrom-SrtCueList -Text $Source -Strict $true)
    $translationCues = @(ConvertFrom-SrtCueList -Text $Translation -Strict $false)

    if ($sourceCues.Count -ne $translationCues.Count) {
        throw "Le nombre de cues SRT de la traduction ($($translationCues.Count)) diffère de la source ($($sourceCues.Count))."
    }

    if ($sourceCues.Count -eq 0) {
        return $Source
    }

    $nl = Get-SubtitleNewline -Text $Source
    $blocks = foreach ($i in 0..($sourceCues.Count - 1)) {
        $cue = $sourceCues[$i]
        $parts = @($cue.Id, $cue.Timestamp)
        if (-not [string]::IsNullOrEmpty($translationCues[$i].Text)) {
            $parts += $translationCues[$i].Text
        }
        $parts -join $nl
    }

    $merged = $blocks -join "$nl$nl"
    if ($Source.EndsWith("`n") -or $Source.EndsWith("`r")) {
        return $merged + $nl
    }
    return $merged
}

function Get-AssEventsTextIndex {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Line)

    $inEvents = $false
    foreach ($entry in $Line) {
        if ($entry -match '^\[Events\]') {
            $inEvents = $true
            continue
        }
        if ($inEvents -and $entry -match '^\[') {
            break
        }
        if ($inEvents -and $entry -match '^Format:') {
            $colon = $entry.IndexOf(':')
            $names = @(
                $entry.Substring($colon + 1) -split ',' |
                    ForEach-Object { $_.Trim() }
            )
            for ($i = 0; $i -lt $names.Count; $i++) {
                if ($names[$i].Equals('Text', [StringComparison]::OrdinalIgnoreCase)) {
                    return $i
                }
            }
            throw 'Le champ Text est absent de la ligne Format: de [Events].'
        }
    }

    throw 'La ligne Format: de la section [Events] est introuvable.'
}

function Get-AssDialogueField {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line,
        [Parameter(Mandatory)][int] $TextIndex
    )

    if ($Line -notmatch '^Dialogue:\s*(.*)$') {
        throw "Ligne Dialogue: attendue : $Line"
    }

    $payload = $Matches[1]
    $field = @($payload -split ',', ($TextIndex + 1))
    if ($field.Count -le $TextIndex) {
        throw 'Ligne Dialogue: incomplète : champ Text introuvable.'
    }

    return $field
}

function Get-AssTextTechnicalToken {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return @()
    }

    return @([regex]::Matches($Text, '\{[^{}]*\}|\\N') | ForEach-Object { $_.Value })
}

function Assert-AssTextContract {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $SourceText,
        [Parameter(Mandatory)][AllowEmptyString()][string] $TranslationText
    )

    $sourceToken = @(Get-AssTextTechnicalToken -Text $SourceText)
    $translationToken = @(Get-AssTextTechnicalToken -Text $TranslationText)

    $same = ($sourceToken.Count -eq $translationToken.Count)
    if ($same) {
        for ($i = 0; $i -lt $sourceToken.Count; $i++) {
            if ($sourceToken[$i] -ne $translationToken[$i]) {
                $same = $false
                break
            }
        }
    }
    if ($same) {
        return
    }

    $sourceTag = @($sourceToken | Where-Object { $_.StartsWith('{') })
    $translationTag = @($translationToken | Where-Object { $_.StartsWith('{') })
    $sourceTagKey = $sourceTag -join [char]0x1E
    $translationTagKey = $translationTag -join [char]0x1E
    if ($sourceTagKey -ne $translationTagKey) {
        throw 'Les balises {...} du champ Text diffèrent de la source.'
    }

    throw 'Les retours forcés \N du champ Text diffèrent de la source.'
}

function Merge-AssTranslatedSubtitle {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Source,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Translation
    )

    $sourceLine = @(Split-SubtitleLine -Text $Source)
    $translationLine = @(Split-SubtitleLine -Text $Translation)

    $sourceTextIndex = Get-AssEventsTextIndex -Line $sourceLine
    $translationTextIndex = Get-AssEventsTextIndex -Line $translationLine

    $translationText = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $translationLine) {
        if ($entry -match '^Dialogue:') {
            $field = Get-AssDialogueField -Line $entry -TextIndex $translationTextIndex
            [void]$translationText.Add($field[$translationTextIndex])
        }
    }

    $sourceDialogueCount = @($sourceLine | Where-Object { $_ -match '^Dialogue:' }).Count
    if ($sourceDialogueCount -ne $translationText.Count) {
        throw "Le nombre de lignes Dialogue: de la traduction ($($translationText.Count)) diffère de la source ($sourceDialogueCount)."
    }

    $geminiIndex = 0
    $mergedLine = foreach ($entry in $sourceLine) {
        if ($entry -notmatch '^(Dialogue:)(\s*)') {
            $entry
            continue
        }

        $prefix = $Matches[1] + $Matches[2]
        $field = Get-AssDialogueField -Line $entry -TextIndex $sourceTextIndex
        $geminiText = $translationText[$geminiIndex]
        Assert-AssTextContract -SourceText $field[$sourceTextIndex] -TranslationText $geminiText
        $geminiIndex++

        if ($sourceTextIndex -eq 0) {
            $prefix + $geminiText
        }
        else {
            $head = $field[0..($sourceTextIndex - 1)] -join ','
            $prefix + $head + ',' + $geminiText
        }
    }

    $nl = Get-SubtitleNewline -Text $Source
    return ($mergedLine -join $nl)
}

function Merge-TranslatedSubtitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Source,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Translation,

        [Parameter(Mandatory)]
        [string] $Extension
    )

    $kind = $Extension.Trim().TrimStart('.').ToLowerInvariant()
    switch ($kind) {
        'srt' {
            return Merge-SrtTranslatedSubtitle -Source $Source -Translation $Translation
        }
        { $_ -in @('ass', 'ssa') } {
            return Merge-AssTranslatedSubtitle -Source $Source -Translation $Translation
        }
        default {
            throw "Extension de sous-titres non supportée pour la fusion : $Extension"
        }
    }
}
