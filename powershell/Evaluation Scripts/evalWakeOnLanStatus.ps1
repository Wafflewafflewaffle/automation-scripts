<#
EVALUATION - WOL Baseline Trigger (Dell + Custom Field) [Windows, Ninja-safe]

Trigger logic:
  TRIGGER   = (Dell device) AND (wakeonlanEnabled is EMPTY)
  NO_ACTION = (wakeonlanEnabled has any value, e.g. TRUE) OR (not Dell)

Notes:
  - If field is TRUE, we ignore (NO_ACTION) but explicitly state it.
  - If Dell check cannot be determined, treat as NOT Dell (NO_ACTION) to avoid false triggers.

Logs:
  C:\MME\AutoLogs\WOL_Eval.log

Output (final line):
  TRIGGER | ...
  NO_ACTION | ...

Exit:
  Always 0
#>

$ErrorActionPreference = "Stop"

$LogDir  = "C:\MME\AutoLogs"
$LogFile = Join-Path $LogDir "WOL_Eval.log"

function Ensure-Dir([string]$p) {
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
function Log([string]$m) {
    Ensure-Dir $LogDir
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$ts [WOL-Eval] $m"
}
function Finish([string]$out) {
    Log "FINAL: $out"
    Write-Output $out
    exit 0
}

function Get-NinjaField([string]$name) {
    try {
        if (Get-Command ninja-property-get -ErrorAction SilentlyContinue) {
            return (ninja-property-get $name 2>$null | Out-String).Trim()
        }
    } catch {}
    return $null
}

function Is-DellDevice {
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $mfr = [string]$cs.Manufacturer
        if ([string]::IsNullOrWhiteSpace($mfr)) { return $false }
        return ($mfr -match '(?i)^\s*Dell\b')
    } catch {
        return $false
    }
}

try {
    Ensure-Dir $LogDir
    Log "============================================================"
    Log "Starting WOL eval: TRIGGER if (Dell) AND (wakeonlanEnabled empty)."

    $isDell = Is-DellDevice
    Log "Detected Dell manufacturer = $isDell"

    if (-not $isDell) {
        Finish "NO_ACTION | Not a Dell device"
    }

    $val = Get-NinjaField "wakeonlanEnabled"
    Log "wakeonlanEnabled raw = '$val'"

    if ([string]::IsNullOrWhiteSpace($val)) {
        Finish "TRIGGER | Dell device and wakeonlanEnabled is EMPTY"
    } else {
        if ($val.Trim().ToUpperInvariant() -eq "TRUE") {
            Finish "NO_ACTION | wakeonlanEnabled=TRUE (Dell device)"
        } else {
            Finish "NO_ACTION | wakeonlanEnabled is set ('$val') (Dell device)"
        }
    }
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Finish "NO_ACTION | Eval error (ignored): $($_.Exception.Message)"
}
