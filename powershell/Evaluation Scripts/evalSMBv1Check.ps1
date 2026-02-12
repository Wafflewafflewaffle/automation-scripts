# EVALUATION - SMBv1 Enabled + Usage Check
#
# Logic:
#   NO_ACTION -> SMBv1 already disabled
#   NO_ACTION -> SMBv1 enabled but usage detected
#   TRIGGER   -> SMBv1 enabled and no usage detected
#
# Output (final line):
#   TRIGGER   | ...
#   NO_ACTION | ...
#   ERROR     | ...
#
# Exit Code:
#   Always 0
#
# Logging:
#   C:\MME\AutoLogs\SMBv1_Eval.log

$ErrorActionPreference = "SilentlyContinue"

$LookbackHours = 168
$LogFile = "C:\MME\AutoLogs\SMBv1_Eval.log"

function Ensure-Dir($filePath) {
    $dir = Split-Path -Parent $filePath
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

function Log($msg) {
    Ensure-Dir $LogFile
    Add-Content -Path $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
}

function Emit($line) { Write-Output $line; exit 0 }

Log "=== SMBv1 eval start ==="

# ---- SMBv1 enabled state (best effort) ----
$smb1Enabled = $false
$stateKnown  = $false

try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol
    $stateKnown = $true
    if ($feature.State -eq "Enabled") { $smb1Enabled = $true }
} catch {
    Log "Optional feature check failed: $($_.Exception.Message)"
}

try {
    $cfg = Get-SmbServerConfiguration
    $stateKnown = $true
    if ($cfg.EnableSMB1Protocol) { $smb1Enabled = $true }
} catch {
    Log "Server config check failed: $($_.Exception.Message)"
}

if (-not $stateKnown) {
    Log "ERROR | Unable to determine SMBv1 state"
    Emit "ERROR | Unable to determine SMBv1 state"
}

Log "SMBv1 enabled: $smb1Enabled"

if (-not $smb1Enabled) {
    Log "NO_ACTION | SMBv1 already disabled"
    Emit "NO_ACTION | SMBv1 already disabled"
}

# ---- Usage checks ----
$activeCount = 0
try {
    $activeCount = @(Get-SmbConnection | Where-Object { $_.Dialect -eq "NT LM 0.12" }).Count
} catch {
    Log "Connection query failed: $($_.Exception.Message)"
}

Log "Active SMBv1 connections: $activeCount"

$auditCount = 0
try {
    $startTime  = (Get-Date).AddHours(-$LookbackHours)
    $auditCount = @(Get-WinEvent -FilterHashtable @{ LogName="Microsoft-Windows-SMBServer/Audit"; StartTime=$startTime }).Count
} catch {
    Log "Audit log unavailable"
}

Log "Audit events (last $LookbackHours hours): $auditCount"

if (($activeCount -gt 0) -or ($auditCount -gt 0)) {
    Log "NO_ACTION | SMBv1 usage detected"
    Emit "NO_ACTION | SMBv1 usage detected"
}

Log "TRIGGER | SMBv1 enabled with no recent usage"
Emit "TRIGGER | SMBv1 enabled with no recent usage"
