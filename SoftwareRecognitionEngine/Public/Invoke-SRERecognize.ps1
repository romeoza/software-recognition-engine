function Invoke-SRERecognize {
    <#
    .SYNOPSIS
        Recognizes a single software item and returns a RecognitionResult.
    .PARAMETER Catalog
        A SoftwareCatalog instance.
    .PARAMETER Item
        A PSObject with at minimum Vendor and Name properties.
    .PARAMETER Vendor
        Vendor string (alternative to -Item).
    .PARAMETER Name
        Product name string (alternative to -Item).
    .EXAMPLE
        $result = Invoke-SRERecognize -Catalog $catalog -Vendor "Citrix" -Name "Citrix Workspace 2409"
        $result.FamilyName   # "Citrix Workspace App"
        $result.Confidence   # 95
        $result.MatchMethod  # "Rule"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SoftwareCatalog] $Catalog,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [PSObject] $Item,

        [Parameter(Mandatory, ParameterSetName = 'Strings')]
        [string] $Vendor,

        [Parameter(Mandatory, ParameterSetName = 'Strings')]
        [string] $Name
    )

    if ($PSCmdlet.ParameterSetName -eq 'Strings') {
        $Item = [PSCustomObject]@{ Vendor = $Vendor; Name = $Name }
    }

    return $Catalog.Recognize($Item)
}
