function New-SRERule {
    <#
    .SYNOPSIS
        Creates a normalization rule from a set of unrecognized software items.
    .DESCRIPTION
        Inspects the raw vendor and name strings across the supplied items, auto-generates
        VendorPattern, NamePattern, and StripPatterns, then saves the rule to the database.
        Pipe the output of Get-SREUnrecognized, filter to the items you want grouped, and
        pass them here with a target family name.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER Items
        One or more unrecognized item rows (e.g. from Get-SREUnrecognized). Each must have
        RawVendor and RawName properties.
    .PARAMETER FamilyName
        The canonical product family name to assign matching items to.
    .PARAMETER Vendor
        Target vendor string stored with the family. Auto-derived from the most common
        RawVendor in the items if not supplied.
    .PARAMETER Priority
        Rule priority. Lower numbers run first. Default 55 (custom rule range: 50-79).
    .PARAMETER WhatIf
        Generates and displays the rule without saving it or touching the database.
    .PARAMETER Reprocess
        After saving the rule, immediately reprocess all unmatched History rows so that
        items already in the database benefit from the new rule.
    .EXAMPLE
        $items = Get-SREUnrecognized -Catalog $c | Where-Object { $_.RawName -like 'SAP Business Client*' }
        New-SRERule -Catalog $c -Items $items -FamilyName 'SAP Business Client' -Vendor 'SAP' -WhatIf
    .EXAMPLE
        New-SRERule -Catalog $c -Items $items -FamilyName 'SAP Business Client' -Vendor 'SAP' -Reprocess
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [Parameter(Mandatory, ValueFromPipeline)]
        [PSObject[]] $Items,

        [Parameter(Mandatory)]
        [string] $FamilyName,

        [string] $Vendor,

        [ValidateRange(1, 999)]
        [int] $Priority = 55,

        [switch] $WhatIf,

        [switch] $Reprocess
    )

    begin {
        $allItems = [System.Collections.Generic.List[PSObject]]::new()
    }

    process {
        foreach ($item in $Items) { $allItems.Add($item) }
    }

    end {
        if ($allItems.Count -eq 0) {
            Write-Warning 'No items supplied. Pipe Get-SREUnrecognized output or pass -Items.'
            return
        }

        $vendors = @($allItems | ForEach-Object { [string]$_.RawVendor } | Where-Object { $_ } | Select-Object -Unique)
        $names   = @($allItems | ForEach-Object { [string]$_.RawName   } | Where-Object { $_ } | Select-Object -Unique)

        # ── VendorPattern ─────────────────────────────────────────────────────────
        $escapedVendors = @($vendors | ForEach-Object { [regex]::Escape($_) })
        $vendorPattern  = if ($escapedVendors.Count -eq 1) {
            $escapedVendors[0]
        } else {
            "($($escapedVendors -join '|'))"
        }

        # ── NamePattern (longest common prefix) ───────────────────────────────────
        $namePattern = ''
        if ($names.Count -eq 1) {
            $namePattern = '^' + [regex]::Escape($names[0])
        } elseif ($names.Count -gt 1) {
            $prefix = $names[0]
            foreach ($n in $names[1..($names.Count - 1)]) {
                $maxLen = [Math]::Min($prefix.Length, $n.Length)
                $i = 0
                while ($i -lt $maxLen -and $prefix[$i] -eq $n[$i]) { $i++ }
                $prefix = $prefix.Substring(0, $i)
            }
            $prefix = $prefix.TrimEnd()
            if ($prefix.Length -ge 3) {
                $namePattern = '^' + [regex]::Escape($prefix)
            } else {
                Write-Warning "Names are too diverse for a common prefix (shortest prefix: '$prefix'). NamePattern left empty — rule will match all names for this vendor. Refine manually after review."
            }
        }

        # ── StripPatterns ─────────────────────────────────────────────────────────
        $stripPatterns = @(
            '\s+v?\d+[\.\d]*\s*$'   # trailing version numbers
            '\s+\d{4}$'             # trailing standalone year token
        )
        if ($names | Where-Object { $_ -match '\(' }) {
            $stripPatterns += '\s*\(.*?\)\s*$'
        }

        # ── TargetVendor ──────────────────────────────────────────────────────────
        $targetVendor = if ($Vendor) { $Vendor } else { $vendors | Select-Object -First 1 }

        # ── Assemble rule hashtable ───────────────────────────────────────────────
        $ruleHash = @{
            RuleName      = $FamilyName
            Priority      = $Priority
            VendorPattern = $vendorPattern
            NamePattern   = $namePattern
            TargetFamily  = $FamilyName
            TargetVendor  = $targetVendor
            StripPatterns = $stripPatterns
            Description   = "Auto-generated from $($allItems.Count) unrecognized items"
        }

        # ── Display generated rule ────────────────────────────────────────────────
        Write-Host "`nGenerated rule:" -ForegroundColor Cyan
        Write-Host "  RuleName      : $($ruleHash.RuleName)"
        Write-Host "  Priority      : $($ruleHash.Priority)"
        Write-Host "  VendorPattern : $($ruleHash.VendorPattern)"
        Write-Host "  NamePattern   : $(if ($ruleHash.NamePattern) { $ruleHash.NamePattern } else { '(empty — matches all names)' })"
        Write-Host "  TargetFamily  : $($ruleHash.TargetFamily)"
        Write-Host "  TargetVendor  : $($ruleHash.TargetVendor)"
        Write-Host "  StripPatterns : $($ruleHash.StripPatterns -join ' | ')"
        Write-Host "  Items matched : $($allItems.Count) input items`n"

        $rule = [NormalizationRule]::new($ruleHash)

        if ($WhatIf) {
            Write-Host "[-WhatIf] Rule not saved." -ForegroundColor Yellow
            return $rule
        }

        Add-SRERule -Catalog $Catalog -Rule $rule
        Write-Host "Rule '$FamilyName' saved (RuleId: $($rule.RuleId))." -ForegroundColor Green

        if ($Reprocess) {
            Write-Host "Reprocessing unmatched History rows..." -ForegroundColor Cyan
            $reprocessed = Invoke-SREReprocess -Catalog $Catalog -MatchMethod 'None'
            $improved = @($reprocessed | Where-Object Updated)
            Write-Host "$($improved.Count) of $($reprocessed.Count) unmatched pairs now resolved." -ForegroundColor Green
        }

        return $rule
    }
}
