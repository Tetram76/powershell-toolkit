# Aide au paramétrage (PSScriptAnalyzer, racine du dépôt)
# ------------------------------------------------------------------
# CI : `.github/workflows/powershell-ci.yml` appelle Invoke-ScriptAnalyzer avec ce fichier
#      puis ne fait échouer le job que sur ParseError et Error → garde ces severités ci-dessous
#      synchro avec le filtre `$failures` du workflow pour ne pas avoir vert local / rouge GH (ou inverse).
# Localement : Invoke-ScriptAnalyzer -Path .\chemin\fichier.ps1 -Settings $PWD/.PSScriptAnalyzerSettings.psd1
# Règles dispo : Get-ScriptAnalyzerRule

@{

    # Niveaux pris en compte ci : typiquement @('ParseError','Error').
    # Attention : passer -Severity différent en ligne de commande peut encore restreindre la sortie selon la version de PSA.
    Severity = @('ParseError', 'Error')

    # Noms exacts des règles à désactiver, ex. 'PSAvoidUsingCmdletAliases'.
    # Remplir uniquement après décision équipe ou ticket ; tout ajout doit être justifié (bruit faux positifs, bug PSA, migration en cours…).
    ExcludeRules = @(
    )

    # Laisser @() vide pour conserver « toutes les règles par défaut − ExcludeRules ».
    # Une liste non vide fait de PSA un filtre *exclusif* : seules ces règles s'exécutent — à utiliser avec parcimonie (scénarios ciblés, pas le quotidien).
    IncludeRules = @(
    )
}
