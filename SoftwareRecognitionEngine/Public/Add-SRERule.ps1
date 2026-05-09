function Add-SRERule {
    <#
    .SYNOPSIS
        Adds a custom normalization rule to the catalog engine and persists it to the database.
    .PARAMETER Catalog
        A SoftwareCatalog instance.
    .PARAMETER Rule
        A NormalizationRule object.
    .PARAMETER Hashtable
        A hashtable of rule properties (alternative to -Rule). A NormalizationRule will be
        constructed from the hashtable.
    .EXAMPLE
        Add-SRERule -Catalog $catalog -Hashtable @{
            RuleName      = 'My Corporate App'
            Priority      = 55
            VendorPattern = 'ACME Corp'
            NamePattern   = '^MyApp'
            TargetFamily  = 'ACME MyApp'
            TargetVendor  = 'ACME'
            StripPatterns = @('\s+\d+[\.\d]*$')
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [NormalizationRule] $Rule,

        [Parameter(Mandatory, ParameterSetName = 'Hash')]
        [hashtable] $Hashtable
    )

    if ($PSCmdlet.ParameterSetName -eq 'Hash') {
        $Rule = [NormalizationRule]::new($Hashtable)
    }

    $Catalog.AddRule($Rule)
}
