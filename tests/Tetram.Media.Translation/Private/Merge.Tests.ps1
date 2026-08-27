# Étendre la suite autour de Merge-TranslatedSubtitle (fusion source + textes par cueId).
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

Describe 'ConvertTo-TechnicalTemplateCueJson' {
    It 'émet cueId/start/end sans text' {
        $json = InModuleScope 'Tetram.Media.Translation' {
            ConvertTo-TechnicalTemplateCueJson -Cue @(
                [pscustomobject][ordered]@{
                    cueId = 1
                    start = '00:00:01,000'
                    end   = '00:00:02,000'
                    text  = 'Hello'
                }
            )
        }

        $got = ConvertFrom-Json -InputObject $json
        @($got).Count | Should -Be 1
        $got.cueId | Should -Be 1
        $got.start | Should -Be '00:00:01,000'
        $got.end | Should -Be '00:00:02,000'
        $got.PSObject.Properties['text'] | Should -BeNullOrEmpty
        $json | Should -Not -Match '"text"'
    }
}

Describe 'Merge-TranslatedSubtitle SRT' {
    It 'conserve les identifiants SRT natifs indépendants du cueId' {
        $got = InModuleScope 'Tetram.Media.Translation' {
            $source = "10`n00:00:01,000 --> 00:00:02,000`nHello`n`n42`n00:00:03,000 --> 00:00:04,000`nWorld`n"
            Merge-TranslatedSubtitle -Source $source -TranslationByCueId @{ 1 = 'Bonjour'; 2 = 'Monde' } -Extension '.srt'
        }

        ConvertTo-Lf $got | Should -Be "10`n00:00:01,000 --> 00:00:02,000`nBonjour`n`n42`n00:00:03,000 --> 00:00:04,000`nMonde"
    }

    It 'reconstruit correctement si les traductions ne sont pas dans l''ordre des cueId' {
        $got = InModuleScope 'Tetram.Media.Translation' {
            $source = "10`n00:00:01,000 --> 00:00:02,000`nHello`n`n42`n00:00:03,000 --> 00:00:04,000`nWorld`n"
            Merge-TranslatedSubtitle -Source $source -TranslationByCueId @{ 2 = 'Monde'; 1 = 'Bonjour' } -Extension '.srt'
        }

        ConvertTo-Lf $got | Should -Be "10`n00:00:01,000 --> 00:00:02,000`nBonjour`n`n42`n00:00:03,000 --> 00:00:04,000`nMonde"
    }

    It 'reprend exactement les timestamps de la source' {
        $got = InModuleScope 'Tetram.Media.Translation' {
            $source = "37`n00:05:59,237 --> 00:06:00,057`nEnglish text`n"
            Merge-TranslatedSubtitle -Source $source -TranslationByCueId @{ 1 = 'texte français' } -Extension '.srt'
        }

        ConvertTo-Lf $got | Should -Be "37`n00:05:59,237 --> 00:06:00,057`ntexte français"
        ConvertTo-Lf $got | Should -Not -Match '00:09:59'
    }
}

Describe 'Merge-TranslatedSubtitle ASS' {
    It 'place le texte du bon cueId même si les traductions sont dans l''ordre inverse' {
        $got = InModuleScope 'Tetram.Media.Translation' {
            $source = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello`nDialogue: 1,0:00:03.00,0:00:04.00,Default,,0,0,0,,World`n"
            Merge-TranslatedSubtitle -Source $source -TranslationByCueId @{ 2 = 'Monde'; 1 = 'Bonjour' } -Extension '.ass'
        }

        $gotLf = ConvertTo-Lf $got
        $gotLf | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
        $gotLf | Should -Match 'Dialogue: 1,0:00:03.00,0:00:04.00,Default,,0,0,0,,Monde'
    }

    It 'ne change que le champ Text des lignes Dialogue:' {
        $got = InModuleScope 'Tetram.Media.Translation' {
            $source = "[Script Info]`nTitle: Source`n`n[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello`n"
            Merge-TranslatedSubtitle -Source $source -TranslationByCueId @{ 1 = 'Bonjour' } -Extension '.ass'
        }

        $gotLf = ConvertTo-Lf $got
        $gotLf | Should -Match 'Title: Source'
        $gotLf | Should -Match 'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Bonjour'
        $gotLf | Should -Not -Match 'Hello'
    }

    It 'lève si Gemini altère les balises \{\.\.\.\}' {
        InModuleScope 'Tetram.Media.Translation' {
            $source = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\i1}Hello{\i0}`n"

            { Merge-TranslatedSubtitle -Source $source -TranslationByCueId @{ 1 = '{\b1}Bonjour{\i0}' } -Extension '.ass' } |
                Should -Throw -ExpectedMessage '*balise*'
        }
    }

    It 'lève si Gemini altère les retours forcés \N' {
        InModuleScope 'Tetram.Media.Translation' {
            $source = "[Events]`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello\Nworld`n"

            { Merge-TranslatedSubtitle -Source $source -TranslationByCueId @{ 1 = 'Bonjour world' } -Extension '.ass' } |
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
            Merge-TranslatedSubtitle -Source $Source -TranslationByCueId @{ 1 = 'Bonjour' } -Extension '.ass'
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
