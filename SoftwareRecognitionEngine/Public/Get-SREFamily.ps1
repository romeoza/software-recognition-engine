function Get-SREFamily {
    <#
    .SYNOPSIS
        Lists product families in the catalog, with optional name/vendor filtering.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER Name
        Filter families whose name contains this string (case-insensitive LIKE match).
    .PARAMETER Vendor
        Filter families whose vendor contains this string (case-insensitive LIKE match).
    .EXAMPLE
        Get-SREFamily -Catalog $catalog
    .EXAMPLE
        Get-SREFamily -Catalog $catalog -Vendor 'Microsoft'
    .EXAMPLE
        Get-SREFamily -Catalog $catalog -Name 'Citrix' | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [string] $Name,

        [string] $Vendor
    )

    if ($Name -or $Vendor) {
        $Catalog.GetFamilies($Name, $Vendor)
    } else {
        $Catalog.GetFamilies()
    }
}
