<#
ROLLBACK - Reinstall MSXML 4 SP3 (KB2758694) (Windows) [PS 5.1 SAFE]

Purpose:
  Reinstalls MSXML 4 runtime for app compatibility.
  Downloads from Microsoft download.microsoft.com direct URL and installs silently.
  VERIFIES install via uninstall registry entry (no "attempted").

Output:
  RESULT | MSXML 4 installed successfully (Version=...)
  RESULT | ERROR (...)

Exit Code:
  Always 0

Logging:
  C:\MME\AutoLogs\MSXML4_Rollback.log
#>

$ErrorActionPreference = "Stop"

$LogDir  = "C:\MME\AutoLogs"
$LogFile = Join-Path $LogDir "MSXML4_Rollback.log"
$OutExe  = Join-Path $LogDir "msxml4-KB2758694-enu.exe"

# Direct Microsoft CDN URL for the installer
$DlUrl = "https://download.microsoft.com/download/A/7/6/A7611FFC-4F68-4FB1-A931-95882EC013FC/msxml4-KB2758694-enu.exe"

function Ensure-Dir([string]$p) { if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Log([string]$m) {
  Ensure-Dir $LogDir
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -Path $LogFile -Value "$ts [MSXML4-ROLLBACK] $m"
}
function Finish([string]$out) { Log $out; Write-Output $out; exit 0 }

function Get-MSXML4Product() {
  $roots = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  Get-ItemProperty $roots -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "MSXML\s*4|Microsoft XML Core Services\s*4" } |
    Select-Object -First 1 DisplayName, DisplayVersion, PSPath
}

try {
  Log "============================================================"
  Log "Starting MSXML 4 rollback (KB2758694)..."
  Log "Download URL: $DlUrl"
  Log "Destination:  $OutExe"

  # Force TLS 1.2 (common cause of weird download failures in PS 5.1)
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Log "TLS set to 1.2"
  } catch {
    Log "WARN: Could not set TLS 1.2: $($_.Exception.Message)"
  }

  Ensure-Dir $LogDir

  # If already installed, report and exit cleanly
  $pre = Get-MSXML4Product
  if ($pre) {
    Finish ("RESULT | MSXML 4 already installed (Name='{0}', Version={1})" -f $pre.DisplayName, $pre.DisplayVersion)
  }

  # Download with BITS (most reliable in managed environments)
  if (Test-Path $OutExe) {
    try { Remove-Item $OutExe -Force -ErrorAction SilentlyContinue } catch {}
  }

  try {
    Start-BitsTransfer -Source $DlUrl -Destination $OutExe -ErrorAction Stop
    Log "Download completed via BITS."
  } catch {
    # Fallback to Invoke-WebRequest if BITS is blocked
    Log "WARN: BITS failed: $($_.Exception.Message)"
    Log "Attempting fallback download via Invoke-WebRequest..."
    Invoke-WebRequest -Uri $DlUrl -OutFile $OutExe -UseBasicParsing -Headers @{ "User-Agent" = "Mozilla/5.0" } -ErrorAction Stop
    Log "Download completed via Invoke-WebRequest."
  }

  if (!(Test-Path $OutExe)) {
    throw "Download did not produce expected file: $OutExe"
  }

  Log "Installing silently: /quiet /norestart"
  $p = Start-Process -FilePath $OutExe -ArgumentList "/quiet /norestart" -Wait -NoNewWindow -PassThru
  Log "Installer exit code: $($p.ExitCode)"

  # VERIFY install
  Start-Sleep -Seconds 2
  $post = Get-MSXML4Product
  if (-not $post) {
    throw "Install verification failed: MSXML 4 uninstall entry not found after install (exit code $($p.ExitCode))."
  }

  Finish ("RESULT | MSXML 4 installed successfully (Name='{0}', Version={1})" -f $post.DisplayName, $post.DisplayVersion)
}
catch {
  Finish ("RESULT | ERROR (rollback failed): " + $_.Exception.Message)
}
