<#
REMEDIATION - Remove MSXML 4 Everywhere (Windows) [PS 5.1 SAFE]

Purpose:
  Aggressively removes MSXML 4:
    - Uninstalls MSXML 4 if present
    - Unregisters msxml4*.dll
    - Deletes msxml4*.dll from System32/SysWOW64 + Program Files trees
  (Excludes WinSxS to avoid OS servicing breakage.)

Output:
  RESULT | ...   NO_ACTION | ...   RESULT | ERROR (...)

Exit Code:
  Always 0

Logging:
  C:\MME\AutoLogs\MSXML4_Remediation.log

Ninja Fields Updated:
  lastRemediationDate (overwrite, ISO)
  remediationSummary  (append + capped, DATE ONLY + clean message)
#>

$ErrorActionPreference = "Stop"

$LogDir  = "C:\MME\AutoLogs"
$LogFile = Join-Path $LogDir "MSXML4_Remediation.log"

$LedgerCharCap = 4000
$LedgerLineCap = 60

function Ensure-Dir([string]$p) { if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Log([string]$m) {
  Ensure-Dir $LogDir
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -Path $LogFile -Value "$ts [MSXML4-REMED] $m"
}

function Update-Ledger([string]$summaryLine) {
  try {
    # lastRemediationDate = full ISO timestamp (unchanged global standard)
    $nowIsoFull = (Get-Date).ToString("s")

    # remediationSummary prefix = DATE ONLY (new standard)
    $nowDateOnly = (Get-Date).ToString("yyyy-MM-dd")

    try { & ninja-property-set lastRemediationDate $nowIsoFull | Out-Null } catch {}

    $existing = ""
    try { $existing = (& ninja-property-get remediationSummary) -join "`n" } catch { $existing = "" }

    $lines = @()
    if ($existing) { $lines = $existing -split "(`r`n|`n|`r)" }

    # Append clean summary line (NOT the full script output)
    $lines += "$nowDateOnly | $summaryLine"

    # De-dupe adjacent identical
    $deduped = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
      if ($deduped.Count -eq 0 -or $deduped[$deduped.Count-1] -ne $l) { $deduped.Add($l) | Out-Null }
    }

    # Cap lines
    if ($deduped.Count -gt $LedgerLineCap) {
      $deduped = $deduped[($deduped.Count-$LedgerLineCap)..($deduped.Count-1)]
    }

    # Cap chars
    $joined = ($deduped -join "`n")
    if ($joined.Length -gt $LedgerCharCap) {
      $joined = $joined.Substring($joined.Length - $LedgerCharCap)
    }

    try { & ninja-property-set remediationSummary $joined | Out-Null } catch {}
  } catch {}
}

function Finish([string]$out, [string]$ledgerLine = $null) {
  Log $out
  if ([string]::IsNullOrWhiteSpace($ledgerLine)) { $ledgerLine = $out }
  Update-Ledger $ledgerLine
  Write-Output $out
  exit 0
}

function Run-QuietUninstall([string]$cmd) {
  if (-not $cmd) { return $false }
  $c = $cmd.Trim()

  if ($c -match "msiexec\.exe" -and $c -match "\{[0-9A-Fa-f\-]{36}\}") {
    $guid = ($c | Select-String -Pattern "\{[0-9A-Fa-f\-]{36}\}" -AllMatches).Matches[0].Value
    $args = "/x $guid /qn /norestart"
    Log "Uninstalling via MSI GUID: $guid"
    Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -NoNewWindow | Out-Null
    return $true
  }

  Log "Attempting uninstall string: $c"
  Start-Process -FilePath "cmd.exe" -ArgumentList "/c $c /quiet /norestart" -Wait -NoNewWindow | Out-Null
  return $true
}

try {
  Log "============================================================"
  Log "Starting MSXML 4 aggressive removal..."

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

  $uninstallCount = 0
  if ($msxmlProducts.Count -gt 0) {
    Log "Found $($msxmlProducts.Count) MSXML 4 uninstall entries."
    foreach ($p in $msxmlProducts) {
      Log ("Product: {0} | Ver={1}" -f $p.DisplayName, $p.DisplayVersion)
      $did = $false
      if ($p.QuietUninstallString) { $did = Run-QuietUninstall $p.QuietUninstallString }
      elseif ($p.UninstallString)  { $did = Run-QuietUninstall $p.UninstallString }
      if ($did) { $uninstallCount++ }
    }
  } else {
    Log "No MSXML 4 uninstall entries found."
  }

  # Find DLLs (System32/SysWOW64 + Program Files trees). Exclude WinSxS.
  $dllTargets = New-Object System.Collections.Generic.List[string]

  $patterns = @(
    "$env:windir\System32\msxml4*.dll",
    "$env:windir\SysWOW64\msxml4*.dll"
  )
  foreach ($pat in $patterns) {
    Get-ChildItem -Path $pat -Force -ErrorAction SilentlyContinue | ForEach-Object {
      $dllTargets.Add($_.FullName) | Out-Null
    }
  }

  $scanRoots = @("C:\Program Files", "C:\Program Files (x86)")
  foreach ($r in $scanRoots) {
    if (Test-Path $r) {
      Get-ChildItem -Path $r -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "msxml4*.dll" -and $_.FullName -notmatch "\\Windows\\WinSxS\\" } |
        ForEach-Object { $dllTargets.Add($_.FullName) | Out-Null }
    }
  }

  $dllTargets = $dllTargets | Sort-Object -Unique

  if ($dllTargets.Count -eq 0 -and $msxmlProducts.Count -eq 0) {
    Finish "NO_ACTION | MSXML 4 not found (nothing to remove)" "MSXML4 Not Found"
  }

  $deleted = 0
  $unreg   = 0

  foreach ($dll in $dllTargets) {
    try {
      Log "Target DLL: $dll"

      try {
        Start-Process -FilePath "regsvr32.exe" -ArgumentList "/u /s `"$dll`"" -Wait -NoNewWindow | Out-Null
        $unreg++
        Log "Unregistered: $dll"
      } catch {
        Log "WARN: Unregister failed for ${dll}: $($_.Exception.Message)"
      }

      try {
        Remove-Item -Path $dll -Force -ErrorAction Stop
        $deleted++
        Log "Deleted: $dll"
      } catch {
        Log "WARN: Delete failed; attempting takeown/icacls then retry: $dll"
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c takeown /f `"$dll`" /a" -Wait -NoNewWindow | Out-Null
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c icacls `"$dll`" /grant Administrators:F /c" -Wait -NoNewWindow | Out-Null
        Remove-Item -Path $dll -Force -ErrorAction Stop
        $deleted++
        Log "Deleted after permissions fix: $dll"
      }
    } catch {
      Log "ERROR: Failed to remove ${dll}: $($_.Exception.Message)"
    }
  }

  $out = "RESULT | MSXML 4 removal complete (UninstallOps=$uninstallCount; DLLsUnregistered=$unreg; DLLsDeleted=$deleted)"
  Finish $out "MSXML4 Removed"
}
catch {
  Finish ("RESULT | ERROR (MSXML 4 removal failed): " + $_.Exception.Message) "MSXML4 Remove FAILED"
}
