function Get-SREUnrecognized {
    <#
    .SYNOPSIS
        Lists software items the engine could not identify (MatchMethod = None).
    .DESCRIPTION
        These are the items that fell through all recognition steps — exact lookup,
        normalization rules, and fuzzy matching. Review them to write new rules or
        improve existing ones.
    .PARAMETER Catalog
        A SoftwareCatalog instance (from New-SoftwareCatalog).
    .PARAMETER HostName
        Scope results to a specific host (partial match).
    .PARAMETER Top
        Limit the number of rows returned. Default 100.
    .EXAMPLE
        Get-SREUnrecognized -Catalog $catalog
    .EXAMPLE
        Get-SREUnrecognized -Catalog $catalog -HostName 'SERVER-01' -Top 50
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [string] $HostName,

        [int] $Top = 100
    )

    $Catalog.GetUnrecognized($HostName, $Top)
}
