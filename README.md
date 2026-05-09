# Software Recognition Engine (SRE)

A self-learning PowerShell module that normalizes, deduplicates, and classifies software inventory data from sources such as Zabbix, SCCM, or any JSON-based software scan. Raw install names like `"Citrix Workspace 2409"`, `"Citrix Receiver 4.9"`, and `"Citrix Workspace App 24.8.0.138"` are all resolved to a single canonical family -- `Citrix Workspace App` -- so you can query, count, and audit your estate cleanly.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Prerequisites and Installation](#3-prerequisites-and-installation)
4. [Configuration](#4-configuration)
5. [Quick Start](#5-quick-start)
6. [Recognition Pipeline](#6-recognition-pipeline)
7. [Core Functions](#7-core-functions)
8. [Query Functions](#8-query-functions)
9. [Data Model](#9-data-model)
10. [How Rules Work](#10-how-rules-work)
11. [Rule Authoring Functions](#11-rule-authoring-functions)
12. [Rule Maintenance in Production](#12-rule-maintenance-in-production)
13. [Operational Workflows](#13-operational-workflows)
14. [Performance Notes](#14-performance-notes)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. Overview

### The Problem

Software inventory data from enterprise environments is noisy. The same product appears under dozens of raw names depending on the version, architecture, installer packaging, and vendor naming convention. Standard queries like "how many machines have Citrix?" are unanswerable without manual deduplication.

### What SRE Does

SRE sits between your raw inventory feed and your reporting layer. It:

- **Normalizes** raw software names using regex-based rules (strip trailing version numbers, consolidate vendor name variants)
- **Groups** related installs into **Product Families** (all Citrix Workspace and Receiver variants become one family)
- **Fuzzy-matches** unrecognized items against the known catalog using Levenshtein + Jaccard similarity
- **Self-learns** from your data -- items that score above 50% fuzzy confidence are auto-assigned to the nearest existing family; truly unknown items seed new families automatically
- **Persists everything** to MySQL with a full audit trail, so you can query across time, host, version, and confidence

### Key Capabilities

| Area | Capability |
|---|---|
| Ingest | Bulk import from JSON or PSObject arrays |
| Recognize | Per-item recognition with confidence score and match method |
| Query | 11 purpose-built query functions covering catalog, fleet, audit, and change tracking |
| Rules | 28+ built-in normalization rules; derive and add custom rules at runtime |
| Rule Authoring | Auto-generate rules from observed unrecognized items with `New-SRERule` |
| Reprocessing | Retroactively re-recognize historical data after adding new rules with `Invoke-SREReprocess` |
| Audit | Full history table -- every recognition event is logged with method and confidence |
| Change | Track new software appearances and stale/removed products over time |

---

## 2. Architecture

```
+------------------------------------------------------------------+
|                    SoftwareCatalog (class)                        |
|                                                                   |
|  +--------------------+  +--------------+  +------------------+  |
|  | NormalizationEngine|  | FuzzyMatcher |  |    History       |  |
|  | (priority-ordered  |  | (Levenshtein |  | (audit trail)    |  |
|  |  regex rules)      |  |  + Jaccard)  |  |                  |  |
|  +--------------------+  +--------------+  +------------------+  |
|                                                                   |
|  In-memory lookup cache (hashtable) <-> LookupTable (MySQL)      |
+------------------------------------------------------------------+
                              |
                              | SimplySql
                              v
+------------------------------------------------------------------+
|                         MySQL Database                            |
|                                                                   |
|  ProductFamilies  Products  Variants  History                     |
|  NormalizationRules  LookupTable  FuzzyIndex                      |
+------------------------------------------------------------------+
```

### Components

| Component | File | Responsibility |
|---|---|---|
| `SoftwareCatalog` | `Classes/06_SoftwareCatalog.ps1` | Orchestrates all subsystems; public API |
| `NormalizationEngine` | `Classes/03_NormalizationEngine.ps1` | Applies priority-ordered regex rules |
| `NormalizationRule` | `Classes/02_NormalizationRule.ps1` | Single rule with match and transform logic |
| `FuzzyMatcher` | `Classes/04_FuzzyMatcher.ps1` | Levenshtein + Jaccard similarity scoring |
| `History` | `Classes/05_History.ps1` | Persists every recognition event |
| Built-in Rules | `Data/BuiltInRules.ps1` | 28+ vendor-specific normalization rules |
| Schema | `Data/Schema.sql` | MySQL DDL -- idempotent, run-once |

---

## 3. Prerequisites and Installation

### Requirements

| Requirement | Minimum Version | Notes |
|---|---|---|
| PowerShell | 5.1 | Works on both Windows PowerShell and PowerShell 7+ |
| MySQL | 5.7 or 8.x | MariaDB 10.3+ also works |
| [SimplySql](https://www.powershellgallery.com/packages/SimplySql) | 2.0+ | MySQL adapter for PowerShell |

### Install SimplySql

```powershell
Install-Module -Name SimplySql -Scope CurrentUser -Force
```

### Set Up the Database

Create an empty database in MySQL, then import the schema:

```sql
CREATE DATABASE SRE CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'sreuser'@'localhost' IDENTIFIED BY 'yourpassword';
GRANT ALL PRIVILEGES ON SRE.* TO 'sreuser'@'localhost';
FLUSH PRIVILEGES;
```

The schema is applied automatically the first time you call `New-SoftwareCatalog`. The `_EnsureSchema()` method runs all DDL statements idempotently using `IF NOT EXISTS`.

### Import the Module

```powershell
Import-Module .\SoftwareRecognitionEngine\SoftwareRecognitionEngine.psd1
```

---

## 4. Configuration

The connection string is checked in this order:

### Option 1 -- Constructor parameter (recommended for scripts)

```powershell
$catalog = New-SoftwareCatalog -ConnectionString "Server=localhost;Database=SRE;Uid=sreuser;Pwd=yourpassword;"
```

### Option 2 -- Environment variable (CI/CD pipelines, scheduled tasks)

```powershell
$env:SRE_CONNECTION_STRING = "Server=localhost;Database=SRE;Uid=sreuser;Pwd=yourpassword;"
$catalog = New-SoftwareCatalog
```

### Option 3 -- Config file (shared workstation setups)

Create `%APPDATA%\SoftwareRecognitionEngine\config.json`:

```json
{
  "ConnectionString": "Server=localhost;Database=SRE;Uid=sreuser;Pwd=yourpassword;"
}
```

---

## 5. Quick Start

```powershell
Import-Module .\SoftwareRecognitionEngine\SoftwareRecognitionEngine.psd1

# Connect
$c = New-SoftwareCatalog -ConnectionString "Server=localhost;Database=SRE;Uid=root;Pwd=;"

# Ingest a JSON export from Zabbix or SCCM
Add-SREInventory -Catalog $c -JsonPath .\inventory.json

# Query -- what are the most-deployed products across the estate?
Get-SRETopSoftware -Catalog $c | Format-Table FamilyName, HostCount, TotalInstalls

# Audit -- what did the engine fail to recognize?
Get-SREUnrecognized -Catalog $c | Format-Table SourceHost, RawVendor, RawName

# Change -- what software appeared in the last 7 days?
Get-SRENewSoftware -Catalog $c -Days 7 | Format-Table SourceHost, RawName, FamilyName, FirstSeen
```

---

## 6. Recognition Pipeline

Every item passed to the engine goes through four steps in order. The pipeline short-circuits as soon as a match is found.

```
Item (Vendor + Name)
        |
        v
+--------------------------------------+
|  Step 1: Exact Lookup (O(1))         |  Hit  -> return cached result immediately
|  In-memory hashtable                 |  Miss -> continue
+--------------------------------------+
        |
        v
+--------------------------------------+
|  Step 2: Normalization Rules         |  Match       -> 95% confidence, MatchMethod = Rule
|  Priority-ordered regex engine       |  Exclude hit -> IsExcluded = true, stop
|  First match wins                    |  No match    -> continue
+--------------------------------------+
        |
        v
+--------------------------------------+
|  Step 3: Fuzzy Match                 |  Score >= 60% -> return best, MatchMethod = Fuzzy
|  Token lookup -> Levenshtein         |  Score 50-59% -> self-learn: assign to family
|  + Jaccard hybrid score              |  Score < 50%  -> no match, continue
+--------------------------------------+
        |
        v
+--------------------------------------+
|  Step 4: Self-Learning               |  Create new ProductFamily from normalized name
|  Auto-seed FuzzyIndex                |  MatchMethod = Learned
|  Cache result for next run           |
+--------------------------------------+
```

### Match Methods

| Method | Meaning | Typical Confidence |
|---|---|---|
| `Exact` | Found in O(1) lookup cache from a prior recognition | Same as original match |
| `Rule` | Matched by a normalization rule | 95% |
| `Fuzzy` | Matched by Levenshtein + Jaccard scoring against FuzzyIndex | 60-94% |
| `Learned` | Auto-assigned to an existing family (50-59% fuzzy score) | 50-65% |
| `None` | No match at any step | 0% |

### Fuzzy Scoring

The confidence score is a weighted average of two similarity measures:

```
Confidence = (LevenshteinScore x 0.6) + (JaccardScore x 0.4)
```

- **Levenshtein** -- character-level edit distance, normalized to 0-100
- **Jaccard** -- word-token set overlap (intersection divided by union), case-insensitive
- Minimum confidence threshold: **60%** -- scores below this are not returned as matches

---

## 7. Core Functions

### `New-SoftwareCatalog`

Creates a `SoftwareCatalog` instance and connects to the database. On first run this seeds the schema and built-in rules.

```powershell
$catalog = New-SoftwareCatalog [-ConnectionString <string>]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-ConnectionString` | string | No | MySQL connection string. Falls back to env var or config file if omitted. |

---

### `Add-SREInventory`

Ingests an array of raw software install objects. Each item is recognized, logged to History, and upserted into Products and Variants.

```powershell
Add-SREInventory -Catalog <SoftwareCatalog> [-Items <PSObject[]>] [-JsonPath <string>]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Catalog` | SoftwareCatalog | Yes | Catalog instance from `New-SoftwareCatalog` |
| `-Items` | PSObject[] | Yes (or JsonPath) | Array of install objects |
| `-JsonPath` | string | Yes (or Items) | Path to a JSON file containing install objects |

Each install object must have at minimum:

| Field | Type | Description |
|---|---|---|
| `Vendor` | string | Publisher name (e.g. `"Citrix Systems, Inc."`) |
| `Name` | string | Product name (e.g. `"Citrix Workspace 2409"`) |
| `DisplayVersion` | string | Version string |
| `SoftwareId` | any | Unique ID from the source system |
| `SourceHost` | string | Hostname the install was found on |

```powershell
# From JSON file
Add-SREInventory -Catalog $c -JsonPath .\zabbix_export.json

# From PowerShell objects
$items = @(
    [PSCustomObject]@{ Vendor='Citrix Systems, Inc.'; Name='Citrix Workspace 2409'; DisplayVersion='24.9.0.100'; SourceHost='PC-001'; SoftwareId=1 }
    [PSCustomObject]@{ Vendor='Cisco Systems, Inc.'; Name='Cisco AnyConnect Secure Mobility Client'; DisplayVersion='4.10.04065'; SourceHost='PC-001'; SoftwareId=2 }
)
Add-SREInventory -Catalog $c -Items $items
```

---

### `Invoke-SRERecognize`

Runs a single item through the recognition pipeline and returns a `RecognitionResult` without writing to the database. Use this to test rules or check what a specific name resolves to before committing data.

```powershell
$result = Invoke-SRERecognize -Catalog <SoftwareCatalog> [-Item <PSObject>] [-Vendor <string> -Name <string>]
```

**Returns** a `RecognitionResult` object:

| Property | Type | Description |
|---|---|---|
| `FamilyId` | int | Matched family ID (0 if unrecognized) |
| `FamilyName` | string | Canonical family name |
| `ProductId` | int | Matched product ID |
| `ProductName` | string | Matched product name |
| `Confidence` | int | Match confidence 0-100 |
| `MatchMethod` | string | `None`, `Exact`, `Rule`, `Fuzzy`, or `Learned` |
| `IsExcluded` | bool | True if an exclude rule matched (noise item) |

```powershell
$r = Invoke-SRERecognize -Catalog $c -Vendor 'Citrix' -Name 'Citrix Workspace 2409'
$r.FamilyName    # "Citrix Workspace App"
$r.Confidence    # 95
$r.MatchMethod   # "Rule"

$r = Invoke-SRERecognize -Catalog $c -Vendor 'Microsoft' -Name 'Update for Windows (KB4576750)'
$r.IsExcluded    # True  (matched the KB hotfix exclusion rule)
```

---

### `Add-SRERule`

Adds a custom normalization rule to the engine and persists it to the database. The rule takes effect immediately for subsequent `Recognize` calls in the same session.

```powershell
Add-SRERule -Catalog <SoftwareCatalog> [-Rule <NormalizationRule>] [-Hashtable <hashtable>]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Catalog` | SoftwareCatalog | Yes | |
| `-Rule` | NormalizationRule | Yes (or Hashtable) | Pre-built rule object |
| `-Hashtable` | hashtable | Yes (or Rule) | Property bag -- a NormalizationRule is constructed from it |

See [Section 10](#10-how-rules-work) for the full rule property reference and [Section 11](#11-rule-authoring-functions) for auto-generation from observed data.

---

### `Export-SRECatalog`

Exports the current catalog state (families, stats) to a JSON file.

```powershell
Export-SRECatalog -Catalog <SoftwareCatalog> [-Path <string>] [-StatsOnly]
```

| Parameter | Required | Description |
|---|---|---|
| `-Path` | No | Output path. Defaults to `.\SRECatalogExport_<timestamp>.json` |
| `-StatsOnly` | No | Only export table row counts, not full family data |

---

## 8. Query Functions

All query functions accept a `-Catalog` parameter and return pipeline-friendly `PSObject` arrays. Pipe to `Format-Table`, `Select-Object`, `Where-Object`, `Export-Csv`, etc.

---

### `Get-SREFamily`

Lists product families. Without filters, returns all known families.

```powershell
Get-SREFamily -Catalog <SoftwareCatalog> [-Name <string>] [-Vendor <string>]
```

**Returns:** `FamilyId`, `FamilyName`, `NormalizedName`, `Vendor`, `IsKnown`, `ConfidenceFloor`, `CreatedAt`, `UpdatedAt`

`IsKnown = 1` means the family was created by a normalization rule. `IsKnown = 0` means it was auto-learned from inventory data (may be noisy).

```powershell
Get-SREFamily -Catalog $c -Vendor 'Microsoft'
Get-SREFamily -Catalog $c | Group-Object IsKnown | Select-Object Name, Count
```

---

### `Get-SREProduct`

Lists products joined to their parent family.

```powershell
Get-SREProduct -Catalog <SoftwareCatalog> [-FamilyId <int>] [-FamilyName <string>] [-Search <string>]
```

**Returns:** `ProductId`, `FamilyId`, `FamilyName`, `ProductName`, `Vendor`, `InstallCount`, `FirstSeen`, `LastSeen`

```powershell
Get-SREProduct -Catalog $c -FamilyName 'Cisco Secure Client'
Get-SREProduct -Catalog $c -Search 'AnyConnect'
```

---

### `Get-SREVariant`

Lists all raw name variants recorded for a specific product. Each unique combination of vendor, name, and version creates a variant record.

```powershell
Get-SREVariant -Catalog <SoftwareCatalog> -ProductId <int>
```

**Returns:** `VariantId`, `ProductId`, `ProductName`, `RawName`, `RawVendor`, `Version`, `SeenCount`, `FirstSeen`, `LastSeen`

```powershell
$prod = Get-SREProduct -Catalog $c -Search 'AnyConnect Secure Mobility' | Select-Object -First 1
Get-SREVariant -Catalog $c -ProductId $prod.ProductId | Format-Table RawName, Version, SeenCount
```

---

### `Get-SREHostInventory`

Shows installed software on a host or lists all known hosts.

```powershell
Get-SREHostInventory -Catalog <SoftwareCatalog> -ListHosts
Get-SREHostInventory -Catalog <SoftwareCatalog> -HostName <string> [-Top <int>]
```

| Parameter | Description |
|---|---|
| `-ListHosts` | List all distinct hosts with item count and last-seen date |
| `-HostName` | Partial host name (LIKE match). Returns recognized items for matching hosts |
| `-Top` | Limit result rows (default: unlimited) |

```powershell
Get-SREHostInventory -Catalog $c -ListHosts | Sort-Object ItemCount -Descending
Get-SREHostInventory -Catalog $c -HostName 'SERVER-01' | Where-Object { $_.MatchMethod -eq 'None' }
```

---

### `Get-SREVersionSprawl`

Shows how many distinct versions of a product family exist across the estate. Use this to identify where patching is lagging.

```powershell
Get-SREVersionSprawl -Catalog <SoftwareCatalog> -FamilyId <int> [-Top <int>]
Get-SREVersionSprawl -Catalog <SoftwareCatalog> -FamilyName <string> [-Top <int>]
```

**Returns:** `FamilyName`, `DisplayVersion`, `HostCount`, `InstallCount`, `FirstSeen`, `LastSeen`

```powershell
Get-SREVersionSprawl -Catalog $c -FamilyName 'Cisco Secure Client' | Sort-Object HostCount -Descending
```

---

### `Get-SREHostCount`

Returns the number of distinct hosts that have a specific product family installed.

```powershell
Get-SREHostCount -Catalog <SoftwareCatalog> -FamilyId <int>
Get-SREHostCount -Catalog <SoftwareCatalog> -FamilyName <string>
```

**Returns:** `FamilyName`, `HostCount`, `TotalInstalls`, `FirstSeen`, `LastSeen`

```powershell
@('Citrix Workspace App', 'Cisco Secure Client', 'Microsoft Edge') | ForEach-Object {
    Get-SREHostCount -Catalog $c -FamilyName $_
} | Format-Table FamilyName, HostCount, TotalInstalls
```

---

### `Get-SRETopSoftware`

Returns the most-deployed product families across the estate.

```powershell
Get-SRETopSoftware -Catalog <SoftwareCatalog> [-Top <int>] [-RankBy <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `-Top` | 25 | Number of families to return (1-1000) |
| `-RankBy` | `HostCount` | `HostCount` -- distinct machines; `InstallCount` -- total install events |

```powershell
Get-SRETopSoftware -Catalog $c | Format-Table FamilyName, Vendor, HostCount
Get-SRETopSoftware -Catalog $c -Top 50 | Where-Object { $_.Vendor -notmatch 'Microsoft|Citrix|Cisco|Adobe' }
```

---

### `Get-SREUnrecognized`

Lists software items the engine could not classify (MatchMethod = None). These are your primary candidates for writing new normalization rules.

```powershell
Get-SREUnrecognized -Catalog <SoftwareCatalog> [-HostName <string>] [-Top <int>]
```

**Returns:** `SourceHost`, `RawVendor`, `RawName`, `DisplayVersion`, `MatchMethod`, `MatchConfidence`, `SeenAt`

```powershell
# Daily triage -- what did the engine miss?
Get-SREUnrecognized -Catalog $c | Group-Object RawVendor | Sort-Object Count -Descending

# Export for rule authoring
Get-SREUnrecognized -Catalog $c -Top 500 |
    Select-Object RawVendor, RawName |
    Sort-Object RawVendor, RawName -Unique |
    Export-Csv .\unrecognized.csv -NoTypeInformation
```

---

### `Get-SRELowConfidence`

Lists fuzzy and learned matches below a confidence threshold. These are matches the engine made but may have gotten wrong.

```powershell
Get-SRELowConfidence -Catalog <SoftwareCatalog> [-Threshold <int>] [-Top <int>]
```

| Parameter | Default | Description |
|---|---|---|
| `-Threshold` | 70 | Return matches with MatchConfidence below this value (1-99) |
| `-Top` | 100 | Maximum rows to return |

**Returns:** `SourceHost`, `RawVendor`, `RawName`, `DisplayVersion`, `FamilyName`, `MatchMethod`, `MatchConfidence`, `SeenAt`

```powershell
# Group by assigned family to find systematic mismatches
Get-SRELowConfidence -Catalog $c -Top 1000 |
    Group-Object FamilyName |
    Sort-Object Count -Descending |
    Select-Object Name, Count
```

---

### `Get-SRENewSoftware`

Lists software first seen in the catalog within the last N days.

```powershell
Get-SRENewSoftware -Catalog <SoftwareCatalog> [-Days <int>] [-HostName <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `-Days` | 7 | Look back this many days (1-3650) |
| `-HostName` | -- | Scope to a specific host (partial match) |

```powershell
# New unrecognized software this week (potential shadow IT)
Get-SRENewSoftware -Catalog $c -Days 7 |
    Where-Object { $_.MatchMethod -eq 'None' } |
    Select-Object SourceHost, RawVendor, RawName, FirstSeen
```

---

### `Get-SREStaleSoftware`

Lists products whose `LastSeen` timestamp is older than N days.

```powershell
Get-SREStaleSoftware -Catalog <SoftwareCatalog> [-Days <int>]
```

| Parameter | Default | Description |
|---|---|---|
| `-Days` | 30 | Return products not seen within this many days (1-3650) |

**Returns:** `ProductId`, `FamilyName`, `ProductName`, `Vendor`, `InstallCount`, `LastSeen`, `DaysSinceLastSeen`

```powershell
Get-SREStaleSoftware -Catalog $c -Days 90 | Sort-Object DaysSinceLastSeen -Descending
```

---

## 9. Data Model

```
ProductFamilies                 Products                  Variants
-----------------               -----------------         -----------------
FamilyId   PK                   ProductId   PK            VariantId   PK
FamilyName                      FamilyId    FK            ProductId   FK
NormalizedName                  ProductName               RawName
Vendor                          NormalizedName            RawVendor
NormalizedVendor                Vendor                    NormalizedKey
IsKnown  (1=rule, 0=auto)       NormalizedVendor          SeenCount
ConfidenceFloor                 CanonicalVersion          FirstSeen
CreatedAt                       InstallCount              LastSeen
UpdatedAt                       FirstSeen
                                LastSeen

History                         NormalizationRules        LookupTable
-----------------               -----------------         -----------------
HistoryId   PK                  RuleId      PK (GUID)     LookupKey   PK
SoftwareId                      RuleName                  FamilyId
RawVendor                       Priority                  FamilyName
RawName                         IsActive                  ProductId
DisplayVersion                  IsBuiltIn                 MatchMethod
Guid                            IsExcludeRule             Confidence
InstallDate                     VendorPattern
RawUser                         NamePattern               FuzzyIndex
RegistryKey                     TargetFamily              -----------------
FamilyId    FK                  TargetVendor              FuzzyIndexId  PK
ProductId   FK                  StripPatterns (JSON)      TokenKey
MatchMethod                     Transformations (JSON)    FamilyId
MatchConfidence                 Description               FamilyName
SeenAt                          CreatedAt                 ProductId
SourceHost                      UpdatedAt                 NormName
                                                          Weight
```

### Key Design Decisions

**`LookupTable`** -- An O(1) cache mapping `lower(vendor)::lower(name)` to a recognition result. Populated on every successful match and warmed into an in-memory hashtable at startup. The second time any item is seen, it costs a single hashtable lookup.

**`Variants`** -- Tracks every unique `vendor::name::version` combination seen. Many raw install names map to a single product. The `NormalizedKey` format is `lower(vendor)::lower(name)::lower(version)`.

**`History`** -- Append-only audit log. Every call to `Add-SREInventory` appends a row for every item, regardless of whether it matched. This is the foundation for all change-tracking and audit queries. During reprocessing, only the resolution columns (`FamilyId`, `ProductId`, `MatchMethod`, `MatchConfidence`) are updated in-place on rows that improve -- no rows are deleted.

**`FuzzyIndex`** -- Token-based inverted index. When a new family is created, its normalized name is tokenized and each token inserted as a row. Fuzzy search retrieves candidates by token overlap, then scores them with Levenshtein + Jaccard.

**`IsKnown` on ProductFamilies** -- Distinguishes rule-created families (high confidence, stable) from auto-learned families (may be noisy, worth periodic review).

---

## 10. How Rules Work

Understanding rule mechanics is essential for writing effective rules and diagnosing recognition problems.

### Rule Structure

A `NormalizationRule` object has these properties:

| Property | Type | Default | Description |
|---|---|---|---|
| `RuleId` | string (GUID) | auto | Unique identifier. Auto-generated. |
| `RuleName` | string | -- | Human-readable label shown in logs and `Get-SREFamily` output |
| `Priority` | int | 100 | Evaluation order. Lower numbers run first. |
| `IsActive` | bool | true | When false, the rule is loaded but skipped entirely. |
| `IsBuiltIn` | bool | false | Set to true by the engine for built-in rules. Do not set manually. |
| `IsExcludeRule` | bool | false | When true, a match suppresses the item from recognition. No family is assigned. |
| `VendorPattern` | string | empty | Regex matched against the raw vendor string. Empty = match any vendor. |
| `NamePattern` | string | empty | Regex matched against the raw product name. Empty = match any name. |
| `TargetFamily` | string | empty | The canonical family name assigned to matching items. |
| `TargetVendor` | string | empty | Override for the vendor stored with the family. |
| `StripPatterns` | string[] | [] | Ordered list of regex patterns removed from the product name before it is stored. |
| `Transformations` | hashtable[] | [] | Field-level regex replacements. Each entry is `@{Field; Pattern; Replacement}`. |
| `Description` | string | empty | Free-text documentation. Stored in the database. |

### The Matching Step

When a rule is evaluated against an item, both `VendorPattern` and `NamePattern` must match. This is the `Matches()` method in `NormalizationRule.ps1`:

```
Matches(vendor, name):
  1. If VendorPattern is non-empty AND vendor does NOT match the regex -> return false
  2. If NamePattern   is non-empty AND name   does NOT match the regex -> return false
  3. Return true
```

**Either pattern can be empty.** An empty `VendorPattern` matches any vendor. An empty `NamePattern` matches any name. A rule with both patterns empty matches everything -- use with caution and a low priority.

**Matching is case-insensitive** by default because PowerShell's `-match` operator uses case-insensitive regex. If you need case-sensitive matching, prefix your pattern with `(?-i)`.

### The Application Step

Once a rule matches, `Apply()` produces the normalized result:

```
Apply(vendor, name):
  1. Initialize result:
       NormalizedName   = name  (raw input)
       NormalizedVendor = vendor (raw input)
       FamilyName       = TargetFamily
       TargetVendor     = rule.TargetVendor
       IsExcluded       = rule.IsExcludeRule

  2. If IsExcludeRule is TRUE:
       Skip all transformations. Return result as-is.
       (IsExcluded = true signals the caller to discard this item.)

  3. For each pattern in StripPatterns (in order):
       NormalizedName = NormalizedName -replace pattern, ''

  4. For each entry in Transformations (in order):
       result[entry.Field] = result[entry.Field] -replace entry.Pattern, entry.Replacement

  5. Collapse extra whitespace; trim both fields.

  6. If TargetVendor is non-empty:
       NormalizedVendor = TargetVendor
       (Overrides whatever the vendor field contained after step 4.)

  7. Return result hashtable.
```

`StripPatterns` run first, then `Transformations`. Order matters -- a later strip pattern operates on the output of all earlier ones. Strip patterns receive no replacement string (they remove the matched text). Transformations support a replacement string and can target either `NormalizedName` or `NormalizedVendor`.

### Evaluation Order and Priority

The engine loads all active rules sorted by `Priority` ascending and evaluates them sequentially:

```
For each rule (ordered by Priority ascending):
  If rule.IsActive = false: skip
  If rule.Matches(vendor, name): return rule.Apply(vendor, name)

If no rule matched: return BaselineClean(vendor, name)
```

**The first matching rule wins.** Subsequent rules are never evaluated for that item, regardless of whether the first match produced a good result. This means:

- Exclusion rules (Priority 1-19) must have a **lower** number than any match rule that might otherwise claim the same items.
- Specific rules (matching one product) should have a **lower** priority number than broad rules (matching all products from a vendor).
- If two rules could both match an item, the one with the smaller Priority number always wins.

### Baseline Cleaning (No Rule Match)

When no rule matches, the engine applies `_BaselineClean()` before passing the item to the fuzzy matcher. This strips common noise that would otherwise produce poor fuzzy scores:

- Architecture suffixes: `(x86)`, `(x64)`, `32-bit`, `64-bit`, `amd64`
- Trailing version numbers: `7-Zip 24.08` becomes `7-Zip`
- Trailing 4-digit year tokens: `Citrix Workspace 2409` becomes `Citrix Workspace`
- Double whitespace collapsed to single space
- Vendor legal suffixes stripped: `Inc.`, `LLC`, `Corp.`, `Ltd.`, `GmbH`, etc.

This means items without an explicit rule still get a reasonable normalized form for fuzzy matching -- but they will not be assigned a family with 95% confidence.

### What Happens After a Rule Match

After `Apply()` returns:

1. The engine calls `_GetOrCreateFamily(FamilyName, TargetVendor)` which either fetches the existing `FamilyId` from `ProductFamilies` or inserts a new row with `IsKnown = 1`.
2. The result is cached in `LookupTable` and in the in-memory `_lookupCache` so future identical items skip rules entirely.
3. The item is logged to `History` with `MatchMethod = 'Rule'` and `MatchConfidence = 95`.
4. The `Products` and `Variants` tables are upserted.

Exclusion rule matches do **not** create a family or a product. They are logged to History with `IsExcluded` noted but `FamilyId = NULL`, so you can still audit what was discarded.

### Priority Guidelines

| Range | Recommended Use |
|---|---|
| 1-9 | Do not use (reserved for future system use) |
| 10-19 | Noise and exclusion filters -- must run before any match rules |
| 20-49 | Built-in vendor rules (shipped with the module) |
| 50-79 | Custom organization-specific match rules |
| 80-89 | Catch-all or fallback match rules (broad patterns) |
| 90-99 | Vendor name normalization rules (no family assignment -- just clean the vendor field) |

### Vendor Name Normalization Rules

A rule with an empty `TargetFamily` and a non-empty `TargetVendor` acts as a vendor normalizer. It sets `NormalizedVendor` without assigning a family. These rules run at Priority 90-99 in the built-in set, after all family assignment rules. Their purpose is to ensure that items which slip past all match rules still reach the fuzzy matcher with a clean vendor name.

Example -- normalizing `"Google LLC"` to `"Google"`:

```powershell
Add-SRERule -Catalog $c -Hashtable @{
    RuleName      = 'Normalize Google Vendor'
    Priority      = 91
    VendorPattern = 'Google (LLC|Inc\.?)'
    NamePattern   = ''
    TargetVendor  = 'Google'
    Description   = 'Normalizes Google LLC / Google Inc. to Google'
}
```

### The Built-in Rule Set

The module ships with 28 rules covering the most common enterprise software. They are seeded into `NormalizationRules` on first startup with `IsBuiltIn = 1`. Built-in rules cannot be overridden by editing the database directly -- they are reloaded from `BuiltInRules.ps1` if the database is re-initialized. To override a built-in rule, add a custom rule at a lower priority number that matches the same items first.

| Priority | RuleName | Action |
|---|---|---|
| 10 | Exclude VS Internal Packages | Exclude `vs_*` names from Microsoft |
| 10 | Exclude Microsoft KB Hotfixes | Exclude `(KBxxxxxx)` entries |
| 10 | Exclude .NET Targeting Packs | Exclude developer targeting packs |
| 10 | Exclude Windows SDK Components | Exclude SDK and WinRT components |
| 20 | Citrix Workspace and Receiver | Map all Citrix Workspace/Receiver variants to `Citrix Workspace App` |
| 21 | Citrix Workspace Sub-Components | Map Citrix HDX, Auth Manager, etc. to same family |
| 30 | Cisco AnyConnect / Secure Client | Map all AnyConnect/Secure Client modules to `Cisco Secure Client` |
| 31 | Cisco Secure Client Core | Core package variant |
| 32 | Cisco Webex | Map Webex Meetings and Teams to `Cisco Webex` |
| 40 | Microsoft Visual C++ Redistributable | All VC++ redist packages |
| 41 | Microsoft .NET Runtime | .NET 5+ runtime flavours |
| 42 | Microsoft .NET Framework | Classic .NET Framework |
| 50 | Microsoft Edge | Edge browser and WebView2 |
| 51 | Microsoft Teams | Teams classic, new, and VDI plugin |
| 52 | SQL Server Management Studio | SSMS all versions |
| 60 | Adobe Acrobat Reader | Reader DC, XI, and older |
| 61 | Adobe Acrobat (full) | Acrobat Standard and Pro |
| 62 | Adobe Flash Legacy | Flash Player and Shockwave (EOL) |
| 70 | Java Runtime Environment | JRE and JDK all versions |
| 71 | SAP GUI for Windows | SAP GUI all patch levels |
| 80 | Google Chrome | Chrome browser |
| 81 | 7-Zip | 7-Zip all versions and architectures |
| 82 | Mozilla Firefox | Firefox all channels |
| 90-94 | Normalize [Vendor] Vendor | Vendor name normalization rules for Microsoft, Google, Oracle, Cisco, Adobe |

---

## 11. Rule Authoring Functions

These two functions close the loop between identifying unrecognized software and keeping historical data consistent.

---

### `New-SRERule`

Inspects a set of unrecognized items, auto-generates regex patterns for the vendor and name, and saves a new rule to the database. Optionally triggers immediate reprocessing of all previously unmatched History rows.

```powershell
New-SRERule -Catalog <SoftwareCatalog> -Items <PSObject[]> -FamilyName <string>
            [-Vendor <string>] [-Priority <int>] [-Exclude] [-WhatIf] [-Reprocess]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Catalog` | SoftwareCatalog | Mandatory | |
| `-Items` | PSObject[] | Mandatory | Output rows from `Get-SREUnrecognized`. Accepts pipeline input. |
| `-FamilyName` | string | Required unless -Exclude | The canonical product family name to assign |
| `-Vendor` | string | -- | Target vendor override. Auto-derived from items if omitted. |
| `-Priority` | int | 55 | Rule priority. Use a value below 10 for exclusion rules. |
| `-Exclude` | switch | -- | Creates an exclusion rule. `IsExcludeRule = true`. `FamilyName` becomes optional. |
| `-WhatIf` | switch | -- | Generates and displays the rule without saving or touching the database. |
| `-Reprocess` | switch | -- | After saving, immediately calls `Invoke-SREReprocess -MatchMethod None`. |

#### Pattern Auto-Generation

`New-SRERule` derives three things from the supplied items:

**VendorPattern** -- All unique `RawVendor` values are regex-escaped and joined with `|`. If only one vendor is present, the escaped value is used directly. If multiple vendors are present, they are wrapped in a group: `(Vendor1|Vendor2)`.

```
Items have: ["SAP SE", "SAP SE"]         -> VendorPattern = "SAP\ SE"
Items have: ["SAP SE", "SAP AG"]         -> VendorPattern = "(SAP\ SE|SAP\ AG)"
```

**NamePattern** -- The longest common prefix of all unique `RawName` values is computed character by character. The result is regex-escaped and anchored with `^`. If the common prefix is shorter than 3 characters (names too diverse), `NamePattern` is left empty with a warning -- the rule will then match all names for the matched vendor. Review and refine manually in that case.

```
Items have: ["SAP Business Client 7.70", "SAP Business Client 8.00"]
  -> common prefix = "SAP Business Client "
  -> NamePattern   = "^SAP\ Business\ Client\ "
```

**StripPatterns** -- Always seeded with two patterns:
- `\s+v?\d+[\.\d]*\s*$` -- removes trailing version numbers (e.g. `7.70`, `v2.1.3`)
- `\s+\d{4}$` -- removes trailing standalone year tokens (e.g. `2024`)

If any item name contains `(`, a third pattern is added:
- `\s*\(.*?\)\s*$` -- removes trailing parenthetical notes (e.g. `(64-bit)`)

No `StripPatterns` are added for exclusion rules.

#### Exclusion Rules

When `-Exclude` is specified, the generated rule sets `IsExcludeRule = true` and leaves `TargetFamily`, `TargetVendor`, and `StripPatterns` empty. The `RuleName` defaults to `"Exclude <vendor>"` if `-FamilyName` is omitted. Items matching an exclusion rule are suppressed from recognition and are not assigned a family. They still appear in `History` with `FamilyId = NULL` so they are auditable.

Exclusion rules should use a `-Priority` below 10 so they run before any match rules.

```powershell
# Match and exclude all items
$items = Get-SREUnrecognized -Catalog $c -Top 500
$noise = $items | Where-Object { $_.RawVendor -like '*Delivered by Citrix*' }
New-SRERule -Catalog $c -Items $noise -Exclude -Priority 5
```

#### Usage Examples

```powershell
# Step 1: find unrecognized items
$unrecog = Get-SREUnrecognized -Catalog $c -Top 500

# Step 2: filter to a specific vendor/product group
$sapItems = $unrecog | Where-Object { $_.RawVendor -like '*SAP*' -and $_.RawName -like 'SAP Business Client*' }

# Step 3: preview the auto-generated rule without saving
New-SRERule -Catalog $c -Items $sapItems -FamilyName 'SAP Business Client' -Vendor 'SAP' -WhatIf

# Step 4: save the rule and immediately reprocess all unmatched History rows
New-SRERule -Catalog $c -Items $sapItems -FamilyName 'SAP Business Client' -Vendor 'SAP' -Reprocess

# Exclusion rule for noise items (with WhatIf preview first)
$noise = $unrecog | Where-Object { $_.RawVendor -like '*Delivered by Citrix*' }
New-SRERule -Catalog $c -Items $noise -Exclude -Priority 5 -WhatIf
New-SRERule -Catalog $c -Items $noise -Exclude -Priority 5
```

---

### `Invoke-SREReprocess`

Re-runs the recognition pipeline on History rows that previously had no match (or low confidence), and updates `History`, `Products`, `Variants`, and `LookupTable` for any pairs that now resolve to a known family.

Use this after adding new rules to retroactively fix records that were ingested before the rule existed.

```powershell
Invoke-SREReprocess -Catalog <SoftwareCatalog>
                    [-MatchMethod <string[]>]
                    [-ConfidenceBelow <int>]
                    [-WhatIf]
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Catalog` | SoftwareCatalog | Mandatory | |
| `-MatchMethod` | string[] | `@('None')` | Reprocess History rows with these match methods. Valid values: `None`, `Fuzzy`, `Learned`. |
| `-ConfidenceBelow` | int (0-100) | 0 | Also reprocess rows whose `MatchConfidence` is below this value, regardless of method. 0 disables. |
| `-WhatIf` | switch | -- | Runs recognition and reports what would change, without writing anything to the database. |

**Returns** a `PSObject[]` with these columns per unique vendor+name pair examined:

| Column | Description |
|---|---|
| `RawVendor` | The raw vendor string from History |
| `RawName` | The raw product name from History |
| `OldMethod` | Match method before reprocessing |
| `OldConfidence` | Confidence score before reprocessing |
| `NewMethod` | Match method after reprocessing |
| `NewConfidence` | Confidence score after reprocessing |
| `FamilyName` | Family the item resolved to (empty if still unmatched) |
| `Updated` | `$true` if the History rows were updated |

#### How Reprocessing Works Internally

Reprocessing works on **unique `RawVendor + RawName` pairs**, not on individual History rows. This prevents redundant recognition calls when the same software appears on hundreds of hosts.

```
1. Query History for distinct (RawVendor, RawName) pairs where:
     MatchMethod IN (specified methods)
     OR MatchConfidence < ConfidenceBelow threshold (if > 0)
   Use a self-join to fetch one representative row per pair
   (the most recent HistoryId for that pair).

2. For each unique pair:
   a. Build a minimal item object from the representative row.
   b. Call Recognize(item) -- runs the full pipeline (cache -> rules -> fuzzy).
   c. If the new result has FamilyId > 0 AND MatchMethod != 'None'
      AND (old method was 'None' OR new confidence > old confidence):
        - Call _GetOrCreateFamily() to ensure the family row exists
          in ProductFamilies before any FK-constrained insert.
        - Bulk-UPDATE all History rows sharing this (RawVendor, RawName)
          pair: set FamilyId, ProductId, MatchMethod, MatchConfidence.
          Only rows that would improve are touched.
        - Upsert Products and Variants.
        - Add to LookupTable cache.
        - Record as Updated = true in results.
   d. Else: record as Updated = false.

3. Return results array.
```

History is treated as **mutable only for the resolution columns** during reprocessing. Raw data (`RawVendor`, `RawName`, `DisplayVersion`, `SourceHost`, `SeenAt`) is never changed. The audit trail is preserved; only the recognition outcome is corrected.

#### Usage Examples

```powershell
# After adding new rules, reprocess everything that was unrecognized
Invoke-SREReprocess -Catalog $c

# Reprocess unrecognized + any fuzzy matches below 70% confidence
Invoke-SREReprocess -Catalog $c -MatchMethod None, Fuzzy -ConfidenceBelow 70

# Dry run first -- see what would change without touching the database
$preview = Invoke-SREReprocess -Catalog $c -WhatIf
$preview | Where-Object Updated | Format-Table RawName, OldMethod, NewMethod, FamilyName

# After reviewing the preview, apply for real
Invoke-SREReprocess -Catalog $c

# Find out what proportion of previously unmatched items can now be resolved
$results = Invoke-SREReprocess -Catalog $c
$results | Group-Object Updated | Select-Object Name, Count
```

---

## 12. Rule Maintenance in Production

Rules are the primary lever for controlling recognition quality. In a live environment, the rule set drifts out of sync with reality as new software is deployed, vendors change their naming, and your estate evolves. This section describes how to keep the rule set healthy and the data consistent.

### The Maintenance Cycle

The recommended cycle is weekly, or after any large inventory ingest:

```
1. Ingest new inventory data (Add-SREInventory)
2. Review unrecognized items (Get-SREUnrecognized)
3. Review low-confidence matches (Get-SRELowConfidence)
4. Write new rules for clear patterns (New-SRERule -WhatIf, then save)
5. Reprocess historical data (Invoke-SREReprocess)
6. Verify results (Get-SREUnrecognized again -- count should fall)
```

### Auditing the Active Rule Set

View all rules currently in the database:

```powershell
# All active rules, ordered by priority
Import-Module SimplySql
Open-MySqlConnection -ConnectionString $connStr
Invoke-SqlQuery -Query "SELECT RuleName, Priority, IsExcludeRule, VendorPattern, NamePattern, TargetFamily, IsBuiltIn FROM NormalizationRules WHERE IsActive = 1 ORDER BY Priority"
Close-SqlConnection
```

List only custom (non-built-in) rules:

```powershell
Invoke-SqlQuery -Query "SELECT * FROM NormalizationRules WHERE IsBuiltIn = 0 AND IsActive = 1 ORDER BY Priority"
```

Find rules that have never fired (may be redundant or broken):

```powershell
# No direct hit counter in the schema, but proxy via LookupTable method distribution
Invoke-SqlQuery -Query "SELECT MatchMethod, COUNT(*) AS Cnt FROM LookupTable GROUP BY MatchMethod"
```

### Testing a Rule Before Saving

Always use `-WhatIf` and `Invoke-SRERecognize` to validate a rule before committing it. A poorly written rule can silently claim items that belong to a different family.

```powershell
# 1. Preview the auto-generated rule
$items = Get-SREUnrecognized -Catalog $c | Where-Object { $_.RawName -like 'ACME*' }
New-SRERule -Catalog $c -Items $items -FamilyName 'ACME CRM' -Vendor 'ACME' -WhatIf

# 2. Test specific names against the recognition pipeline (rule is not saved yet)
#    Add the rule temporarily to a test catalog, or test the regex directly:
'ACME CRM Suite 2024' -match '^ACME\ CRM'       # True -- will match
'ACME Analytics 2024' -match '^ACME\ CRM'       # False -- will NOT match (good)

# 3. After saving the rule, verify with Invoke-SRERecognize
Add-SRERule -Catalog $c -Hashtable @{ RuleName='ACME CRM'; Priority=55; ... }
Invoke-SRERecognize -Catalog $c -Vendor 'ACME Corp' -Name 'ACME CRM Suite 2024'
# Expect: MatchMethod = Rule, FamilyName = 'ACME CRM', Confidence = 95
```

### Diagnosing Rule Conflicts

A rule conflict occurs when a broad rule matches an item that a more specific (higher priority number) rule was intended to catch. Symptoms: items end up in the wrong family with MatchMethod = Rule.

```powershell
# Find items assigned to family X that look like they belong to family Y
Get-SREHostInventory -Catalog $c -HostName '' |
    Where-Object { $_.FamilyName -eq 'Citrix Workspace App' -and $_.RawName -like '*Receiver*' } |
    Select-Object RawName, MatchMethod, MatchConfidence
```

To resolve a conflict, either:
- Narrow the broad rule's `NamePattern` so it no longer matches the disputed items, or
- Add a new rule with a lower Priority number (runs first) that claims the disputed items for the correct family.

**Never delete the built-in rules.** Override them with a custom rule at a lower priority number instead.

### Disabling vs Deleting Rules

Set `IsActive = 0` to disable a rule without removing it. This preserves the history of what the rule was and lets you re-enable it easily. Only delete a rule if you are certain it was never correct and you want it gone from audit logs.

```powershell
# Disable a rule (keeps it in the database)
Invoke-SqlUpdate -Query "UPDATE NormalizationRules SET IsActive = 0 WHERE RuleName = 'Old Rule Name'"

# Re-enable it
Invoke-SqlUpdate -Query "UPDATE NormalizationRules SET IsActive = 1 WHERE RuleName = 'Old Rule Name'"
```

After disabling a rule, run `Invoke-SREReprocess -MatchMethod Rule` to find items that were matched by that rule and re-run them through the current rule set:

```powershell
# Reprocess items previously matched by any rule (they may now match a different rule or go to fuzzy)
Invoke-SREReprocess -Catalog $c -MatchMethod Rule -WhatIf
Invoke-SREReprocess -Catalog $c -MatchMethod Rule
```

### Handling Fuzzy Mismatches

`Get-SRELowConfidence` is the primary tool for finding systematic fuzzy mismatches -- cases where the engine confidently matched an item to the wrong family.

```powershell
# Find mismatches grouped by the family they were (incorrectly) assigned to
Get-SRELowConfidence -Catalog $c -Threshold 75 -Top 1000 |
    Group-Object FamilyName |
    Sort-Object Count -Descending |
    Select-Object -First 20 Name, Count
```

For each problematic group:

1. Inspect the raw names:
   ```powershell
   Get-SRELowConfidence -Catalog $c -Threshold 75 -Top 1000 |
       Where-Object { $_.FamilyName -eq 'Wrong Family' } |
       Select-Object RawVendor, RawName, MatchConfidence
   ```

2. Write an explicit rule that claims those items for the correct family:
   ```powershell
   $items = Get-SREUnrecognized -Catalog $c  # or pull from LowConfidence
   New-SRERule -Catalog $c -Items $wrongItems -FamilyName 'Correct Family' -Priority 45 -WhatIf
   ```

3. After saving the rule, reprocess the low-confidence rows:
   ```powershell
   Invoke-SREReprocess -Catalog $c -MatchMethod Fuzzy -ConfidenceBelow 75
   ```

### Reprocessing Safely in Production

`Invoke-SREReprocess` modifies History rows in bulk. Follow this sequence to avoid data surprises:

```powershell
# Step 1: Always preview first
$preview = Invoke-SREReprocess -Catalog $c -WhatIf
Write-Host "Would update: $(($preview | Where-Object Updated).Count) pairs"
Write-Host "Would leave unchanged: $(($preview | Where-Object { -not $_.Updated }).Count) pairs"

# Step 2: Inspect what would change -- spot-check a few
$preview | Where-Object Updated | Select-Object -First 20 | Format-Table RawVendor, RawName, OldMethod, NewMethod, FamilyName

# Step 3: If the preview looks correct, apply for real
Invoke-SREReprocess -Catalog $c

# Step 4: Verify the unrecognized count dropped
Get-SREUnrecognized -Catalog $c -Top 500 | Measure-Object | Select-Object Count
```

**What Reprocess will never do:**
- Delete History rows
- Change `RawVendor`, `RawName`, `DisplayVersion`, or `SeenAt` on any row
- Downgrade a row from a higher-confidence match to a lower-confidence one
- Touch rows whose current `MatchConfidence` is already higher than the new result

### Managing Auto-Learned Families

The self-learning step creates `ProductFamilies` rows with `IsKnown = 0` for items that scored 50-59% against existing families or had no fuzzy match at all. Over time, these accumulate and can become noise.

```powershell
# How many auto-learned families exist?
Get-SREFamily -Catalog $c | Where-Object { $_.IsKnown -eq 0 } | Measure-Object | Select-Object Count

# Review the newest auto-learned families
Get-SREFamily -Catalog $c |
    Where-Object { $_.IsKnown -eq 0 } |
    Sort-Object CreatedAt -Descending |
    Select-Object -First 30 FamilyName, Vendor, CreatedAt
```

For each auto-learned family, decide one of:

- **It is a real product** -- write an explicit rule with `TargetFamily` set to this name. The next reprocess will promote it to `IsKnown = 1` (the family already exists; the rule will use it).
- **It is a duplicate of an existing family** -- write a rule that maps its items to the correct family. After reprocessing, the duplicate family will have zero products and can be manually deleted from `ProductFamilies`.
- **It is noise** -- write an exclusion rule at Priority 5-10. After reprocessing, the family will have zero products and can be deleted.

### Backing Up and Restoring Rules

Export all custom rules before making bulk changes:

```powershell
Import-Module SimplySql
Open-MySqlConnection -ConnectionString $connStr
$rules = Invoke-SqlQuery -Query "SELECT * FROM NormalizationRules WHERE IsBuiltIn = 0"
$rules | ConvertTo-Json -Depth 5 | Set-Content ".\rules_backup_$(Get-Date -Format yyyyMMdd).json"
Close-SqlConnection
```

To restore from backup if a batch of rule changes goes wrong:

```sql
-- In MySQL client: remove custom rules added after the backup date
DELETE FROM NormalizationRules WHERE IsBuiltIn = 0 AND CreatedAt > '2025-01-01';
```

Then reload the module (to refresh the in-memory rule set) and reprocess.

### Rule Naming Conventions

Consistent naming makes the rule set auditable at a glance:

| Pattern | Example |
|---|---|
| Family assignment rules | Vendor + Product: `"SAP Business Client"`, `"Cisco Webex"` |
| Exclusion rules | `"Exclude "` prefix: `"Exclude VS Internal Packages"`, `"Exclude Delivered by Citrix"` |
| Vendor normalizers | `"Normalize "` prefix: `"Normalize Microsoft Vendor"` |
| Catch-all rules | `"All "` prefix: `"All ACME Products"` |

---

## 13. Operational Workflows

### Daily Audit Workflow

```powershell
$c = New-SoftwareCatalog -ConnectionString $connStr

# 1. What did the engine fail to classify?
$unrecog = Get-SREUnrecognized -Catalog $c -Top 500
Write-Host "Unrecognized: $($unrecog.Count)"
$unrecog | Group-Object RawVendor | Sort-Object Count -Descending | Select-Object -First 10 Name, Count

# 2. Review shaky matches
$lowConf = Get-SRELowConfidence -Catalog $c -Threshold 70 -Top 200
Write-Host "Low-confidence: $($lowConf.Count)"
$lowConf | Format-Table RawName, FamilyName, MatchConfidence

# 3. For any clear pattern in unrecognized items, derive and save a rule
$sapItems = $unrecog | Where-Object { $_.RawVendor -like '*SAP*' -and $_.RawName -like 'SAP Business Client*' }
if ($sapItems) {
    New-SRERule -Catalog $c -Items $sapItems -FamilyName 'SAP Business Client' -Vendor 'SAP' -WhatIf
    # Review output, then:
    New-SRERule -Catalog $c -Items $sapItems -FamilyName 'SAP Business Client' -Vendor 'SAP' -Reprocess
}

# 4. Re-verify
Get-SREUnrecognized -Catalog $c | Measure-Object | Select-Object Count
```

### Rule Deployment Workflow

```powershell
$c = New-SoftwareCatalog -ConnectionString $connStr

# Preview the auto-generated rule
$items = Get-SREUnrecognized -Catalog $c -Top 500
$targetItems = $items | Where-Object { $_.RawVendor -like '*ACME*' }
New-SRERule -Catalog $c -Items $targetItems -FamilyName 'ACME CRM' -Vendor 'ACME Corp' -WhatIf

# Validate the generated patterns manually
'ACME CRM Suite 2024' -match '^ACME\ CRM'        # expect True
'ACME Analytics Platform' -match '^ACME\ CRM'    # expect False

# Save the rule (without reprocess yet)
$rule = New-SRERule -Catalog $c -Items $targetItems -FamilyName 'ACME CRM' -Vendor 'ACME Corp'

# Spot-check recognition on a known item
Invoke-SRERecognize -Catalog $c -Vendor 'ACME Corp' -Name 'ACME CRM Suite 2024'

# Preview reprocess impact
$preview = Invoke-SREReprocess -Catalog $c -WhatIf
$preview | Where-Object Updated | Format-Table RawVendor, RawName, NewMethod, FamilyName

# Apply reprocess
Invoke-SREReprocess -Catalog $c

# Confirm
Get-SREFamily -Catalog $c -Name 'ACME CRM'
Get-SREHostCount -Catalog $c -FamilyName 'ACME CRM'
```

### Weekly Change Report

```powershell
$c = New-SoftwareCatalog -ConnectionString $connStr

$newSw = Get-SRENewSoftware -Catalog $c -Days 7
Write-Host "=== New Software This Week ==="
$newSw | Group-Object FamilyName | Sort-Object Count -Descending |
    Select-Object -First 20 Name, Count | Format-Table

$newUnknown = $newSw | Where-Object { $_.MatchMethod -eq 'None' }
if ($newUnknown.Count -gt 0) {
    Write-Host "`n=== New UNRECOGNIZED Software (potential shadow IT) ==="
    $newUnknown | Select-Object SourceHost, RawVendor, RawName, FirstSeen | Format-Table
}
```

### Fleet Coverage Report

```powershell
$c = New-SoftwareCatalog -ConnectionString $connStr

$hosts = Get-SREHostInventory -Catalog $c -ListHosts
Write-Host "Total hosts: $($hosts.Count)"

Write-Host "`n=== Top 15 Software by Host Count ==="
Get-SRETopSoftware -Catalog $c -Top 15 | Format-Table FamilyName, HostCount, TotalInstalls

foreach ($product in @('Citrix Workspace App', 'Cisco Secure Client', 'Microsoft Edge')) {
    Write-Host "`n=== Version Sprawl: $product ==="
    Get-SREVersionSprawl -Catalog $c -FamilyName $product |
        Format-Table DisplayVersion, HostCount
}
```

### Host Compliance Check

```powershell
$c = New-SoftwareCatalog -ConnectionString $connStr
$requiredProduct = 'Cisco Secure Client'

$totalHosts   = (Get-SREHostInventory -Catalog $c -ListHosts).Count
$coveredCount = (Get-SREHostCount -Catalog $c -FamilyName $requiredProduct).HostCount
Write-Host "$requiredProduct: $coveredCount / $totalHosts hosts ($($totalHosts - $coveredCount) missing)"
```

---

## 14. Performance Notes

### Lookup Cache

On startup, `SoftwareCatalog` loads the entire `LookupTable` into an in-memory hashtable (`_lookupCache`). Every previously-seen `vendor::name` pair resolves in O(1) without a database query. For a catalog with thousands of entries and hundreds of thousands of history records, typical startup takes under 5 seconds.

### FuzzyIndex

Fuzzy matching uses a token-based inverted index. Only items that share at least one token with the query are scored, dramatically reducing the candidate set. Token extraction filters out stop words and tokens under 3 characters.

### Bulk Ingestion

`Add-SREInventory` processes items sequentially. For very large datasets (100,000+ items), consider splitting the JSON into chunks and calling `Add-SREInventory` in a loop. Each item that hits the lookup cache costs approximately 1ms; unrecognized items requiring fuzzy search cost 10-50ms depending on FuzzyIndex size.

### Reprocessing Performance

`Invoke-SREReprocess` works on unique `RawVendor + RawName` pairs, not individual History rows, so its cost scales with the number of unique software titles -- not the number of hosts. A catalog with 2,000 unique products reprocesses in seconds even if each product is installed on 1,000 hosts.

### Query Performance

All query functions use indexed columns:

| Query | Index used |
|---|---|
| `GetNewSoftware(days)` | `idx_history_seen` on `SeenAt` |
| `GetVersionSprawl(familyId)` | `idx_history_family` on `FamilyId` |
| `GetUnrecognized()` | `idx_history_seen` + MatchMethod filter |

For estates with millions of History rows, a composite index on `(MatchMethod, SeenAt)` will improve audit query performance:

```sql
ALTER TABLE History ADD INDEX idx_history_method_seen (MatchMethod, SeenAt);
```

---

## 15. Troubleshooting

### `No MySQL connection string found`

Supply a connection string using one of the three methods in [Section 4](#4-configuration).

### `Invoke-SqlQuery: Query returned no resultset`

This warning from SimplySql appears when a query returns zero rows. It is suppressed on internal module calls. If you see it from your own code, wrap the call with `@()` to force an empty array return.

### Rules are not matching

1. Test the regex independently:
   ```powershell
   'Citrix Workspace 2409' -match 'Citrix (Workspace|Receiver)'   # expect True
   ```
2. Check priority -- a higher-priority rule (lower number) may be matching first. List active rules ordered by priority to find conflicts.
3. Reload the module after adding rules if the in-session cache is stale:
   ```powershell
   Remove-Module SoftwareRecognitionEngine
   Import-Module .\SoftwareRecognitionEngine\SoftwareRecognitionEngine.psd1
   $c = New-SoftwareCatalog -ConnectionString $connStr
   ```
4. Verify the rule is active:
   ```powershell
   Invoke-SqlQuery -Query "SELECT IsActive FROM NormalizationRules WHERE RuleName = 'My Rule'"
   ```

### `Invoke-SRERecognize` returns the wrong family

An existing rule is claiming the item. Identify which rule:

```powershell
# Check what method and confidence the item resolves with
$r = Invoke-SRERecognize -Catalog $c -Vendor 'My Vendor' -Name 'My Product'
$r | Select-Object FamilyName, MatchMethod, Confidence

# If MatchMethod = 'Rule', the item hit a rule -- find which one by testing patterns
Invoke-SqlQuery -Query "SELECT RuleName, Priority, VendorPattern, NamePattern FROM NormalizationRules WHERE IsActive = 1 ORDER BY Priority" |
    Where-Object { 'My Vendor' -match $_.VendorPattern -or $_.VendorPattern -eq '' } |
    Where-Object { 'My Product' -match $_.NamePattern  -or $_.NamePattern  -eq '' }
```

Add a more specific rule at a lower priority number to override the incorrect match.

### Fuzzy matches seem wrong

Run `Get-SRELowConfidence` and follow the [Handling Fuzzy Mismatches](#handling-fuzzy-mismatches) workflow in Section 12. An explicit normalization rule at Priority 45-55 will always beat a fuzzy match.

### Reprocess ran but unrecognized count did not drop

The remaining items may have empty `RawName` (these cannot be matched by any rule) or their `RawName` genuinely does not match any current rule's `NamePattern`. Check:

```powershell
Get-SREUnrecognized -Catalog $c -Top 500 |
    Where-Object { $_.RawName -and $_.RawName.Trim() -ne '' } |
    Select-Object RawVendor, RawName | Format-Table
```

Items with empty names are not addressable by rules. Items with names but no rule match are candidates for new rules.

### Self-learning created too many families

Filter and review auto-learned families:

```powershell
Get-SREFamily -Catalog $c |
    Where-Object { $_.IsKnown -eq 0 } |
    Sort-Object CreatedAt -Descending |
    Select-Object FamilyName, Vendor, CreatedAt
```

Write explicit rules or exclusion rules for the noisy ones, then reprocess. See [Managing Auto-Learned Families](#managing-auto-learned-families) in Section 12.

### Module type identity error on reload

**Symptom:** `Cannot convert the "..." value of type "NormalizationRule" to type "NormalizationRule"` after re-importing the module.

**Cause:** PowerShell compiles class types per module scope. Re-importing the module creates a new type identity. Old objects in your session no longer satisfy the new type check.

**Fix:** Always create a fresh catalog instance after re-importing:

```powershell
Remove-Module SoftwareRecognitionEngine -ErrorAction SilentlyContinue
Import-Module .\SoftwareRecognitionEngine\SoftwareRecognitionEngine.psd1 -Force
$c = New-SoftwareCatalog -ConnectionString $connStr
```
