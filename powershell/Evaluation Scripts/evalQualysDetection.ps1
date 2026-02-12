# QUALYS detection (standardized trigger style for Ninja)
#
# Logic:
#   NO_ACTION -> Qualys installed
#   TRIGGER   -> Qualys not installed
#
# Output:
#   NO_ACTION | ...
#   TRIGGER   | ...
#
# Exit code:
#   Always 0

$QualysPattern = '(?i)qualys'

$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "Registry::HKEY_USERS\*\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "Registry::HKEY_USERS\*\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$qualysHits = @()

foreach ($path in $registryPaths) {
    Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        ForEach-Object {
            $dn = $_.DisplayName
            $dv = $_.DisplayVersion

            if ($dn -match $QualysPattern) {
                $qualysHits += [pscustomobject]@{
                    DisplayName    = $dn
                    DisplayVersion = $dv
                    RegPath        = $path
                }
            }
        }
}

# Qualys present -> healthy
if ($qualysHits.Count -gt 0) {
    $details = ($qualysHits | ForEach-Object {
        "'$($_.DisplayName)' v$($_.DisplayVersion)"
    }) -join "; "

    Write-Output "NO_ACTION | Qualys installed ($details)"
    exit 0
}

# Qualys missing -> trigger install/remediation
Write-Output "TRIGGER | Qualys not installed"
exit 0
