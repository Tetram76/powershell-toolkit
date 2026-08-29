# Étendre la suite autour de ConvertTo-CompactTranscriptJson (réduction des JSON Tetram secondaires).
#
# RepoRoot depuis tests/<Module>/Private : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Translation') -Force
# InModuleScope 'Tetram.Media.Translation' : ConvertTo-CompactTranscriptJson n'est pas exportée.
# La fonction doit échouer si Get-Command ne la trouve pas : un Should -Throw seul passerait à tort.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranslation = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ModuleRootTranslation = Join-Path $script:RepoRootTranslation 'Tetram.Media.Translation'
    Import-Module -Name $script:ModuleRootTranslation -Force -ErrorAction Stop

    $script:RepresentativeTetramJson = @'
{
  "engine": "faster-whisper",
  "model": "large-v3",
  "language": "ja",
  "languageSource": "forced",
  "audioTrack": 1,
  "unexpected_root": 123,
  "segments": [
    {
      "start": 12.34,
      "end": 15.67,
      "text": "recognized text",
      "words": [
        {
          "text": "recognized",
          "start": 12.34,
          "end": 12.80,
          "probability": 0.93
        }
      ],
      "diagnostics": {
        "temperature": 0,
        "avg_logprob": -0.42,
        "compression_ratio": 1.31,
        "no_speech_prob": 0.02,
        "tokens": [50364, 1234, 5678]
      },
      "unexpected_segment": "drop me"
    }
  ]
}
'@

    $script:LegacyWhisperJson = @'
{
  "language": "ja",
  "segments": [
    {
      "start": 1.0,
      "end": 2.0,
      "text": "...",
      "avg_logprob": -0.4
    }
  ]
}
'@

    function script:Invoke-CompactTranscriptJson {
        param($InputObject)

        InModuleScope 'Tetram.Media.Translation' -Parameters @{ InputObject = $InputObject } {
            param($InputObject)
            $cmd = Get-Command -Name ConvertTo-CompactTranscriptJson -ErrorAction SilentlyContinue
            if ($null -eq $cmd) {
                throw 'ConvertTo-CompactTranscriptJson est introuvable dans le module.'
            }
            ConvertTo-CompactTranscriptJson -InputObject $InputObject
        }
    }

    function script:Get-MinimalTetramJson {
        param(
            [string] $Engine = 'faster-whisper',
            [string] $Model = 'large-v3',
            [string] $Vad,
            [string] $SegmentBody = '"start":1.0,"end":2.0,"text":"hello"'
        )

        $vadJson = if (-not [string]::IsNullOrWhiteSpace($Vad)) {
            "`n  `"vad`": `"$Vad`","
        }
        else {
            ''
        }

        return @"
{
  "engine": "$Engine",
  "model": "$Model",$vadJson
  "language": "ja",
  "languageSource": "forced",
  "audioTrack": 1,
  "segments": [
    {
      $SegmentBody
    }
  ]
}
"@
    }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Translation' -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-CompactTranscriptJson' {
    It 'conserve engine, model, language et les diagnostics aplatis du JSON Faster-Whisper' {
        $compact = Invoke-CompactTranscriptJson -InputObject $script:RepresentativeTetramJson
        $got = ConvertFrom-Json -InputObject $compact

        $got.engine | Should -Be 'faster-whisper'
        $got.model | Should -Be 'large-v3'
        $got.language | Should -Be 'ja'
        $got.PSObject.Properties.Name | Should -Not -Contain 'vad'
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

    It 'omet languageSource, audioTrack, words, diagnostics, tokens et les champs inconnus' {
        $compact = Invoke-CompactTranscriptJson -InputObject $script:RepresentativeTetramJson
        $got = ConvertFrom-Json -InputObject $compact
        $segment = @($got.segments)[0]

        $got.PSObject.Properties['languageSource'] | Should -BeNullOrEmpty
        $got.PSObject.Properties['audioTrack'] | Should -BeNullOrEmpty
        $got.PSObject.Properties['unexpected_root'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['words'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['diagnostics'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['tokens'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['unexpected_segment'] | Should -BeNullOrEmpty
        $compact | Should -Not -Match '"languageSource"'
        $compact | Should -Not -Match '"audioTrack"'
        $compact | Should -Not -Match '"diagnostics"'
        $compact | Should -Not -Match '"tokens"'
        $compact | Should -Not -Match '"words"'
        $compact | Should -Not -Match 'drop me'
        $compact | Should -Not -Match '50364'
    }

    It 'reste valide sans diagnostics et n''invente aucune métrique' {
        $json = script:Get-MinimalTetramJson
        $compact = Invoke-CompactTranscriptJson -InputObject $json
        $segment = @( (ConvertFrom-Json -InputObject $compact).segments )[0]

        $segment.text | Should -Be 'hello'
        $segment.PSObject.Properties['temperature'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['avg_logprob'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['compression_ratio'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['no_speech_prob'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['diagnostics'] | Should -BeNullOrEmpty
    }

    It 'ne copie qu''une métrique présente dans un diagnostics partiel' {
        $json = script:Get-MinimalTetramJson -SegmentBody '"start":1.0,"end":2.0,"text":"hello","diagnostics":{"avg_logprob":-0.1}'
        $compact = Invoke-CompactTranscriptJson -InputObject $json
        $segment = @( (ConvertFrom-Json -InputObject $compact).segments )[0]

        $segment.text | Should -Be 'hello'
        $segment.avg_logprob | Should -Be -0.1
        $segment.PSObject.Properties['temperature'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['compression_ratio'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['no_speech_prob'] | Should -BeNullOrEmpty
        $compact | Should -Not -Match '"diagnostics"'
    }

    It 'préserve le texte, y compris les espaces internes, et les timestamps' {
        $json = script:Get-MinimalTetramJson -SegmentBody '"start":12.34,"end":15.67,"text":"recognized  text"'
        $compact = Invoke-CompactTranscriptJson -InputObject $json
        $segment = @( (ConvertFrom-Json -InputObject $compact).segments )[0]

        $segment.start | Should -Be 12.34
        $segment.end | Should -Be 15.67
        $segment.text | Should -Be 'recognized  text'
    }

    It 'produit un JSON valide et compact' {
        $compact = Invoke-CompactTranscriptJson -InputObject $script:RepresentativeTetramJson

        { ConvertFrom-Json -InputObject $compact -ErrorAction Stop } | Should -Not -Throw
        $compact | Should -Not -Match '[\r\n]'
        $compact | Should -Match '"segments":\['
    }

    It 'accepte un objet déjà désérialisé' {
        $parsed = ConvertFrom-Json -InputObject $script:RepresentativeTetramJson
        $compact = Invoke-CompactTranscriptJson -InputObject $parsed
        $got = ConvertFrom-Json -InputObject $compact

        $got.engine | Should -Be 'faster-whisper'
        $got.model | Should -Be 'large-v3'
        $got.language | Should -Be 'ja'
        @($got.segments)[0].text | Should -Be 'recognized text'
        @($got.segments)[0].avg_logprob | Should -Be -0.42
    }

    It 'accepte un JSON Sherpa vad=silero sans inventer de diagnostic Whisper' {
        $json = script:Get-MinimalTetramJson -Engine 'sherpa-onnx' -Model 'reazon-k2-v2' -Vad 'silero' -SegmentBody '"start":12.34,"end":15.67,"text":"reazon silero"'
        $compact = Invoke-CompactTranscriptJson -InputObject $json
        $got = ConvertFrom-Json -InputObject $compact
        $segment = @($got.segments)[0]

        $got.engine | Should -Be 'sherpa-onnx'
        $got.model | Should -Be 'reazon-k2-v2'
        $got.vad | Should -Be 'silero'
        $got.language | Should -Be 'ja'
        $segment.start | Should -Be 12.34
        $segment.end | Should -Be 15.67
        $segment.text | Should -Be 'reazon silero'
        $segment.PSObject.Properties['temperature'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['avg_logprob'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['compression_ratio'] | Should -BeNullOrEmpty
        $segment.PSObject.Properties['no_speech_prob'] | Should -BeNullOrEmpty
        $compact | Should -Not -Match '"diagnostics"'
        $compact | Should -Not -Match '"words"'
        $compact | Should -Not -Match '"tokens"'
    }

    It 'accepte un JSON Sherpa vad=ten' {
        $json = script:Get-MinimalTetramJson -Engine 'sherpa-onnx' -Model 'reazon-k2-v2' -Vad 'ten'
        $got = ConvertFrom-Json -InputObject (Invoke-CompactTranscriptJson -InputObject $json)
        $got.engine | Should -Be 'sherpa-onnx'
        $got.model | Should -Be 'reazon-k2-v2'
        $got.vad | Should -Be 'ten'
    }

    It 'lève si un JSON Whisper legacy à diagnostics plats est fourni' {
        { Invoke-CompactTranscriptJson -InputObject $script:LegacyWhisperJson } |
            Should -Throw '*Tetram*'
    }

    It 'lève si les métadonnées racine Tetram manquent' {
        { Invoke-CompactTranscriptJson -InputObject '{"language":"ja","segments":[]}' } |
            Should -Throw '*Tetram*'
        { Invoke-CompactTranscriptJson -InputObject '{"engine":"faster-whisper","model":"large-v3","language":"ja","languageSource":"forced","segments":[]}' } |
            Should -Throw '*Tetram*'
        { Invoke-CompactTranscriptJson -InputObject '{"text":"x"}' } |
            Should -Throw '*Tetram*'
    }

    It 'lève si engine est inconnu' {
        $json = script:Get-MinimalTetramJson -Engine 'unknown-engine'
        { Invoke-CompactTranscriptJson -InputObject $json } |
            Should -Throw '*Tetram*'
    }

    It 'lève si Sherpa n''a pas de provenance vad' {
        $json = script:Get-MinimalTetramJson -Engine 'sherpa-onnx' -Model 'reazon-k2-v2'
        { Invoke-CompactTranscriptJson -InputObject $json } |
            Should -Throw '*Tetram*'
    }

    It 'lève si un segment n''a pas start, end ou text' {
        { Invoke-CompactTranscriptJson -InputObject (script:Get-MinimalTetramJson -SegmentBody '"start":1.0,"end":2.0') } |
            Should -Throw '*Tetram*'
        { Invoke-CompactTranscriptJson -InputObject (script:Get-MinimalTetramJson -SegmentBody '"start":1.0,"text":"x"') } |
            Should -Throw '*Tetram*'
        { Invoke-CompactTranscriptJson -InputObject (script:Get-MinimalTetramJson -SegmentBody '"end":2.0,"text":"x"') } |
            Should -Throw '*Tetram*'
    }
}
