function Get-SRELowConfidence {
    <#
    .SYNOPSIS
        Lists fuzzy and learned matches below a confidence threshold.
    .DESCRIPTION
        These items were matched but with low certainty. Review them to confirm the
        assignment is correct or to add a more specific normalization rule.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER Threshold
        Confidence percentage below which matches are returned. Default 70.
    .PARAMETER Top
        Limit the number of rows returned. Default 100.
    .EXAMPLE
        Get-SRELowConfidence -Catalog $catalog
    .EXAMPLE
        Get-SRELowConfidence -Catalog $catalog -Threshold 60 | Sort-Object MatchConfidence
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [ValidateRange(1, 99)]
        [int] $Threshold = 70,

        [int] $Top = 100
    )

    $Catalog.GetLowConfidence($Threshold, $Top)
}
