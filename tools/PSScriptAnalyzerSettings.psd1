# PSScriptAnalyzer — paramètres partagés (local + CI)
# ------------------------------------------------------------------
# CI : .github/workflows/PSScriptAnalyzer.yml (microsoft/psscriptanalyzer-action)
#      référence ce fichier directement ; le gate bloquant = severity: "ParseError","Error"
#      renseigné dans le workflow.
# Localement : .\tools\Invoke-Analyzer.ps1 (gate = son paramètre -Severity)
#              ou Invoke-ScriptAnalyzer -Path ... -Settings .\tools\PSScriptAnalyzerSettings.psd1
# Règles dispo : Get-ScriptAnalyzerRule
#
# Découverte automatique par nom : seulement si le répertoire analysé est celui qui
# contient ce fichier ; ici on passe -Settings explicitement pour éviter toute ambiguïté.

@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
    )

    # Laisser @() vide pour conserver « toutes les règles par défaut − ExcludeRules ».
    # Une liste non vide fait de PSA un filtre *exclusif* : seules ces règles s'exécutent — à utiliser avec parcimonie.
    IncludeRules = @(
    )

    Rules = @{
        PSUseConsistentIndentation = @{
            Enable          = $true
            Kind            = 'space'
            IndentationSize = 4
        }

        PSUseConsistentWhitespace = @{
            Enable = $true
        }

        PSAvoidTrailingWhitespace = @{
            Enable = $true
        }

        PSUseCorrectCasing = @{
            Enable = $true
        }

        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }
    }
}
