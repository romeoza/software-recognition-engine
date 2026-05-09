function Get-SREHostInventory {
    <#
    .SYNOPSIS
        Shows installed software on one or more hosts, or lists all known hosts.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER HostName
        Partial host name to match (LIKE pattern). Returns all recognition history for matching hosts.
    .PARAMETER ListHosts
        When specified, returns distinct host names with item counts instead of install details.
    .PARAMETER Top
        Limit the number of rows returned. Default 0 (unlimited).
    .EXAMPLE
        Get-SREHostInventory -Catalog $catalog -ListHosts
    .EXAMPLE
        Get-SREHostInventory -Catalog $catalog -HostName 'LAPTOP-001'
    .EXAMPLE
        Get-SREHostInventory -Catalog $catalog -HostName 'SERVER' -Top 50
    #>
    [CmdletBinding(DefaultParameterSetName = 'Inventory')]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [Parameter(ParameterSetName = 'Inventory')]
        [string] $HostName,

        [Parameter(Mandatory, ParameterSetName = 'ListHosts')]
        [switch] $ListHosts,

        [Parameter(ParameterSetName = 'Inventory')]
        [int] $Top = 0
    )

    if ($ListHosts) {
        $Catalog.GetHosts()
    } else {
        if (-not $HostName) {
            Write-Warning 'Specify -HostName to filter by host, or use -ListHosts to see all known hosts.'
            return
        }
        $Catalog.GetHostInventory($HostName, $Top)
    }
}
