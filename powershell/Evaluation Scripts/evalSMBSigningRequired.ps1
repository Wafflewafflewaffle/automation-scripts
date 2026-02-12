# EVALUATION - SMB Signing Requirement
# Log: C:\MME\AutoLogs\SMBSigning_Check.log
# Always exit 0
# Output (final line):
#   TRIGGER   | SMB signing not required
#   NO_ACTION | SMB signing required
#   ERROR     | evaluation failure

$ErrorActionPreference = "SilentlyContinue"
$LogPath = "C:\MME\AutoLogs\SMBSigning_Check.log"

function Ensure-Dir($filePath) {
    $dir = Split-Path -Parent $filePath
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

function Log($msg) {
    Ensure-Dir $LogPath
    Add-Content -Path $LogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
}

function Emit($line) { Write-Output $line; exit 0 }

$wkstPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
$srvrPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"

try {
    $wkst = (Get-ItemProperty $wkstPath -Name RequireSecuritySignature -ErrorAction Stop).RequireSecuritySignature
    $srvr = (Get-ItemProperty $srvrPath -Name RequireSecuritySignature -ErrorAction Stop).RequireSecuritySignature
    Log "Workstation RequireSecuritySignature=$wkst ; Server RequireSecuritySignature=$srvr"
} catch {
    Log "ERROR reading SMB signing values: $($_.Exception.Message)"
    Emit "ERROR | Unable to read SMB signing configuration"
}

if (($wkst -ne 1) -or ($srvr -ne 1)) {
    Log "TRIGGER: SMB signing not required"
    Emit "TRIGGER | SMB signing not required"
}

Log "NO_ACTION: SMB signing required"
Emit "NO_ACTION | SMB signing required"
