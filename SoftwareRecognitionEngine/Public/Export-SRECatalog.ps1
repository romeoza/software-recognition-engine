function Export-SRECatalog {
    <#
    .SYNOPSIS
        Exports the current catalog state (families, rules, stats) to a JSON file.
    .PARAMETER Catalog
        A SoftwareCatalog instance.
    .PARAMETER Path
        Output file path. Defaults to .\SRECatalogExport_<timestamp>.json
    .PARAMETER StatsOnly
        If specified, exports only statistics rather than full catalog data.
    .EXAMPLE
        Export-SRECatalog -Catalog $catalog -Path C:\Exports\catalog.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [string] $Path,

        [switch] $StatsOnly
    )

    if (-not $Path) {
        $ts   = Get-Date -Format 'yyyyMMdd_HHmmss'
        $Path = ".\SRECatalogExport_$ts.json"
    }

    if ($StatsOnly) {
        $export = $Catalog.GetStats()
    } else {
        $export = @{
            ExportedAt = [datetime]::UtcNow.ToString('o')
            Stats      = $Catalog.GetStats()
            Families   = $Catalog.GetFamilies()
        }
    }

    $export | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
    Write-Host "Catalog exported to: $Path"
}
