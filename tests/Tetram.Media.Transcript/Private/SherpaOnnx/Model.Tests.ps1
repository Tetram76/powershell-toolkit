# Étendre la suite autour du contrat modèle Sherpa (fichiers, langue, arguments ASR).
#
# Tout passe par InModuleScope 'Tetram.Media.Transcript' : ces fonctions ne sont pas exportées.
# $TestDrive n'est pas visible depuis InModuleScope : le passer via -Parameters @{ Work = $TestDrive }.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootTranscript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
    $script:ModuleRootTranscript = Join-Path $script:RepoRootTranscript 'Tetram.Media.Transcript'
    Import-Module -Name $script:ModuleRootTranscript -Force -ErrorAction Stop

    $module = Get-Module -Name 'Tetram.Media.Transcript'
    . $module {
        . (Join-Path $script:TranscriptPrivateRoot 'SherpaOnnx.ps1')
    }

    function script:New-SherpaModelTree {
        param(
            [Parameter(Mandatory)] [string] $Root,
            [Parameter(Mandatory)] [string] $Model,
            [Parameter(Mandatory)] [string[]] $Files
        )
        $modelDir = Join-Path $Root 'models' $Model
        New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
        foreach ($name in $Files) {
            Set-Content -LiteralPath (Join-Path $modelDir $name) -Value 'stub'
        }
        $modelDir
    }
}

AfterAll {
    Remove-Module -Name 'Tetram.Media.Transcript' -Force -ErrorAction SilentlyContinue
}
Describe 'Get-SherpaOnnxModelFiles' {
    It 'trouve tokens/encoder/decoder/joiner dans models/reazon-k2-v2' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'fp32-only'
            $modelDir = Join-Path $root 'models' 'reazon-k2-v2'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            foreach ($name in @('tokens.txt', 'encoder-epoch-99-avg-1.onnx', 'decoder-epoch-99-avg-1.onnx', 'joiner-epoch-99-avg-1.onnx')) {
                Set-Content -LiteralPath (Join-Path $modelDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                $got = Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2'
                $got.Tokens | Should -Be (Join-Path $modelDir 'tokens.txt')
                $got.Encoder | Should -Be (Join-Path $modelDir 'encoder-epoch-99-avg-1.onnx')
                $got.Decoder | Should -Be (Join-Path $modelDir 'decoder-epoch-99-avg-1.onnx')
                $got.Joiner | Should -Be (Join-Path $modelDir 'joiner-epoch-99-avg-1.onnx')
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'suit la recette Reazon INT8 : encoder/joiner int8, decoder FP32' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'reazon-int8-recipe'
            $modelDir = Join-Path $root 'models' 'reazon-k2-v2'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            foreach ($name in @(
                    'tokens.txt',
                    'encoder-epoch-99-avg-1.onnx',
                    'encoder-epoch-99-avg-1.int8.onnx',
                    'decoder-epoch-99-avg-1.onnx',
                    'decoder-epoch-99-avg-1.int8.onnx',
                    'joiner-epoch-99-avg-1.onnx',
                    'joiner-epoch-99-avg-1.int8.onnx'
                )) {
                Set-Content -LiteralPath (Join-Path $modelDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                $got = Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2'
                $got.Encoder | Should -Be (Join-Path $modelDir 'encoder-epoch-99-avg-1.int8.onnx')
                $got.Decoder | Should -Be (Join-Path $modelDir 'decoder-epoch-99-avg-1.onnx')
                $got.Joiner | Should -Be (Join-Path $modelDir 'joiner-epoch-99-avg-1.int8.onnx')
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'prend le decoder int8 seulement s''il n''y a pas de FP32' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'int8-decoder-only'
            $modelDir = Join-Path $root 'models' 'reazon-k2-v2'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            foreach ($name in @(
                    'tokens.txt',
                    'encoder-epoch-99-avg-1.int8.onnx',
                    'decoder-epoch-99-avg-1.int8.onnx',
                    'joiner-epoch-99-avg-1.int8.onnx'
                )) {
                Set-Content -LiteralPath (Join-Path $modelDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                $got = Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2'
                $got.Decoder | Should -Be (Join-Path $modelDir 'decoder-epoch-99-avg-1.int8.onnx')
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'lève si models/reazon-k2-v2 est absent' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = Join-Path $Work 'vide'
                New-Item -ItemType Directory -Path $script:SherpaOnnxRoot -Force | Out-Null
                { Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2' } | Should -Throw '*models*reazon-k2-v2*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'ignore un dossier homonyme à la racine SherpaOnnx' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'legacy-racine'
            $legacyDir = Join-Path $root 'reazon-k2-v2'
            New-Item -ItemType Directory -Path $legacyDir -Force | Out-Null
            foreach ($name in @('tokens.txt', 'encoder.onnx', 'decoder.onnx', 'joiner.onnx')) {
                Set-Content -LiteralPath (Join-Path $legacyDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                { Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2' } | Should -Throw '*models*reazon-k2-v2*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'ignore un autre sous-dossier de models/' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'autre-modele'
            $otherDir = Join-Path $root 'models' 'sherpa-onnx-zipformer-en'
            New-Item -ItemType Directory -Path $otherDir -Force | Out-Null
            foreach ($name in @('tokens.txt', 'encoder.onnx', 'decoder.onnx', 'joiner.onnx')) {
                Set-Content -LiteralPath (Join-Path $otherDir $name) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                { Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2' } | Should -Throw '*models*reazon-k2-v2*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'lève si models/reazon-k2-v2 est incomplet même si un autre modèle l''est' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'incomplet-plus-autre'
            $modelDir = Join-Path $root 'models' 'reazon-k2-v2'
            $otherDir = Join-Path $root 'models' 'sherpa-onnx-zipformer-en'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            New-Item -ItemType Directory -Path $otherDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $modelDir 'tokens.txt') -Value 'stub'
            foreach ($file in @('tokens.txt', 'encoder.onnx', 'decoder.onnx', 'joiner.onnx')) {
                Set-Content -LiteralPath (Join-Path $otherDir $file) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                { Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2' } | Should -Throw '*incomplet*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'prend models/reazon-k2-v2 et ignore un autre sous-dossier de models/' {
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Work = "$TestDrive" } {
            param($Work)
            $root = Join-Path $Work 'deux-modeles'
            $modelDir = Join-Path $root 'models' 'reazon-k2-v2'
            $otherDir = Join-Path $root 'models' 'sherpa-onnx-zipformer-en'
            New-Item -ItemType Directory -Path $modelDir -Force | Out-Null
            New-Item -ItemType Directory -Path $otherDir -Force | Out-Null
            foreach ($file in @('tokens.txt', 'encoder.onnx', 'decoder.onnx', 'joiner.onnx')) {
                Set-Content -LiteralPath (Join-Path $modelDir $file) -Value 'stub'
                Set-Content -LiteralPath (Join-Path $otherDir $file) -Value 'stub'
            }
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $root
                $got = Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2'
                $got.Tokens | Should -Be (Join-Path $modelDir 'tokens.txt')
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'trouve tokens.txt et model.int8.onnx pour <Model>' -TestCases @(
        @{ Model = 'parakeet-0.6b-ja'; Property = 'NemoCtcModel' }
        @{ Model = 'sensevoice-small'; Property = 'SenseVoiceModel' }
    ) {
        param($Model, $Property)
        $root = Join-Path $TestDrive "single-file-$Model"
        $modelDir = script:New-SherpaModelTree -Root $root -Model $Model -Files @('tokens.txt', 'model.int8.onnx')
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{
            Root     = $root
            Model    = $Model
            Property = $Property
            ModelDir = $modelDir
        } {
            param($Root, $Model, $Property, $ModelDir)
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $Root
                $got = Get-SherpaOnnxModelFiles -Model $Model
                $got.Tokens | Should -Be (Join-Path $ModelDir 'tokens.txt')
                $got.$Property | Should -Be (Join-Path $ModelDir 'model.int8.onnx')
                $got.PSObject.Properties.Name | Should -Not -Contain 'Encoder'
                $got.PSObject.Properties.Name | Should -Not -Contain 'Decoder'
                $got.PSObject.Properties.Name | Should -Not -Contain 'Joiner'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'lève si tokens.txt manque pour <Model>' -TestCases @(
        @{ Model = 'parakeet-0.6b-ja' }
        @{ Model = 'sensevoice-small' }
    ) {
        param($Model)
        $root = Join-Path $TestDrive "sans-tokens-$Model"
        script:New-SherpaModelTree -Root $root -Model $Model -Files @('model.int8.onnx') | Out-Null
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Root = $root; Model = $Model } {
            param($Root, $Model)
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $Root
                { Get-SherpaOnnxModelFiles -Model $Model } | Should -Throw '*incomplet*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'lève si model.int8.onnx manque pour <Model>' -TestCases @(
        @{ Model = 'parakeet-0.6b-ja' }
        @{ Model = 'sensevoice-small' }
    ) {
        param($Model)
        $root = Join-Path $TestDrive "sans-onnx-$Model"
        script:New-SherpaModelTree -Root $root -Model $Model -Files @('tokens.txt') | Out-Null
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Root = $root; Model = $Model } {
            param($Root, $Model)
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $Root
                { Get-SherpaOnnxModelFiles -Model $Model } | Should -Throw '*incomplet*'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }

    It 'ne prend pas les fichiers d''un autre dossier modèle' {
        $root = Join-Path $TestDrive 'isolation-dossiers'
        script:New-SherpaModelTree -Root $root -Model 'reazon-k2-v2' -Files @(
            'tokens.txt', 'encoder.onnx', 'decoder.onnx', 'joiner.onnx'
        ) | Out-Null
        script:New-SherpaModelTree -Root $root -Model 'parakeet-0.6b-ja' -Files @(
            'tokens.txt', 'model.int8.onnx'
        ) | Out-Null
        InModuleScope 'Tetram.Media.Transcript' -Parameters @{ Root = $root } {
            param($Root)
            $saved = $script:SherpaOnnxRoot
            try {
                $script:SherpaOnnxRoot = $Root
                $parakeet = Get-SherpaOnnxModelFiles -Model 'parakeet-0.6b-ja'
                $reazon = Get-SherpaOnnxModelFiles -Model 'reazon-k2-v2'
                $parakeet.Tokens | Should -Match 'parakeet-0\.6b-ja'
                $parakeet.NemoCtcModel | Should -Match 'parakeet-0\.6b-ja'
                $reazon.Tokens | Should -Match 'reazon-k2-v2'
                $reazon.Encoder | Should -Match 'reazon-k2-v2'
            }
            finally {
                $script:SherpaOnnxRoot = $saved
            }
        }
    }
}

Describe 'Get-SherpaOnnxAsrArguments' {
    It 'Reazon : tokens/encoder/decoder/joiner, sans NeMo ni SenseVoice ni num-threads' {
        InModuleScope 'Tetram.Media.Transcript' {
            $files = [pscustomobject]@{
                Tokens  = Join-Path 'm' 'tokens.txt'
                Encoder = Join-Path 'm' 'encoder.onnx'
                Decoder = Join-Path 'm' 'decoder.onnx'
                Joiner  = Join-Path 'm' 'joiner.onnx'
            }
            $got = Get-SherpaOnnxAsrArguments -Model 'reazon-k2-v2' -ModelFiles $files
            $got | Should -Be @(
                "--tokens=$($files.Tokens)"
                "--encoder=$($files.Encoder)"
                "--decoder=$($files.Decoder)"
                "--joiner=$($files.Joiner)"
            )
            ($got -join ' ') | Should -Not -Match 'nemo-ctc-model'
            ($got -join ' ') | Should -Not -Match 'sense-voice'
            ($got -join ' ') | Should -Not -Match 'num-threads'
        }
    }

    It 'Parakeet : tokens + nemo-ctc-model, sans flags Reazon ni SenseVoice' {
        InModuleScope 'Tetram.Media.Transcript' {
            $files = [pscustomobject]@{
                Tokens       = Join-Path 'p' 'tokens.txt'
                NemoCtcModel = Join-Path 'p' 'model.int8.onnx'
            }
            $got = Get-SherpaOnnxAsrArguments -Model 'parakeet-0.6b-ja' -ModelFiles $files
            $got | Should -Be @(
                "--tokens=$($files.Tokens)"
                "--nemo-ctc-model=$($files.NemoCtcModel)"
            )
            ($got -join ' ') | Should -Not -Match '--encoder'
            ($got -join ' ') | Should -Not -Match '--decoder'
            ($got -join ' ') | Should -Not -Match '--joiner'
            ($got -join ' ') | Should -Not -Match 'sense-voice'
            ($got -join ' ') | Should -Not -Match 'num-threads'
        }
    }

    It 'SenseVoice : tokens + sense-voice-model + language=ja même sans UseLanguage' {
        InModuleScope 'Tetram.Media.Transcript' {
            $files = [pscustomobject]@{
                Tokens          = Join-Path 's' 'tokens.txt'
                SenseVoiceModel = Join-Path 's' 'model.int8.onnx'
            }
            $got = Get-SherpaOnnxAsrArguments -Model 'sensevoice-small' -ModelFiles $files
            $got | Should -Be @(
                "--tokens=$($files.Tokens)"
                "--sense-voice-model=$($files.SenseVoiceModel)"
                '--sense-voice-language=ja'
            )
            ($got -join ' ') | Should -Not -Match '--encoder'
            ($got -join ' ') | Should -Not -Match '--decoder'
            ($got -join ' ') | Should -Not -Match '--joiner'
            ($got -join ' ') | Should -Not -Match 'nemo-ctc-model'
            ($got -join ' ') | Should -Not -Match 'num-threads'
        }
    }
}
