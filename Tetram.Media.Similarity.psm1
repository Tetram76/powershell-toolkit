Set-StrictMode -Version 3.0

function New-VideoSignatureFile {
    param(
		$InputPath, 
		$OutputPath
	)
	
    $args = @(
		'-loglevel', 'error'
		'-y'
		'-i', $InputPath
		'-vf', "signature=format=binary:filename='$OutputPath'"
		'-f', 'null'
	)
    Invoke-FFmpeg -Arguments $args
}

function Get-SignatureConfidence {
    param(
		$SigAPath, 
		$SigBPath
	)
	
    $exe = Get-FFmpegPath
    # Ici on capture la sortie pour parser la confidence
    $raw = & $exe -loglevel info -i $SigAPath -i $SigBPath -filter_complex "signature=detectmode=full:nb_inputs=2" -f null - 2>&1
    if ($raw -match "confidence:(?<conf>\d+)") { return [int]$Matches['conf'] }
    return 0
}

function Sync-SignatureRegistry {
    param(
		$Files
	)
	
	Write-Verbose ">> Sync-SignatureRegistry"
	
    $registry = @()
    Write-Log "Indexation et vérification des empreintes..." -Color Cyan
    
    foreach ($file in $Files) {
        $vHash = Get-MediaFastHash -Path $file.FullName
        $sigPath = Join-Path $file.DirectoryName "$($file.BaseName).$vHash.sig"

        # Nettoyage
        Get-ChildItem $file.DirectoryName -Filter "$($file.BaseName).*.sig" | Where-Object { $_.FullName -ne $sigPath } | ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.Name, "Supprimer signature obsolète")) { Remove-Item $_.FullName -Force }
        }

        if (-not (Test-Path $sigPath)) {
            if ($PSCmdlet.ShouldProcess($file.Name, "Générer signature visuelle")) {
                Write-Log "Génération de l'empreinte : $($file.Name)" -Color Yellow
                New-VideoSignatureFile -InputPath $file.FullName -OutputPath $sigPath
                $script:signaturesCreated++
            }
        }
        if (Test-Path $sigPath) { $registry += @{ File = $file; SigPath = $sigPath } }
    }
	
	Write-Verbose "Sync-SignatureRegistry >>`n $($registry)"
    return $registry
}

function Invoke-SimilarityAnalysis {
    param(
		$Registry, 
		$Threshold
	)
	
    $results = @()
    Write-Log "Analyse des correspondances visuelles..." -Color Cyan

    for ($i = 0; $i -lt $Registry.Count; $i++) {
        $source = $Registry[$i]; $matches = @()
        for ($j = $i + 1; $j -lt $Registry.Count; $j++) {
            $target = $Registry[$j]
            $conf = Get-SignatureConfidence -SigAPath $source.SigPath -SigBPath $target.SigPath
            if ($conf -ge $Threshold) {
                $matches += [PSCustomObject]@{ TargetFile = $target.File.Name; Confidence = $conf }
            }
        }
        if ($matches.Count -gt 0) {
            $results += [PSCustomObject]@{ SourceFile = $source.File.Name; Matches = $matches }
        }
    }
    return $results
}

function Test-MediaSimilarity {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string] $Path,
        
		[switch] $Recurse,

        [ValidateNotNullOrEmpty()]
        [string[]] $InputMasks = @('*.mkv', '*.mp4', '*.avi', '*.wmv', '*.mov', '*.flv', '*.mpeg', '*.mpg', '*.heic', '*.ts', '*.webm'),

        [int] $ConfidenceThreshold = 90,
        
		[switch] $UpdateOnly
    )

    begin {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $script:signaturesCreated = 0
    }

    process {
        $files = Get-ChildItem -Path (Resolve-Path $Path) -Include $InputMasks -Recurse:$Recurse | Where-Object { -not $_.PSIsContainer }
        $registry = @(Sync-SignatureRegistry -Files $files)
				
        if ($UpdateOnly -or $registry.Count -lt 2) { $results = @(); return }
        $results = @(Invoke-SimilarityAnalysis -Registry $registry -Threshold $ConfidenceThreshold)
    }

    end {
        if ($results.Count -gt 0) {
            foreach ($res in $results) {
                Write-Log "Origine : $($res.SourceFile)" -Color Yellow
                $res.Matches | ForEach-Object { Write-Host "  -> [$($_.Confidence)%] $($_.TargetFile)" -ForegroundColor Gray }
            }
        }
        Write-InfoLog -Color Green "`nRésumé : $($files.Count) vidéos, $script:signaturesCreated signatures MAJ, $($results.Count) similitudes en $(Format-Duration $sw.Elapsed.TotalSeconds)"
        if ($results) { return $results }
    }
}