# PSScriptAnalyzer — paramètres partagés (local + CI)
# ------------------------------------------------------------------
# CI : build/Invoke-Analyzer.ps1 ; le gate bloquant = paramètre -Severity du
#      script (phase 1 typique : ParseError, Error). Les severités ci-dessous
#      fixent ce que PSA évalue ; Invoke-Analyzer filtre ce qui fait échouer la build.
# Localement : .\build\Invoke-Analyzer.ps1
#              ou Invoke-ScriptAnalyzer -Path ... -Settings .\build\PSScriptAnalyzerSettings.psd1
# Règles dispo : Get-ScriptAnalyzerRule
#
# Découverte automatique par nom : seulement si le répertoire analysé est celui qui
# contient ce fichier ; ici on passe -Settings explicitement depuis Invoke-Analyzer.ps1.

@{

    # Severités analysées. Les warnings peuvent être non bloquants selon -Severity sur Invoke-Analyzer.ps1.
    # Attention : -Severity en ligne de commande peut encore varier selon la version de PSA ; le filtre du script reste la référence.
    Severity = @(
        'ParseError'
        'Error'
        'Warning'
    )

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
