function Get-SRETopSoftware {
    <#
    .SYNOPSIS
        Returns the top N most-installed product families across the estate.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER Top
        Number of families to return. Default 25.
    .PARAMETER RankBy
        Rank by 'HostCount' (distinct machines — default) or 'InstallCount' (total install events).
    .EXAMPLE
        Get-SRETopSoftware -Catalog $catalog
    .EXAMPLE
        Get-SRETopSoftware -Catalog $catalog -Top 10 -RankBy InstallCount
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [ValidateRange(1, 1000)]
        [int] $Top = 25,

        [ValidateSet('HostCount', 'InstallCount')]
        [string] $RankBy = 'HostCount'
    )

    $Catalog.GetTopSoftware($RankBy, $Top)
}
