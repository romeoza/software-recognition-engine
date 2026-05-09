function Get-SREVariant {
    <#
    .SYNOPSIS
        Lists raw name variants recorded for a specific product.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER ProductId
        The product to retrieve variants for.
    .EXAMPLE
        Get-SREVariant -Catalog $catalog -ProductId 42
    .EXAMPLE
        Get-SREProduct -Catalog $catalog -FamilyName 'Citrix Workspace' |
            ForEach-Object { Get-SREVariant -Catalog $catalog -ProductId $_.ProductId }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [Parameter(Mandatory)]
        [int] $ProductId
    )

    $Catalog.GetVariants($ProductId)
}
