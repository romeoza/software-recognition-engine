function Get-SRENewSoftware {
    <#
    .SYNOPSIS
        Lists software first seen in the catalog within the last N days.
    .DESCRIPTION
        Useful for detecting new deployments, unapproved installs, or changes since the
        last inventory scan. Results are grouped by host so repeated scans don't inflate counts.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER Days
        Look back this many days. Default 7.
    .PARAMETER HostName
        Scope results to a specific host (partial match).
    .EXAMPLE
        Get-SRENewSoftware -Catalog $catalog
    .EXAMPLE
        Get-SRENewSoftware -Catalog $catalog -Days 1 -HostName 'LAPTOP-001'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [ValidateRange(1, 3650)]
        [int] $Days = 7,

        [string] $HostName
    )

    $Catalog.GetNewSoftware($Days, $HostName)
}
