function Get-SREHostCount {
    <#
    .SYNOPSIS
        Returns the number of distinct hosts that have a given product family installed.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER FamilyId
        The product family to count hosts for.
    .PARAMETER FamilyName
        The product family to count hosts for, resolved by name (partial match).
    .EXAMPLE
        Get-SREHostCount -Catalog $catalog -FamilyName 'Citrix Workspace'
    .EXAMPLE
        Get-SREHostCount -Catalog $catalog -FamilyId 12
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [int] $FamilyId,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string] $FamilyName
    )

    $resolvedFamilyId = $FamilyId

    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $families = $Catalog.GetFamilies($FamilyName, '')
        if ($families.Count -eq 0) {
            Write-Warning "No family found matching '$FamilyName'."
            return
        }
        if ($families.Count -gt 1) {
            Write-Warning "$($families.Count) families match '$FamilyName' — using '$($families[0].FamilyName)'. Use -FamilyId to be specific."
        }
        $resolvedFamilyId = [int]$families[0].FamilyId
    }

    $Catalog.GetHostCount($resolvedFamilyId)
}
