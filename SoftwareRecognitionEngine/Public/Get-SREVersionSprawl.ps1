function Get-SREVersionSprawl {
    <#
    .SYNOPSIS
        Shows distinct versions of a product family observed across the estate, ordered by host count.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER FamilyId
        The product family to analyze.
    .PARAMETER FamilyName
        The product family to analyze, resolved by name (partial match).
    .PARAMETER Top
        Limit the number of version rows returned. Default 0 (unlimited).
    .EXAMPLE
        Get-SREVersionSprawl -Catalog $catalog -FamilyName 'Citrix Workspace'
    .EXAMPLE
        Get-SREVersionSprawl -Catalog $catalog -FamilyId 7 -Top 10
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [int] $FamilyId,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string] $FamilyName,

        [int] $Top = 0
    )

    $resolvedFamilyId = $FamilyId

    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $families = $Catalog.GetFamilies($FamilyName, '')
        if ($families.Count -eq 0) {
            Write-Warning "No family found matching '$FamilyName'."
            return
        }
        if ($families.Count -gt 1) {
            Write-Warning "$($families.Count) families match '$FamilyName' using '$($families[0].FamilyName)'. Use -FamilyId to be specific."
        }
        $resolvedFamilyId = [int]$families[0].FamilyId
    }

    $Catalog.GetVersionSprawl($resolvedFamilyId, $Top)
}
