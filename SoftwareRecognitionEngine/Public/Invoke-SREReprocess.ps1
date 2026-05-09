function Invoke-SREReprocess {
    <#
    .SYNOPSIS
        Re-runs recognition on previously unmatched or low-confidence History rows.
    .DESCRIPTION
        Finds unique RawVendor+RawName pairs in History that match the specified criteria,
        re-runs the recognition pipeline on each, and updates History, Products, Variants,
        and LookupTable for any pairs that now resolve to a known family.

        Use this after adding new rules (via New-SRERule or Add-SRERule) to retroactively
        fix records that were ingested before the rule existed.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER MatchMethod
        Reprocess History rows with these match methods. Default: 'None'.
        Valid values: None, Fuzzy, Learned.
    .PARAMETER ConfidenceBelow
        Also reprocess rows whose MatchConfidence is below this value, regardless of method.
        0 (default) disables this filter.
    .PARAMETER WhatIf
        Runs recognition and reports what would change, without writing anything to the database.
    .EXAMPLE
        # Reprocess everything that was unrecognized
        Invoke-SREReprocess -Catalog $c
    .EXAMPLE
        # Reprocess unrecognized + fuzzy matches below 70%
        Invoke-SREReprocess -Catalog $c -MatchMethod None, Fuzzy, Learned -ConfidenceBelow 70
    .EXAMPLE
        # Dry run — see what would improve without touching the DB
        Invoke-SREReprocess -Catalog $c -WhatIf | Format-Table RawName, OldMethod, NewMethod, FamilyName
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [ValidateSet('None', 'Fuzzy', 'Learned')]
        [string[]] $MatchMethod = @('None'),

        [ValidateRange(0, 100)]
        [int] $ConfidenceBelow = 0,

        [switch] $WhatIf
    )

    $dryRun = $WhatIf.IsPresent

    $results = $Catalog.Reprocess($MatchMethod, $ConfidenceBelow, $dryRun)

    $updated   = @($results | Where-Object { $_.Updated })
    $unchanged = @($results | Where-Object { -not $_.Updated })

    if ($dryRun) {
        Write-Host "[WhatIf] $($results.Count) unique pairs examined: $($updated.Count) would improve, $($unchanged.Count) would remain unchanged." -ForegroundColor Yellow
    } else {
        Write-Host "$($results.Count) unique pairs examined: $($updated.Count) improved, $($unchanged.Count) unchanged." -ForegroundColor Green
    }

    return $results
}
