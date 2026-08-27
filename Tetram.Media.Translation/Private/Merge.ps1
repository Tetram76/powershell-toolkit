Set-StrictMode -Version 3.0

# Le modèle ne fournit que du texte indexé par cueId. Toute la structure
# technique (identifiants SRT natifs, timestamps, champs ASS) reste celle
# de la source. Une omission de cueId ne doit jamais décaler les suivants.

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
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $normalized = ($Text -replace '\r\n', "`n" -replace '\r', "`n").TrimEnd()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return @()
    }

    $blocks = @([regex]::Split($normalized, '\n[ \t]*\n+') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cues = foreach ($block in $blocks) {
        $lines = @($block -split '\n')
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
    return @($cues)
}

function Split-SrtTimestampRange {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Timestamp)

    $part = @($Timestamp -split '\s*-->\s*', 2)
    if ($part.Count -ne 2 -or [string]::IsNullOrWhiteSpace($part[0]) -or [string]::IsNullOrWhiteSpace($part[1])) {
        throw 'Un cue SRT source n''a pas de ligne de timestamp avec -->.'
    }

    [pscustomobject]@{
        Start = $part[0].Trim()
        End   = $part[1].Trim()
    }
}

function Get-AssEventsFormatName {
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
            return @(
                $entry.Substring($colon + 1) -split ',' |
                    ForEach-Object { $_.Trim() }
            )
        }
    }

    throw 'La ligne Format: de la section [Events] est introuvable.'
}

function Get-AssEventsFieldIndex {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Line,
        [Parameter(Mandatory)][string] $FieldName
    )

    $name = @(Get-AssEventsFormatName -Line $Line)
    for ($i = 0; $i -lt $name.Count; $i++) {
        if ($name[$i].Equals($FieldName, [StringComparison]::OrdinalIgnoreCase)) {
            return $i
        }
    }

    throw "Le champ $FieldName est absent de la ligne Format: de [Events]."
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

function Get-CanonicalSrtCue {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Source)

    $sourceCue = @(ConvertFrom-SrtCueList -Text $Source)
    $cueId = 0
    foreach ($cue in $sourceCue) {
        $cueId++
        $range = Split-SrtTimestampRange -Timestamp $cue.Timestamp
        [pscustomobject][ordered]@{
            cueId = $cueId
            start = $range.Start
            end   = $range.End
            text  = $cue.Text
        }
    }
}

function Get-CanonicalAssCue {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Source)

    $line = @(Split-SubtitleLine -Text $Source)
    $startIndex = Get-AssEventsFieldIndex -Line $line -FieldName 'Start'
    $endIndex = Get-AssEventsFieldIndex -Line $line -FieldName 'End'
    $textIndex = Get-AssEventsFieldIndex -Line $line -FieldName 'Text'
    if ($startIndex -ge $textIndex -or $endIndex -ge $textIndex) {
        throw 'Les champs Start et End doivent précéder Text dans Format: de [Events].'
    }

    $cueId = 0
    foreach ($entry in $line) {
        if ($entry -notmatch '^Dialogue:') {
            continue
        }
        $cueId++
        $field = Get-AssDialogueField -Line $entry -TextIndex $textIndex
        [pscustomobject][ordered]@{
            cueId = $cueId
            start = $field[$startIndex]
            end   = $field[$endIndex]
            text  = $field[$textIndex]
        }
    }
}

function ConvertTo-SecondarySubtitleCueJson {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][object[]] $Cue)

    $stripped = @(
        foreach ($item in $Cue) {
            [pscustomobject][ordered]@{
                start = $item.start
                end   = $item.end
                text  = $item.text
            }
        }
    )
    return ConvertTo-CanonicalCueJson -Cue $stripped
}

function ConvertTo-CanonicalCueJson {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][object[]] $Cue)

    if ($Cue.Count -eq 0) {
        return '[]'
    }

    # ConvertTo-Json d'un tableau à un seul élément émet un objet, pas un tableau.
    $itemJson = foreach ($item in $Cue) {
        ConvertTo-Json -InputObject $item -Depth 5
    }
    return '[' + ($itemJson -join ',') + ']'
}

function Get-CanonicalSubtitleCue {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Source,
        [Parameter(Mandatory)][string] $Extension
    )

    $cue = switch (Get-SubtitleMergeKind -Extension $Extension) {
        'srt' { @(Get-CanonicalSrtCue -Source $Source) }
        'ass' { @(Get-CanonicalAssCue -Source $Source) }
    }
    return @($cue)
}

function Test-IntegerCueId {
    param($Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [bool] -or $Value -is [string] -or $Value -is [char]) {
        return $false
    }
    if ($Value -is [double] -or $Value -is [decimal] -or $Value -is [float] -or $Value -is [single]) {
        return $false
    }

    try {
        $asInt = [int]$Value
        return ([long]$Value -eq [long]$asInt)
    }
    catch {
        return $false
    }
}

function ConvertFrom-CueTranslationJson {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Json,
        [Parameter(Mandatory)][int] $CueCount
    )

    try {
        $parsed = ConvertFrom-Json -InputObject $Json -NoEnumerate -ErrorAction Stop
    }
    catch {
        throw 'la réponse du modèle n''est pas un JSON exploitable.'
    }

    if ($null -eq $parsed -or $parsed -is [string] -or $parsed -isnot [System.Collections.IList]) {
        throw 'la racine de la réponse du modèle doit être un tableau JSON.'
    }

    $map = [System.Collections.Generic.Dictionary[int, string]]::new()
    foreach ($item in $parsed) {
        if ($null -eq $item) {
            throw 'un élément de la réponse du modèle n''est pas un objet JSON.'
        }

        if ($item -is [System.Collections.IDictionary]) {
            $cueIdProp = $item['cueId']
            $textProp = $item['text']
            $hasCueId = $item.Contains('cueId')
            $hasText = $item.Contains('text')
        }
        else {
            $cueIdMember = $item.PSObject.Properties['cueId']
            $textMember = $item.PSObject.Properties['text']
            $hasCueId = $null -ne $cueIdMember
            $hasText = $null -ne $textMember
            $cueIdProp = if ($hasCueId) { $cueIdMember.Value } else { $null }
            $textProp = if ($hasText) { $textMember.Value } else { $null }
        }

        if (-not $hasCueId -or -not $hasText) {
            throw 'un objet de la réponse du modèle n''a pas les propriétés cueId et text.'
        }

        if (-not (Test-IntegerCueId -Value $cueIdProp)) {
            throw 'un cueId de la réponse du modèle n''est pas un entier valide.'
        }

        $cueId = [int]$cueIdProp
        if ($cueId -lt 1 -or $cueId -gt $CueCount) {
            throw "cueId $cueId hors plage (1..$CueCount)."
        }
        if ($map.ContainsKey($cueId)) {
            throw "cueId $cueId dupliqué."
        }
        if ($textProp -isnot [string]) {
            throw "la propriété text du cueId $cueId n'est pas une chaîne."
        }
        $map[$cueId] = $textProp
    }

    for ($id = 1; $id -le $CueCount; $id++) {
        if (-not $map.ContainsKey($id)) {
            throw "cueId $id manquant"
        }
    }

    return $map
}

function Assert-CueTranslationNotEmptied {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $SourceText,
        [Parameter(Mandatory)][System.Collections.IDictionary] $TranslationByCueId
    )

    for ($i = 0; $i -lt $SourceText.Count; $i++) {
        $cueId = $i + 1
        $translated = Get-CueTranslationText -TranslationByCueId $TranslationByCueId -CueId $cueId
        # Un text réduit à des espaces n'est pas une proposition linguistique ;
        # IsNullOrEmpty le laisserait passer et produirait un final « vide ».
        if (-not [string]::IsNullOrWhiteSpace($SourceText[$i]) -and [string]::IsNullOrWhiteSpace($translated)) {
            throw "le texte du cueId $cueId est vide alors que la source ne l'est pas."
        }
    }
}

function Get-CueTranslationText {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $TranslationByCueId,
        [Parameter(Mandatory)][int] $CueId
    )

    # Dictionary<TKey,TValue>.Contains entre en conflit avec Enumerable.Contains
    # (1 argument). On compare les clés plutôt que d'appeler Contains/ContainsKey.
    foreach ($key in @($TranslationByCueId.Keys)) {
        $asInt = 0
        if (-not [int]::TryParse([string]$key, [ref]$asInt)) {
            continue
        }
        if ($asInt -eq $CueId) {
            return [string]$TranslationByCueId[$key]
        }
    }

    throw "cueId $CueId manquant"
}

function Merge-SrtTranslatedSubtitle {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Source,
        [Parameter(Mandatory)][System.Collections.IDictionary] $TranslationByCueId
    )

    $sourceCue = @(ConvertFrom-SrtCueList -Text $Source)
    if ($sourceCue.Count -eq 0) {
        return $Source
    }

    $nl = Get-SubtitleNewline -Text $Source
    $block = for ($i = 0; $i -lt $sourceCue.Count; $i++) {
        $cue = $sourceCue[$i]
        $text = Get-CueTranslationText -TranslationByCueId $TranslationByCueId -CueId ($i + 1)
        $part = @($cue.Id, $cue.Timestamp)
        if (-not [string]::IsNullOrEmpty($text)) {
            $part += $text
        }
        $part -join $nl
    }

    $merged = $block -join "$nl$nl"
    if ($Source.EndsWith("`n") -or $Source.EndsWith("`r")) {
        return $merged + $nl
    }
    return $merged
}

function Merge-AssTranslatedSubtitle {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Source,
        [Parameter(Mandatory)][System.Collections.IDictionary] $TranslationByCueId
    )

    $sourceLine = @(Split-SubtitleLine -Text $Source)
    $sourceTextIndex = Get-AssEventsFieldIndex -Line $sourceLine -FieldName 'Text'

    $cueId = 0
    $mergedLine = foreach ($entry in $sourceLine) {
        if ($entry -notmatch '^(Dialogue:)(\s*)') {
            $entry
            continue
        }

        $cueId++
        $prefix = $Matches[1] + $Matches[2]
        $field = Get-AssDialogueField -Line $entry -TextIndex $sourceTextIndex
        $translatedText = Get-CueTranslationText -TranslationByCueId $TranslationByCueId -CueId $cueId
        Assert-AssTextContract -SourceText $field[$sourceTextIndex] -TranslationText $translatedText

        if ($sourceTextIndex -eq 0) {
            $prefix + $translatedText
        }
        else {
            $head = $field[0..($sourceTextIndex - 1)] -join ','
            $prefix + $head + ',' + $translatedText
        }
    }

    $nl = Get-SubtitleNewline -Text $Source
    return ($mergedLine -join $nl)
}

function Get-SubtitleMergeKind {
    param([Parameter(Mandatory)][string] $Extension)

    $kind = $Extension.Trim().TrimStart('.').ToLowerInvariant()
    switch ($kind) {
        'srt' { 'srt' }
        { $_ -in @('ass', 'ssa') } { 'ass' }
        default {
            throw "Extension de sous-titres non supportée : $Extension"
        }
    }
}

function Merge-TranslatedSubtitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Source,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $TranslationByCueId,

        [Parameter(Mandatory)]
        [string] $Extension
    )

    switch (Get-SubtitleMergeKind -Extension $Extension) {
        'srt' {
            return Merge-SrtTranslatedSubtitle -Source $Source -TranslationByCueId $TranslationByCueId
        }
        'ass' {
            return Merge-AssTranslatedSubtitle -Source $Source -TranslationByCueId $TranslationByCueId
        }
    }
}
