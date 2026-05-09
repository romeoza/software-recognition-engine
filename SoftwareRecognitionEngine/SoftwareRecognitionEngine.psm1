# Dot-source class files in dependency order (numeric prefix enforces load sequence)
$classFiles = Get-ChildItem "$PSScriptRoot\Classes\*.ps1" | Sort-Object Name
foreach ($f in $classFiles) { . $f.FullName }

# Load private helpers (not exported)
$privateFiles = Get-ChildItem "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue
foreach ($f in $privateFiles) { . $f.FullName }

# Load public functions and export them
$publicFiles = Get-ChildItem "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($f in $publicFiles) { . $f.FullName }

Export-ModuleMember -Function ($publicFiles.BaseName)
