@{
    RootModule        = 'SoftwareRecognitionEngine.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f7c2d1-4e8b-4f1a-9c3d-2b5e6f7a8c9d'
    Author            = ''
    Description       = 'Self-learning software inventory normalization and recognition engine for Zabbix and similar inventory systems.'
    PowerShellVersion = '5.1'
    RequiredModules   = @('SimplySql')
    FunctionsToExport = @(
        'New-SoftwareCatalog',
        'Add-SREInventory',
        'Invoke-SRERecognize',
        'Add-SRERule',
        'Export-SRECatalog',
        'Get-SREFamily',
        'Get-SREProduct',
        'Get-SREVariant',
        'Get-SREHostInventory',
        'Get-SREVersionSprawl',
        'Get-SREUnrecognized',
        'Get-SRELowConfidence',
        'Get-SRENewSoftware',
        'Get-SREStaleSoftware',
        'Get-SREHostCount',
        'Get-SRETopSoftware',
        'New-SRERule',
        'Invoke-SREReprocess'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
