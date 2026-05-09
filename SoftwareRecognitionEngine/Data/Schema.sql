-- Software Recognition Engine — MySQL schema
-- Run once against an empty database. All tables use IF NOT EXISTS so the script is idempotent.

CREATE TABLE IF NOT EXISTS ProductFamilies (
    FamilyId         INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    FamilyName       VARCHAR(300)     NOT NULL,
    NormalizedName   VARCHAR(300)     NOT NULL,
    Vendor           VARCHAR(200)     NOT NULL DEFAULT '',
    NormalizedVendor VARCHAR(200)     NOT NULL DEFAULT '',
    -- IsKnown=1 means this family was created by a normalization rule (high confidence)
    -- IsKnown=0 means it was auto-learned from inventory data
    IsKnown          TINYINT(1)       NOT NULL DEFAULT 0,
    ConfidenceFloor  TINYINT UNSIGNED NOT NULL DEFAULT 50,
    CreatedAt        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (FamilyId),
    UNIQUE KEY uq_family (NormalizedName, NormalizedVendor)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS Products (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS Variants (
    VariantId      INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    ProductId      INT UNSIGNED     NOT NULL,
    RawName        VARCHAR(500)     NOT NULL,
    RawVendor      VARCHAR(200)     NOT NULL DEFAULT '',
    NormalizedKey  VARCHAR(500)     NOT NULL,   -- dedup key: lower(vendor)::lower(name)::version
    FirstSeen      DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    LastSeen       DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    SeenCount      INT UNSIGNED     NOT NULL DEFAULT 1,
    PRIMARY KEY (VariantId),
    UNIQUE KEY uq_variant_key (NormalizedKey),
    KEY idx_variant_product (ProductId),
    CONSTRAINT fk_variant_product FOREIGN KEY (ProductId)
        REFERENCES Products (ProductId) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS LookupTable (
    LookupKey   VARCHAR(500)     NOT NULL,   -- lower(vendor)::lower(name)
    FamilyId    INT UNSIGNED     NOT NULL,
    FamilyName  VARCHAR(300)     NOT NULL DEFAULT '',
    ProductId   INT UNSIGNED,
    MatchMethod VARCHAR(20)      NOT NULL DEFAULT '',
    Confidence  TINYINT UNSIGNED NOT NULL DEFAULT 100,
    PRIMARY KEY (LookupKey),
    KEY idx_lookup_family (FamilyId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS NormalizationRules (
    RuleId          VARCHAR(36)      NOT NULL,   -- GUID
    RuleName        VARCHAR(200)     NOT NULL,
    Priority        SMALLINT         NOT NULL DEFAULT 100,
    IsActive        TINYINT(1)       NOT NULL DEFAULT 1,
    IsBuiltIn       TINYINT(1)       NOT NULL DEFAULT 0,
    IsExcludeRule   TINYINT(1)       NOT NULL DEFAULT 0,
    VendorPattern   VARCHAR(500)     NOT NULL DEFAULT '',
    NamePattern     VARCHAR(500)     NOT NULL DEFAULT '',
    TargetFamily    VARCHAR(300)     NOT NULL DEFAULT '',
    TargetVendor    VARCHAR(200)     NOT NULL DEFAULT '',
    -- JSON arrays: StripPatterns=[...], Transformations=[{Field,Pattern,Replacement}]
    StripPatterns   TEXT             NOT NULL,
    Transformations TEXT             NOT NULL,
    Description     VARCHAR(500)     NOT NULL DEFAULT '',
    CreatedAt       DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt       DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (RuleId),
    KEY idx_rule_priority (Priority),
    KEY idx_rule_active (IsActive)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS History (
    HistoryId       BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    SoftwareId      BIGINT UNSIGNED,
    RawVendor       VARCHAR(200)     NOT NULL DEFAULT '',
    RawName         VARCHAR(500)     NOT NULL,
    DisplayVersion  VARCHAR(100)     NOT NULL DEFAULT '',
    Guid            CHAR(36)         NOT NULL DEFAULT '',
    InstallDate     DATE,
    RawUser         VARCHAR(100)     NOT NULL DEFAULT '',
    RegistryKey     VARCHAR(1000)    NOT NULL DEFAULT '',
    -- Resolution
    FamilyId        INT UNSIGNED,
    ProductId       INT UNSIGNED,
    MatchMethod     VARCHAR(20)      NOT NULL DEFAULT '',
    MatchConfidence TINYINT UNSIGNED NOT NULL DEFAULT 0,
    -- Audit
    SeenAt          DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    SourceHost      VARCHAR(200)     NOT NULL DEFAULT '',
    PRIMARY KEY (HistoryId),
    KEY idx_history_family  (FamilyId),
    KEY idx_history_rawname (RawName(100)),
    KEY idx_history_seen    (SeenAt),
    KEY idx_history_softwareid (SoftwareId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS FuzzyIndex (
    FuzzyIndexId INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    TokenKey     VARCHAR(100)  NOT NULL,
    FamilyId     INT UNSIGNED  NOT NULL,
    FamilyName   VARCHAR(300)  NOT NULL DEFAULT '',
    ProductId    INT UNSIGNED  NOT NULL,
    NormName     VARCHAR(400)  NOT NULL DEFAULT '',   -- full normalized name for Levenshtein
    Weight       FLOAT         NOT NULL DEFAULT 1.0,
    PRIMARY KEY (FuzzyIndexId),
    KEY idx_fuzzy_token  (TokenKey),
    KEY idx_fuzzy_family (FamilyId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
