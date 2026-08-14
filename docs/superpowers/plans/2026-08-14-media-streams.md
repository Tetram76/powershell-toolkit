# Tetram.Media.Streams — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Module `Tetram.Media.Streams` : `Split-MediaStream` / `Merge-MediaStream` pour éditer des pistes hors d’un MKV puis réinjecter un MKV équivalent (replace / add / keep).

**Architecture:** Manifeste racine + psm1 qui dot-source `Tetram.Media.Streams.Private\*.ps1` (comme Reencode). NestedModules = `Tetram.Common` + `Tetram.Media.FFmpeg`. Grammaire de noms et matching testables sans binaire FFmpeg ; les commandes publiques catch `Get-FFmpegPath` → `Write-ErrorLog` → return.

**Tech Stack:** PowerShell 7+, Pester 5, FFmpeg/ffprobe via `Tetram.Media.FFmpeg`, aide PlatyPS (`tools/New-HelpMarkdown.ps1` + `tools/New-HelpMaml.ps1`).

**Spec:** `docs/superpowers/specs/2026-08-14-media-streams-design.md`

## Global Constraints

- PowerShell 7+ / Core ; `Set-StrictMode -Version 3.0`.
- Entrée des deux commandes : un fichier `.mkv` existant (insensible à la casse).
- FFmpeg `-c copy` uniquement ; pas de mkvmerge, pas de manifeste JSON.
- Merge = toujours update du MKV (pas de mux sidecars-seuls).
- `Show-CommandLine` **avant** `ShouldProcess` (y compris `-WhatIf`).
- Erreurs publiques : `Write-ErrorLog` puis return/continue, pas de throw vers l’appelant.
- Pas de `Write-InfoLog -Force`.
- Commentaires code : pourquoi, pas quoi (`comments-why-not-what`).
- Tests `*Tests.ps1` : commentaire d’en-tête d’onboarding autorisé.
- Tag Pester `Integration` pour tout vrai FFmpeg (exclu CI).
- Chaque tâche TDD : test rouge → implémentation → test vert → **un commit** (writing-plans).
- Commits fréquents : un par tâche, après tests verts.

---

## File map

| Fichier | Responsabilité |
|---|---|
| `Tetram.Media.Streams.psd1` | Manifeste v1.0.0, NestedModules Common + FFmpeg, export Split/Merge |
| `Tetram.Media.Streams.psm1` | Dot-source privé + `Split-MediaStream` + `Merge-MediaStream` |
| `Tetram.Media.Streams.Private/Naming.ps1` | Flags, allowlists, `ConvertTo-StreamFileName` / `ConvertFrom-StreamFileName`, clés |
| `Tetram.Media.Streams.Private/CodecMap.ps1` | `Get-ElementaryExtension` |
| `Tetram.Media.Streams.Private/Descriptors.ps1` | Probe JSON → descripteurs + index de collision |
| `Tetram.Media.Streams.Private/Matching.ps1` | Collecte sidecars, matching replace/add/keep, args FFmpeg merge |
| `Tetram.Media.Streams.Private/Invoke.ps1` | `Invoke-StreamsFFmpeg` |
| `tests/Tetram.Media.Streams.Tests.ps1` | Manifeste, exports, MKV, FFmpeg absent, WhatIf, Force, RemoveSidecars |
| `tests/Tetram.Media.Streams.Private/Naming.Tests.ps1` | Grammaire |
| `tests/Tetram.Media.Streams.Private/CodecMap.Tests.ps1` | Carte codec |
| `tests/Tetram.Media.Streams.Private/Descriptors.Tests.ps1` | Collision source + filtres |
| `tests/Tetram.Media.Streams.Private/Matching.Tests.ps1` | replace/add/keep + args |
| `docs/help/Tetram.Media.Streams/*.md` | Aide PlatyPS fr-FR |
| `fr-FR/Tetram.Media.Streams-Help.xml` | MAML |

### Contrat descripteur (`pscustomobject`)

Propriétés **exactes** (toutes les tâches suivantes s’y conforment) :

| Propriété | Type | Sens |
|---|---|---|
| `Class` | `string` | `Video`, `Audio`, `Subtitle`, `Cover`, `Attachment`, `Chapter` |
| `StreamIndex` | `int` ou `$null` | index ffprobe global ; `$null` pour Chapter |
| `Language` | `string` | code tel quel, `''` si und/unk/absent |
| `Flags` | `string[]` | jetons fichier canoniques présents, **ordre table spec** |
| `Extension` | `string` | avec le point (`.srt`) |
| `CollisionIndex` | `int` | ≥ 1 ; 1 n’apparaît pas dans le nom |
| `Codec` | `string` | `codec_name` ffprobe |
| `AttachmentName` | `string` | nom original (`''` sinon) |
| `AttachmentNameSanitized` | `string` | `''` sinon |
| `MimeType` | `string` | `''` sinon |
| `CollisionKey` | `string` | clé stable pour matching |

Parse sidecar (`ConvertFrom-StreamFileName`) : même forme, `StreamIndex`/`Codec`/`MimeType`/`AttachmentName` vides si inconnus.

---

### Task 1: Scaffold manifeste + module

**Files:**
- Create: `Tetram.Media.Streams.psd1`
- Create: `Tetram.Media.Streams.psm1`
- Create: `Tetram.Media.Streams.Private/Naming.ps1` (StrictMode seulement)
- Create: `Tetram.Media.Streams.Private/CodecMap.ps1`
- Create: `Tetram.Media.Streams.Private/Descriptors.ps1`
- Create: `Tetram.Media.Streams.Private/Matching.ps1`
- Create: `Tetram.Media.Streams.Private/Invoke.ps1`
- Test: `tests/Tetram.Media.Streams.Tests.ps1`

**Interfaces:**
- Produces: module importable ; `Split-MediaStream`, `Merge-MediaStream` exportés (corps stub `return`)

- [ ] **Step 1: Écrire le test manifeste / exports (échoue)**

Créer `tests/Tetram.Media.Streams.Tests.ps1` :

```powershell
# Étendre la suite autour du module SUD Tetram.Media.Streams (split/merge MKV).
#
# RepoRoot depuis tests/ racine : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
# Manifeste : Tetram.Media.Streams.psd1 — Test-ModuleManifest puis Import-Module -Force
# Privé : InModuleScope 'Tetram.Media.Streams' ; mocks Get-FFmpegPath / Write-ErrorLog / Show-CommandLine
# $TestDrive pour sidecars ; tag Integration seulement si vrai ffmpeg.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRootStreams = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestStreams = Join-Path $script:RepoRootStreams 'Tetram.Media.Streams.psd1'
}

Describe 'Tetram.Media.Streams manifest' {
    It 'passe Test-ModuleManifest' {
        { Test-ModuleManifest -Path $script:ManifestStreams } | Should -Not -Throw
    }
}

Describe 'Tetram.Media.Streams exports' {
    BeforeAll {
        Import-Module -Name $script:ManifestStreams -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
    }

    It 'exporte uniquement Split-MediaStream et Merge-MediaStream' {
        $names = @(Get-Command -Module 'Tetram.Media.Streams' | Select-Object -ExpandProperty Name | Sort-Object)
        $names | Should -Be @('Merge-MediaStream', 'Split-MediaStream')
    }
}
```

- [ ] **Step 2: Exécuter — doit échouer**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Tests.ps1' -Output Detailed"`  
Expected: FAIL — manifeste introuvable

- [ ] **Step 3: Créer manifeste, psm1, fichiers privés vides, stubs**

`Tetram.Media.Streams.psd1` :

```powershell
@{
    RootModule = 'Tetram.Media.Streams.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'e7d4a1c8-3b92-4f6e-a1d5-8c9b0e2f4a71'
    Author = 'TRL'
    CompanyName = 'Tetram'
    Description = 'Extraction et réinjection de flux MKV (sidecars nommés, update in-place).'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    RequiredModules = @()
    RequiredAssemblies = @()
    NestedModules = @(
        '.\Utils\Tetram.Common',
        '.\Utils\Tetram.Media.FFmpeg'
    )
    FunctionsToExport = @(
        'Split-MediaStream'
        'Merge-MediaStream'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('ffmpeg', 'mkv', 'media', 'demux', 'mux', 'ps7')
            ReleaseNotes = @'
- 1.0.0 : Split-MediaStream / Merge-MediaStream (round-trip MKV, WhatIf/Force).
'@
        }
    }
}
```

Chaque `Tetram.Media.Streams.Private/*.ps1` :

```powershell
Set-StrictMode -Version 3.0
```

`Tetram.Media.Streams.psm1` :

```powershell
Set-StrictMode -Version 3.0

$PrivateRoot = Join-Path $PSScriptRoot 'Tetram.Media.Streams.Private'
. (Join-Path $PrivateRoot 'Naming.ps1')
. (Join-Path $PrivateRoot 'CodecMap.ps1')
. (Join-Path $PrivateRoot 'Descriptors.ps1')
. (Join-Path $PrivateRoot 'Matching.ps1')
. (Join-Path $PrivateRoot 'Invoke.ps1')

function Split-MediaStream {
    <#
.EXTERNALHELP Tetram.Media.Streams-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $LiteralPath,
        [ValidateSet('Video', 'Audio', 'Subtitle', 'Attachment', 'Chapter')]
        [string[]] $StreamType,
        [string[]] $Language,
        [switch] $Force
    )
}

function Merge-MediaStream {
    <#
.EXTERNALHELP Tetram.Media.Streams-Help.xml
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $LiteralPath,
        [string] $Destination,
        [switch] $RemoveSidecars,
        [switch] $Force
    )
}

Export-ModuleMember -Function Split-MediaStream, Merge-MediaStream
```

- [ ] **Step 4: Exécuter — doit passer**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Tests.ps1' -Output Detailed"`  
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Streams.psd1 Tetram.Media.Streams.psm1 Tetram.Media.Streams.Private/Naming.ps1 Tetram.Media.Streams.Private/CodecMap.ps1 Tetram.Media.Streams.Private/Descriptors.ps1 Tetram.Media.Streams.Private/Matching.ps1 Tetram.Media.Streams.Private/Invoke.ps1 tests/Tetram.Media.Streams.Tests.ps1
git commit -m "$(cat <<'EOF'
feat(streams): scaffold du module Split/Merge

EOF
)"
```

---

### Task 2: Grammaire des noms

**Files:**
- Modify: `Tetram.Media.Streams.Private/Naming.ps1`
- Test: `tests/Tetram.Media.Streams.Private/Naming.Tests.ps1`

**Interfaces:**
- Produces:
  - `$script:StreamsDispositionFlags` : tableau **ordonné** de `@{ FileToken = '...'; ProbeName = '...'; FfmpegName = '...' }` (7 lignes spec)
  - `$script:StreamsContainerExtensions` : `.mkv`, `.mp4`, `.avi`, `.mov`, `.webm`, `.m4v`, `.wmv`, `.flv`, `.mpeg`, `.mpg`, `.ts`
  - `Get-StreamCollisionKey([pscustomobject]$Descriptor) → [string]`
  - `ConvertTo-StreamFileName -Basename <string> -Descriptor <pscustomobject> → [string]` (nom de fichier, pas chemin)
  - `ConvertFrom-StreamFileName -Basename <string> -FileName <string> → [pscustomobject]|$null`

- [ ] **Step 1: Tests grammaire (échouent)**

`tests/Tetram.Media.Streams.Private/Naming.Tests.ps1` — en-tête onboarding (RepoRoot deux `..`, Import manifeste, `InModuleScope 'Tetram.Media.Streams'`).

Cas :

```powershell
BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams.psd1') -Force -ErrorAction Stop
}
AfterAll { Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue }

Describe 'ConvertTo / ConvertFrom-StreamFileName' {
    It 'round-trip eng + forced + commentary + collision 2' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{
                Class = 'Subtitle'; Language = 'eng'
                Flags = @('forced', 'commentary'); Extension = '.srt'
                CollisionIndex = 2; AttachmentNameSanitized = ''
            }
            $name = ConvertTo-StreamFileName -Basename 'film' -Descriptor $d
            $name | Should -Be 'film.eng.forced.commentary.2.srt'
            $p = ConvertFrom-StreamFileName -Basename 'film' -FileName $name
            $p.Language | Should -Be 'eng'
            $p.Flags | Should -Be @('forced', 'commentary')
            $p.CollisionIndex | Should -Be 2
            $p.Class | Should -Be 'Subtitle'
        }
    }
    It 'omet la langue und / vide' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{
                Class = 'Audio'; Language = ''; Flags = @(); Extension = '.aac'
                CollisionIndex = 1; AttachmentNameSanitized = ''
            }
            ConvertTo-StreamFileName -Basename 'film' -Descriptor $d | Should -Be 'film.aac'
        }
    }
    It 'écrit les flags dans l''ordre spec même si Flags est dans le désordre' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{
                Class = 'Audio'; Language = 'eng'
                Flags = @('dub', 'default'); Extension = '.aac'
                CollisionIndex = 1; AttachmentNameSanitized = ''
            }
            ConvertTo-StreamFileName -Basename 'film' -Descriptor $d | Should -Be 'film.eng.default.dub.aac'
        }
    }
    It 'lit comment/comments comme commentary' {
        InModuleScope 'Tetram.Media.Streams' {
            $p = ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.eng.comments.aac'
            $p.Flags | Should -Be @('commentary')
        }
    }
    It 'ne traite pas dub comme langue' {
        InModuleScope 'Tetram.Media.Streams' {
            $p = ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.dub.aac'
            $p.Language | Should -Be ''
            $p.Flags | Should -Be @('dub')
        }
    }
    It 'cover et chapters exigent le jeton de classe' {
        InModuleScope 'Tetram.Media.Streams' {
            (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.cover.jpg').Class | Should -Be 'Cover'
            ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.jpg' | Should -BeNullOrEmpty
            (ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.chapters.ffmeta').Class | Should -Be 'Chapter'
            ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.ffmeta' | Should -BeNullOrEmpty
        }
    }
    It 'ignore les conteneurs' {
        InModuleScope 'Tetram.Media.Streams' {
            ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.mkv' | Should -BeNullOrEmpty
            ConvertFrom-StreamFileName -Basename 'film' -FileName 'film.mp4' | Should -BeNullOrEmpty
        }
    }
    It 'parse une police sanitisée' {
        InModuleScope 'Tetram.Media.Streams' {
            $d = [pscustomobject]@{
                Class = 'Attachment'; Language = ''; Flags = @()
                Extension = '.ttf'; CollisionIndex = 1
                AttachmentNameSanitized = 'Arial_Bold'
            }
            $name = ConvertTo-StreamFileName -Basename 'film' -Descriptor $d
            $name | Should -Be 'film.Arial_Bold.ttf'
            $p = ConvertFrom-StreamFileName -Basename 'film' -FileName $name
            $p.Class | Should -Be 'Attachment'
            $p.AttachmentNameSanitized | Should -Be 'Arial_Bold'
        }
    }
}
```

- [ ] **Step 2: Exécuter — FAIL** (`ConvertTo-StreamFileName` introuvable)

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Private/Naming.Tests.ps1' -Output Detailed"`

- [ ] **Step 3: Remplacer `Tetram.Media.Streams.Private/Naming.ps1` par le contenu suivant**

```powershell
Set-StrictMode -Version 3.0

$script:StreamsDispositionFlags = @(
    @{ FileToken = 'default'; ProbeName = 'default'; FfmpegName = 'default' }
    @{ FileToken = 'forced'; ProbeName = 'forced'; FfmpegName = 'forced' }
    @{ FileToken = 'commentary'; ProbeName = 'comment'; FfmpegName = 'comment' }
    @{ FileToken = 'original'; ProbeName = 'original'; FfmpegName = 'original' }
    @{ FileToken = 'dub'; ProbeName = 'dub'; FfmpegName = 'dub' }
    @{ FileToken = 'hearing_impaired'; ProbeName = 'hearing_impaired'; FfmpegName = 'hearing_impaired' }
    @{ FileToken = 'visual_impaired'; ProbeName = 'visual_impaired'; FfmpegName = 'visual_impaired' }
)

$script:StreamsFlagAlias = @{
    'comment' = 'commentary'
    'comments' = 'commentary'
}

$script:StreamsContainerExtensions = @(
    '.mkv', '.mp4', '.avi', '.mov', '.webm', '.m4v', '.wmv', '.flv', '.mpeg', '.mpg', '.ts'
)

$script:StreamsExtClass = @{
    '.h264' = 'Video'; '.hevc' = 'Video'; '.ivf' = 'Video'; '.m2v' = 'Video'; '.vc1' = 'Video'
    '.aac' = 'Audio'; '.ac3' = 'Audio'; '.eac3' = 'Audio'; '.dts' = 'Audio'; '.thd' = 'Audio'
    '.flac' = 'Audio'; '.opus' = 'Audio'; '.mp3' = 'Audio'; '.mp2' = 'Audio'; '.ogg' = 'Audio'; '.wav' = 'Audio'
    '.srt' = 'Subtitle'; '.ass' = 'Subtitle'; '.ssa' = 'Subtitle'; '.vtt' = 'Subtitle'; '.sup' = 'Subtitle'
    '.jpg' = 'Cover'; '.jpeg' = 'Cover'; '.png' = 'Cover'
    '.ttf' = 'Attachment'; '.otf' = 'Attachment'; '.ttc' = 'Attachment'
    '.woff' = 'Attachment'; '.woff2' = 'Attachment'; '.bin' = 'Attachment'
    '.ffmeta' = 'Chapter'
}

function Get-StreamsOrderedFlags {
    param([string[]] $Flags)
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @($Flags)) {
        if ($f) { [void]$set.Add($f) }
    }
    $out = @()
    foreach ($row in $script:StreamsDispositionFlags) {
        if ($set.Contains([string]$row.FileToken)) { $out += [string]$row.FileToken }
    }
    return $out
}

function Get-StreamCollisionKey {
    param([Parameter(Mandatory)][pscustomobject] $Descriptor)
    $ext = ([string]$Descriptor.Extension).ToLowerInvariant()
    switch ($Descriptor.Class) {
        'Cover' { return "Cover||$ext" }
        'Attachment' { return "Attachment|$($Descriptor.AttachmentNameSanitized)|$ext" }
        'Chapter' { return 'Chapter' }
        default {
            $lang = if ($Descriptor.Language) { ([string]$Descriptor.Language).ToLowerInvariant() } else { '' }
            $flags = (Get-StreamsOrderedFlags $Descriptor.Flags) -join ','
            return "$($Descriptor.Class)|$lang|$flags|$ext"
        }
    }
}

function New-StreamDescriptorObject {
    param(
        [string] $Class,
        [string] $Language = '',
        [string[]] $Flags = @(),
        [string] $Extension,
        [int] $CollisionIndex = 1,
        [string] $AttachmentNameSanitized = '',
        $StreamIndex = $null,
        [string] $Codec = '',
        [string] $AttachmentName = '',
        [string] $MimeType = ''
    )
    $d = [pscustomobject]@{
        Class = $Class
        StreamIndex = $StreamIndex
        Language = $Language
        Flags = @(Get-StreamsOrderedFlags $Flags)
        Extension = $Extension
        CollisionIndex = $CollisionIndex
        Codec = $Codec
        AttachmentName = $AttachmentName
        AttachmentNameSanitized = $AttachmentNameSanitized
        MimeType = $MimeType
        CollisionKey = ''
    }
    $d.CollisionKey = Get-StreamCollisionKey $d
    return $d
}

function ConvertTo-StreamFileName {
    param(
        [Parameter(Mandatory)][string] $Basename,
        [Parameter(Mandatory)][pscustomobject] $Descriptor
    )
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($Basename)
    switch ($Descriptor.Class) {
        'Cover' {
            $parts.Add('cover')
            if ([int]$Descriptor.CollisionIndex -ge 2) { $parts.Add([string]$Descriptor.CollisionIndex) }
        }
        'Chapter' { $parts.Add('chapters') }
        'Attachment' {
            if ($Descriptor.AttachmentNameSanitized) { $parts.Add([string]$Descriptor.AttachmentNameSanitized) }
            if ([int]$Descriptor.CollisionIndex -ge 2) { $parts.Add([string]$Descriptor.CollisionIndex) }
        }
        default {
            if ($Descriptor.Language) { $parts.Add([string]$Descriptor.Language) }
            foreach ($f in Get-StreamsOrderedFlags $Descriptor.Flags) { $parts.Add($f) }
            if ([int]$Descriptor.CollisionIndex -ge 2) { $parts.Add([string]$Descriptor.CollisionIndex) }
        }
    }
    return ($parts -join '.') + $Descriptor.Extension
}

function ConvertFrom-StreamFileName {
    param(
        [Parameter(Mandatory)][string] $Basename,
        [Parameter(Mandatory)][string] $FileName
    )
    $name = [IO.Path]::GetFileName($FileName)
    $ext = [IO.Path]::GetExtension($name)
    if (-not $ext) { return $null }
    $extLower = $ext.ToLowerInvariant()
    if ($script:StreamsContainerExtensions -contains $extLower) { return $null }
    if (-not $script:StreamsExtClass.ContainsKey($extLower)) { return $null }
    $prefix = $Basename + '.'
    if ($name.Length -le $prefix.Length -or -not $name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    $stem = $name.Substring(0, $name.Length - $ext.Length)
    $rest = $stem.Substring($Basename.Length)
    if ($rest.StartsWith('.')) { $rest = $rest.Substring(1) }
    $tokens = @()
    if ($rest) { $tokens = @($rest.Split('.', [StringSplitOptions]::RemoveEmptyEntries)) }

    $classHint = $script:StreamsExtClass[$extLower]
    $hasCover = $false
    $hasChapters = $false
    $flags = @()
    $language = ''
    $collision = 1
    $attachParts = @()
    $flagLookup = @{}
    foreach ($row in $script:StreamsDispositionFlags) { $flagLookup[[string]$row.FileToken] = [string]$row.FileToken }
    foreach ($alias in $script:StreamsFlagAlias.Keys) { $flagLookup[$alias] = [string]$script:StreamsFlagAlias[$alias] }

    foreach ($tok in $tokens) {
        $low = $tok.ToLowerInvariant()
        if ($low -eq 'cover') { $hasCover = $true; continue }
        if ($low -eq 'chapters') { $hasChapters = $true; continue }
        if ($flagLookup.ContainsKey($low)) { $flags += $flagLookup[$low]; continue }
        $n = 0
        if ([int]::TryParse($tok, [ref]$n) -and $n -ge 2) { $collision = $n; continue }
        if ($low -in @('und', 'unk')) { continue }
        if ($classHint -in @('Video', 'Audio', 'Subtitle') -and $tok.Length -in 2, 3 -and $tok -match '^[A-Za-z]{2,3}$') {
            $language = $tok
            continue
        }
        $attachParts += $tok
    }

    if ($extLower -eq '.ffmeta') {
        if (-not $hasChapters) { return $null }
        return New-StreamDescriptorObject -Class 'Chapter' -Extension '.ffmeta' -CollisionIndex 1
    }
    if ($classHint -eq 'Cover') {
        if (-not $hasCover) { return $null }
        return New-StreamDescriptorObject -Class 'Cover' -Extension $extLower -CollisionIndex $collision
    }
    if ($classHint -eq 'Attachment') {
        $san = $attachParts -join '.'
        return New-StreamDescriptorObject -Class 'Attachment' -Extension $extLower -CollisionIndex $collision -AttachmentNameSanitized $san
    }
    return New-StreamDescriptorObject -Class $classHint -Language $language -Flags $flags -Extension $extLower -CollisionIndex $collision
}

function Get-FfmpegDispositionValue {
    param([string[]] $Flags)
    $ordered = Get-StreamsOrderedFlags $Flags
    if ($ordered.Count -eq 0) { return '0' }
    $names = foreach ($tok in $ordered) {
        ($script:StreamsDispositionFlags | Where-Object { $_.FileToken -eq $tok } | Select-Object -First 1).FfmpegName
    }
    return ($names -join '+')
}
```

- [ ] **Step 4: Exécuter — PASS**

Run: même commande Step 2. Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Streams.Private/Naming.ps1 tests/Tetram.Media.Streams.Private/Naming.Tests.ps1
git commit -m "$(cat <<'EOF'
feat(streams): grammaire des noms de sidecars

EOF
)"
```

---

### Task 3: Carte codec → extension

**Files:**
- Modify: `Tetram.Media.Streams.Private/CodecMap.ps1`
- Test: `tests/Tetram.Media.Streams.Private/CodecMap.Tests.ps1`

**Interfaces:**
- Consumes: classes de `Naming.ps1` (extensions)
- Produces: `Get-ElementaryExtension -CodecName <string> -CodecType <string> -AttachedPic <bool> → [pscustomobject]@{ Class; Extension } | $null`

- [ ] **Step 1: Écrire `tests/Tetram.Media.Streams.Private/CodecMap.Tests.ps1` (échoue)**

```powershell
# Étendre la suite autour de CodecMap.ps1 (codec ffprobe → extension/classe).
#
# RepoRoot : (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module (Join-Path $RepoRoot 'Tetram.Media.Streams.psd1') -Force
# InModuleScope 'Tetram.Media.Streams' { Get-ElementaryExtension ... }

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams.psd1') -Force -ErrorAction Stop
}
AfterAll {
    Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-ElementaryExtension' {
    It 'mappe <Codec> vers <Ext> / <Class>' -TestCases @(
        @{ Codec = 'h264'; Type = 'video'; Pic = $false; Ext = '.h264'; Class = 'Video' }
        @{ Codec = 'avc'; Type = 'video'; Pic = $false; Ext = '.h264'; Class = 'Video' }
        @{ Codec = 'hevc'; Type = 'video'; Pic = $false; Ext = '.hevc'; Class = 'Video' }
        @{ Codec = 'h265'; Type = 'video'; Pic = $false; Ext = '.hevc'; Class = 'Video' }
        @{ Codec = 'av1'; Type = 'video'; Pic = $false; Ext = '.ivf'; Class = 'Video' }
        @{ Codec = 'vp9'; Type = 'video'; Pic = $false; Ext = '.ivf'; Class = 'Video' }
        @{ Codec = 'mpeg2video'; Type = 'video'; Pic = $false; Ext = '.m2v'; Class = 'Video' }
        @{ Codec = 'vc1'; Type = 'video'; Pic = $false; Ext = '.vc1'; Class = 'Video' }
        @{ Codec = 'aac'; Type = 'audio'; Pic = $false; Ext = '.aac'; Class = 'Audio' }
        @{ Codec = 'subrip'; Type = 'subtitle'; Pic = $false; Ext = '.srt'; Class = 'Subtitle' }
        @{ Codec = 'mjpeg'; Type = 'video'; Pic = $true; Ext = '.jpg'; Class = 'Cover' }
        @{ Codec = 'png'; Type = 'video'; Pic = $true; Ext = '.png'; Class = 'Cover' }
        @{ Codec = 'pcm_s16le'; Type = 'audio'; Pic = $false; Ext = '.wav'; Class = 'Audio' }
        @{ Codec = 'alac'; Type = 'audio'; Pic = $false; Ext = '.wav'; Class = 'Audio' }
    ) {
        InModuleScope 'Tetram.Media.Streams' -Parameters $_ {
            param($Codec, $Type, $Pic, $Ext, $Class)
            $r = Get-ElementaryExtension -CodecName $Codec -CodecType $Type -AttachedPic $Pic
            $r.Extension | Should -Be $Ext
            $r.Class | Should -Be $Class
        }
    }
    It 'retourne null pour mpeg4 et mov_text' {
        InModuleScope 'Tetram.Media.Streams' {
            Get-ElementaryExtension -CodecName 'mpeg4' -CodecType 'video' -AttachedPic $false | Should -BeNullOrEmpty
            Get-ElementaryExtension -CodecName 'mov_text' -CodecType 'subtitle' -AttachedPic $false | Should -BeNullOrEmpty
        }
    }
}
```

- [ ] **Step 2: Exécuter — FAIL** (`Get-ElementaryExtension` introuvable)

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Private/CodecMap.Tests.ps1' -Output Detailed"`  
Expected: FAIL

- [ ] **Step 3: Remplacer `Tetram.Media.Streams.Private/CodecMap.ps1`**

```powershell
Set-StrictMode -Version 3.0

function Get-ElementaryExtension {
    param(
        [Parameter(Mandatory)][string] $CodecName,
        [Parameter(Mandatory)][string] $CodecType,
        [bool] $AttachedPic = $false
    )
    $c = $CodecName.ToLowerInvariant()
    $t = $CodecType.ToLowerInvariant()
    if ($AttachedPic -and $c -eq 'mjpeg') { return [pscustomobject]@{ Class = 'Cover'; Extension = '.jpg' } }
    if ($AttachedPic -and $c -eq 'png') { return [pscustomobject]@{ Class = 'Cover'; Extension = '.png' } }
    $map = @{
        'h264' = @{ Class = 'Video'; Extension = '.h264' }
        'avc' = @{ Class = 'Video'; Extension = '.h264' }
        'hevc' = @{ Class = 'Video'; Extension = '.hevc' }
        'h265' = @{ Class = 'Video'; Extension = '.hevc' }
        'av1' = @{ Class = 'Video'; Extension = '.ivf' }
        'vp8' = @{ Class = 'Video'; Extension = '.ivf' }
        'vp9' = @{ Class = 'Video'; Extension = '.ivf' }
        'mpeg2video' = @{ Class = 'Video'; Extension = '.m2v' }
        'vc1' = @{ Class = 'Video'; Extension = '.vc1' }
        'aac' = @{ Class = 'Audio'; Extension = '.aac' }
        'ac3' = @{ Class = 'Audio'; Extension = '.ac3' }
        'eac3' = @{ Class = 'Audio'; Extension = '.eac3' }
        'dts' = @{ Class = 'Audio'; Extension = '.dts' }
        'dca' = @{ Class = 'Audio'; Extension = '.dts' }
        'truehd' = @{ Class = 'Audio'; Extension = '.thd' }
        'flac' = @{ Class = 'Audio'; Extension = '.flac' }
        'opus' = @{ Class = 'Audio'; Extension = '.opus' }
        'mp3' = @{ Class = 'Audio'; Extension = '.mp3' }
        'mp2' = @{ Class = 'Audio'; Extension = '.mp2' }
        'vorbis' = @{ Class = 'Audio'; Extension = '.ogg' }
        'alac' = @{ Class = 'Audio'; Extension = '.wav' }
        'subrip' = @{ Class = 'Subtitle'; Extension = '.srt' }
        'ass' = @{ Class = 'Subtitle'; Extension = '.ass' }
        'ssa' = @{ Class = 'Subtitle'; Extension = '.ssa' }
        'webvtt' = @{ Class = 'Subtitle'; Extension = '.vtt' }
        'hdmv_pgs_subtitle' = @{ Class = 'Subtitle'; Extension = '.sup' }
    }
    if ($c.StartsWith('pcm_')) { return [pscustomobject]@{ Class = 'Audio'; Extension = '.wav' } }
    if ($map.ContainsKey($c)) {
        return [pscustomobject]@{ Class = [string]$map[$c].Class; Extension = [string]$map[$c].Extension }
    }
    return $null
}
```

- [ ] **Step 4: Exécuter — PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Private/CodecMap.Tests.ps1' -Output Detailed"`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Streams.Private/CodecMap.ps1 tests/Tetram.Media.Streams.Private/CodecMap.Tests.ps1
git commit -m "$(cat <<'EOF'
feat(streams): carte codec vers extension élémentaire

EOF
)"
```

---

### Task 4: Descripteurs + collision source

**Files:**
- Modify: `Tetram.Media.Streams.Private/Descriptors.ps1`
- Test: `tests/Tetram.Media.Streams.Private/Descriptors.Tests.ps1`

**Interfaces:**
- Consumes: `Get-ElementaryExtension`, `Get-StreamCollisionKey`, `$script:StreamsDispositionFlags`
- Produces:
  - `Get-MediaStreamDescriptors -Probe <hashtable> → [pscustomobject[]]` (collision déjà attribuée sur **tout** le fichier)
  - `Select-MediaStreamDescriptors -Descriptors <pscustomobject[]> -StreamType <string[]> -Language <string[]> → [pscustomobject[]]`

Sonde : hashtable style `ConvertFrom-Json -AsHashtable` avec `streams` (liste) et `chapters` (liste ou absente).

- [ ] **Step 1: Écrire `tests/Tetram.Media.Streams.Private/Descriptors.Tests.ps1` (échoue)**

```powershell
# Étendre la suite autour de Descriptors.ps1 (probe → descripteurs + collision source).
#
# RepoRoot : (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module Tetram.Media.Streams.psd1 ; InModuleScope

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams.psd1') -Force -ErrorAction Stop
}
AfterAll { Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue }

Describe 'Get-MediaStreamDescriptors collision' {
    It 'numérote deux subrip eng 1 puis 2 dans l''ordre ffprobe' {
        $probe = @{
            streams = @(
                @{ index = 0; codec_type = 'video'; codec_name = 'h264'; tags = @{}; disposition = @{ default = 1; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 5; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            $subs = @($all | Where-Object { $_.Class -eq 'Subtitle' })
            $subs.Count | Should -Be 2
            $subs[0].CollisionIndex | Should -Be 1
            $subs[1].CollisionIndex | Should -Be 2
            $subs[0].StreamIndex | Should -Be 3
            $subs[1].StreamIndex | Should -Be 5
            (ConvertTo-StreamFileName -Basename 'film' -Descriptor $subs[0]) | Should -Be 'film.eng.srt'
            (ConvertTo-StreamFileName -Basename 'film' -Descriptor $subs[1]) | Should -Be 'film.eng.2.srt'
        }
    }
    It 'filtre StreamType Subtitle et Language eng' {
        $probe = @{
            streams = @(
                @{ index = 1; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fra' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 2; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 3; codec_type = 'audio'; codec_name = 'aac'; tags = @{ language = 'eng' }; disposition = @{ default = 1; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            $sel = @(Select-MediaStreamDescriptors -Descriptors $all -StreamType @('Subtitle') -Language @('eng'))
            $sel.Count | Should -Be 1
            $sel[0].Language | Should -Be 'eng'
            $sel[0].Class | Should -Be 'Subtitle'
        }
    }
    It 'conserve CollisionIndex 2 si on ne sélectionne que la 2e piste eng' {
        $probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 5; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            $second = $all | Where-Object { $_.StreamIndex -eq 5 }
            $second.CollisionIndex | Should -Be 2
            (ConvertTo-StreamFileName -Basename 'film' -Descriptor $second) | Should -Be 'film.eng.2.srt'
        }
    }
    It 'ajoute un descripteur Chapter si chapters est non vide' {
        $probe = @{
            streams = @()
            chapters = @(@{ id = 1; start_time = '0' })
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            $all = @(Get-MediaStreamDescriptors -Probe $Probe)
            @($all | Where-Object { $_.Class -eq 'Chapter' }).Count | Should -Be 1
        }
    }
    It 'omet mpeg4 des mappés et le liste en unmapped' {
        $probe = @{
            streams = @(
                @{ index = 0; codec_type = 'video'; codec_name = 'mpeg4'; tags = @{}; disposition = @{} }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Probe = $probe } {
            param($Probe)
            @(Get-MediaStreamDescriptors -Probe $Probe).Count | Should -Be 0
            $u = @(Get-UnmappedStreamDescriptors -Probe $Probe)
            $u.Count | Should -Be 1
            $u[0].codec_name | Should -Be 'mpeg4'
        }
    }
}
```

- [ ] **Step 2: Exécuter — FAIL**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Private/Descriptors.Tests.ps1' -Output Detailed"`  
Expected: FAIL — `Get-MediaStreamDescriptors` introuvable

- [ ] **Step 3: Remplacer `Tetram.Media.Streams.Private/Descriptors.ps1`**

```powershell
Set-StrictMode -Version 3.0

function Get-ProbeProperty {
    param($Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        return $null
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function ConvertTo-IntOrNull {
    param($Value)
    if ($null -eq $Value) { return $null }
    $n = 0
    if ([int]::TryParse([string]$Value, [ref]$n)) { return $n }
    return $null
}

function Get-StreamLanguage {
    param($Tags)
    $raw = [string](Get-ProbeProperty $Tags 'language')
    if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
    $low = $raw.ToLowerInvariant()
    if ($low -in @('und', 'unk')) { return '' }
    return $raw
}

function Get-StreamFlags {
    param($Disposition, [string] $Class)
    if ($Class -in @('Cover', 'Attachment', 'Chapter')) { return @() }
    $flags = @()
    foreach ($row in $script:StreamsDispositionFlags) {
        $v = Get-ProbeProperty $Disposition ([string]$row.ProbeName)
        if ("$v" -eq '1') { $flags += [string]$row.FileToken }
    }
    return $flags
}

function ConvertTo-SanitizedAttachmentName {
    param([string] $Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $invalid = [IO.Path]::GetInvalidFileNameChars() + [char]'.'
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalid -contains $ch) { [void]$sb.Append('_') }
        else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function Resolve-StreamCollisionIndex {
    param([pscustomobject[]] $Descriptors)
    $groups = $Descriptors | Group-Object -Property CollisionKey
    foreach ($g in $groups) {
        $i = 1
        foreach ($d in @($g.Group)) {
            $d.CollisionIndex = $i
            $i++
        }
    }
}

function Get-MediaStreamDescriptors {
    param([Parameter(Mandatory)][hashtable] $Probe)
    $list = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($st in @($Probe['streams'])) {
        $codecType = [string](Get-ProbeProperty $st 'codec_type')
        $codecName = [string](Get-ProbeProperty $st 'codec_name')
        $index = ConvertTo-IntOrNull (Get-ProbeProperty $st 'index')
        $tags = Get-ProbeProperty $st 'tags'
        $disp = Get-ProbeProperty $st 'disposition'
        $attached = ((Get-ProbeProperty $disp 'attached_pic') -eq 1)
        if ($codecType -eq 'attachment') {
            $fn = [string](Get-ProbeProperty $tags 'filename')
            $ext = [IO.Path]::GetExtension($fn)
            if (-not $ext) { $ext = '.bin' }
            $base = [IO.Path]::GetFileNameWithoutExtension($fn)
            $d = New-StreamDescriptorObject -Class 'Attachment' -Extension $ext.ToLowerInvariant() `
                -AttachmentName $fn -AttachmentNameSanitized (ConvertTo-SanitizedAttachmentName $base) `
                -StreamIndex $index -Codec $codecName -MimeType ([string](Get-ProbeProperty $tags 'mimetype'))
            $list.Add($d)
            continue
        }
        $mapped = Get-ElementaryExtension -CodecName $codecName -CodecType $codecType -AttachedPic $attached
        if ($null -eq $mapped) { continue }
        $d = New-StreamDescriptorObject -Class $mapped.Class -Language (Get-StreamLanguage $tags) `
            -Flags (Get-StreamFlags $disp $mapped.Class) -Extension $mapped.Extension `
            -StreamIndex $index -Codec $codecName
        $list.Add($d)
    }
    $chapters = $Probe['chapters']
    if (@($chapters).Count -gt 0) {
        $list.Add((New-StreamDescriptorObject -Class 'Chapter' -Extension '.ffmeta'))
    }
    $arr = @($list)
    foreach ($d in $arr) { $d.CollisionKey = Get-StreamCollisionKey $d }
    Resolve-StreamCollisionIndex -Descriptors $arr
    return $arr
}

function Get-UnmappedStreamDescriptors {
    param([Parameter(Mandatory)][hashtable] $Probe)
    $out = @()
    foreach ($st in @($Probe['streams'])) {
        $codecType = [string](Get-ProbeProperty $st 'codec_type')
        if ($codecType -eq 'attachment') { continue }
        $codecName = [string](Get-ProbeProperty $st 'codec_name')
        $disp = Get-ProbeProperty $st 'disposition'
        $attached = ((Get-ProbeProperty $disp 'attached_pic') -eq 1)
        if ($null -eq (Get-ElementaryExtension -CodecName $codecName -CodecType $codecType -AttachedPic $attached)) {
            $out += $st
        }
    }
    return $out
}

function Select-MediaStreamDescriptors {
    param(
        [pscustomobject[]] $Descriptors,
        [string[]] $StreamType,
        [string[]] $Language
    )
    $sel = @($Descriptors)
    if (@($StreamType).Count -gt 0) {
        $sel = @($sel | Where-Object {
            $c = $_.Class
            $ok = $false
            foreach ($t in $StreamType) {
                if ($t -eq 'Video' -and $c -in @('Video', 'Cover')) { $ok = $true }
                elseif ($t -eq 'Attachment' -and $c -eq 'Attachment') { $ok = $true }
                elseif ($t -eq 'Chapter' -and $c -eq 'Chapter') { $ok = $true }
                elseif ($t -eq $c) { $ok = $true }
            }
            $ok
        })
    }
    if (@($Language).Count -gt 0) {
        $sel = @($sel | Where-Object {
            if ($_.Class -in @('Attachment', 'Chapter')) { return $true }
            foreach ($l in $Language) {
                if ($_.Language -and ($_.Language -ieq $l)) { return $true }
            }
            return $false
        })
    }
    return $sel
}

function Test-StreamsMkvPath {
    param([string] $LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return $false }
    return ([IO.Path]::GetExtension($LiteralPath) -ieq '.mkv')
}

function Get-StreamsProbeHashtable {
    param(
        [Parameter(Mandatory)][string] $Ffprobe,
        [Parameter(Mandatory)][string] $LiteralPath
    )
    try {
        $raw = & $Ffprobe $LiteralPath -v quiet -show_format -show_streams -show_chapters -of json 2>$null | Out-String
        if (-not $raw) { return $null }
        return ConvertFrom-Json -InputObject $raw -AsHashtable
    }
    catch { return $null }
}
```

- [ ] **Step 4: Exécuter — PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Private/Descriptors.Tests.ps1' -Output Detailed"`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Streams.Private/Descriptors.ps1 tests/Tetram.Media.Streams.Private/Descriptors.Tests.ps1
git commit -m "$(cat <<'EOF'
feat(streams): descripteurs ffprobe et index de collision source

EOF
)"
```

---

### Task 5: Matching merge + args FFmpeg

**Files:**
- Modify: `Tetram.Media.Streams.Private/Matching.ps1`
- Test: `tests/Tetram.Media.Streams.Private/Matching.Tests.ps1`

**Interfaces:**
- Consumes: `ConvertFrom-StreamFileName`, `Get-StreamCollisionKey`, descripteurs
- Produces:
  - `Get-SidecarFiles -Directory <string> -Basename <string> -ExcludePath <string[]> → [pscustomobject[]]` (parse + chemin `FullName`)
  - `Resolve-MergeActions -MkvDescriptors <pscustomobject[]> -Sidecars <pscustomobject[]> → [pscustomobject]@{ Keeps; Replaces; Adds }`
    - `Keeps` : descripteurs MKV sans sidecar
    - `Replaces` : `@{ Mkv = <desc>; Sidecar = <parse+FullName> }`
    - `Adds` : sidecars sans match, ordre classes Video (covers last), Audio, Subtitle, Attachment, Chapter
  - `Build-MergeFFmpegArgs -MkvPath <string> -Actions <pscustomobject> -OutputPath <string> → [string[]]`

Règle matching : même `CollisionKey` **et** même `CollisionIndex`.

- [ ] **Step 1: Écrire `tests/Tetram.Media.Streams.Private/Matching.Tests.ps1` (échoue)**

Le fichier complet est dans le bloc ci-dessous (BeforeAll Import comme CodecMap.Tests, `$TestDrive`).

```powershell
# Étendre la suite autour de Matching.ps1 (sidecars, replace/add/keep, args merge).
#
# RepoRoot : (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
# Import-Module Tetram.Media.Streams.psd1 ; InModuleScope ; $TestDrive pour fichiers

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module -Name (Join-Path $script:RepoRoot 'Tetram.Media.Streams.psd1') -Force -ErrorAction Stop
}
AfterAll { Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue }

Describe 'Get-SidecarFiles / Resolve-MergeActions' {
    It 'exclut film.mkv, remplace les deux eng, ajoute spa' {
        $dir = Join-Path $TestDrive 'm'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mkv = Join-Path $dir 'film.mkv'
        New-Item -ItemType File -Path $mkv | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.srt') | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.eng.2.srt') | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'film.spa.srt') | Out-Null
        $probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
                @{ index = 5; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        InModuleScope 'Tetram.Media.Streams' -Parameters @{ Dir = $dir; Mkv = $mkv; Probe = $probe } {
            param($Dir, $Mkv, $Probe)
            $desc = @(Get-MediaStreamDescriptors -Probe $Probe)
            $sides = @(Get-SidecarFiles -Directory $Dir -Basename 'film' -ExcludePath @($Mkv))
            $sides.FullName | Should -Not -Contain $Mkv
            $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars $sides
            $act.Replaces.Count | Should -Be 2
            $act.Keeps.Count | Should -Be 0
            $act.Adds.Count | Should -Be 1
            $act.Adds[0].Language | Should -Be 'spa'
            $ffmpegArgs = Build-MergeFFmpegArgs -MkvPath $Mkv -Actions $act -OutputPath (Join-Path $Dir 'out.mkv')
            ($ffmpegArgs -join ' ') | Should -Match '-map 1:0'
            ($ffmpegArgs -join ' ') | Should -Match 'language=eng'
            ($ffmpegArgs -join ' ') | Should -Match 'language=spa'
        }
    }
}

Describe 'Get-FfmpegDispositionValue' {
    It 'joint comment pour commentary' {
        InModuleScope 'Tetram.Media.Streams' {
            Get-FfmpegDispositionValue -Flags @('commentary', 'default') | Should -Be 'default+comment'
            Get-FfmpegDispositionValue -Flags @() | Should -Be '0'
        }
    }
}
```

- [ ] **Step 2: Exécuter — FAIL**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Private/Matching.Tests.ps1' -Output Detailed"`  
Expected: FAIL — `Get-SidecarFiles` introuvable

- [ ] **Step 3: Remplacer `Tetram.Media.Streams.Private/Matching.ps1` par le code ci-dessous**

Implémenter `Get-SidecarFiles`, `Resolve-MergeActions` (clé+index, Adds triés Video/Cover/Audio/Subtitle/Attachment/Chapter), `Get-MapSpecLetter`, `Build-MergeFFmpegArgs` :

- `-hide_banner -y -i $MkvPath` puis `-i` chaque sidecar A/V/S (replaces puis adds, sans doublon), puis éventuellement `-i` du `.chapters.ffmeta`
- `-c copy`
- Pour chaque descripteur dans `$Actions.OrderedMkv` (sauf Chapter) : replace A/V/S → `-map N:0` + `-metadata:s:L:i language=` + `-disposition:L:i` via `Get-FfmpegDispositionValue` ; keep → `-map 0:StreamIndex` sans metadata ; Attachment replace → `-attach` + `filename=` ; Attachment keep → `-map 0:StreamIndex`
- Puis chaque Add A/V/S/Cover/Attachment (pas Chapter)
- Cover : ajouter `attached_pic` sur la disposition vidéo
- Si sidecar chapters : `-map_chapters N`
- Dernier argument : `$OutputPath`

Le listing PowerShell complet à coller (copie fidèle de cette logique) :

```powershell
Set-StrictMode -Version 3.0

function Get-SidecarFiles {
    param(
        [Parameter(Mandatory)][string] $Directory,
        [Parameter(Mandatory)][string] $Basename,
        [string[]] $ExcludePath = @()
    )
    $exclude = @()
    foreach ($p in @($ExcludePath)) {
        if ($p) { $exclude += [IO.Path]::GetFullPath($p) }
    }
    $out = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue)) {
        $full = [IO.Path]::GetFullPath($f.FullName)
        if ($exclude -contains $full) { continue }
        $parsed = ConvertFrom-StreamFileName -Basename $Basename -FileName $f.Name
        if ($null -eq $parsed) { continue }
        $parsed | Add-Member -NotePropertyName FullName -NotePropertyValue $full -Force
        $out += $parsed
    }
    return $out
}

function Resolve-MergeActions {
    param(
        [Parameter(Mandatory)][pscustomobject[]] $MkvDescriptors,
        [Parameter(Mandatory)][AllowEmptyCollection()][pscustomobject[]] $Sidecars
    )
    $used = @{}
    $replaces = @()
    $keeps = @()
    foreach ($mkv in @($MkvDescriptors)) {
        $hit = @($Sidecars | Where-Object {
            $_.CollisionKey -eq $mkv.CollisionKey -and [int]$_.CollisionIndex -eq [int]$mkv.CollisionIndex
        }) | Select-Object -First 1
        if ($hit) {
            $replaces += [pscustomobject]@{ Mkv = $mkv; Sidecar = $hit }
            $used[$hit.FullName] = $true
        }
        else { $keeps += $mkv }
    }
    $classOrder = @{ Video = 0; Cover = 1; Audio = 2; Subtitle = 3; Attachment = 4; Chapter = 5 }
    $adds = @($Sidecars | Where-Object { -not $used.ContainsKey($_.FullName) } |
            Sort-Object { $classOrder[$_.Class] }, CollisionIndex)
    return [pscustomobject]@{
        OrderedMkv = @($MkvDescriptors)
        Keeps = $keeps
        Replaces = $replaces
        Adds = $adds
    }
}

function Get-MapSpecLetter {
    param([string] $Class)
    switch ($Class) {
        'Video' { 'v' }
        'Cover' { 'v' }
        'Audio' { 'a' }
        'Subtitle' { 's' }
        default { $null }
    }
}

function Build-MergeFFmpegArgs {
    param(
        [Parameter(Mandatory)][string] $MkvPath,
        [Parameter(Mandatory)][pscustomobject] $Actions,
        [Parameter(Mandatory)][string] $OutputPath
    )
    $a = [System.Collections.Generic.List[string]]::new()
    [void]$a.Add('-hide_banner')
    [void]$a.Add('-y')
    [void]$a.Add('-i'); [void]$a.Add($MkvPath)
    $inputIndex = @{}
    $n = 1
    $sideForInput = @()
    foreach ($r in @($Actions.Replaces)) { $sideForInput += $r.Sidecar }
    $sideForInput += @($Actions.Adds)
    foreach ($item in $sideForInput) {
        if ($null -eq $item) { continue }
        if ($item.Class -in @('Attachment', 'Chapter')) { continue }
        if ($inputIndex.ContainsKey($item.FullName)) { continue }
        [void]$a.Add('-i'); [void]$a.Add($item.FullName)
        $inputIndex[$item.FullName] = $n
        $n++
    }
    $chapter = @($Actions.Adds | Where-Object { $_.Class -eq 'Chapter' })
    foreach ($r in @($Actions.Replaces)) {
        if ($r.Mkv.Class -eq 'Chapter') { $chapter = @($r.Sidecar); break }
    }
    $chapterInput = $null
    if ($chapter.Count -gt 0 -and $chapter[0].FullName) {
        [void]$a.Add('-i'); [void]$a.Add($chapter[0].FullName)
        $chapterInput = $n
        $n++
    }
    [void]$a.Add('-c'); [void]$a.Add('copy')
    $outIdx = @{ v = 0; a = 0; s = 0; t = 0 }
    $replaceByIndex = @{}
    foreach ($r in @($Actions.Replaces)) {
        if ($null -ne $r.Mkv.StreamIndex) { $replaceByIndex[[int]$r.Mkv.StreamIndex] = $r }
    }
    foreach ($mkv in @($Actions.OrderedMkv)) {
        if ($mkv.Class -eq 'Chapter') { continue }
        if ($mkv.Class -eq 'Attachment') {
            $r = $null
            if ($null -ne $mkv.StreamIndex) { $r = $replaceByIndex[[int]$mkv.StreamIndex] }
            if ($r) {
                [void]$a.Add('-attach'); [void]$a.Add($r.Sidecar.FullName)
                $ti = $outIdx['t']
                $fn = $r.Sidecar.AttachmentName
                if (-not $fn) { $fn = $r.Sidecar.AttachmentNameSanitized + $r.Sidecar.Extension }
                [void]$a.Add("-metadata:s:t:${ti}"); [void]$a.Add("filename=$fn")
                $outIdx['t']++
            }
            else {
                [void]$a.Add('-map'); [void]$a.Add("0:$($mkv.StreamIndex)")
                $outIdx['t']++
            }
            continue
        }
        $letter = Get-MapSpecLetter $mkv.Class
        $r = $null
        if ($null -ne $mkv.StreamIndex) { $r = $replaceByIndex[[int]$mkv.StreamIndex] }
        if ($r) {
            $in = $inputIndex[$r.Sidecar.FullName]
            [void]$a.Add('-map'); [void]$a.Add("${in}:0")
            $oi = $outIdx[$letter]
            $lang = if ($r.Sidecar.Language) { $r.Sidecar.Language } else { 'und' }
            [void]$a.Add("-metadata:s:${letter}:${oi}"); [void]$a.Add("language=$lang")
            [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add((Get-FfmpegDispositionValue $r.Sidecar.Flags))
            if ($mkv.Class -eq 'Cover') {
                [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add('attached_pic')
            }
            $outIdx[$letter]++
        }
        else {
            [void]$a.Add('-map'); [void]$a.Add("0:$($mkv.StreamIndex)")
            $outIdx[$letter]++
        }
    }
    foreach ($add in @($Actions.Adds)) {
        if ($add.Class -eq 'Chapter') { continue }
        if ($add.Class -eq 'Attachment') {
            [void]$a.Add('-attach'); [void]$a.Add($add.FullName)
            $ti = $outIdx['t']
            $fn = $add.AttachmentNameSanitized + $add.Extension
            [void]$a.Add("-metadata:s:t:${ti}"); [void]$a.Add("filename=$fn")
            $outIdx['t']++
            continue
        }
        $letter = Get-MapSpecLetter $add.Class
        $in = $inputIndex[$add.FullName]
        [void]$a.Add('-map'); [void]$a.Add("${in}:0")
        $oi = $outIdx[$letter]
        $lang = if ($add.Language) { $add.Language } else { 'und' }
        [void]$a.Add("-metadata:s:${letter}:${oi}"); [void]$a.Add("language=$lang")
        [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add((Get-FfmpegDispositionValue $add.Flags))
        if ($add.Class -eq 'Cover') {
            [void]$a.Add("-disposition:${letter}:${oi}"); [void]$a.Add('attached_pic')
        }
        $outIdx[$letter]++
    }
    if ($null -ne $chapterInput) {
        [void]$a.Add('-map_chapters'); [void]$a.Add([string]$chapterInput)
    }
    [void]$a.Add($OutputPath)
    return @($a)
}
```

- [ ] **Step 4: Exécuter — PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Private/Matching.Tests.ps1' -Output Detailed"`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Streams.Private/Matching.ps1 tests/Tetram.Media.Streams.Private/Matching.Tests.ps1
git commit -m "$(cat <<'EOF'
feat(streams): matching replace/add/keep et args FFmpeg de merge

EOF
)"
```

---

### Task 6: Invoke-StreamsFFmpeg + Split-MediaStream

**Files:**
- Modify: `Tetram.Media.Streams.Private/Invoke.ps1`
- Modify: `Tetram.Media.Streams.psm1` (corps de `Split-MediaStream`)
- Test: `tests/Tetram.Media.Streams.Tests.ps1` (étendre)

**Interfaces:**
- Consumes: `Test-StreamsMkvPath`, `Get-StreamsProbeHashtable` (déjà dans `Descriptors.ps1` tâche 4)
- Produces: `Invoke-StreamsFFmpeg -Cmdlet <PSCmdlet> -Exe <string> -Arguments <string[]> -TargetLabel <string> → [bool]`
- Produces: `Split-MediaStream` conforme spec

- [ ] **Step 1: Ajouter les tests publics suivants à `tests/Tetram.Media.Streams.Tests.ps1` (échouent)**

Après le Describe exports, coller :

```powershell
Describe 'Split-MediaStream erreurs' {
    BeforeAll {
        Import-Module -Name $script:ManifestStreams -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
    }

    It 'ne throw pas si le fichier n''est pas un mkv' {
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        $txt = Join-Path $TestDrive 'x.txt'
        Set-Content -LiteralPath $txt -Value 'nope'
        { Split-MediaStream -LiteralPath $txt } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog -Times 1
    }

    It 'ne throw pas si FFmpeg est introuvable' {
        Mock -ModuleName Tetram.Media.Streams Get-FFmpegPath { throw 'FFmpeg introuvable (test)' }
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        $mkv = Join-Path $TestDrive 'film.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        { Split-MediaStream -LiteralPath $mkv } | Should -Not -Throw
        Should -Invoke -ModuleName Tetram.Media.Streams Write-ErrorLog -Times 1
    }
}

Describe 'Split-MediaStream WhatIf' {
    BeforeAll {
        Import-Module -Name $script:ManifestStreams -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
    }

    It 'affiche Show-CommandLine et n''appelle pas Invoke-FFmpeg' {
        $mkv = Join-Path $TestDrive 'film.mkv'
        Set-Content -LiteralPath $mkv -Value 'fake'
        Mock -ModuleName Tetram.Media.Streams Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Streams Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Streams Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Streams Show-CommandLine {}
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'ne doit pas tourner' }
        $probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'fra' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        Mock -ModuleName Tetram.Media.Streams Get-StreamsProbeHashtable { $probe }
        Split-MediaStream -LiteralPath $mkv -StreamType Subtitle -Language fra -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Streams Show-CommandLine -Times 1
        Should -Invoke -ModuleName Tetram.Media.Streams Invoke-FFmpeg -Times 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'film.fra.srt') | Should -BeFalse
    }
}
```

- [ ] **Step 2: Exécuter — FAIL** (corps Split vide / Show-CommandLine 0 fois)

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Tests.ps1' -Output Detailed"`

- [ ] **Step 3: Écrire `Invoke.ps1` et le corps de `Split-MediaStream`**

`Tetram.Media.Streams.Private/Invoke.ps1` :

```powershell
Set-StrictMode -Version 3.0

function Invoke-StreamsFFmpeg {
    param(
        [Parameter(Mandatory)] $Cmdlet,
        [Parameter(Mandatory)][string] $Exe,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $TargetLabel
    )
    Show-CommandLine $Exe $Arguments -NoPathDetectionParameters 'metadata*', 'disposition*', 'map*'
    if ($Cmdlet.ShouldProcess($TargetLabel, "ffmpeg on $TargetLabel")) {
        $code = Invoke-FFmpeg -ExePath $Exe -Arguments $Arguments
        return ($code -eq 0)
    }
    Write-InfoLog -Color Magenta "[WhatIf] Would run ffmpeg on $TargetLabel"
    return $true
}

function Get-SplitExtractArguments {
    param([pscustomobject] $Descriptor, [string] $MkvPath, [string] $OutPath)
    if ($Descriptor.Class -eq 'Chapter') {
        return @('-hide_banner', '-i', $MkvPath, '-f', 'ffmetadata', '-map_chapters', '0', '-y', $OutPath)
    }
    return @('-hide_banner', '-i', $MkvPath, '-map', "0:$($Descriptor.StreamIndex)", '-c', 'copy', '-y', $OutPath)
}
```

Remplacer le corps de `Split-MediaStream` dans `Tetram.Media.Streams.psm1` (garder le `[CmdletBinding]` / `param` existants) par :

```powershell
    try { $ffmpeg = Get-FFmpegPath; $ffprobe = Get-FfprobePath }
    catch { Write-ErrorLog $_.Exception.Message; return }

    if (-not (Test-StreamsMkvPath -LiteralPath $LiteralPath)) {
        Write-ErrorLog "Not a .mkv file: '$LiteralPath'"
        return
    }

    $probe = Get-StreamsProbeHashtable -Ffprobe $ffprobe -LiteralPath $LiteralPath
    if ($null -eq $probe) {
        Write-ErrorLog "Can't get media info for '$LiteralPath'"
        return
    }

    foreach ($u in @(Get-UnmappedStreamDescriptors -Probe $probe)) {
        $cn = [string](Get-ProbeProperty $u 'codec_name')
        Write-ErrorLog "Unmapped codec '$cn' in '$LiteralPath' — skipped"
    }

    $all = @(Get-MediaStreamDescriptors -Probe $probe)
    $sel = @(Select-MediaStreamDescriptors -Descriptors $all -StreamType $StreamType -Language $Language)
    if ($sel.Count -eq 0) {
        Write-InfoLog "No stream to extract from '$LiteralPath'"
        return
    }

    $dir = Split-Path -Parent (Resolve-Path -LiteralPath $LiteralPath)
    $base = [IO.Path]::GetFileNameWithoutExtension($LiteralPath)
    foreach ($d in $sel) {
        $name = ConvertTo-StreamFileName -Basename $base -Descriptor $d
        $out = Join-Path $dir $name
        if ((Test-Path -LiteralPath $out -PathType Leaf) -and -not $WhatIfPreference) {
            if (-not $Force -and -not $PSCmdlet.ShouldContinue($out, 'Overwrite sidecar')) {
                Write-InfoLog "Skip existing sidecar '$out'"
                continue
            }
        }
        $ffmpegArgs = Get-SplitExtractArguments -Descriptor $d -MkvPath $LiteralPath -OutPath $out
        $ok = Invoke-StreamsFFmpeg -Cmdlet $PSCmdlet -Exe $ffmpeg -Arguments $ffmpegArgs -TargetLabel $out
        if (-not $ok) {
            Write-ErrorLog "ffmpeg failed extracting '$out'"
        }
    }
```

- [ ] **Step 4: Exécuter — PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Tests.ps1' -Output Detailed"`  
Expected: PASS (manifeste + exports + 3 nouveaux tests)

Puis : `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Private' -Output Detailed"`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Streams.Private/Invoke.ps1 Tetram.Media.Streams.psm1 tests/Tetram.Media.Streams.Tests.ps1
git commit -m "$(cat <<'EOF'
feat(streams): Split-MediaStream et Invoke-StreamsFFmpeg

EOF
)"
```

---

### Task 7: Merge-MediaStream + RemoveSidecars

**Files:**
- Modify: `Tetram.Media.Streams.psm1` (`Merge-MediaStream`)
- Test: `tests/Tetram.Media.Streams.Tests.ps1`

**Interfaces:**
- Consumes: `Get-SidecarFiles`, `Resolve-MergeActions`, `Build-MergeFFmpegArgs`, `Invoke-StreamsFFmpeg -Cmdlet`
- Produces: `Merge-MediaStream` conforme spec

- [ ] **Step 1: Ajouter à `tests/Tetram.Media.Streams.Tests.ps1`**

```powershell
Describe 'Merge-MediaStream' {
    BeforeAll {
        Import-Module -Name $script:ManifestStreams -Force -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name 'Tetram.Media.Streams' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:Work = Join-Path $TestDrive ('mw-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Work | Out-Null
        $script:Mkv = Join-Path $script:Work 'film.mkv'
        Set-Content -LiteralPath $script:Mkv -Value 'fake-mkv'
        $script:Srt = Join-Path $script:Work 'film.eng.srt'
        Set-Content -LiteralPath $script:Srt -Value '1'
        $script:Probe = @{
            streams = @(
                @{ index = 3; codec_type = 'subtitle'; codec_name = 'subrip'; tags = @{ language = 'eng' }; disposition = @{ default = 0; forced = 0; comment = 0; original = 0; dub = 0; hearing_impaired = 0; visual_impaired = 0 } }
            )
        }
        Mock -ModuleName Tetram.Media.Streams Get-FFmpegPath { 'ffmpeg' }
        Mock -ModuleName Tetram.Media.Streams Get-FfprobePath { 'ffprobe' }
        Mock -ModuleName Tetram.Media.Streams Get-StreamsProbeHashtable { $script:Probe }
        Mock -ModuleName Tetram.Media.Streams Write-ErrorLog {}
        Mock -ModuleName Tetram.Media.Streams Write-InfoLog {}
        Mock -ModuleName Tetram.Media.Streams Show-CommandLine {}
    }

    It 'WhatIf affiche la commande et ne touche pas aux sidecars' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { throw 'no ffmpeg' }
        Merge-MediaStream -LiteralPath $script:Mkv -WhatIf
        Should -Invoke -ModuleName Tetram.Media.Streams Show-CommandLine -Times 1
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
        Test-Path -LiteralPath ($script:Mkv + '.tmp') | Should -BeFalse
    }

    It 'RemoveSidecars après succès supprime le srt' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg {
            param($Arguments, $ExePath)
            $out = $Arguments[-1]
            Set-Content -LiteralPath $out -Value 'muxed'
            return 0
        }
        Merge-MediaStream -LiteralPath $script:Mkv -Force -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeFalse
        Test-Path -LiteralPath $script:Mkv | Should -BeTrue
    }

    It 'RemoveSidecars ne supprime rien si ffmpeg échoue' {
        Mock -ModuleName Tetram.Media.Streams Invoke-FFmpeg { return 1 }
        Merge-MediaStream -LiteralPath $script:Mkv -Force -RemoveSidecars
        Test-Path -LiteralPath $script:Srt | Should -BeTrue
    }
}
```

- [ ] **Step 2: Exécuter — FAIL** (Merge vide)

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Tests.ps1' -Output Detailed"`

- [ ] **Step 3: Remplacer le corps de `Merge-MediaStream` dans `Tetram.Media.Streams.psm1`**

```powershell
    try { $ffmpeg = Get-FFmpegPath; $ffprobe = Get-FfprobePath }
    catch { Write-ErrorLog $_.Exception.Message; return }

    if (-not (Test-StreamsMkvPath -LiteralPath $LiteralPath)) {
        Write-ErrorLog "Not a .mkv file: '$LiteralPath'"
        return
    }

    $src = [IO.Path]::GetFullPath($LiteralPath)
    if ($Destination) {
        if ([IO.Path]::GetExtension($Destination) -ine '.mkv') {
            Write-ErrorLog "Destination must be a .mkv path: '$Destination'"
            return
        }
        $dest = [IO.Path]::GetFullPath($Destination)
    }
    else { $dest = $src }

    $probe = Get-StreamsProbeHashtable -Ffprobe $ffprobe -LiteralPath $src
    if ($null -eq $probe) {
        Write-ErrorLog "Can't get media info for '$src'"
        return
    }

    $dir = Split-Path -Parent $src
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $sides = @(Get-SidecarFiles -Directory $dir -Basename $base -ExcludePath @($src, $dest))
    if ($sides.Count -eq 0) {
        Write-ErrorLog "No sidecar files found for '$base'"
        return
    }

    $desc = @(Get-MediaStreamDescriptors -Probe $probe)
    $act = Resolve-MergeActions -MkvDescriptors $desc -Sidecars $sides

    if ((Test-Path -LiteralPath $dest -PathType Leaf) -and -not $WhatIfPreference) {
        if (-not $Force -and -not $PSCmdlet.ShouldContinue($dest, 'Overwrite MKV')) {
            Write-InfoLog "Skip existing '$dest'"
            return
        }
    }

    $temp = $dest + '.tmp'
    $n = 2
    while (Test-Path -LiteralPath $temp) {
        $temp = $dest + ".tmp$n"
        $n++
    }

    $ffmpegArgs = Build-MergeFFmpegArgs -MkvPath $src -Actions $act -OutputPath $temp
    $ok = Invoke-StreamsFFmpeg -Cmdlet $PSCmdlet -Exe $ffmpeg -Arguments $ffmpegArgs -TargetLabel $dest
    if ($WhatIfPreference) { return }
    if (-not $ok) {
        Write-ErrorLog "ffmpeg failed muxing '$dest'"
        if (Test-Path -LiteralPath $temp) {
            if ($PSCmdlet.ShouldProcess($temp, 'Cleanup temp')) { Remove-Item -LiteralPath $temp -Force }
        }
        return
    }
    if ($PSCmdlet.ShouldProcess($dest, "Move temp over '$dest'")) {
        Move-Item -LiteralPath $temp -Destination $dest -Force
    }
    if ($RemoveSidecars) {
        $toRemove = @($act.Replaces | ForEach-Object { $_.Sidecar.FullName }) + @($act.Adds | ForEach-Object { $_.FullName })
        foreach ($p in $toRemove) {
            if (-not $p) { continue }
            if ($PSCmdlet.ShouldProcess($p, 'Remove sidecar')) {
                try { Remove-Item -LiteralPath $p -ErrorAction Stop }
                catch { Write-ErrorLog "Unable to delete sidecar '$p': $($_.Exception.Message)" }
            }
        }
    }
```

- [ ] **Step 4: Exécuter — PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Tests.ps1' -Output Detailed"`  
Expected: PASS

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Tetram.Media.Streams.Private' -Output Detailed"`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tetram.Media.Streams.psm1 tests/Tetram.Media.Streams.Tests.ps1
git commit -m "$(cat <<'EOF'
feat(streams): Merge-MediaStream update in-place et RemoveSidecars

EOF
)"
```

---

### Task 8: Aide PlatyPS complète

**Files:**
- Create: `docs/help/Tetram.Media.Streams/Tetram.Media.Streams.md`
- Create: `docs/help/Tetram.Media.Streams/Split-MediaStream.md`
- Create: `docs/help/Tetram.Media.Streams/Merge-MediaStream.md`
- Create: `fr-FR/Tetram.Media.Streams-Help.xml` (via outil)

**Interfaces:**
- Consumes: commandes Task 6–7 (paramètres réels)

- [ ] **Step 1: Générer le squelette markdown**

Run (racine repo) : `pwsh -NoProfile -File tools/New-HelpMarkdown.ps1 -Force`  
Expected: fichiers sous `docs/help/Tetram.Media.Streams/`

- [ ] **Step 2: Remplacer SYNOPSIS / DESCRIPTION / EXAMPLES des pages générées** par le fond suivant (conserver le YAML PlatyPS des paramètres, n’écraser que le texte métier).

**`Split-MediaStream.md` — SYNOPSIS :** extraire des flux d’un MKV vers des sidecars à côté du fichier.

**DESCRIPTION à coller :**

```
Importer Tetram.Media.Streams.psd1 (PowerShell 7+). -LiteralPath est un fichier .mkv existant.

ffprobe lit toutes les pistes ; l'index de collision (.2, .3) est calculé sur le MKV entier avant -StreamType / -Language. Extraire seulement la 2e VO anglais produit film.eng.2.srt.

Noms : {basename}[.{langue}][.default][.forced][.commentary][.original][.dub][.hearing_impaired][.visual_impaired][.{n}].{ext}. Langue omise si und/unk/absente. dub est un flag, pas une langue. Cover : film.cover.jpg. Chapitres : film.chapters.ffmeta. Polices : film.{nom}.ttf.

Copie FFmpeg (-c copy). Show-CommandLine avant ShouldProcess (y compris -WhatIf). Cible existante : -Force ou confirmation. Codec non mappé : Write-ErrorLog, piste ignorée. FFmpeg manquant : Write-ErrorLog, pas d'exception.
```

**Exemples à coller (5) :**

```powershell
Split-MediaStream -LiteralPath 'D:\Media\film.mkv' -StreamType Subtitle -Language fra
Split-MediaStream -LiteralPath 'D:\Media\film.mkv' -WhatIf
Split-MediaStream -LiteralPath 'D:\Media\film.mkv' -Force
```

**`Merge-MediaStream.md` — SYNOPSIS :** réinjecter les sidecars dans le MKV (replace / add / keep).

**DESCRIPTION à coller :**

```
Toujours un update du MKV passé en -LiteralPath (fichier .mkv existant). Sidecars du même basename : même clé (classe, langue, flags, extension, index) = replace ; sinon add ; piste MKV sans sidecar = keep. Pas de suppression de piste.

-Destination optionnel (sinon in-place via .tmp). -RemoveSidecars après mux réussi seulement. -WhatIf affiche la ligne FFmpeg, n'écrit pas, ne supprime pas. commentary fichier = comment FFmpeg.
```

**Exemples :** merge après édition srt ; add film.spa.srt ; -RemoveSidecars ; -WhatIf.

**Page module :** une phrase : round-trip MKV, deux commandes, importer le psd1.

- [ ] **Step 3: Générer le MAML**

Run: `pwsh -NoProfile -File tools/New-HelpMaml.ps1 -Force`  
Expected: `fr-FR/Tetram.Media.Streams-Help.xml`

- [ ] **Step 4: Vérifier Get-Help**

```powershell
Import-Module .\Tetram.Media.Streams.psd1 -Force
Get-Help Split-MediaStream -Full
Get-Help Merge-MediaStream -Full
```

Expected: synopsis/description/exemples non vides (pas « function not found », pas aide auto générique vide).

- [ ] **Step 5: Suite Pester complète hors Integration**

Run: `pwsh -NoProfile -File .github/ci/Invoke-Tests.ps1`  
Expected: Exit 0 ; les nouveaux tests verts ; pas de régression.

- [ ] **Step 6: Commit**

```bash
git add docs/help/Tetram.Media.Streams/Tetram.Media.Streams.md docs/help/Tetram.Media.Streams/Split-MediaStream.md docs/help/Tetram.Media.Streams/Merge-MediaStream.md fr-FR/Tetram.Media.Streams-Help.xml
git commit -m "$(cat <<'EOF'
docs(streams): aide PlatyPS et MAML Split/Merge

EOF
)"
```

---

## Spec coverage (self-review)

| Exigence spec | Tâche |
|---|---|
| Manifeste / NestedModules / exports | 1 |
| Grammaire, flags, dub≠langue, cover/chapters, polices, conteneurs exclus | 2 |
| Carte codec + unmapped mpeg4/mov_text | 3 |
| Collision sur le fichier source + filtres StreamType/Language | 4 |
| replace/add/keep + args metadata/disposition | 5 |
| Split, Show-CommandLine, WhatIf, Force/ShouldContinue, erreurs sans throw | 6 |
| Merge in-place, Destination, RemoveSidecars, temp | 7 |
| Aide PlatyPS + MAML | 8 |
| Tag Integration / CI sans vrai ffmpeg | 6–7 (mocks) ; pas de tests Integration obligatoires en v1 |
| Hors scope (from-scratch, Recurse, mkvmerge) | aucune tâche — ne pas implémenter |

## Type consistency

- `Class` / `Flags` / `CollisionIndex` / `CollisionKey` : Task 2 définit la clé ; Task 4–5 réutilisent `Get-StreamCollisionKey`, pas une seconde formule.
- `Invoke-StreamsFFmpeg -Cmdlet` : Task 6 et 7.
- `Get-StreamsProbeHashtable` : Task 4 (Descriptors.ps1), mocké dans 6–7.
