# Étendre la suite autour de ConvertTo-CompactWhisperJson (réduction des JSON Whisper secondaires).
#
# RepoRoot depuis tests/<Module>/Private : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Translation') -Force
# InModuleScope 'Tetram.Media.Translation' : ConvertTo-CompactWhisperJson n'est pas exportée.
# La fonction doit échouer si Get-Command ne la trouve pas : un Should -Throw seul passerait à tort.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranslation = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranslation = Join-Path $script:RepoRootTranslation 'Tetram.Media.Translation'
    Import-Module -Name $script:ModuleRootTranslation -Force -ErrorAction Stop

    $script:RepresentativeWhisperJson = @'
{
  "text": "texte global dupliqué",
  "language": "ja",
  "duration": 1400.0,
  "unexpected_root": 123,
  "segments": [
    {
      "id": 7,
      "seek": 1000,
      "start": 12.34,
      "end": 15.67,
      "text": "recognized text",
      "tokens": [50364, 1234, 5678, 50420],
      "temperature": 0.0,
      "avg_logprob": -0.42,
      "compression_ratio": 1.31,
      "no_speech_prob": 0.02,
      "words": [
        {
          "start": 12.34,
          "end": 12.80,
          "word": "recognized",
          "probability": 0.93
        }
      ],
      "unexpected_segment": "drop me"
    }
  ]
}
'@

    function script:Invoke-CompactWhisperJson {
        param($InputObject)

        InModuleScope 'Tetram.Media.Translation' -Parameters @{ InputObject = $InputObject } {
            param($InputObject)
            $cmd = Get-Command -Name ConvertTo-CompactWhisperJson -ErrorAction SilentlyContinue
            if ($null -eq $cmd) {
                throw 'ConvertTo-CompactWhisperJson est introuvable dans le module.'
            }
            ConvertTo-CompactWhisperJson -InputObject $InputObject
        }
    }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Translation' -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-CompactWhisperJson' {
    It 'conserve language et les champs segmentaires utiles du JSON représentatif' {
        $compact = Invoke-CompactWhisperJson -InputObject $script:RepresentativeWhisperJson
        $got = ConvertFrom-Json -InputObject $compact

        $got.language | Should -Be 'ja'
        @($got.segments).Count | Should -Be 1
        $segment = @($got.segments)[0]
        $segment.start | Should -Be 12.34
        $segment.end | Should -Be 15.67
        $segment.text | Should -Be 'recognized text'
        $segment.temperature | Should -Be 0
        $segment.avg_logprob | Should -Be -0.42
        $segment.compression_ratio | Should -Be 1.31
        $segment.no_speech_prob | Should -Be 0.02
    }

    It 'omet text racine, id, seek, tokens, words et les champs inconnus' {
        $compact = Invoke-CompactWhisperJson -InputObject $script:RepresentativeWhisperJson
        $got = ConvertFrom-Json -InputObject $compact
        $segment = @($got.segments)[0]

        $got.PSObject.Properties['text'] | Should -BeNullOrEmpty
        $got.PSObject.Properties['duration'] | Should -BeNullOrEmpty
        $got.PSObject.Properties['unexpected_root'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['id'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['seek'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['tokens'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['words'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['unexpected_segment'] | Should -BeNullOrEmpty
        $compact | Should -Not -Match 'texte global dupliqué'
        $compact | Should -Not -Match 'drop me'
        $compact | Should -Not -Match '"tokens"'
        $compact | Should -Not -Match '"words"'
    }

    It 'n''invente pas une métrique optionnelle absente' {
        $json = '{"segments":[{"start":1.0,"end":2.0,"text":"hello","avg_logprob":-0.1}]}'
        $compact = Invoke-CompactWhisperJson -InputObject $json
        $segment = @( (ConvertFrom-Json -InputObject $compact).segments )[0]

        $segment.text | Should -Be 'hello'
        $segment.avg_logprob | Should -Be -0.1
        $segment.PSObject.Properties['temperature'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['compression_ratio'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['no_speech_prob'] | Should -BeNullOrEmpty
        $compact | Should -Not -Match '"language"'
    }

    It 'préserve le texte, y compris les espaces internes, et les timestamps' {
        $json = '{"segments":[{"start":12.34,"end":15.67,"text":"recognized  text"}]}'
        $compact = Invoke-CompactWhisperJson -InputObject $json
        $segment = @( (ConvertFrom-Json -InputObject $compact).segments )[0]

        $segment.start | Should -Be 12.34
        $segment.end | Should -Be 15.67
        $segment.text | Should -Be 'recognized  text'
    }

    It 'produit un JSON valide et compact' {
        $compact = Invoke-CompactWhisperJson -InputObject $script:RepresentativeWhisperJson

        { ConvertFrom-Json -InputObject $compact -ErrorAction Stop } | Should -Not -Throw
        $compact | Should -Not -Match '[\r\n]'
        $compact | Should -Match '"segments":\['
    }

    It 'accepte un objet déjà désérialisé' {
        $parsed = ConvertFrom-Json -InputObject $script:RepresentativeWhisperJson
        $compact = Invoke-CompactWhisperJson -InputObject $parsed
        $got = ConvertFrom-Json -InputObject $compact

        $got.language | Should -Be 'ja'
        @($got.segments)[0].text | Should -Be 'recognized text'
    }

    It 'lève si segments est absent' {
        { Invoke-CompactWhisperJson -InputObject '{"text":"x"}' } |
            Should -Throw '*structure Whisper*'
    }

    It 'lève si un segment n''a pas start, end ou text' {
        { Invoke-CompactWhisperJson -InputObject '{"segments":[{"start":1.0,"end":2.0}]}' } |
            Should -Throw '*structure Whisper*'
        { Invoke-CompactWhisperJson -InputObject '{"segments":[{"start":1.0,"text":"x"}]}' } |
            Should -Throw '*structure Whisper*'
        { Invoke-CompactWhisperJson -InputObject '{"segments":[{"end":2.0,"text":"x"}]}' } |
            Should -Throw '*structure Whisper*'
    }
}
