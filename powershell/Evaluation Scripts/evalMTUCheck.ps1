# ==========================================
# EVALUATION: MTU Check (Physical Only)
# Triggers if connected PHYSICAL interface MTU < 1500
# Logs: C:\MME\AutoLogs\MTU_Check.log
# Output: TRIGGER | or NO_ACTION |
# Always exit 0
# ==========================================

$ErrorActionPreference = "SilentlyContinue"

$LogDir  = "C:\MME\AutoLogs\"
$LogFile = Join-Path $LogDir "MTU_Check.log"

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$ts | $Message"
}

Write-Log "=== START MTU evaluation ==="

$badIfaces = @()

try {
    # Get physical adapters only
    $physicalAdapters = Get-NetAdapter -Physical |
                         Where-Object { $_.Status -eq "Up" }

    foreach ($adapter in $physicalAdapters) {

        $ipIfaces = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4

        foreach ($iface in $ipIfaces) {
            if ($iface.NlMtu -lt 1500 -and $iface.NlMtu -gt 0) {
                $badIfaces += "$($adapter.Name) (MTU=$($iface.NlMtu))"
            }
        }
    }
}
catch {
    Write-Log "ERROR retrieving interfaces: $($_.Exception.Message)"
}

if ($badIfaces.Count -gt 0) {
    $msg = $badIfaces -join ", "
    Write-Log "TRIGGER: Physical interfaces below MTU 1500: $msg"
    Write-Output "TRIGGER | Physical MTU below 1500 detected: $msg"
}
else {
    Write-Log "NO_ACTION: All connected physical interfaces MTU >= 1500"
    Write-Output "NO_ACTION | Physical MTU normal"
}

Write-Log "=== END MTU evaluation ==="
exit 0
