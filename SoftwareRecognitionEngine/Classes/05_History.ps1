class HistoryEntry {
    [long]               $SoftwareId
    [string]             $RawVendor
    [string]             $RawName
    [string]             $DisplayVersion
    [string]             $Guid
    [nullable[datetime]] $InstallDate
    [string]             $RawUser
    [string]             $RegistryKey
    [int]                $FamilyId
    [int]                $ProductId
    [string]             $MatchMethod
    [int]                $MatchConfidence
    [datetime]           $SeenAt
    [string]             $SourceHost

    HistoryEntry() {
        $this.SeenAt = [datetime]::UtcNow
    }

    # Construct from a raw Zabbix install object
    HistoryEntry([PSObject]$raw) {
        $this.SeenAt          = [datetime]::UtcNow
        $this.SoftwareId      = [long]$raw.SoftwareId
        $this.RawVendor       = [string]$raw.Vendor
        $this.RawName         = [string]$raw.Name
        $this.DisplayVersion  = [string]$raw.DisplayVersion
        $this.Guid            = [string]$raw.Guid
        $this.RawUser         = [string]$raw.User
        $this.RegistryKey     = [string]$raw.RegistryKey
        $this.SourceHost      = if ($raw.HostName) { [string]$raw.HostName } else { '' }

        if ($raw.InstallDate -and
            $raw.InstallDate -ne '0001-01-01T00:00:00' -and
            $raw.InstallDate -ne '') {
            try { $this.InstallDate = [datetime]$raw.InstallDate } catch { }
        }
    }
}

class History {
    hidden [string] $_conn   # SimplySql connection name

    History([string]$connectionName) {
        $this._conn = $connectionName
    }

    [void] Record([HistoryEntry]$entry) {
        $sql = @'
INSERT INTO History
    (SoftwareId, RawVendor, RawName, DisplayVersion, Guid,
     InstallDate, RawUser, RegistryKey,
     FamilyId, ProductId, MatchMethod, MatchConfidence, SeenAt, SourceHost)
VALUES
    (@SoftwareId, @RawVendor, @RawName, @DisplayVersion, @Guid,
     @InstallDate, @RawUser, @RegistryKey,
     @FamilyId, @ProductId, @MatchMethod, @MatchConfidence, @SeenAt, @SourceHost)
'@
        Invoke-SqlUpdate -ConnectionName $this._conn -Query $sql -Parameters @{
            SoftwareId      = $entry.SoftwareId
            RawVendor       = if ($null -ne $entry.RawVendor) { $entry.RawVendor } else { '' }
            RawName         = if ($null -ne $entry.RawName) { $entry.RawName } else { '' }
            DisplayVersion  = if ($null -ne $entry.DisplayVersion) { $entry.DisplayVersion } else { '' }
            Guid            = if ($null -ne $entry.Guid) { $entry.Guid } else { '' }
            InstallDate     = $entry.InstallDate
            RawUser         = if ($null -ne $entry.RawUser) { $entry.RawUser } else { '' }
            RegistryKey     = if ($null -ne $entry.RegistryKey) { $entry.RegistryKey } else { '' }
            FamilyId        = if ($entry.FamilyId) { $entry.FamilyId } else { [DBNull]::Value }
            ProductId       = if ($entry.ProductId) { $entry.ProductId } else { [DBNull]::Value }
            MatchMethod     = if ($null -ne $entry.MatchMethod) { $entry.MatchMethod } else { '' }
            MatchConfidence = $entry.MatchConfidence
            SeenAt          = $entry.SeenAt
            SourceHost      = if ($null -ne $entry.SourceHost) { $entry.SourceHost } else { '' }
        }
    }

    [PSObject[]] GetRecent([int]$limit) {
        return Invoke-SqlQuery -ConnectionName $this._conn `
            -Query 'SELECT * FROM History ORDER BY SeenAt DESC LIMIT @n' `
            -Parameters @{ n = $limit }
    }

    [PSObject[]] GetByFamily([int]$familyId, [int]$limit) {
        return Invoke-SqlQuery -ConnectionName $this._conn `
            -Query 'SELECT * FROM History WHERE FamilyId = @fid ORDER BY SeenAt DESC LIMIT @n' `
            -Parameters @{ fid = $familyId; n = $limit }
    }

    [int] GetCount() {
        $row = Invoke-SqlQuery -ConnectionName $this._conn `
            -Query 'SELECT COUNT(*) AS Total FROM History'
        return [int]$row.Total
    }
}
