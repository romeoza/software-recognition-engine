function New-SoftwareCatalog {
    <#
    .SYNOPSIS
        Creates and returns a new SoftwareCatalog instance connected to MySQL.
    .PARAMETER ConnectionString
        MySQL connection string. If omitted, falls back to $env:SRE_CONNECTION_STRING or
        %APPDATA%\SoftwareRecognitionEngine\config.json.
    .PARAMETER ConnectionName
        Optional name for the SimplySql connection. Defaults to a generated unique name.
    .EXAMPLE
        $catalog = New-SoftwareCatalog -ConnectionString "Server=localhost;Database=SRE;Uid=root;Pwd=secret;"
    #>
    [CmdletBinding()]
    param(
        [string] $ConnectionString,
        [string] $ConnectionName
    )

    if ($ConnectionName -and $ConnectionString) {
        return [SoftwareCatalog]::new($ConnectionName, $ConnectionString)
    }
    if ($ConnectionString) {
        return [SoftwareCatalog]::new($ConnectionString)
    }
    return [SoftwareCatalog]::new()
}
