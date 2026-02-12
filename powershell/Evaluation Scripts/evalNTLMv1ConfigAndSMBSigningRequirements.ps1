# ==========================================
# EVALUATION - NTLM/SMB Config Posture (Non-breaking)
# - Checks local policy/registry that commonly maps to:
#     * NTLMv2-only (LmCompatibilityLevel = 5)
#     * SMB signing required (Workstation + Server RequireSecuritySignature = 1)
# - Always exit 0 (Ninja-safe)
# - Logs: C:\MME\AutoLogs\NTLMv1_Config_Posture.log
#
# Output (final line):
#   TRIGGER   | Weak config (details=...)
#   NO_ACTION | Config appears hardened
#   TRIGGER   | UNKNOWN: Could not read required settings reliably (fail-safe)
# ==========================================

$ErrorActionPreference = "SilentlyContinue"

# ---------- CONFIG ----------
$LogPath = "C:\MME\AutoLogs\NTLMv1_Config_Posture.log"

# ---------- HELPERS ----------
function Ensure-Dir($path) {
    $dir = Split-Path -Path $path -Parent
    if (!(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}
function Write-Log($msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogPath -Value "$ts | $msg" -Encoding UTF8
}
function Get-RegDword($path, $name) {
    try {
        return [int]((Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name)
    } catch {
        return $null
    }
}
function IsRequireOn($v) { return ($v -eq 1) }

# ---------- MAIN ----------
Ensure-Dir $LogPath
"==== START NTLM/SMB Config Posture ====" | Out-File -FilePath $LogPath -Encoding UTF8

$unknown = $false
$details = New-Object System.Collections.Generic.List[string]

# NTLM level
$lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$lmLevel = Get-RegDword $lsaPath "LmCompatibilityLevel"

if ($null -eq $lmLevel) {
    Write-Log "LmCompatibilityLevel not set."
    $unknown = $true
    $details.Add("LmCompatibilityLevel=NOT_SET")
} else {
    Write-Log "LmCompatibilityLevel=$lmLevel"
    if ($lmLevel -lt 5) { $details.Add("LmCompatibilityLevel<5 (=$lmLevel)") }
}

# SMB signing
$wkstPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
$srvrPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"

$wkstReq = Get-RegDword $wkstPath "RequireSecuritySignature"
$srvrReq = Get-RegDword $srvrPath "RequireSecuritySignature"

Write-Log "Workstation RequireSecuritySignature=$wkstReq"
Write-Log "Server      RequireSecuritySignature=$srvrReq"

if (-not (IsRequireOn $wkstReq)) { $details.Add("Workstation SMB signing NOT required (Require=$wkstReq)") }
if (-not (IsRequireOn $srvrReq)) { $details.Add("Server SMB signing NOT required (Require=$srvrReq)") }

if ($unknown) {
    Write-Output "TRIGGER | UNKNOWN: Could not fully determine config posture (details=$($details -join '; '))"
    exit 0
}

if ($details.Count -gt 0) {
    Write-Output "TRIGGER | Weak config (details=$($details -join '; '))"
    exit 0
}

Write-Output "NO_ACTION | Config appears hardened"
exit 0
