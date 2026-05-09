function Get-SREStaleSoftware {
    <#
    .SYNOPSIS
        Lists products that have not been seen in inventory for at least N days.
    .DESCRIPTION
        Products absent from recent scans may have been uninstalled or the host may have
        been decommissioned. Use this to clean up the catalog or flag items for review.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER Days
        Products not seen within this many days are returned. Default 30.
    .EXAMPLE
        Get-SREStaleSoftware -Catalog $catalog
    .EXAMPLE
        Get-SREStaleSoftware -Catalog $catalog -Days 90 | Select-Object FamilyName, ProductName, DaysSinceLastSeen
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [ValidateRange(1, 3650)]
        [int] $Days = 30
    )

    $Catalog.GetStaleSoftware($Days)
}
