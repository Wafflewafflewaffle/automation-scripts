<#
REMEDIATION - Firefox Update (Windows)

Purpose:
  Updates Mozilla Firefox to latest stable.

Contract:
  Always performs remediation when invoked.
  Eval script determines whether remediation runs.

Output:
  RESULT | UPDATED
  RESULT | ERROR

Exit Code:
  Always 0 (Ninja-safe)

Logging:
  C:\MME\AutoLogs\Firefox_Remediation.log

Ninja Fields Updated:
  lastRemediationDate (overwrite)
  remediationSummary  (append)
#>

$ErrorActionPreference = "Stop"

# -------- CONFIG --------
$LogDir  = "C:\MME\AutoLogs"
$LogFile = Join-Path $LogDir "Firefox_Remediation.log"
$Installer = "$env:TEMP\Firefox_Setup.exe"

# -------- HELPERS --------
function Ensure-Dir($p) {
    if (!(Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}

function Write-Log {
    param([string]$Message)
    Ensure-Dir $LogDir
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$ts [FirefoxFix] $Message"
}

function Update-Ledger {
    try {
        $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # lastRemediationDate overwrite
        Ninja-Property-Set lastRemediationDate $now

        # remediationSummary append
        $entry = "$now - Firefox updated"
        Ninja-Property-Append remediationSummary $entry
    } catch {
        Write-Log "Ledger update failed: $_"
    }
}

# -------- MAIN --------
Write-Log "Starting Firefox remediation..."

try {
    Write-Log "Stopping Firefox processes..."
    Get-Process firefox -ErrorAction SilentlyContinue | Stop-Process -Force

    Write-Log "Downloading latest Firefox installer..."
    Invoke-WebRequest `
        -Uri "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US" `
        -OutFile $Installer

    Write-Log "Running silent installer..."
    Start-Process -FilePath $Installer -ArgumentList "-ms" -Wait

    Write-Log "Firefox installation completed."

    Update-Ledger

    Write-Output "RESULT | UPDATED"
    exit 0
}
catch {
    Write-Log "Remediation failed: $_"
    Write-Output "RESULT | ERROR"
    exit 0
}
