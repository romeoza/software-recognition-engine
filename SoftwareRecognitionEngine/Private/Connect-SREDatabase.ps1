function Connect-SREDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConnectionName,

        [Parameter(Mandatory)]
        [string] $ConnectionString,

        [int] $RetryCount  = 3,
        [int] $RetryDelay  = 2   # seconds between retries
    )

    $attempt = 0
    while ($attempt -lt $RetryCount) {
        $attempt++
        try {
            Open-MySqlConnection -ConnectionName $ConnectionName -ConnectionString $ConnectionString
            return  # success
        }
        catch {
            if ($attempt -ge $RetryCount) {
                throw "Failed to connect to MySQL after $RetryCount attempts. Connection: '$ConnectionName'. Error: $_"
            }
            Write-Verbose "MySQL connection attempt $attempt failed; retrying in ${RetryDelay}s..."
            Start-Sleep -Seconds $RetryDelay
        }
    }
}
