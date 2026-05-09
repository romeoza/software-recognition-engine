class NormalizationRule {
    [string]        $RuleId
    [string]        $RuleName
    [int]           $Priority        # lower = runs first
    [bool]          $IsActive
    [bool]          $IsBuiltIn
    [bool]          $IsExcludeRule   # if true, matched items are marked as noise
    [string]        $VendorPattern   # regex; empty = match all vendors
    [string]        $NamePattern     # regex; empty = match all names
    [string]        $TargetFamily
    [string]        $TargetVendor
    [string[]]      $StripPatterns   # regex strings to remove from name
    [hashtable[]]   $Transformations # [{Field, Pattern, Replacement}]
    [string]        $Description

    NormalizationRule() {
        $this.Priority      = 100
        $this.IsActive      = $true
        $this.IsBuiltIn     = $false
        $this.IsExcludeRule = $false
        $this.StripPatterns = @()
        $this.Transformations = @()
        $this.RuleId        = [guid]::NewGuid().ToString()
    }

    NormalizationRule([hashtable]$props) {
        # Defaults
        $this.Priority        = 100
        $this.IsActive        = $true
        $this.IsBuiltIn       = $false
        $this.IsExcludeRule   = $false
        $this.StripPatterns   = @()
        $this.Transformations = @()
        $this.RuleId          = [guid]::NewGuid().ToString()

        foreach ($key in $props.Keys) {
            $this.$key = $props[$key]
        }
    }

    # Returns $true if this rule applies to the given vendor+name pair
    [bool] Matches([string]$vendor, [string]$name) {
        if ($this.VendorPattern -and $vendor -notmatch $this.VendorPattern) {
            return $false
        }
        if ($this.NamePattern -and $name -notmatch $this.NamePattern) {
            return $false
        }
        return $true
    }

    # Applies strip patterns and transformations; returns result hashtable
    [hashtable] Apply([string]$vendor, [string]$name) {
        $result = @{
            NormalizedName   = $name
            NormalizedVendor = $vendor
            FamilyName       = $this.TargetFamily
            TargetVendor     = $this.TargetVendor
            IsExcluded       = $this.IsExcludeRule
        }

        if (-not $this.IsExcludeRule) {
            foreach ($pattern in $this.StripPatterns) {
                $result.NormalizedName = $result.NormalizedName -replace $pattern, ''
            }
            foreach ($t in $this.Transformations) {
                $field = $t.Field
                if ($result.ContainsKey($field)) {
                    $result[$field] = $result[$field] -replace $t.Pattern, $t.Replacement
                }
            }
            $result.NormalizedName   = ($result.NormalizedName).Trim() -replace '\s{2,}', ' '
            $result.NormalizedVendor = ($result.NormalizedVendor).Trim()

            # Use TargetVendor override if provided
            if ($this.TargetVendor) {
                $result.NormalizedVendor = $this.TargetVendor
            }
        }

        return $result
    }

    [string] ToString() {
        return "[P$($this.Priority)] $($this.RuleName)"
    }
}
