# Dot-source class files in dependency order (numeric prefix enforces load sequence)
$classFiles = Get-ChildItem "$PSScriptRoot\Classes\*.ps1" | Sort-Object Name
foreach ($f in $classFiles) { . $f.FullName }

# Load data files (BuiltInRules etc.) in the same module scope as the classes.
# Must happen AFTER classes so [NormalizationRule] resolves to the same type identity.
$dataFiles = Get-ChildItem "$PSScriptRoot\Data\*.ps1" -ErrorAction SilentlyContinue
foreach ($f in $dataFiles) { . $f.FullName }

# Load private helpers (not exported)
$privateFiles = Get-ChildItem "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue
foreach ($f in $privateFiles) { . $f.FullName }

# Load public functions and export them
$publicFiles = Get-ChildItem "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($f in $publicFiles) { . $f.FullName }

Export-ModuleMember -Function ($publicFiles.BaseName)
