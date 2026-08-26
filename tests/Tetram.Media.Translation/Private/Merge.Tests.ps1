# Étendre la suite autour de Merge-TranslatedSubtitle (fusion source + proposition Gemini).
#
# RepoRoot depuis tests/<Module>/Private : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Translation') -Force
# InModuleScope 'Tetram.Media.Translation' : Merge-TranslatedSubtitle n'est pas exportée.
# ConvertTo-Lf reste hors InModuleScope : le helper n'existe pas dans le scope du module.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranslation = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranslation = Join-Path $script:RepoRootTranslation 'Tetram.Media.Translation'
    Import-Module -Name $script:ModuleRootTranslation -Force -ErrorAction Stop

    function script:ConvertTo-Lf([string] $Text) {
        ($Text -replace '\r\n', "`n" -replace '\r', "`n").TrimEnd()
    }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Translation' -Force -ErrorAction SilentlyContinue
}

Describe 'Merge-TranslatedSubtitle SRT' {
    It 'restaure le timestamp source quand Gemini le corrompt' {
        $got = InModuleScope 'Tetram.Media.Translation' {
            $source = "37`n00:05:59,237 --> 00:06:00,057`nEnglish text`n"
            $translation = "37`n00:09:59,237 --> 00:06:00,057`ntexte français`n"
            Merge-TranslatedSubtitle -Source $source -Translation $translation -Extension '.srt'
        }

        ConvertTo-Lf $got | Should -Be "37`n00:05:59,237 --> 00:06:00,057`ntexte français"
    }

    It 'récupère le texte Gemini même si le timestamp traduit est invalide' {
        $got = InModuleScope 'Tetram.Media.Translation' {
            $source = "37`n00:05:59,237 --> 00:06:00,057`nEnglish text`n"
            $translation = "37`n99:99:99,999 --> not-a-time`ntexte français`n"
            Merge-TranslatedSubtitle -Source $source -Translation $translation -Extension '.srt'
        }

        ConvertTo-Lf $got | Should -Be "37`n00:05:59,237 --> 00:06:00,057`ntexte français"
    }

    It 'lève si le nombre de cues diffère' {
        InModuleScope 'Tetram.Media.Translation' {
            $source = "1`n00:00:01,000 --> 00:00:02,000`nA`n`n2`n00:00:03,000 --> 00:00:04,000`nB`n"
            $translation = "1`n00:00:01,000 --> 00:00:02,000`nA`n"

            { Merge-TranslatedSubtitle -Source $source -Translation $translation -Extension '.srt' } |
                Should -Throw -ExpectedMessage '*cues*'
        }
    }
}

Describe 'Merge-TranslatedSubtitle ASS' {
    It 'ne change que le champ Text des lignes Dialogue:' {
        $got = InModuleScope 'Tetram.Media.Translation' {
            $source = "[Script Info]`nTitle: Source`n`n[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello`n"
            $translation = "[Script Info]`nTitle: Gemini a tout cassé`n`n[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 9,9:99:99.99,9:99:99.99,Other,,1,1,1,,Bonjour`n"
            Merge-TranslatedSubtitle -Source $source -Translation $translation -Extension '.ass'
        }

        $gotLf = ConvertTo-Lf $got
        $gotLf | Should -Match 'Title: Source'
        $gotLf | Should -Not -Match 'Gemini a tout cassé'
        $gotLf | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
        $gotLf | Should -Not -Match 'Hello'
    }

    It 'lève si Gemini altère les balises \{\.\.\.\}' {
        InModuleScope 'Tetram.Media.Translation' {
            $source = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\i1}Hello{\i0}`n"
            $translation = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\b1}Bonjour{\i0}`n"

            { Merge-TranslatedSubtitle -Source $source -Translation $translation -Extension '.ass' } |
                Should -Throw -ExpectedMessage '*balise*'
        }
    }

    It 'lève si Gemini altère les retours forcés \N' {
        InModuleScope 'Tetram.Media.Translation' {
            $source = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello\Nworld`n"
            $translation = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour world`n"

            { Merge-TranslatedSubtitle -Source $source -Translation $translation -Extension '.ass' } |
                Should -Throw -ExpectedMessage '*retours forcés*'
        }
    }

    It 'copie strictement depuis la source toutes les lignes non Dialogue:' {
        $source = @"
[Script Info]
Title: Keep me
PlayResX: 1920

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Comment: 0,0:00:00.00,0:00:00.01,Default,,0,0,0,,NOTE
Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello
"@
        $got = InModuleScope 'Tetram.Media.Translation' -Parameters @{ Source = $source } {
            $translation = @"
[Script Info]
Title: DROPPED

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Other,Comic Sans,99

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Comment: 0,0:00:00.00,0:00:00.01,Default,,0,0,0,,GEMINI NOTE
Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour
"@
            Merge-TranslatedSubtitle -Source $Source -Translation $translation -Extension '.ass'
        }

        $gotLines = @((ConvertTo-Lf $got) -split "`n")
        $srcLines = @((ConvertTo-Lf $source) -split "`n")

        for ($i = 0; $i -lt $srcLines.Count; $i++) {
            if ($srcLines[$i] -match '^Dialogue:') {
                continue
            }
            $gotLines[$i] | Should -Be $srcLines[$i] -Because "ligne source $i doit être inchangée"
        }

        ($gotLines | Where-Object { $_ -match '^Dialogue:' }) | Should -Be 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
    }
}
