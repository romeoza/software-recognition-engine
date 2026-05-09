class NormalizationEngine {
    hidden [System.Collections.Generic.List[NormalizationRule]] $_rules

    NormalizationEngine() {
        $this._rules = [System.Collections.Generic.List[NormalizationRule]]::new()
    }

    [void] LoadRules([NormalizationRule[]]$rules) {
        $this._rules.Clear()
        $sorted = $rules | Sort-Object Priority
        foreach ($r in $sorted) { $this._rules.Add($r) }
    }

    [void] AddRule([NormalizationRule]$rule) {
        $this._rules.Add($rule)
        $sorted = @($this._rules | Sort-Object Priority)
        $this._rules.Clear()
        foreach ($r in $sorted) { $this._rules.Add($r) }
    }

    [void] RemoveRule([string]$ruleId) {
        $toRemove = $this._rules | Where-Object { $_.RuleId -eq $ruleId }
        if ($toRemove) { $this._rules.Remove($toRemove) | Out-Null }
    }

    # Returns first matching rule's result, or baseline-cleaned result if no rule matches
    [hashtable] Normalize([string]$vendor, [string]$name) {
        foreach ($rule in $this._rules) {
            if (-not $rule.IsActive) { continue }
            if ($rule.Matches($vendor, $name)) {
                return $rule.Apply($vendor, $name)
            }
        }
        return $this._BaselineClean($vendor, $name)
    }

    [int] get_Count() { return $this._rules.Count }

    [NormalizationRule[]] GetRules() { return $this._rules.ToArray() }

    hidden [hashtable] _BaselineClean([string]$vendor, [string]$name) {
        $n = $name

        # Strip architecture suffixes
        $n = $n -replace '\s*\(x86\)', ''
        $n = $n -replace '\s*\(x64\)', ''
        $n = $n -replace '\s*\b(32-bit|64-bit|amd64|x86_64)\b', ''

        # Strip trailing version numbers (e.g. "7-Zip 24.08" → "7-Zip")
        $n = $n -replace '\s+\d+\.\d+[\.\d]*\s*$', ''

        # Strip trailing 4-digit year tokens (e.g. "Citrix Workspace 2409" → "Citrix Workspace")
        $n = $n -replace '\s+\d{4}$', ''

        # Collapse whitespace
        $n = ($n -replace '\s{2,}', ' ').Trim()

        # Normalize vendor: strip common legal suffixes
        $v = $vendor -replace ',?\s*(Incorporated|Corporation|Corp\.|Inc\.|LLC|Ltd\.|Limited|SE|AG|GmbH|B\.V\.|S\.A\.)\.?\s*$', ''
        $v = $v.Trim()

        return @{
            NormalizedName   = $n
            NormalizedVendor = $v
            FamilyName       = ''
            TargetVendor     = ''
            IsExcluded       = $false
        }
    }
}
