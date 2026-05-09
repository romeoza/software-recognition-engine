class RecognitionResult {
    [int]    $FamilyId
    [string] $FamilyName
    [int]    $ProductId
    [string] $ProductName
    [int]    $Confidence      # 0-100
    [string] $MatchMethod     # None / Exact / Rule / Fuzzy / Learned
    [bool]   $IsExcluded
}

class SoftwareCatalog {
    [string] $ConnectionName
    [string] $ConnectionString

    hidden [NormalizationEngine] $_engine
    hidden [FuzzyMatcher]        $_fuzzy
    hidden [History]             $_history
    hidden [hashtable]           $_lookupCache   # LookupKey -> @{FamilyId,FamilyName,ProductId,Confidence}

    # == Constructors ============================================================

    SoftwareCatalog() {
        $this._Init('SRE_Default', $this._ResolveConnectionString($null))
    }

    SoftwareCatalog([string]$connectionString) {
        $name = 'SRE_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $this._Init($name, $connectionString)
    }

    SoftwareCatalog([string]$connectionName, [string]$connectionString) {
        $this._Init($connectionName, $connectionString)
    }

    # == Public API ==============================================================

    # Ingest an array of raw install objects (from Zabbix JSON or similar)
    [void] AddInventory([PSObject[]]$items) {
        foreach ($item in $items) {
            $result = $this.Recognize($item)

            $entry                 = [HistoryEntry]::new($item)
            $entry.FamilyId        = $result.FamilyId
            $entry.ProductId       = $result.ProductId
            $entry.MatchMethod     = $result.MatchMethod
            $entry.MatchConfidence = $result.Confidence

            $this._history.Record($entry)

            if ($result.IsExcluded) { continue }

            if ($result.FamilyId -gt 0) {
                $productId = $this._UpsertProduct($item, $result)
                if ($productId -gt 0) {
                    $result.ProductId = $productId
                    $this._UpsertVariant($item, $result)
                }
            } else {
                # Unknown item — learn it
                $this._LearnNewFamily($item)
            }
        }
    }

    # Recognize a single software item; returns RecognitionResult
    [RecognitionResult] Recognize([PSObject]$item) {
        $vendor = [string]$item.Vendor
        $name   = [string]$item.Name

        # == Step 1: Exact lookup (O(1) hashtable) ==
        $key = $this._MakeLookupKey($vendor, $name)
        if ($this._lookupCache.ContainsKey($key)) {
            $cached = $this._lookupCache[$key]
            return [RecognitionResult]@{
                FamilyId    = $cached.FamilyId
                FamilyName  = $cached.FamilyName
                ProductId   = $cached.ProductId
                Confidence  = $cached.Confidence
                MatchMethod = $cached.MatchMethod   # preserves original method (Rule/Fuzzy/Learned)
                IsExcluded  = $false
            }
        }

        # == Step 2: Normalization rules ==
        $normalized = $this._engine.Normalize($vendor, $name)

        if ($normalized.IsExcluded) {
            return [RecognitionResult]@{
                Confidence  = 100
                MatchMethod = 'Rule'
                IsExcluded  = $true
            }
        }

        if ($normalized.FamilyName) {
            $familyVendor = if ($normalized.TargetVendor) { $normalized.TargetVendor } else { $normalized.NormalizedVendor }
            $family = $this._GetOrCreateFamily($normalized.FamilyName, $familyVendor)
            $this._AddToLookupCache($key, $family.FamilyId, $family.FamilyName, 0, 95, 'Rule')
            return [RecognitionResult]@{
                FamilyId    = $family.FamilyId
                FamilyName  = $family.FamilyName
                Confidence  = 95
                MatchMethod = 'Rule'
                IsExcluded  = $false
            }
        }

        # == Step 3: Fuzzy match against FuzzyIndex ==
        $fuzzyResult = $this._FuzzySearch($normalized.NormalizedName, $normalized.NormalizedVendor)
        if ($null -ne $fuzzyResult -and $fuzzyResult.Confidence -ge $this._fuzzy.MinConfidence) {
            $this._AddToLookupCache($key, $fuzzyResult.FamilyId, $fuzzyResult.FamilyName, 0, $fuzzyResult.Confidence, 'Fuzzy')
            return [RecognitionResult]@{
                FamilyId    = $fuzzyResult.FamilyId
                FamilyName  = $fuzzyResult.FamilyName
                ProductId   = $fuzzyResult.ProductId
                Confidence  = $fuzzyResult.Confidence
                MatchMethod = 'Fuzzy'
                IsExcluded  = $false
            }
        }

        # No match
        return [RecognitionResult]@{
            Confidence  = 0
            MatchMethod = 'None'
            IsExcluded  = $false
        }
    }

    [void] AddRule([NormalizationRule]$rule) {
        $this._engine.AddRule($rule)
        $this._SaveRuleToDb($rule)
    }

    # Returns all known product families
    [PSObject[]] GetFamilies() {
        return Invoke-SqlQuery -ConnectionName $this.ConnectionName `
            -Query 'SELECT * FROM ProductFamilies ORDER BY FamilyName'
    }

    # Returns catalog statistics
    [hashtable] GetStats() {
        $stats = @{}
        $tables = @('ProductFamilies','Products','Variants','History','NormalizationRules','LookupTable')
        foreach ($t in $tables) {
            $row = Invoke-SqlQuery -ConnectionName $this.ConnectionName `
                -Query "SELECT COUNT(*) AS n FROM $t"
            $stats[$t] = [int]$row.n
        }
        $stats['LookupCacheEntries'] = $this._lookupCache.Count
        return $stats
    }

    # == Initialisation ==========================================================

    hidden [void] _Init([string]$connName, [string]$connStr) {
        $this.ConnectionName   = $connName
        $this.ConnectionString = $connStr
        $this._engine          = [NormalizationEngine]::new()
        $this._fuzzy           = [FuzzyMatcher]::new()
        $this._lookupCache     = @{}

        Connect-SREDatabase -ConnectionName $connName -ConnectionString $connStr
        $this._history = [History]::new($connName)

        $this._EnsureSchema()
        $this._LoadRulesFromDb()
        $this._WarmLookupCache()
    }

    hidden [string] _ResolveConnectionString([string]$supplied) {
        if ($supplied) { return $supplied }

        $fromEnv = $env:SRE_CONNECTION_STRING
        if ($fromEnv) { return $fromEnv }

        $cfgPath = Join-Path $env:APPDATA 'SoftwareRecognitionEngine\config.json'
        if (Test-Path $cfgPath) {
            try {
                $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
                if ($cfg.ConnectionString) { return $cfg.ConnectionString }
            } catch { }
        }

        throw @'
No MySQL connection string found. Supply one via:
  1. Constructor parameter: [SoftwareCatalog]::new("Server=...;Database=SRE;User=...;Password=...")
  2. Environment variable:  $env:SRE_CONNECTION_STRING = "..."
  3. Config file:           %APPDATA%\SoftwareRecognitionEngine\config.json  {"ConnectionString":"..."}
'@
    }

    hidden [void] _EnsureSchema() {
        $schemaPath = Join-Path $PSScriptRoot '..\Data\Schema.sql'
        if (-not (Test-Path $schemaPath)) { return }

        $WarningPreference = 'SilentlyContinue'

        # Split on statement boundaries; skip pure-comment or blank segments
        $ddl = Get-Content $schemaPath -Raw
        $statements = $ddl -split ';\s*\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -notmatch '^--' -and $_ -match '\bCREATE\b|\bALTER\b|\bINSERT\b|\bDROP\b' }
        foreach ($stmt in $statements) {
            $trimmed = $stmt.Trim()
            if ($trimmed) {
                try {
                    Invoke-SqlUpdate -ConnectionName $this.ConnectionName -Query $trimmed | Out-Null
                } catch {
                    # Ignore already-existing objects (IF NOT EXISTS handles most cases)
                }
            }
        }
    }

    hidden [void] _LoadRulesFromDb() {
        # Load any custom rules persisted in DB
        $rows = @(Invoke-SqlQuery -ConnectionName $this.ConnectionName `
            -Query 'SELECT * FROM NormalizationRules WHERE IsActive = 1 ORDER BY Priority')

        $rules = foreach ($row in $rows) {
            [NormalizationRule]@{
                RuleId          = $row.RuleId
                RuleName        = $row.RuleName
                Priority        = [int]$row.Priority
                IsActive        = [bool]$row.IsActive
                IsBuiltIn       = [bool]$row.IsBuiltIn
                IsExcludeRule   = [bool]$row.IsExcludeRule
                VendorPattern   = $row.VendorPattern
                NamePattern     = $row.NamePattern
                TargetFamily    = $row.TargetFamily
                TargetVendor    = $row.TargetVendor
                StripPatterns   = @(($row.StripPatterns  | ConvertFrom-Json) | Where-Object { $_ })
                Transformations = @(($row.Transformations | ConvertFrom-Json) | Where-Object { $_ } |
                                  ForEach-Object { @{ Field = $_.Field; Pattern = $_.Pattern; Replacement = $_.Replacement } })
                Description     = $row.Description
            }
        }

        if ($rules.Count -eq 0) {
            # First run — seed built-in rules
            . (Join-Path $PSScriptRoot '..\Data\BuiltInRules.ps1')
            $builtIn = Get-SREBuiltInRules
            foreach ($r in $builtIn) { $this._SaveRuleToDb($r) }
            $this._engine.LoadRules($builtIn)
        } else {
            $this._engine.LoadRules($rules)
        }
    }

    hidden [void] _WarmLookupCache() {
        $this._lookupCache = @{}
        $rows = @(Invoke-SqlQuery -ConnectionName $this.ConnectionName `
            -Query 'SELECT LookupKey, FamilyId, FamilyName, ProductId, Confidence, MatchMethod FROM LookupTable')
        foreach ($row in $rows) {
            $this._lookupCache[$row.LookupKey] = @{
                FamilyId    = [int]$row.FamilyId
                FamilyName  = [string]$row.FamilyName
                ProductId   = if ($row.ProductId -is [System.DBNull] -or $null -eq $row.ProductId) { 0 } else { [int]$row.ProductId }
                Confidence  = [int]$row.Confidence
                MatchMethod = [string]$row.MatchMethod
            }
        }
    }

    # == Lookup helpers ==========================================================

    hidden [string] _MakeLookupKey([string]$vendor, [string]$name) {
        $v = ($vendor.ToLower().Trim() -replace '[^\w]', '')
        $n = ($name.ToLower().Trim()   -replace '\s{2,}', ' ')
        return "${v}::${n}"
    }

    hidden [void] _AddToLookupCache([string]$key, [int]$familyId, [string]$familyName, [int]$productId, [int]$confidence, [string]$matchMethod) {
        $this._lookupCache[$key] = @{
            FamilyId    = $familyId
            FamilyName  = $familyName
            ProductId   = $productId
            Confidence  = $confidence
            MatchMethod = $matchMethod
        }
        # Persist to DB (upsert)
        $sql = @'
INSERT INTO LookupTable (LookupKey, FamilyId, FamilyName, ProductId, Confidence, MatchMethod)
VALUES (@k, @fid, @fname, @pid, @conf, @method)
ON DUPLICATE KEY UPDATE
    FamilyId    = VALUES(FamilyId),
    FamilyName  = VALUES(FamilyName),
    ProductId   = VALUES(ProductId),
    Confidence  = VALUES(Confidence),
    MatchMethod = VALUES(MatchMethod)
'@
        Invoke-SqlUpdate -ConnectionName $this.ConnectionName -Query $sql -Parameters @{
            k      = $key
            fid    = $familyId
            fname  = $familyName
            pid    = if ($productId) { $productId } else { [DBNull]::Value }
            conf   = $confidence
            method = $matchMethod
        } | Out-Null
    }

    # == Family management ========================================================

    hidden [hashtable] _GetOrCreateFamily([string]$familyName, [string]$vendor) {
        $normName   = $familyName.ToLower().Trim()
        $normVendor = $vendor.ToLower().Trim()

        $existing = Invoke-SqlQuery -ConnectionName $this.ConnectionName `
            -Query 'SELECT FamilyId, FamilyName FROM ProductFamilies WHERE NormalizedName = @n AND NormalizedVendor = @v LIMIT 1' `
            -Parameters @{ n = $normName; v = $normVendor }

        if ($existing) {
            return @{ FamilyId = [int]$existing.FamilyId; FamilyName = [string]$existing.FamilyName }
        }

        Invoke-SqlUpdate -ConnectionName $this.ConnectionName -Query @'
INSERT INTO ProductFamilies (FamilyName, NormalizedName, Vendor, NormalizedVendor, IsKnown)
VALUES (@fn, @nn, @v, @nv, 1)
'@ -Parameters @{ fn = $familyName; nn = $normName; v = $vendor; nv = $normVendor } | Out-Null

        $newId = [int](Invoke-SqlScalar -ConnectionName $this.ConnectionName `
            -Query 'SELECT LAST_INSERT_ID()')
        return @{ FamilyId = $newId; FamilyName = $familyName }
    }

    # == Fuzzy search =============================================================

    hidden [FuzzyMatchResult] _FuzzySearch([string]$normName, [string]$normVendor) {
        $tokens = $this._fuzzy.Tokenize($normName)
        if ($tokens.Count -eq 0) { return $null }

        # Build parameterised IN list
        $params = @{}
        $placeholders = for ($i = 0; $i -lt $tokens.Count; $i++) {
            $params["t$i"] = $tokens[$i]
            "@t$i"
        }
        $inClause = $placeholders -join ','

        $candidates = @(Invoke-SqlQuery -ConnectionName $this.ConnectionName `
            -Query "SELECT DISTINCT FamilyId, FamilyName, ProductId, NormName FROM FuzzyIndex WHERE TokenKey IN ($inClause)" `
            -Parameters $params -WarningAction SilentlyContinue)

        if ($candidates.Count -eq 0) { return $null }

        # Build hashtable for FindBest
        $candidateMap = @{}
        foreach ($c in $candidates) {
            $k = $c.NormName
            if (-not $candidateMap.ContainsKey($k)) {
                $candidateMap[$k] = @{
                    FamilyId   = [int]$c.FamilyId
                    FamilyName = [string]$c.FamilyName
                    ProductId  = [int]$c.ProductId
                }
            }
        }

        return $this._fuzzy.FindBest($normName, $candidateMap)
    }

    # == Self-learning =============================================================

    hidden [void] _LearnNewFamily([PSObject]$item) {
        $normalized = $this._engine.Normalize([string]$item.Vendor, [string]$item.Name)
        $normName   = $normalized.NormalizedName
        $normVendor = $normalized.NormalizedVendor

        if (-not $normName) { return }

        # Check if a similar family already exists via token search
        $existing = $this._FuzzySearch($normName, $normVendor)
        if ($null -ne $existing -and $existing.Confidence -ge 50) {
            # Close enough — assign to the existing family
            $key = $this._MakeLookupKey([string]$item.Vendor, [string]$item.Name)
            $this._AddToLookupCache($key, $existing.FamilyId, $existing.FamilyName, $existing.ProductId, $existing.Confidence, 'Learned')
            $learnedProductId = $this._UpsertProduct($item, [RecognitionResult]@{
                FamilyId    = $existing.FamilyId
                FamilyName  = $existing.FamilyName
                ProductId   = $existing.ProductId
                Confidence  = $existing.Confidence
                MatchMethod = 'Learned'
            })
            if ($learnedProductId -gt 0) {
                $this._UpsertVariant($item, [RecognitionResult]@{
                    FamilyId    = $existing.FamilyId
                    FamilyName  = $existing.FamilyName
                    ProductId   = $learnedProductId
                    Confidence  = $existing.Confidence
                    MatchMethod = 'Learned'
                })
            }
            return
        }

        # Create a brand-new auto-learned family
        $vendorForFamily = if ($normalized.TargetVendor) { $normalized.TargetVendor } else { $normVendor }
        Invoke-SqlUpdate -ConnectionName $this.ConnectionName -Query @'
INSERT INTO ProductFamilies (FamilyName, NormalizedName, Vendor, NormalizedVendor, IsKnown, ConfidenceFloor)
VALUES (@fn, @nn, @v, @nv, 0, 50)
ON DUPLICATE KEY UPDATE UpdatedAt = CURRENT_TIMESTAMP
'@ -Parameters @{
            fn = $normName
            nn = $normName.ToLower()
            v  = [string]$item.Vendor
            nv = $vendorForFamily.ToLower()
        } | Out-Null

        $familyId = [int](Invoke-SqlScalar -ConnectionName $this.ConnectionName `
            -Query 'SELECT LAST_INSERT_ID()')

        if ($familyId -eq 0) {
            # Row already existed (DUPLICATE KEY); fetch the real id
            $row = Invoke-SqlQuery -ConnectionName $this.ConnectionName `
                -Query 'SELECT FamilyId FROM ProductFamilies WHERE NormalizedName = @nn AND NormalizedVendor = @nv LIMIT 1' `
                -Parameters @{ nn = $normName.ToLower(); nv = $vendorForFamily.ToLower() }
            $familyId = [int]$row.FamilyId
        }

        $result = [RecognitionResult]@{
            FamilyId    = $familyId
            FamilyName  = $normName
            Confidence  = 65
            MatchMethod = 'Learned'
        }

        $productId = $this._UpsertProduct($item, $result)
        $result.ProductId = $productId
        if ($productId -gt 0) {
            $this._UpsertVariant($item, $result)
        }

        # Cache this key so future Recognize() calls return instantly
        $cacheKey = $this._MakeLookupKey([string]$item.Vendor, [string]$item.Name)
        $this._AddToLookupCache($cacheKey, $familyId, $normName, $productId, 65, 'Learned')

        # Add tokens to FuzzyIndex
        $tokens = $this._fuzzy.Tokenize($normName)
        foreach ($token in $tokens) {
            Invoke-SqlUpdate -ConnectionName $this.ConnectionName -Query @'
INSERT IGNORE INTO FuzzyIndex (TokenKey, FamilyId, FamilyName, ProductId, NormName)
VALUES (@tok, @fid, @fname, @pid, @nn)
'@ -Parameters @{
                tok   = $token
                fid   = $familyId
                fname = $normName
                pid   = $productId
                nn    = $normName
            } | Out-Null
        }

        $key = $this._MakeLookupKey([string]$item.Vendor, [string]$item.Name)
        $this._AddToLookupCache($key, $familyId, $normName, $productId, 65, 'Learned')
    }

    # == Product / Variant upserts =================================================

    hidden [int] _UpsertProduct([PSObject]$item, [RecognitionResult]$result) {
        $normVendor = ($item.Vendor.ToLower().Trim() -replace ',?\s*(Inc\.|LLC|Ltd\.|Corp\.|Corporation)\.?\s*$', '').Trim()
        $normName   = [string]$item.Name

        Invoke-SqlUpdate -ConnectionName $this.ConnectionName -Query @'
INSERT INTO Products
    (FamilyId, ProductName, NormalizedName, Vendor, NormalizedVendor, InstallCount, LastSeen)
VALUES
    (@fid, @pname, @nname, @vendor, @nvendor, 1, @now)
ON DUPLICATE KEY UPDATE
    InstallCount = InstallCount + 1,
    LastSeen     = VALUES(LastSeen),
    FamilyId     = VALUES(FamilyId)
'@ -Parameters @{
            fid     = $result.FamilyId
            pname   = [string]$item.Name
            nname   = $normName.ToLower()
            vendor  = [string]$item.Vendor
            nvendor = $normVendor
            now     = [datetime]::UtcNow
        } | Out-Null

        $row = Invoke-SqlQuery -ConnectionName $this.ConnectionName `
            -Query 'SELECT ProductId FROM Products WHERE NormalizedName = @n AND NormalizedVendor = @v LIMIT 1' `
            -Parameters @{ n = $normName.ToLower(); v = $normVendor }

        if ($row) { return [int]$row.ProductId } else { return 0 }
    }

    hidden [void] _UpsertVariant([PSObject]$item, [RecognitionResult]$result) {
        $version  = [string]$item.DisplayVersion
        $normKey  = "$($item.Vendor.ToLower().Trim())::$($item.Name.ToLower().Trim())::$($version.ToLower().Trim())"

        Invoke-SqlUpdate -ConnectionName $this.ConnectionName -Query @'
INSERT INTO Variants
    (ProductId, RawName, RawVendor, NormalizedKey, LastSeen, SeenCount)
VALUES
    (@pid, @rname, @rvendor, @nkey, @now, 1)
ON DUPLICATE KEY UPDATE
    SeenCount = SeenCount + 1,
    LastSeen  = VALUES(LastSeen),
    ProductId = VALUES(ProductId)
'@ -Parameters @{
            pid     = $result.ProductId
            rname   = [string]$item.Name
            rvendor = [string]$item.Vendor
            nkey    = $normKey
            now     = [datetime]::UtcNow
        } | Out-Null
    }

    # == Rule persistence ==========================================================

    hidden [void] _SaveRuleToDb([NormalizationRule]$rule) {
        if (-not $rule.RuleId) { $rule.RuleId = [guid]::NewGuid().ToString() }

        # Use -InputObject + array wrapper so empty arrays produce "[]" not null
        $stripJson = ConvertTo-Json -InputObject @($rule.StripPatterns)  -Compress
        $transJson = ConvertTo-Json -InputObject @($rule.Transformations) -Compress

        Invoke-SqlUpdate -ConnectionName $this.ConnectionName -Query @'
INSERT INTO NormalizationRules
    (RuleId, RuleName, Priority, IsActive, IsBuiltIn, IsExcludeRule,
     VendorPattern, NamePattern, TargetFamily, TargetVendor,
     StripPatterns, Transformations, Description)
VALUES
    (@rid, @rname, @pri, @active, @builtin, @exclude,
     @vpat, @npat, @tfam, @tvend,
     @strip, @trans, @desc)
ON DUPLICATE KEY UPDATE
    RuleName      = VALUES(RuleName),
    Priority      = VALUES(Priority),
    IsActive      = VALUES(IsActive),
    IsExcludeRule = VALUES(IsExcludeRule),
    VendorPattern = VALUES(VendorPattern),
    NamePattern   = VALUES(NamePattern),
    TargetFamily  = VALUES(TargetFamily),
    TargetVendor  = VALUES(TargetVendor),
    StripPatterns = VALUES(StripPatterns),
    Transformations = VALUES(Transformations),
    Description   = VALUES(Description),
    UpdatedAt     = CURRENT_TIMESTAMP
'@ -Parameters @{
            rid     = $rule.RuleId
            rname   = $rule.RuleName
            pri     = $rule.Priority
            active  = [int]$rule.IsActive
            builtin = [int]$rule.IsBuiltIn
            exclude = [int]$rule.IsExcludeRule
            vpat    = if ($rule.VendorPattern)  { $rule.VendorPattern }  else { '' }
            npat    = if ($rule.NamePattern)    { $rule.NamePattern }    else { '' }
            tfam    = if ($rule.TargetFamily)   { $rule.TargetFamily }   else { '' }
            tvend   = if ($rule.TargetVendor)   { $rule.TargetVendor }   else { '' }
            strip   = $stripJson
            trans   = $transJson
            desc    = if ($rule.Description)    { $rule.Description }    else { '' }
        } | Out-Null
    }
}
