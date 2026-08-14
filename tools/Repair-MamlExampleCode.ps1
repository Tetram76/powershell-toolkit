# PlatyPS 1.0.x met tout le corps d'exemple dans maml:introduction et laisse
# dev:code vide (issues #799 / #839, by design). On ne reparse pas le markdown :
# le marqueur est la fence ```powershell déjà copiée dans un maml:para.

Set-StrictMode -Version Latest

function Repair-MamlExampleCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [xml] $Document
    )

    $nsmgr = [System.Xml.XmlNamespaceManager]::new($Document.NameTable)
    $nsmgr.AddNamespace('maml', 'http://schemas.microsoft.com/maml/2004/10')
    $nsmgr.AddNamespace('command', 'http://schemas.microsoft.com/maml/dev/command/2004/10')
    $nsmgr.AddNamespace('dev', 'http://schemas.microsoft.com/maml/dev/2004/10')

    $fenceOpen = '```powershell'
    $fenceClose = '```'

    foreach ($example in $Document.SelectNodes('//command:example', $nsmgr)) {
        $intro = $example.SelectSingleNode('maml:introduction', $nsmgr)
        $codeNode = $example.SelectSingleNode('dev:code', $nsmgr)
        $remarks = $example.SelectSingleNode('dev:remarks', $nsmgr)
        if (-not $intro -or -not $codeNode -or -not $remarks) {
            continue
        }

        $paras = @($intro.SelectNodes('maml:para', $nsmgr))
        $fenceIndexes = [System.Collections.Generic.List[int]]::new()
        for ($i = 0; $i -lt $paras.Count; $i++) {
            $text = $paras[$i].InnerText.Trim()
            if ($text.StartsWith($fenceOpen, [StringComparison]::Ordinal) -and
                $text.EndsWith($fenceClose, [StringComparison]::Ordinal)) {
                $fenceIndexes.Add($i)
            }
        }

        if ($fenceIndexes.Count -ne 1) {
            continue
        }

        $fenceIndex = $fenceIndexes[0]
        $fenceText = $paras[$fenceIndex].InnerText.Trim()
        $lines = $fenceText -split '\r?\n'
        if ($lines.Count -lt 2) {
            continue
        }
        $code = ($lines | Select-Object -Skip 1 | Select-Object -SkipLast 1) -join "`n"
        $codeNode.InnerText = $code

        $keep = [System.Collections.Generic.List[System.Xml.XmlElement]]::new()
        for ($i = 0; $i -lt $paras.Count; $i++) {
            if ($i -eq $fenceIndex) {
                continue
            }
            if ($paras[$i].InnerText.Trim() -eq [string][char]0x80) {
                continue
            }
            $keep.Add($paras[$i])
        }

        foreach ($child in @($intro.ChildNodes)) {
            $null = $intro.RemoveChild($child)
        }
        foreach ($para in $keep) {
            $null = $remarks.AppendChild($para)
        }
    }
}
