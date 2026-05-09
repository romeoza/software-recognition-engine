# Software Recognition Engine (SRE)

A self-learning PowerShell module that normalizes, deduplicates, and classifies software inventory data from sources such as Zabbix, SCCM, or any JSON-based software scan. Raw install names like `"Citrix Workspace 2409"`, `"Citrix Receiver 4.9"`, and `"Citrix Workspace App 24.8.0.138"` are all resolved to a single canonical family — `Citrix Workspace App` — so you can query, count, and audit your estate cleanly.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Prerequisites & Installation](#3-prerequisites--installation)
4. [Configuration](#4-configuration)
5. [Quick Start](#5-quick-start)
6. [Recognition Pipeline](#6-recognition-pipeline)
7. [Core Functions](#7-core-functions)
8. [Query Functions](#8-query-functions)
9. [Data Model](#9-data-model)
10. [Writing Custom Rules](#10-writing-custom-rules)
11. [Operational Workflows](#11-operational-workflows)
12. [Performance Notes](#12-performance-notes)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Overview

### The Problem

Software inventory data from enterprise environments is noisy. The same product appears under dozens of raw names depending on the version, architecture, installer packaging, and vendor naming convention. Standard queries like "how many machines have Citrix?" are unanswerable without manual deduplication.

### What SRE Does

SRE sits between your raw inventory feed and your reporting layer. It:

- **Normalizes** raw software names using regex-based rules (e.g. strip trailing version numbers, consolidate vendor name variants)
- **Groups** related installs into **Product Families** (e.g. all Citrix Workspace and Receiver variants → one family)
- **Fuzzy-matches** unrecognized items against the known catalog using Levenshtein + Jaccard similarity
- **Self-learns** from your data — items that score above 50% fuzzy confidence are auto-assigned to the nearest existing family; truly unknown items seed new families automatically
- **Persists everything** to MySQL with a full audit trail, so you can query across time, host, version, and confidence

### Key Capabilities

| Area | Capability |
|---|---|
| Ingest | Bulk import from JSON or PSObject arrays |
| Recognize | Per-item recognition with confidence score and match method |
| Query | 11 purpose-built query functions covering catalog, fleet, audit, and change tracking |
| Rules | 28+ built-in normalization rules; add custom rules at runtime |
| Audit | Full history table — every recognition is logged with method and confidence |
| Change | Track new software appearances and stale/removed products over time |

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SoftwareCatalog (class)                       │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ NormalizationEngine│  │ FuzzyMatcher │  │    History       │   │
│  │ (priority-ordered │  │ (Levenshtein │  │ (audit trail)    │   │
│  │  regex rules)    │  │  + Jaccard)  │  │                  │   │
│  └──────────────────┘  └──────────────┘  └──────────────────┘   │
│                                                                  │
│  In-memory lookup cache (hashtable)  ←→  LookupTable (MySQL)    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ SimplySql
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         MySQL Database                           │
│                                                                  │
│  ProductFamilies  Products  Variants  History                    │
│  NormalizationRules  LookupTable  FuzzyIndex                     │
└─────────────────────────────────────────────────────────────────┘
```

### Components

| Component | File | Responsibility |
|---|---|---|
| `SoftwareCatalog` | `Classes/06_SoftwareCatalog.ps1` | Orchestrates all subsystems; public API |
| `NormalizationEngine` | `Classes/03_NormalizationEngine.ps1` | Applies priority-ordered regex rules |
| `NormalizationRule` | `Classes/02_NormalizationRule.ps1` | Single rule with match + transform logic |
| `FuzzyMatcher` | `Classes/04_FuzzyMatcher.ps1` | Levenshtein + Jaccard similarity scoring |
| `History` | `Classes/05_History.ps1` | Persists every recognition event |
| Built-in Rules | `Data/BuiltInRules.ps1` | 28+ vendor-specific normalization rules |
| Schema | `Data/Schema.sql` | MySQL DDL — idempotent, run-once |

---

## 3. Prerequisites & Installation

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
-- In MySQL client
CREATE DATABASE SRE CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'sreuser'@'localhost' IDENTIFIED BY 'yourpassword';
GRANT ALL PRIVILEGES ON SRE.* TO 'sreuser'@'localhost';
FLUSH PRIVILEGES;
```

The schema is applied automatically the first time you call `New-SoftwareCatalog` — the `_EnsureSchema()` method runs all DDL statements idempotently using `IF NOT EXISTS`.

Alternatively, run the setup script manually:

```powershell
.\Setup-SREDatabase.ps1
```

### Import the Module

```powershell
Import-Module .\SoftwareRecognitionEngine\SoftwareRecognitionEngine.psd1
```

---

## 4. Configuration

The connection string can be supplied in three ways, checked in this order:

### Option 1 — Constructor parameter (recommended for scripts)

```powershell
$catalog = New-SoftwareCatalog -ConnectionString "Server=localhost;Database=SRE;Uid=sreuser;Pwd=yourpassword;"
```

### Option 2 — Environment variable (CI/CD pipelines, scheduled tasks)

```powershell
$env:SRE_CONNECTION_STRING = "Server=localhost;Database=SRE;Uid=sreuser;Pwd=yourpassword;"
$catalog = New-SoftwareCatalog
```

### Option 3 — Config file (shared workstation setups)

Create `%APPDATA%\SoftwareRecognitionEngine\config.json`:

```json
{
  "ConnectionString": "Server=localhost;Database=SRE;Uid=sreuser;Pwd=yourpassword;"
}
```

Then call `New-SoftwareCatalog` with no parameters.

---

## 5. Quick Start

```powershell
Import-Module .\SoftwareRecognitionEngine\SoftwareRecognitionEngine.psd1

# Connect
$c = New-SoftwareCatalog -ConnectionString "Server=localhost;Database=SRE;Uid=root;Pwd=;"

# Ingest a JSON export from Zabbix or SCCM
Add-SREInventory -Catalog $c -JsonPath .\inventory.json

# Query — what are the most-deployed products across the estate?
Get-SRETopSoftware -Catalog $c | Format-Table FamilyName, HostCount, TotalInstalls

# Audit — what did the engine fail to recognize?
Get-SREUnrecognized -Catalog $c | Format-Table SourceHost, RawVendor, RawName

# Change — what software appeared in the last 7 days?
Get-SRENewSoftware -Catalog $c -Days 7 | Format-Table SourceHost, RawName, FamilyName, FirstSeen
```

---

## 6. Recognition Pipeline

Every item passed to the engine goes through four steps in order. The pipeline short-circuits as soon as a match is found.

```
Item (Vendor + Name)
        │
        ▼
┌───────────────────────────────────┐
│  Step 1: Exact Lookup (O(1))      │  Hit → return cached result immediately
│  In-memory hashtable              │  Miss → continue
└───────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────┐
│  Step 2: Normalization Rules      │  Match → 95% confidence, MatchMethod = Rule
│  Priority-ordered regex engine    │  Exclude rule hit → IsExcluded = true
│  First match wins                 │  No match → continue
└───────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────┐
│  Step 3: Fuzzy Match              │  Score ≥ 60% → return best match, MatchMethod = Fuzzy
│  Token lookup → Levenshtein       │  Score 50–59% → self-learn: assign to existing family
│  + Jaccard hybrid score           │  Score < 50% → no match → continue
└───────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────┐
│  Step 4: Self-Learning            │  Create new ProductFamily from normalized name
│  Auto-seed FuzzyIndex             │  MatchMethod = Learned
│  Cache result for next run        │
└───────────────────────────────────┘
```

### Match Methods

| Method | Meaning | Typical Confidence |
|---|---|---|
| `Exact` | Found in O(1) lookup cache from a prior recognition | Same as original match |
| `Rule` | Matched by a normalization rule | 95% |
| `Fuzzy` | Matched by Levenshtein + Jaccard scoring against FuzzyIndex | 60–94% |
| `Learned` | Auto-assigned to an existing family (50–59% fuzzy score) | 50–65% |
| `None` | No match at any step | 0% |

### Fuzzy Scoring

The confidence score is a weighted average of two similarity measures:

```
Confidence = (LevenshteinScore × 0.6) + (JaccardScore × 0.4)
```

- **Levenshtein** — character-level edit distance, normalized to 0–100
- **Jaccard** — word-token set overlap (intersection ÷ union), case-insensitive
- Minimum confidence threshold: **60%** — scores below this are not returned as matches

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

```powershell
# Explicit connection string
$c = New-SoftwareCatalog -ConnectionString "Server=db01;Database=SRE;Uid=sre;Pwd=secret;"

# From environment variable
$env:SRE_CONNECTION_STRING = "Server=localhost;Database=SRE;Uid=root;Pwd=;"
$c = New-SoftwareCatalog
```

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

Runs a single item through the recognition pipeline and returns a `RecognitionResult` without writing to the database. Useful for testing rules or checking what a specific name resolves to.

```powershell
$result = Invoke-SRERecognize -Catalog <SoftwareCatalog> [-Item <PSObject>] [-Vendor <string> -Name <string>]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Catalog` | SoftwareCatalog | Yes | |
| `-Item` | PSObject | Yes (or Vendor+Name) | Object with Vendor and Name properties |
| `-Vendor` | string | Yes (or Item) | Vendor string |
| `-Name` | string | Yes (or Item) | Product name string |

**Returns** a `RecognitionResult` object:

| Property | Type | Description |
|---|---|---|
| `FamilyId` | int | Matched family ID (0 if unrecognized) |
| `FamilyName` | string | Canonical family name |
| `ProductId` | int | Matched product ID |
| `ProductName` | string | Matched product name |
| `Confidence` | int | Match confidence 0–100 |
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

Adds a custom normalization rule to the engine and persists it to the database. The rule takes effect immediately for subsequent `Recognize` calls.

```powershell
Add-SRERule -Catalog <SoftwareCatalog> [-Rule <NormalizationRule>] [-Hashtable <hashtable>]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Catalog` | SoftwareCatalog | Yes | |
| `-Rule` | NormalizationRule | Yes (or Hashtable) | Pre-built rule object |
| `-Hashtable` | hashtable | Yes (or Rule) | Property bag — a NormalizationRule is constructed from it |

See [Section 10](#10-writing-custom-rules) for full rule property reference and examples.

---

### `Export-SRECatalog`

Exports the current catalog state (families, stats) to a JSON file.

```powershell
Export-SRECatalog -Catalog <SoftwareCatalog> [-Path <string>] [-StatsOnly]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Catalog` | SoftwareCatalog | Yes | |
| `-Path` | string | No | Output path. Defaults to `.\SRECatalogExport_<timestamp>.json` |
| `-StatsOnly` | switch | No | Only export table row counts, not full family data |

```powershell
Export-SRECatalog -Catalog $c -Path C:\Reports\catalog.json
Export-SRECatalog -Catalog $c -StatsOnly   # lightweight stats snapshot
```

---

## 8. Query Functions

All query functions accept a `-Catalog` parameter and return pipeline-friendly `PSObject` arrays. Pipe to `Format-Table`, `Select-Object`, `Where-Object`, `Export-Csv`, etc.

---

### `Get-SREFamily`

Lists product families. Without filters, returns all 1,800+ families.

```powershell
Get-SREFamily -Catalog <SoftwareCatalog> [-Name <string>] [-Vendor <string>]
```

| Parameter | Description |
|---|---|
| `-Name` | Filter families whose name contains this string (LIKE match) |
| `-Vendor` | Filter families whose vendor contains this string (LIKE match) |

**Returns:** `FamilyId`, `FamilyName`, `NormalizedName`, `Vendor`, `IsKnown`, `ConfidenceFloor`, `CreatedAt`, `UpdatedAt`

`IsKnown = 1` means the family was created by a normalization rule (high confidence). `IsKnown = 0` means it was auto-learned from inventory data.

```powershell
# All families
Get-SREFamily -Catalog $c

# All Microsoft families
Get-SREFamily -Catalog $c -Vendor 'Microsoft'

# Families with "Citrix" in the name
Get-SREFamily -Catalog $c -Name 'Citrix'

# How many families are rule-created vs auto-learned?
Get-SREFamily -Catalog $c | Group-Object IsKnown | Select-Object Name, Count
```

---

### `Get-SREProduct`

Lists products joined to their parent family.

```powershell
Get-SREProduct -Catalog <SoftwareCatalog> [-FamilyId <int>] [-FamilyName <string>] [-Search <string>]
```

| Parameter | Description |
|---|---|
| `-FamilyId` | Return only products in this family (exact ID) |
| `-FamilyName` | Return only products in matching families (partial name match; warns if ambiguous) |
| `-Search` | Filter by product name substring |

**Returns:** `ProductId`, `FamilyId`, `FamilyName`, `ProductName`, `Vendor`, `InstallCount`, `FirstSeen`, `LastSeen`

```powershell
# All products
Get-SREProduct -Catalog $c

# Products in the Cisco Secure Client family
Get-SREProduct -Catalog $c -FamilyName 'Cisco Secure Client'

# Search by name fragment
Get-SREProduct -Catalog $c -Search 'AnyConnect'

# Products not seen recently (stale products within a known family)
Get-SREProduct -Catalog $c -FamilyName 'Java' |
    Where-Object { $_.LastSeen -lt (Get-Date).AddDays(-60) } |
    Select-Object ProductName, InstallCount, LastSeen
```

---

### `Get-SREVariant`

Lists all raw name variants recorded for a specific product. Each unique combination of vendor, name, and version creates a variant record. The `Version` column is extracted from the normalized key.

```powershell
Get-SREVariant -Catalog <SoftwareCatalog> -ProductId <int>
```

**Returns:** `VariantId`, `ProductId`, `ProductName`, `RawName`, `RawVendor`, `Version`, `SeenCount`, `FirstSeen`, `LastSeen`

```powershell
# Find a product first
$prod = Get-SREProduct -Catalog $c -Search 'AnyConnect Secure Mobility' | Select-Object -First 1

# Then inspect its raw variants
Get-SREVariant -Catalog $c -ProductId $prod.ProductId |
    Format-Table RawName, Version, SeenCount
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
| `-HostName` | Partial host name (LIKE match). Returns all recognized items for matching hosts |
| `-Top` | Limit result rows (default: unlimited) |

**`-ListHosts` returns:** `SourceHost`, `ItemCount`, `LastSeen`

**`-HostName` returns:** `SourceHost`, `RawName`, `RawVendor`, `DisplayVersion`, `FamilyName`, `MatchMethod`, `MatchConfidence`, `SeenAt`

```powershell
# All hosts in the estate
Get-SREHostInventory -Catalog $c -ListHosts | Sort-Object ItemCount -Descending

# Everything on a specific machine
Get-SREHostInventory -Catalog $c -HostName 'LAPTOP-001'

# Partial hostname (returns all matching)
Get-SREHostInventory -Catalog $c -HostName 'LAPTOP' -Top 500

# What did the engine fail to classify on host SERVER-01?
Get-SREHostInventory -Catalog $c -HostName 'SERVER-01' |
    Where-Object { $_.MatchMethod -eq 'None' }
```

---

### `Get-SREVersionSprawl`

Shows how many distinct versions of a product family exist across the estate, ordered by the number of hosts running each version. Use this to identify where patching is lagging.

```powershell
Get-SREVersionSprawl -Catalog <SoftwareCatalog> -FamilyId <int> [-Top <int>]
Get-SREVersionSprawl -Catalog <SoftwareCatalog> -FamilyName <string> [-Top <int>]
```

| Parameter | Description |
|---|---|
| `-FamilyId` | Family to analyze (exact ID) |
| `-FamilyName` | Family to analyze (partial name match) |
| `-Top` | Limit version rows returned (default: unlimited) |

**Returns:** `FamilyName`, `DisplayVersion`, `HostCount`, `InstallCount`, `FirstSeen`, `LastSeen`

```powershell
# Version spread for Cisco Secure Client
Get-SREVersionSprawl -Catalog $c -FamilyName 'Cisco Secure Client'

# How many machines are still on the old version?
Get-SREVersionSprawl -Catalog $c -FamilyName 'Cisco Secure Client' |
    Sort-Object HostCount -Descending |
    Select-Object DisplayVersion, HostCount

# Top 5 versions for all Java families
Get-SREFamily -Catalog $c -Name 'Java' | ForEach-Object {
    Get-SREVersionSprawl -Catalog $c -FamilyId $_.FamilyId -Top 5
}
```

---

### `Get-SREHostCount`

Returns the number of distinct hosts that have a specific product family installed — the core "how many machines have X?" query.

```powershell
Get-SREHostCount -Catalog <SoftwareCatalog> -FamilyId <int>
Get-SREHostCount -Catalog <SoftwareCatalog> -FamilyName <string>
```

**Returns:** `FamilyName`, `HostCount`, `TotalInstalls`, `FirstSeen`, `LastSeen`

```powershell
# Licensing headcount for Citrix Workspace
Get-SREHostCount -Catalog $c -FamilyName 'Citrix Workspace App'

# Compare host counts across multiple products
@('Citrix Workspace App', 'Cisco Secure Client', 'Microsoft Edge') | ForEach-Object {
    Get-SREHostCount -Catalog $c -FamilyName $_
} | Format-Table FamilyName, HostCount, TotalInstalls
```

---

### `Get-SRETopSoftware`

Returns the most-deployed product families across the estate, ranked by host count or total install count.

```powershell
Get-SRETopSoftware -Catalog <SoftwareCatalog> [-Top <int>] [-RankBy <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `-Top` | 25 | Number of families to return (1–1000) |
| `-RankBy` | `HostCount` | `HostCount` — distinct machines; `InstallCount` — total install events |

**Returns:** `FamilyName`, `Vendor`, `HostCount`, `TotalInstalls`, `LastSeen`

```powershell
# Executive summary — top 25 by machine count
Get-SRETopSoftware -Catalog $c | Format-Table FamilyName, Vendor, HostCount

# Top 10 by total installs (reveals multi-component suites)
Get-SRETopSoftware -Catalog $c -Top 10 -RankBy InstallCount

# Find any unexpected high-ranked software
Get-SRETopSoftware -Catalog $c -Top 50 |
    Where-Object { $_.Vendor -notmatch 'Microsoft|Citrix|Cisco|Adobe' }
```

---

### `Get-SREUnrecognized`

Lists software items the engine could not classify at any step of the pipeline (MatchMethod = None). These are your primary candidates for writing new normalization rules.

```powershell
Get-SREUnrecognized -Catalog <SoftwareCatalog> [-HostName <string>] [-Top <int>]
```

| Parameter | Default | Description |
|---|---|---|
| `-HostName` | — | Scope to a specific host (partial match) |
| `-Top` | 100 | Maximum rows to return |

**Returns:** `SourceHost`, `RawVendor`, `RawName`, `DisplayVersion`, `MatchMethod`, `MatchConfidence`, `SeenAt`

```powershell
# Daily triage — what did the engine miss?
Get-SREUnrecognized -Catalog $c | Group-Object RawVendor | Sort-Object Count -Descending

# Unrecognized items on a specific host
Get-SREUnrecognized -Catalog $c -HostName 'SERVER-01'

# Export unrecognized items for rule authoring
Get-SREUnrecognized -Catalog $c -Top 500 |
    Select-Object RawVendor, RawName |
    Sort-Object RawVendor, RawName -Unique |
    Export-Csv .\unrecognized.csv -NoTypeInformation
```

---

### `Get-SRELowConfidence`

Lists fuzzy and learned matches below a confidence threshold. These are matches where the engine made a decision but may have been wrong — worth reviewing before the catalog is used for compliance reporting.

```powershell
Get-SRELowConfidence -Catalog <SoftwareCatalog> [-Threshold <int>] [-Top <int>]
```

| Parameter | Default | Description |
|---|---|---|
| `-Threshold` | 70 | Return matches with MatchConfidence below this value (1–99) |
| `-Top` | 100 | Maximum rows to return |

**Returns:** `SourceHost`, `RawVendor`, `RawName`, `DisplayVersion`, `FamilyName`, `MatchMethod`, `MatchConfidence`, `SeenAt`

```powershell
# Default audit — anything below 70%
Get-SRELowConfidence -Catalog $c

# Very low confidence only — likely wrong
Get-SRELowConfidence -Catalog $c -Threshold 60 |
    Format-Table RawName, FamilyName, MatchConfidence

# Group by assigned family to find systematic mismatches
Get-SRELowConfidence -Catalog $c -Top 1000 |
    Group-Object FamilyName |
    Sort-Object Count -Descending |
    Select-Object Name, Count
```

---

### `Get-SRENewSoftware`

Lists software first seen in the catalog within the last N days. Results are grouped per host so repeated scans of the same machine don't inflate counts.

```powershell
Get-SRENewSoftware -Catalog <SoftwareCatalog> [-Days <int>] [-HostName <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `-Days` | 7 | Look back this many days (1–3650) |
| `-HostName` | — | Scope to a specific host (partial match) |

**Returns:** `RawVendor`, `RawName`, `DisplayVersion`, `FamilyName`, `MatchMethod`, `MatchConfidence`, `FirstSeen`, `SourceHost`

```powershell
# Weekly change report
Get-SRENewSoftware -Catalog $c -Days 7

# What appeared in the last 24 hours?
Get-SRENewSoftware -Catalog $c -Days 1

# New software on a specific host
Get-SRENewSoftware -Catalog $c -Days 1 -HostName 'LAPTOP-001'

# New unrecognized software this week (potential shadow IT)
Get-SRENewSoftware -Catalog $c -Days 7 |
    Where-Object { $_.MatchMethod -eq 'None' } |
    Select-Object SourceHost, RawVendor, RawName, FirstSeen
```

---

### `Get-SREStaleSoftware`

Lists products whose `LastSeen` timestamp in the Products table is older than N days. These may have been uninstalled, or the host may have been decommissioned.

```powershell
Get-SREStaleSoftware -Catalog <SoftwareCatalog> [-Days <int>]
```

| Parameter | Default | Description |
|---|---|---|
| `-Days` | 30 | Return products not seen within this many days (1–3650) |

**Returns:** `ProductId`, `FamilyName`, `ProductName`, `Vendor`, `InstallCount`, `LastSeen`, `DaysSinceLastSeen`

```powershell
# Products not seen in the last 30 days
Get-SREStaleSoftware -Catalog $c

# Very stale — not seen in 90+ days
Get-SREStaleSoftware -Catalog $c -Days 90 |
    Select-Object FamilyName, ProductName, DaysSinceLastSeen |
    Sort-Object DaysSinceLastSeen -Descending

# Stale software by vendor
Get-SREStaleSoftware -Catalog $c |
    Group-Object Vendor |
    Sort-Object Count -Descending
```

---

## 9. Data Model

```
ProductFamilies                Products                  Variants
──────────────────             ────────────────────      ─────────────────────
FamilyId   PK                  ProductId   PK            VariantId   PK
FamilyName                     FamilyId    FK ──────┐    ProductId   FK ──────┐
NormalizedName                 ProductName           │   RawName              │
Vendor                         NormalizedName         └── Products             │
NormalizedVendor               Vendor                     RawVendor            │
IsKnown      (1=rule, 0=auto)  NormalizedVendor           NormalizedKey        │
ConfidenceFloor                CanonicalVersion           SeenCount        ────┘
CreatedAt                      InstallCount               FirstSeen
UpdatedAt                      FirstSeen                  LastSeen
                               LastSeen

History                        NormalizationRules         LookupTable
──────────────────             ────────────────────       ─────────────────────
HistoryId   PK                 RuleId      PK (GUID)      LookupKey   PK
SoftwareId                     RuleName                   FamilyId
RawVendor                      Priority                   FamilyName
RawName                        IsActive                   ProductId
DisplayVersion                 IsBuiltIn                  MatchMethod
Guid                           IsExcludeRule              Confidence
InstallDate                    VendorPattern
RawUser                        NamePattern
RegistryKey                    TargetFamily              FuzzyIndex
FamilyId    FK                 TargetVendor              ─────────────────────
ProductId   FK                 StripPatterns (JSON)      FuzzyIndexId  PK
MatchMethod                    Transformations (JSON)    TokenKey
MatchConfidence                Description               FamilyId
SeenAt                         CreatedAt                 FamilyName
SourceHost                     UpdatedAt                 ProductId
                                                         NormName
                                                         Weight
```

### Key Design Decisions

**`LookupTable`** — An O(1) cache mapping `lower(vendor)::lower(name)` → recognition result. Populated on every successful match and warmed into an in-memory hashtable at startup. This means the second time any item is seen, it costs a single hashtable lookup.

**`Variants`** — Tracks every unique `vendor::name::version` combination seen. Distinct from Products because many raw install names map to a single product. The `NormalizedKey` format is `lower(vendor)::lower(name)::lower(version)`.

**`History`** — Immutable audit log. Every call to `AddInventory` appends a row for every item, regardless of whether it matched. This is the foundation for all change-tracking and audit queries.

**`FuzzyIndex`** — Token-based inverted index. When a new family is created, its normalized name is tokenized (stop-words and short tokens removed) and each token inserted as a row. Fuzzy search retrieves candidates by token overlap, then scores them with Levenshtein + Jaccard.

**`IsKnown` on ProductFamilies** — Distinguishes rule-created families (high confidence, stable) from auto-learned families (may be noisy, worth periodic review).

---

## 10. Writing Custom Rules

Rules are the primary tool for improving recognition quality. Each rule is evaluated in priority order; the first matching rule wins.

### Rule Properties

| Property | Type | Description |
|---|---|---|
| `RuleName` | string | Human-readable name for the rule |
| `Priority` | int | Lower number runs first. Built-in rules use 10–90. Custom rules should use 50–90. |
| `VendorPattern` | string | Regex matched against the raw vendor string. Empty = match all vendors. |
| `NamePattern` | string | Regex matched against the raw product name. Empty = match all names. |
| `TargetFamily` | string | The canonical family name to assign matching items to |
| `TargetVendor` | string | Override the vendor stored with the family |
| `StripPatterns` | string[] | Regex patterns removed from the product name before indexing |
| `Transformations` | hashtable[] | Field-level regex replacements: `@{Field='NormalizedName'; Pattern='...'; Replacement='...'}` |
| `IsExcludeRule` | bool | If true, matching items are marked as noise and skipped |
| `Description` | string | Optional documentation string |

### Priority Guidelines

| Range | Use |
|---|---|
| 1–9 | Reserved (do not use) |
| 10–19 | Noise/exclusion filters — run before anything else |
| 20–49 | Built-in vendor rules |
| 50–79 | Custom organization-specific rules |
| 80–99 | Catch-all / fallback rules |

### Examples

**Group a vendor's products under one family:**

```powershell
Add-SRERule -Catalog $c -Hashtable @{
    RuleName      = 'ACME CRM Suite'
    Priority      = 55
    VendorPattern = 'ACME (Corporation|Corp\.?|Inc\.?)'
    NamePattern   = '^ACME CRM'
    TargetFamily  = 'ACME CRM'
    TargetVendor  = 'ACME'
    StripPatterns = @(
        '\s+v?\d+[\.\d]*\s*$'    # strip trailing version numbers
        '\s*\(.*?\)\s*$'         # strip parenthetical notes
    )
    Description   = 'ACME CRM and all versioned variants'
}
```

**Exclude developer/internal components:**

```powershell
Add-SRERule -Catalog $c -Hashtable @{
    RuleName      = 'Exclude ACME Internal Packages'
    Priority      = 10
    VendorPattern = 'ACME'
    NamePattern   = '^(acme_internal|acme_dev|acme_debug)'
    IsExcludeRule = $true
    Description   = 'Internal developer packages not relevant to asset inventory'
}
```

**Fix a systematic fuzzy mismatch (from `Get-SRELowConfidence` findings):**

```powershell
# Get-SRELowConfidence revealed "SAP Business Client" being matched to "SAP Business Explorer"
Add-SRERule -Catalog $c -Hashtable @{
    RuleName      = 'SAP Business Client'
    Priority      = 50
    VendorPattern = 'SAP'
    NamePattern   = 'SAP Business Client'
    TargetFamily  = 'SAP Business Client'
    TargetVendor  = 'SAP'
    StripPatterns = @('\s+\d+[\.\d]*\s*$')
    Description   = 'Disambiguate from SAP Business Explorer'
}
```

**Consolidate a product with many name variants:**

```powershell
Add-SRERule -Catalog $c -Hashtable @{
    RuleName      = 'Zoom Unified Client'
    Priority      = 60
    VendorPattern = 'Zoom (Video Communications|Communications|Inc\.?)?'
    NamePattern   = '^Zoom\b'
    TargetFamily  = 'Zoom'
    TargetVendor  = 'Zoom Video Communications'
    StripPatterns = @(
        '\s+\(\d+[\.\d]*\)\s*$'  # "Zoom (5.17.1.26580)"
        '\s+\d+[\.\d]*\s*$'      # "Zoom 5.17.1"
        '\bOutlook\s+Plugin\b'   # separate plugin entries → same family
        '\bMeetings?\b'
    )
    Description   = 'All Zoom client variants and plugins'
}
```

### Built-in Rules

The module ships with 28 rules covering:

| Priority | Vendor | Scope |
|---|---|---|
| 10 | Microsoft | Exclude VS internal packages (`vs_*`) |
| 10 | Microsoft | Exclude KB hotfixes |
| 10 | Microsoft | Exclude .NET targeting packs |
| 10 | Microsoft | Exclude Windows SDK components |
| 20 | Citrix | Workspace App and legacy Receiver |
| 21 | Citrix | Workspace sub-components |
| 30 | Cisco | AnyConnect / Secure Client modules |
| 40 | Microsoft | .NET Runtime variants |
| 40 | Microsoft | Visual C++ Redistributable variants |
| 50 | Adobe | Reader and Acrobat |
| 60 | Microsoft | Edge browser variants |
| 70+ | Various | Additional vendor-specific rules |

---

## 11. Operational Workflows

### Daily Audit Workflow

```powershell
$c = New-SoftwareCatalog -ConnectionString $connStr

# 1. What did the engine fail to classify?
$unrecog = Get-SREUnrecognized -Catalog $c -Top 200
Write-Host "Unrecognized items: $($unrecog.Count)"
$unrecog | Group-Object RawVendor | Sort-Object Count -Descending | Select-Object -First 10 Name, Count

# 2. Review shaky matches
$lowConf = Get-SRELowConfidence -Catalog $c -Threshold 70
Write-Host "Low-confidence matches: $($lowConf.Count)"
$lowConf | Format-Table RawName, FamilyName, MatchConfidence

# 3. Write new rules for any clear patterns found in step 1
Add-SRERule -Catalog $c -Hashtable @{
    RuleName = '...'
    ...
}

# 4. Re-test
Invoke-SRERecognize -Catalog $c -Vendor 'Previously Unknown Vendor' -Name 'Previously Unknown App'
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

# Total hosts
$hosts = Get-SREHostInventory -Catalog $c -ListHosts
Write-Host "Total hosts in estate: $($hosts.Count)"

# Top deployed software
Write-Host "`n=== Top 15 Software by Host Count ==="
Get-SRETopSoftware -Catalog $c -Top 15 | Format-Table FamilyName, HostCount, TotalInstalls

# Version sprawl for key products
foreach ($product in @('Citrix Workspace App', 'Cisco Secure Client', 'Microsoft Edge')) {
    Write-Host "`n=== Version Sprawl: $product ==="
    Get-SREVersionSprawl -Catalog $c -FamilyName $product |
        Format-Table DisplayVersion, HostCount
}
```

### Stale Software Review

```powershell
$c = New-SoftwareCatalog -ConnectionString $connStr

$stale = Get-SREStaleSoftware -Catalog $c -Days 60
Write-Host "Products not seen in 60+ days: $($stale.Count)"

$stale |
    Sort-Object DaysSinceLastSeen -Descending |
    Select-Object FamilyName, ProductName, InstallCount, LastSeen, DaysSinceLastSeen |
    Format-Table -AutoSize
```

### Host Compliance Check

```powershell
$c = New-SoftwareCatalog -ConnectionString $connStr

# Is a required product installed on all hosts?
$totalHosts  = (Get-SREHostInventory -Catalog $c -ListHosts).Count
$coveredHosts = (Get-SREHostCount -Catalog $c -FamilyName 'Cisco Secure Client').HostCount
$missing      = $totalHosts - $coveredHosts

Write-Host "Cisco Secure Client: $coveredHosts / $totalHosts hosts ($missing missing)"

# Which hosts are missing it?
$allHosts       = (Get-SREHostInventory -Catalog $c -ListHosts).SourceHost
$installedHosts = (Get-SREHostInventory -Catalog $c -HostName '' |
    Where-Object { $_.FamilyName -eq 'Cisco Secure Client' }).SourceHost |
    Select-Object -Unique

$missingHosts = $allHosts | Where-Object { $_ -notin $installedHosts }
$missingHosts | Sort-Object
```

---

## 12. Performance Notes

### Lookup Cache

On startup, `SoftwareCatalog` loads the entire `LookupTable` into an in-memory hashtable (`_lookupCache`). Every previously-seen `vendor::name` pair resolves in O(1) without a database query. For a catalog with 3,000+ entries and 344,000+ history records, typical startup takes under 5 seconds.

### FuzzyIndex

Fuzzy matching uses a token-based inverted index. Only items that share at least one token with the query are scored, dramatically reducing the candidate set. Token extraction filters out stop words and tokens under 3 characters.

### Bulk Ingestion

`Add-SREInventory` processes items sequentially. For very large datasets (100,000+ items), consider splitting the JSON into chunks and calling `Add-SREInventory` in a loop. Each item that hits the lookup cache costs ~1ms; unrecognized items requiring fuzzy search cost ~10–50ms depending on the FuzzyIndex size.

### Query Performance

All query functions use indexed columns:

| Query | Index used |
|---|---|
| `GetFamilies(name, vendor)` | `FamilyName` (table scan on filtered set) |
| `GetHostInventory(host)` | None on SourceHost — add `idx_history_host` if querying frequently |
| `GetNewSoftware(days)` | `idx_history_seen` on `SeenAt` |
| `GetVersionSprawl(familyId)` | `idx_history_family` on `FamilyId` |
| `GetUnrecognized()` | `idx_history_seen` + MatchMethod filter |

For estates with millions of History rows, adding a composite index on `(MatchMethod, SeenAt)` will improve audit query performance:

```sql
ALTER TABLE History ADD INDEX idx_history_method_seen (MatchMethod, SeenAt);
```

---

## 13. Troubleshooting

### `No MySQL connection string found`

You haven't supplied a connection string. Use one of the three configuration methods in [Section 4](#4-configuration).

### `Invoke-SqlQuery: Query returned no resultset`

This warning from SimplySql appears when a query returns zero rows. It is suppressed on internal calls within the module. If you see it from your own code, wrap the call in `@(...)` to force an empty array return.

### Rules aren't matching

1. Test the regex independently:
   ```powershell
   'Citrix Workspace 2409' -match 'Citrix (Workspace|Receiver)'  # should be True
   ```
2. Check the rule priority — a higher-priority rule may be matching first. Use `$c.GetStats()` and check rule count.
3. Verify the rule is active in the database:
   ```powershell
   Get-SREFamily -Catalog $c  # indirectly confirms DB connectivity
   ```

### Fuzzy matches seem wrong

Review `Get-SRELowConfidence` output. If a specific raw name is consistently being mismatched, add an explicit normalization rule for it with a priority lower than 50. Explicit rules always beat fuzzy matches.

### Self-learning created too many families

Auto-learned families (`IsKnown = 0`) can proliferate if the ingested data is very noisy. Filter them:

```powershell
Get-SREFamily -Catalog $c | Where-Object { $_.IsKnown -eq 0 } | Sort-Object CreatedAt -Descending
```

For families that should be merged, add a normalization rule that sets `TargetFamily` to the correct canonical name for both raw names. The next ingestion will re-assign items to the correct family.

### Module won't import

Ensure SimplySql is installed and accessible:

```powershell
Get-Module -ListAvailable SimplySql
# If missing:
Install-Module SimplySql -Scope CurrentUser -Force
```

Check the PowerShell version:

```powershell
$PSVersionTable.PSVersion  # must be 5.1 or higher
```
