#Requires -Modules SimplySql
<#
.SYNOPSIS
    Creates the SRE database and all tables from scratch.
    Safe to re-run — drops and recreates all tables.
#>
param(
    [string] $Server   = 'localhost',
    [int]    $Port     = 3306,
    [string] $Database = 'SRE',
    [string] $User     = 'root',
    [string] $Password = ''
)

$connStr  = "Server=$Server;Port=$Port;Database=mysql;Uid=$User;Pwd=$Password;"
$sreConn  = "Server=$Server;Port=$Port;Database=$Database;Uid=$User;Pwd=$Password;"
$connName = 'SRE_Setup'

Import-Module SimplySql -ErrorAction Stop

Write-Host "Connecting to MySQL at $Server`:$Port ..."
Open-MySqlConnection -ConnectionName $connName -ConnectionString $connStr

# Create database
Invoke-SqlUpdate -ConnectionName $connName `
    -Query "CREATE DATABASE IF NOT EXISTS ``$Database`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci" | Out-Null
Write-Host "Database '$Database' ready."
Close-SqlConnection -ConnectionName $connName

# Reconnect to SRE database
Open-MySqlConnection -ConnectionName $connName -ConnectionString $sreConn

# Drop in FK-safe order
Write-Host "Dropping existing tables..."
Invoke-SqlUpdate -ConnectionName $connName -Query 'SET FOREIGN_KEY_CHECKS = 0' | Out-Null
foreach ($t in @('FuzzyIndex','History','LookupTable','NormalizationRules','Variants','Products','ProductFamilies')) {
    Invoke-SqlUpdate -ConnectionName $connName -Query "DROP TABLE IF EXISTS ``$t``" | Out-Null
    Write-Host "  Dropped $t"
}
Invoke-SqlUpdate -ConnectionName $connName -Query 'SET FOREIGN_KEY_CHECKS = 1' | Out-Null

# Create tables
$statements = @(
    [pscustomobject]@{ Name = 'ProductFamilies'; SQL = @'
CREATE TABLE ProductFamilies (
    FamilyId         INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    FamilyName       VARCHAR(300)     NOT NULL,
    NormalizedName   VARCHAR(300)     NOT NULL,
    Vendor           VARCHAR(200)     NOT NULL DEFAULT '',
    NormalizedVendor VARCHAR(200)     NOT NULL DEFAULT '',
    IsKnown          TINYINT(1)       NOT NULL DEFAULT 0,
    ConfidenceFloor  TINYINT UNSIGNED NOT NULL DEFAULT 50,
    CreatedAt        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (FamilyId),
    UNIQUE KEY uq_family (NormalizedName, NormalizedVendor)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
'@ }

    [pscustomobject]@{ Name = 'Products'; SQL = @'
CREATE TABLE Products (
    ProductId        INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    FamilyId         INT UNSIGNED     NOT NULL,
    ProductName      VARCHAR(400)     NOT NULL,
    NormalizedName   VARCHAR(400)     NOT NULL,
    Vendor           VARCHAR(200)     NOT NULL DEFAULT '',
    NormalizedVendor VARCHAR(200)     NOT NULL DEFAULT '',
    CanonicalVersion VARCHAR(100)     NOT NULL DEFAULT '',
    FirstSeen        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    LastSeen         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    InstallCount     INT UNSIGNED     NOT NULL DEFAULT 0,
    PRIMARY KEY (ProductId),
    UNIQUE KEY uq_product (NormalizedName, NormalizedVendor),
    KEY idx_product_family (FamilyId),
    CONSTRAINT fk_product_family FOREIGN KEY (FamilyId)
        REFERENCES ProductFamilies (FamilyId) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
'@ }

    [pscustomobject]@{ Name = 'Variants'; SQL = @'
CREATE TABLE Variants (
    VariantId      INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    ProductId      INT UNSIGNED     NOT NULL,
    RawName        VARCHAR(500)     NOT NULL,
    RawVendor      VARCHAR(200)     NOT NULL DEFAULT '',
    NormalizedKey  VARCHAR(500)     NOT NULL,
    FirstSeen      DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    LastSeen       DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    SeenCount      INT UNSIGNED     NOT NULL DEFAULT 1,
    PRIMARY KEY (VariantId),
    UNIQUE KEY uq_variant_key (NormalizedKey),
    KEY idx_variant_product (ProductId),
    CONSTRAINT fk_variant_product FOREIGN KEY (ProductId)
        REFERENCES Products (ProductId) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
'@ }

    [pscustomobject]@{ Name = 'LookupTable'; SQL = @'
CREATE TABLE LookupTable (
    LookupKey   VARCHAR(500)     NOT NULL,
    FamilyId    INT UNSIGNED     NOT NULL,
    FamilyName  VARCHAR(300)     NOT NULL DEFAULT '',
    ProductId   INT UNSIGNED,
    MatchMethod VARCHAR(20)      NOT NULL DEFAULT '',
    Confidence  TINYINT UNSIGNED NOT NULL DEFAULT 100,
    PRIMARY KEY (LookupKey),
    KEY idx_lookup_family (FamilyId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
'@ }

    [pscustomobject]@{ Name = 'NormalizationRules'; SQL = @'
CREATE TABLE NormalizationRules (
    RuleId          VARCHAR(36)      NOT NULL,
    RuleName        VARCHAR(200)     NOT NULL,
    Priority        SMALLINT         NOT NULL DEFAULT 100,
    IsActive        TINYINT(1)       NOT NULL DEFAULT 1,
    IsBuiltIn       TINYINT(1)       NOT NULL DEFAULT 0,
    IsExcludeRule   TINYINT(1)       NOT NULL DEFAULT 0,
    VendorPattern   VARCHAR(500)     NOT NULL DEFAULT '',
    NamePattern     VARCHAR(500)     NOT NULL DEFAULT '',
    TargetFamily    VARCHAR(300)     NOT NULL DEFAULT '',
    TargetVendor    VARCHAR(200)     NOT NULL DEFAULT '',
    StripPatterns   TEXT             NOT NULL,
    Transformations TEXT             NOT NULL,
    Description     VARCHAR(500)     NOT NULL DEFAULT '',
    CreatedAt       DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (RuleId),
    KEY idx_rule_priority (Priority),
    KEY idx_rule_active (IsActive)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
'@ }

    [pscustomobject]@{ Name = 'History'; SQL = @'
CREATE TABLE History (
    HistoryId       BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    SoftwareId      BIGINT UNSIGNED,
    RawVendor       VARCHAR(200)     NOT NULL DEFAULT '',
    RawName         VARCHAR(500)     NOT NULL,
    DisplayVersion  VARCHAR(100)     NOT NULL DEFAULT '',
    Guid            CHAR(36)         NOT NULL DEFAULT '',
    InstallDate     DATE,
    RawUser         VARCHAR(100)     NOT NULL DEFAULT '',
    RegistryKey     VARCHAR(1000)    NOT NULL DEFAULT '',
    FamilyId        INT UNSIGNED,
    ProductId       INT UNSIGNED,
    MatchMethod     VARCHAR(20)      NOT NULL DEFAULT '',
    MatchConfidence TINYINT UNSIGNED NOT NULL DEFAULT 0,
    SeenAt          DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    SourceHost      VARCHAR(200)     NOT NULL DEFAULT '',
    PRIMARY KEY (HistoryId),
    KEY idx_history_family     (FamilyId),
    KEY idx_history_rawname    (RawName(100)),
    KEY idx_history_seen       (SeenAt),
    KEY idx_history_softwareid (SoftwareId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
'@ }

    [pscustomobject]@{ Name = 'FuzzyIndex'; SQL = @'
CREATE TABLE FuzzyIndex (
    FuzzyIndexId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    TokenKey     VARCHAR(100)  NOT NULL,
    FamilyId     INT UNSIGNED  NOT NULL,
    FamilyName   VARCHAR(300)  NOT NULL DEFAULT '',
    ProductId    INT UNSIGNED  NOT NULL,
    NormName     VARCHAR(400)  NOT NULL DEFAULT '',
    Weight       FLOAT         NOT NULL DEFAULT 1.0,
    PRIMARY KEY (FuzzyIndexId),
    KEY idx_fuzzy_token  (TokenKey),
    KEY idx_fuzzy_family (FamilyId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
'@ }
)

Write-Host "`nCreating tables..."
foreach ($item in $statements) {
    try {
        Invoke-SqlUpdate -ConnectionName $connName -Query $item.SQL | Out-Null
        Write-Host "  [OK] $($item.Name)"
    } catch {
        Write-Warning "  [FAIL] $($item.Name): $_"
    }
}

# Verify
Write-Host "`nVerifying tables in '$Database':"
$tables = Invoke-SqlQuery -ConnectionName $connName -Query 'SHOW TABLES'
$tables | ForEach-Object { Write-Host "  + $($_.PSObject.Properties.Value | Select-Object -First 1)" }

Close-SqlConnection -ConnectionName $connName
Write-Host "`nDatabase setup complete."
