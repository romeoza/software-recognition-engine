function Add-SREInventory {
    <#
    .SYNOPSIS
        Ingests an array of raw software install objects into the catalog.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER Items
        Array of PSObjects representing software installations. Each must have at minimum:
        Vendor, Name, DisplayVersion, SoftwareId.
    .PARAMETER JsonPath
        Path to a JSON file containing an array of install objects (alternative to -Items).
    .EXAMPLE
        $items = Get-Content zx_installs.json | ConvertFrom-Json
        Add-SREInventory -Catalog $catalog -Items $items
    .EXAMPLE
        Add-SREInventory -Catalog $catalog -JsonPath .\zx_installs.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [Parameter(Mandatory, ParameterSetName = 'Objects')]
        [PSObject[]] $Items,

        [Parameter(Mandatory, ParameterSetName = 'JsonFile')]
        [string] $JsonPath
    )

    if ($PSCmdlet.ParameterSetName -eq 'JsonFile') {
        $Items = Get-Content -Path $JsonPath -Raw | ConvertFrom-Json
    }

    $Catalog.AddInventory($Items)
}
