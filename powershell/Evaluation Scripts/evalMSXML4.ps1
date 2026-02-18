<#
EVALUATION - MSXML 4 Detection (Windows) [PS 5.1 SAFE]
Purpose:
  Detects MSXML 4 footprint (installed product OR msxml4*.dll present).
Output:
  TRIGGER | ...   or   NO_ACTION | ...
Exit:
  Always 0
Logs:
  C:\MME\AutoLogs\MSXML4_Eval.log
#>

$ErrorActionPreference = "SilentlyContinue"

$LogDir  = "C:\MME\AutoLogs"
$LogFile = Join-Path $LogDir "MSXML4_Eval.log"

function Ensure-Dir([string]$p) { if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Log([string]$m) {
  Ensure-Dir $LogDir
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -Path $LogFile -Value "$ts [MSXML4-EVAL] $m"
}

try {
  Log "============================================================"
  Log "Starting MSXML 4 evaluation..."

  # --- Detect uninstall entries (32+64) ---
  $uninstallRoots = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )

  $msxmlProducts = @()
  foreach ($root in $uninstallRoots) {
    $msxmlProducts += Get-ItemProperty $root |
      Where-Object { $_.DisplayName -match "MSXML\s*4" -or $_.DisplayName -match "Microsoft XML Core Services\s*4" } |
      Select-Object DisplayName, DisplayVersion, PSChildName, UninstallString, QuietUninstallString
  }

  if ($msxmlProducts.Count -gt 0) {
    Log "Found MSXML 4 uninstall entries:"
    foreach ($p in $msxmlProducts) {
      Log ("  - {0} | Ver={1} | Key={2}" -f $p.DisplayName, $p.DisplayVersion, $p.PSChildName)
    }
  } else {
    Log "No MSXML 4 uninstall entries found."
  }

  # --- Detect DLL footprint (common + targeted search) ---
  $dllHits = New-Object System.Collections.Generic.List[string]

  $commonPaths = @(
    "$env:windir\System32\msxml4*.dll",
    "$env:windir\SysWOW64\msxml4*.dll",
    "C:\Program Files\*\msxml4*.dll",
    "C:\Program Files (x86)\*\msxml4*.dll"
  )

  foreach ($pat in $commonPaths) {
    Get-ChildItem -Path $pat -Force -ErrorAction SilentlyContinue | ForEach-Object {
      $dllHits.Add($_.FullName) | Out-Null
    }
  }

  # Light recursive scan of app areas (fast-ish). Avoid WinSxS.
  $scanRoots = @("C:\Program Files", "C:\Program Files (x86)")
  foreach ($r in $scanRoots) {
    if (Test-Path $r) {
      Get-ChildItem -Path $r -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "msxml4*.dll" } |
        ForEach-Object { $dllHits.Add($_.FullName) | Out-Null }
    }
  }

  $dllHits = $dllHits | Sort-Object -Unique

  if ($dllHits.Count -gt 0) {
    Log "Found msxml4*.dll footprint:"
    foreach ($h in $dllHits) { Log "  - $h" }
  } else {
    Log "No msxml4*.dll footprint found in common/app paths."
  }

  $hasMsxml4 = ($msxmlProducts.Count -gt 0) -or ($dllHits.Count -gt 0)

  if ($hasMsxml4) {
    $msg = "TRIGGER | MSXML 4 footprint detected (Products=$($msxmlProducts.Count), DLLs=$($dllHits.Count))"
    Log $msg
    Write-Output $msg
  } else {
    $msg = "NO_ACTION | MSXML 4 not detected"
    Log $msg
    Write-Output $msg
  }
}
catch {
  $msg = "TRIGGER | ERROR during eval (defaulting to TRIGGER for safety): $($_.Exception.Message)"
  Log $msg
  Write-Output $msg
}
finally {
  exit 0
}
