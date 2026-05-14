# PSScriptAnalyzer settings for this repository (root). CI job "PSScriptAnalyzer" runs:
#   Invoke-ScriptAnalyzer -Settings ./.PSScriptAnalyzerSettings.psd1
# from the repo root. If the workflow also passes -Severity, some PSA versions may
# narrow output further; keep Severity values here and in the job aligned (ParseError + Error).
#
# Iterate locally with: Get-ScriptAnalyzerRule; Invoke-ScriptAnalyzer -Path <file> -Settings $PWD/.PSScriptAnalyzerSettings.psd1

@{

    # Severity — inclure ParseError pour les échecs de parsing ; aligné avec le job CI (ParseError + Error bloquent).
    Severity = @('ParseError', 'Error')

    # ExcludeRules — rule names such as PSAvoidUsingCmdletAliases; suppress noisy rules temporarily.
    ExcludeRules = @(
    )

    # IncludeRules — if non-empty in some setups, only these rules apply; usually @() meaning "use defaults minus ExcludeRules".
    IncludeRules = @(
    )
}
