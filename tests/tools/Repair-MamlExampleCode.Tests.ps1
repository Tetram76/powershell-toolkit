# Post-traitement MAML : PlatyPS 1.0 met les fences d'exemple dans l'introduction.
# RepoRoot depuis tests/tools : $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path

BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
    $script:RepairScript = Join-Path $script:RepoRoot 'tools' 'Repair-MamlExampleCode.ps1'
    . $script:RepairScript

    function script:Get-ExampleXml {
        param([Parameter(Mandatory)] [xml] $Document)

        $nsmgr = [System.Xml.XmlNamespaceManager]::new($Document.NameTable)
        $nsmgr.AddNamespace('maml', 'http://schemas.microsoft.com/maml/2004/10')
        $nsmgr.AddNamespace('command', 'http://schemas.microsoft.com/maml/dev/command/2004/10')
        $nsmgr.AddNamespace('dev', 'http://schemas.microsoft.com/maml/dev/2004/10')
        [pscustomobject]@{
            Manager    = $nsmgr
            Example    = $Document.SelectSingleNode('//command:example', $nsmgr)
            Code       = $Document.SelectSingleNode('//command:example/dev:code', $nsmgr)
            Remarks    = $Document.SelectSingleNode('//command:example/dev:remarks', $nsmgr)
            IntroParas = @($Document.SelectNodes('//command:example/maml:introduction/maml:para', $nsmgr))
        }
    }

    function script:New-ExampleHelpXml {
        param([Parameter(Mandatory)] [string[]] $Paras)

        $paraXml = ($Paras | ForEach-Object { "          <maml:para>$_</maml:para>" }) -join "`n"
        $raw = @"
<?xml version="1.0" encoding="utf-8"?>
<helpItems xmlns:maml="http://schemas.microsoft.com/maml/2004/10" xmlns:command="http://schemas.microsoft.com/maml/dev/command/2004/10" xmlns:dev="http://schemas.microsoft.com/maml/dev/2004/10" schema="maml" xmlns="http://msh">
  <command:command>
    <command:details>
      <command:name>Get-Foo</command:name>
    </command:details>
    <command:examples>
      <command:example>
        <maml:title>--------- Example 1: Foo ---------</maml:title>
        <maml:introduction>
$paraXml
        </maml:introduction>
        <dev:code />
        <dev:remarks />
      </command:example>
    </command:examples>
  </command:command>
</helpItems>
"@
        [xml] $raw
    }
}

Describe 'Repair-MamlExampleCode' {

    It 'extrait l''unique fence powershell vers dev:code et retire le marqueur PAD' {
        $doc = script:New-ExampleHelpXml -Paras @(
            'Intention : demo.'
            '&#x80;'
            "``````powershell`nGet-Foo -Bar`n``````"
        )

        Repair-MamlExampleCode -Document $doc

        $x = script:Get-ExampleXml -Document $doc
        $x.Code.InnerText | Should -Be 'Get-Foo -Bar'
        $x.IntroParas.Count | Should -Be 0
        @($x.Remarks.ChildNodes | Where-Object { $_.LocalName -eq 'para' }).Count | Should -Be 1
        $x.Remarks.InnerText.Trim() | Should -Be 'Intention : demo.'
    }

    It 'deplace le texte avant et apres la fence vers dev:remarks' {
        $doc = script:New-ExampleHelpXml -Paras @(
            'Intention : demo.'
            '&#x80;'
            "``````powershell`nGet-Foo`n``````"
            '&#x80;'
            'Les paires s''affichent.'
        )

        Repair-MamlExampleCode -Document $doc

        $x = script:Get-ExampleXml -Document $doc
        $x.Code.InnerText | Should -Be 'Get-Foo'
        $x.IntroParas.Count | Should -Be 0
        $remarkParas = @($x.Remarks.ChildNodes | Where-Object { $_.LocalName -eq 'para' })
        $remarkParas.Count | Should -Be 2
        $remarkParas[0].InnerText | Should -Be 'Intention : demo.'
        $remarkParas[1].InnerText | Should -Be "Les paires s'affichent."
    }

    It 'ne touche pas un exemple sans fence' {
        $doc = script:New-ExampleHelpXml -Paras @('Intention : sans script.')
        $before = $doc.OuterXml

        Repair-MamlExampleCode -Document $doc

        $x = script:Get-ExampleXml -Document $doc
        $x.Code.InnerText | Should -BeNullOrEmpty
        $doc.OuterXml | Should -Be $before
    }

    It 'ne touche pas un exemple a deux fences' {
        $doc = script:New-ExampleHelpXml -Paras @(
            "``````powershell`nGet-Foo`n``````"
            "``````powershell`nGet-Bar`n``````"
        )
        $before = $doc.OuterXml

        Repair-MamlExampleCode -Document $doc

        $x = script:Get-ExampleXml -Document $doc
        $x.Code.InnerText | Should -BeNullOrEmpty
        $doc.OuterXml | Should -Be $before
    }
}
