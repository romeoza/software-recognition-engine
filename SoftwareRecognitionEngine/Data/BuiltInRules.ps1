# Returns an array of built-in NormalizationRule objects.
# Called once during SoftwareCatalog initialisation to seed the rule engine and database.
function Get-SREBuiltInRules {
    [OutputType([NormalizationRule[]])]
    param()

    $rules = @(

        # ── Priority 10: Noise / exclusion filters ──────────────────────────────

        [NormalizationRule]@{
            RuleName      = 'Exclude VS Internal Packages'
            Priority      = 10
            IsBuiltIn     = $true
            IsExcludeRule = $true
            VendorPattern = 'Microsoft'
            NamePattern   = '^vs_'
            Description   = 'Visual Studio internal sub-component packages (vs_*) — not user-visible software'
        }

        [NormalizationRule]@{
            RuleName      = 'Exclude Microsoft KB Hotfixes'
            Priority      = 10
            IsBuiltIn     = $true
            IsExcludeRule = $true
            VendorPattern = 'Microsoft'
            NamePattern   = '\(KB\d{4,}\)'
            Description   = 'Windows security patch and hotfix entries'
        }

        [NormalizationRule]@{
            RuleName      = 'Exclude .NET Targeting Packs'
            Priority      = 10
            IsBuiltIn     = $true
            IsExcludeRule = $true
            VendorPattern = 'Microsoft'
            NamePattern   = '(Targeting Pack|Multi-Targeting Pack|Reference Assemblies)'
            Description   = 'Developer-only targeting packs; not end-user software'
        }

        [NormalizationRule]@{
            RuleName      = 'Exclude Windows SDK Components'
            Priority      = 10
            IsBuiltIn     = $true
            IsExcludeRule = $true
            VendorPattern = 'Microsoft'
            NamePattern   = 'Windows SDK|WinRT Intellisense|Universal CRT'
            Description   = 'Windows SDK and developer runtime components'
        }

        # ── Priority 20: Citrix ─────────────────────────────────────────────────

        [NormalizationRule]@{
            RuleName      = 'Citrix Workspace and Receiver'
            Priority      = 20
            IsBuiltIn     = $true
            VendorPattern = 'Citrix'
            NamePattern   = 'Citrix (Workspace|Receiver)'
            TargetFamily  = 'Citrix Workspace App'
            TargetVendor  = 'Citrix'
            StripPatterns = @(
                '\s+\d{4}(\.\d+)*\s*$'   # trailing year-based versions: "2409", "2402.10"
                '\s+\d+\.\d+[\.\d]*\s*$' # trailing semver: "24.8.0.138"
                '\s*\(.*?\)'             # parenthetical notes
            )
            Description   = 'Citrix Workspace App and legacy Receiver — all versions'
        }

        [NormalizationRule]@{
            RuleName      = 'Citrix Workspace Sub-Components'
            Priority      = 21
            IsBuiltIn     = $true
            VendorPattern = 'Citrix'
            NamePattern   = 'Citrix (Authentication Manager|Desktop Lock|PackageInstaller|Web Helper|HDX|Single Sign-On|Endpoint Analysis)'
            TargetFamily  = 'Citrix Workspace App'
            TargetVendor  = 'Citrix'
            StripPatterns = @('\s+\d+[\.\d]*\s*$')
            Description   = 'Citrix Workspace internal components grouped under the same family'
        }

        # ── Priority 30: Cisco ──────────────────────────────────────────────────

        [NormalizationRule]@{
            RuleName      = 'Cisco AnyConnect / Secure Client'
            Priority      = 30
            IsBuiltIn     = $true
            VendorPattern = 'Cisco'
            NamePattern   = '(AnyConnect|Secure Client).*(VPN|Mobility|ISE|NAM|DART|Umbrella|NVM|Posture|Start Before Login|Web Security|SBL)'
            TargetFamily  = 'Cisco Secure Client'
            TargetVendor  = 'Cisco'
            StripPatterns = @('\s+\-\s+.*$', '\s+\d+[\.\d]*\s*$')
            Description   = 'All Cisco AnyConnect and Secure Client module variants'
        }

        [NormalizationRule]@{
            RuleName      = 'Cisco Secure Client Core'
            Priority      = 31
            IsBuiltIn     = $true
            VendorPattern = 'Cisco'
            NamePattern   = '^Cisco (AnyConnect|Secure Client)\s'
            TargetFamily  = 'Cisco Secure Client'
            TargetVendor  = 'Cisco'
            StripPatterns = @('\s+\d+[\.\d]*\s*$', '\s*\(.*?\)')
            Description   = 'Cisco Secure Client core package'
        }

        [NormalizationRule]@{
            RuleName      = 'Cisco Webex'
            Priority      = 32
            IsBuiltIn     = $true
            VendorPattern = 'Cisco|Webex'
            NamePattern   = 'Webex|WebEx'
            TargetFamily  = 'Cisco Webex'
            TargetVendor  = 'Cisco'
            StripPatterns = @('\s+\d+[\.\d]*\s*$')
            Description   = 'Cisco Webex Meetings and Teams — all spelling variants'
        }

        # ── Priority 40: Microsoft runtimes ────────────────────────────────────

        [NormalizationRule]@{
            RuleName      = 'Microsoft Visual C++ Redistributable'
            Priority      = 40
            IsBuiltIn     = $true
            VendorPattern = 'Microsoft'
            NamePattern   = 'Visual C\+\+'
            TargetFamily  = 'Microsoft Visual C++ Redistributable'
            TargetVendor  = 'Microsoft'
            StripPatterns = @(
                '\s+20\d{2}(-20\d{2})?\s*'  # year ranges: "2015-2022", "2019"
                '\s*Redistributable'
                '\s*\(x86\)|\s*\(x64\)'
                '\s*-\s*\d+[\.\d]+'         # version suffix after dash
                '\s+\d+[\.\d]*\s*$'
            )
            Description   = 'All Visual C++ Redistributable packages (any year, any arch)'
        }

        [NormalizationRule]@{
            RuleName      = 'Microsoft .NET Runtime'
            Priority      = 41
            IsBuiltIn     = $true
            VendorPattern = 'Microsoft'
            NamePattern   = '\.NET (Runtime|Host|Desktop Runtime|ASP\.NET Core Runtime|Windows Desktop Runtime)'
            TargetFamily  = 'Microsoft .NET Runtime'
            TargetVendor  = 'Microsoft'
            StripPatterns = @('\s+\d+[\.\d]*\s*$', '\s*\(.*?\)')
            Description   = '.NET 5+ runtime packages (all flavours)'
        }

        [NormalizationRule]@{
            RuleName      = 'Microsoft .NET Framework'
            Priority      = 42
            IsBuiltIn     = $true
            VendorPattern = 'Microsoft'
            NamePattern   = '\.NET Framework\s+\d'
            TargetFamily  = 'Microsoft .NET Framework'
            TargetVendor  = 'Microsoft'
            StripPatterns = @('\s+\d+\.\d+\.\d+[\.\d]*\s*$')
            Description   = '.NET Framework (keeps major version in normalized name)'
        }

        # ── Priority 50: Microsoft productivity ────────────────────────────────

        [NormalizationRule]@{
            RuleName      = 'Microsoft Edge'
            Priority      = 50
            IsBuiltIn     = $true
            VendorPattern = 'Microsoft'
            NamePattern   = '^Microsoft Edge'
            TargetFamily  = 'Microsoft Edge'
            TargetVendor  = 'Microsoft'
            StripPatterns = @('\s+WebView2 Runtime', '\s+\d+[\.\d]*\s*$')
            Description   = 'Microsoft Edge browser and WebView2 runtime'
        }

        [NormalizationRule]@{
            RuleName      = 'Microsoft Teams'
            Priority      = 51
            IsBuiltIn     = $true
            VendorPattern = 'Microsoft'
            NamePattern   = 'Microsoft Teams'
            TargetFamily  = 'Microsoft Teams'
            TargetVendor  = 'Microsoft'
            StripPatterns = @('\s+(classic|VDI Plugin|Meeting Add-in.*)\s*$', '\s+\d+[\.\d]*\s*$')
            Description   = 'Microsoft Teams (classic, new, and VDI plugin variants)'
        }

        [NormalizationRule]@{
            RuleName      = 'SQL Server Management Studio'
            Priority      = 52
            IsBuiltIn     = $true
            VendorPattern = 'Microsoft'
            NamePattern   = 'SQL Server Management Studio'
            TargetFamily  = 'SQL Server Management Studio'
            TargetVendor  = 'Microsoft'
            StripPatterns = @('\s+\d+[\.\d]*\s*$', '\s+\d{4}\s*$')
            Description   = 'SSMS all versions'
        }

        # ── Priority 60: Adobe ──────────────────────────────────────────────────

        [NormalizationRule]@{
            RuleName      = 'Adobe Acrobat Reader'
            Priority      = 60
            IsBuiltIn     = $true
            VendorPattern = 'Adobe'
            NamePattern   = 'Acrobat Reader'
            TargetFamily  = 'Adobe Acrobat Reader'
            TargetVendor  = 'Adobe'
            StripPatterns = @('\s+(DC|XI|X|2017|2020)\s*$', '\s+\d+[\.\d]*\s*$', '\s*\(.*?\)')
            Description   = 'Adobe Acrobat Reader DC, XI, and prior versions'
        }

        [NormalizationRule]@{
            RuleName      = 'Adobe Acrobat (full)'
            Priority      = 61
            IsBuiltIn     = $true
            VendorPattern = 'Adobe'
            NamePattern   = 'Adobe Acrobat\b'
            TargetFamily  = 'Adobe Acrobat'
            TargetVendor  = 'Adobe'
            StripPatterns = @('\s+(DC|Standard|Pro)\s*$', '\s+\d+[\.\d]*\s*$')
            Description   = 'Adobe Acrobat full product (Standard and Pro)'
        }

        [NormalizationRule]@{
            RuleName      = 'Adobe Flash Legacy'
            Priority      = 62
            IsBuiltIn     = $true
            VendorPattern = 'Adobe'
            NamePattern   = 'Flash Player|Shockwave'
            TargetFamily  = 'Adobe Flash (Legacy)'
            TargetVendor  = 'Adobe'
            StripPatterns = @('\s+\d+[\.\d]*\s*$', '\s*NPAPI|\s*PPAPI|\s*ActiveX')
            Description   = 'Adobe Flash and Shockwave (EOL/legacy)'
        }

        # ── Priority 70: Java / SAP ─────────────────────────────────────────────

        [NormalizationRule]@{
            RuleName      = 'Java Runtime Environment'
            Priority      = 70
            IsBuiltIn     = $true
            VendorPattern = 'Oracle|Sun Micro'
            NamePattern   = '^Java\b'
            TargetFamily  = 'Java Runtime Environment'
            TargetVendor  = 'Oracle'
            StripPatterns = @(
                '\s+(SE\s+)?(Runtime Environment|Development Kit|JDK|JRE)\s*'
                '\s+\d+\s+Update\s+\d+$'   # "Java 8 Update 481"
                '\s+\d+[\.\d]*\s*$'
                '\s*\(.*?\)'
            )
            Description   = 'Java JRE and JDK — all versions and vendors'
        }

        [NormalizationRule]@{
            RuleName      = 'SAP GUI for Windows'
            Priority      = 71
            IsBuiltIn     = $true
            VendorPattern = 'SAP'
            NamePattern   = 'SAP GUI for Windows'
            TargetFamily  = 'SAP GUI'
            TargetVendor  = 'SAP'
            StripPatterns = @('\s+\d+[\.\d]*\s*$', '\s+Patch\s+\d+.*$')
            Description   = 'SAP GUI for Windows — all patch levels'
        }

        # ── Priority 80: Common utilities ───────────────────────────────────────

        [NormalizationRule]@{
            RuleName      = 'Google Chrome'
            Priority      = 80
            IsBuiltIn     = $true
            VendorPattern = 'Google'
            NamePattern   = 'Google Chrome'
            TargetFamily  = 'Google Chrome'
            TargetVendor  = 'Google'
            StripPatterns = @('\s+\d+[\.\d]*\s*$')
            Description   = 'Google Chrome browser'
        }

        [NormalizationRule]@{
            RuleName      = '7-Zip'
            Priority      = 81
            IsBuiltIn     = $true
            VendorPattern = ''
            NamePattern   = '^7-Zip\b'
            TargetFamily  = '7-Zip'
            TargetVendor  = 'Igor Pavlov'
            StripPatterns = @('\s+\d+[\.\d]*\s*$', '\s*\(x64\)|\s*\(x86\)')
            Description   = '7-Zip file archiver — all versions and architectures'
        }

        [NormalizationRule]@{
            RuleName      = 'Mozilla Firefox'
            Priority      = 82
            IsBuiltIn     = $true
            VendorPattern = 'Mozilla'
            NamePattern   = 'Firefox'
            TargetFamily  = 'Mozilla Firefox'
            TargetVendor  = 'Mozilla'
            StripPatterns = @('\s+\d+[\.\d]*\s*$', '\s*(ESR|MSI|x64|x86)\s*$')
            Description   = 'Mozilla Firefox — all release channels and architectures'
        }

        # ── Priority 90: Vendor name normalization (no family assignment) ───────
        # These run after family rules; they clean up vendors that slipped through.

        [NormalizationRule]@{
            RuleName      = 'Normalize Microsoft Vendor'
            Priority      = 90
            IsBuiltIn     = $true
            VendorPattern = 'Microsoft (Corp|Corporation|Windows|Office)'
            NamePattern   = ''
            TargetVendor  = 'Microsoft'
            Description   = 'Normalizes Microsoft Corporation/Corp. to Microsoft'
        }

        [NormalizationRule]@{
            RuleName      = 'Normalize Google Vendor'
            Priority      = 91
            IsBuiltIn     = $true
            VendorPattern = 'Google (LLC|Inc\.?)'
            NamePattern   = ''
            TargetVendor  = 'Google'
            Description   = 'Normalizes Google LLC / Google Inc. to Google'
        }

        [NormalizationRule]@{
            RuleName      = 'Normalize Oracle Vendor'
            Priority      = 92
            IsBuiltIn     = $true
            VendorPattern = 'Oracle (Corporation|Corp\.?|America)'
            NamePattern   = ''
            TargetVendor  = 'Oracle'
            Description   = 'Normalizes Oracle Corporation to Oracle'
        }

        [NormalizationRule]@{
            RuleName      = 'Normalize Cisco Vendor'
            Priority      = 93
            IsBuiltIn     = $true
            VendorPattern = 'Cisco Systems,?\s*(Inc\.?)?'
            NamePattern   = ''
            TargetVendor  = 'Cisco'
            Description   = 'Normalizes Cisco Systems, Inc. to Cisco'
        }

        [NormalizationRule]@{
            RuleName      = 'Normalize Adobe Vendor'
            Priority      = 94
            IsBuiltIn     = $true
            VendorPattern = 'Adobe (Systems|Inc\.?)'
            NamePattern   = ''
            TargetVendor  = 'Adobe'
            Description   = 'Normalizes Adobe Systems / Adobe Inc. to Adobe'
        }

    ) # end $rules array

    return $rules
}
