# AuthPoint detection (standardized trigger style for Ninja)
# Output:
#   TRIGGER   | ...  => run remediation
#   NO_ACTION | ...  => do nothing
# Always exits 0.

$OldPattern = '(?i)AuthPoint\s+Agent\s+for\s+Windows'
$NewPattern = '(?i)\bLogon\s+App\b'

$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "Registry::HKEY_USERS\*\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "Registry::HKEY_USERS\*\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$oldHits = @()
$newHits = @()

foreach ($path in $registryPaths) {
    Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        ForEach-Object {
            $dn = $_.DisplayName
            $dv = $_.DisplayVersion

            if ($dn -match $OldPattern) {
                $oldHits += [pscustomobject]@{
                    DisplayName    = $dn
                    DisplayVersion = $dv
                    RegPath        = $path
                }
            }
            elseif ($dn -match $NewPattern) {
                $newHits += [pscustomobject]@{
                    DisplayName    = $dn
                    DisplayVersion = $dv
                    RegPath        = $path
                }
            }
        }
}

# Prioritize OLD over NEW (if both exist, remediate)
if ($oldHits.Count -gt 0) {
    $details = ($oldHits | ForEach-Object { "'$($_.DisplayName)' v$($_.DisplayVersion)" }) -join "; "
    Write-Output "TRIGGER | OLD AuthPoint detected ($details) -> remediate"
    exit 0
}

# New exists -> no action
if ($newHits.Count -gt 0) {
    $details = ($newHits | ForEach-Object { "'$($_.DisplayName)' v$($_.DisplayVersion)" }) -join "; "
    Write-Output "NO_ACTION | NEW AuthPoint detected ($details)"
    exit 0
}

# Neither found -> choose behavior (kept as remediate, matching your current logic)
Write-Output "TRIGGER | No AuthPoint found (OLD='$OldPattern' NEW='$NewPattern') -> install/remediate"
exit 0
