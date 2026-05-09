function Get-SREProduct {
    <#
    .SYNOPSIS
        Lists products in the catalog, optionally scoped to a family or filtered by name.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER FamilyId
        Return only products belonging to this family ID.
    .PARAMETER FamilyName
        Return only products belonging to this family (resolved by name, partial match).
    .PARAMETER Search
        Filter products whose name contains this string (case-insensitive LIKE match).
    .EXAMPLE
        Get-SREProduct -Catalog $catalog
    .EXAMPLE
        Get-SREProduct -Catalog $catalog -FamilyName 'Citrix Workspace'
    .EXAMPLE
        Get-SREProduct -Catalog $catalog -Search 'AnyConnect' | Format-Table
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [Parameter(ParameterSetName = 'ById')]
        [int] $FamilyId,

        [Parameter(ParameterSetName = 'ByName')]
        [string] $FamilyName,

        [string] $Search
    )

    $resolvedFamilyId = 0

    if ($PSCmdlet.ParameterSetName -eq 'ByName' -and $FamilyName) {
        $families = $Catalog.GetFamilies($FamilyName, '')
        if ($families.Count -eq 0) {
            Write-Warning "No family found matching '$FamilyName'."
            return
        }
        # Use first match; warn if ambiguous
        if ($families.Count -gt 1) {
            Write-Warning "$($families.Count) families match '$FamilyName' — using '$($families[0].FamilyName)' (FamilyId $($families[0].FamilyId)). Use -FamilyId to be specific."
        }
        $resolvedFamilyId = [int]$families[0].FamilyId
    } elseif ($FamilyId -gt 0) {
        $resolvedFamilyId = $FamilyId
    }

    $Catalog.GetProducts($resolvedFamilyId, $Search)
}
