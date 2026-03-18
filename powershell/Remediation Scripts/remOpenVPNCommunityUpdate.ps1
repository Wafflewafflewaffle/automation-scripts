# OpenVPN Community - Remediation (Update Enforcement)
# MME Remediation Playbook Compliant

$ErrorActionPreference = 'Stop'

# --- GLOBALS ---
$LogPath = "C:\MME\AutoLogs\OpenVPN_Update.log"
$DownloadDir = "C:\MME\CS"
$InstallerPath = "$DownloadDir\OpenVPN.msi"
$DownloadURL = "https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.10-I001-amd64.msi"

# --- LOG FUNCTION ---
function Write-Log {
    param ($Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "$Timestamp | $Message"
}

# --- LEDGER FUNCTION ---
function Update-Ledger {
    param ($Message)

    $Date = Get-Date -Format "yyyy-MM-dd"

    try {
        $Existing = ninja-property-get remediationSummary
        if (-not $Existing) { $Existing = "" }

        # sanitize existing
        $Clean = ($Existing -split "`n" | Where-Object { $_.Trim() -ne "" })

        $NewEntry = "$Date | $Message"

        if ($Clean -notcontains $NewEntry) {
            $Updated = ($Clean + $NewEntry) -join "`n"
            ninja-property-set remediationSummary "$Updated"
        }

        ninja-property-set lastRemediationDate (Get-Date -Format "o")
    }
    catch {
        Write-Log "Ledger update failed: $_"
    }
}

# --- START ---
try {
    Write-Log "===== OpenVPN Update START ====="

    # Ensure directories
    if (-not (Test-Path $DownloadDir)) {
        New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
    }

    if (-not (Test-Path "C:\MME\AutoLogs")) {
        New-Item -ItemType Directory -Path "C:\MME\AutoLogs" -Force | Out-Null
    }

    # --- DOWNLOAD ---
    Write-Log "Downloading installer..."
    Start-BitsTransfer -Source $DownloadURL -Destination $InstallerPath -ErrorAction Stop

    if (-not (Test-Path $InstallerPath)) {
        throw "Download failed"
    }

    Write-Log "Download complete"

    # --- INSTALL / UPGRADE ---
    Write-Log "Running MSI upgrade..."

    $Process = Start-Process "msiexec.exe" `
        -ArgumentList "/i `"$InstallerPath`" /qn /norestart REINSTALL=ALL REINSTALLMODE=vomus" `
        -Wait -PassThru

    if ($Process.ExitCode -ne 0) {
        throw "MSI failed with exit code $($Process.ExitCode)"
    }

    Write-Log "Upgrade completed successfully"

    # --- LEDGER ---
    Update-Ledger "OpenVPN Community Updated"

    Write-Log "===== OpenVPN Update COMPLETE ====="
    exit 0
}
catch {
    Write-Log "ERROR: $_"
    exit 1
}