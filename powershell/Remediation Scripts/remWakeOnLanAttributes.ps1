$ErrorActionPreference = "Stop"

$LogDir  = "C:\MME\AutoLogs"
$LogFile = Join-Path $LogDir "Dell_PowerBaseline.log"

function Ensure-Dir($p) {
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

function Log($m) {
    Ensure-Dir $LogDir
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$ts [DellPowerBaseline] $m"
}

function Finish($out) {
    Log "FINAL: $out"
    Write-Output $out
    exit 0
}

try {
    Ensure-Dir $LogDir
    Log "============================================================"
    Log "Starting Dell Power baseline enforcement (STRICT)..."

    Import-Module DellBIOSProvider -Force
    Log "DellBIOSProvider imported."

    # Canonical enforced baseline
    $settings = @(
        @{ Path="DellSMBIOS:\PowerManagement\WakeOnLan";     Desired="LanOnly";  Name="WakeOnLan" },
        @{ Path="DellSMBIOS:\PowerManagement\DeepSleepCtrl"; Desired="Disabled"; Name="DeepSleepCtrl" },
        @{ Path="DellSMBIOS:\PowerManagement\AcPwrRcvry";    Desired="On";       Name="AcPwrRcvry" },
        @{ Path="DellSMBIOS:\PowerManagement\BlockSleep";    Desired="Disabled"; Name="BlockSleep" },
        @{ Path="DellSMBIOS:\PowerManagement\UsbWake";       Desired="Disabled"; Name="UsbWake" }
    )

    $changed = @()
    $already = @()

    foreach ($s in $settings) {
        $p       = $s.Path
        $desired = $s.Desired
        $name    = $s.Name

        Log "------------------------------------------------------------"
        Log "Processing ${name}"
        Log "Path: $p"
        Log "Desired: $desired"

        $item = Get-Item -Path $p -ErrorAction Stop

        $current  = [string]$item.CurrentValue
        $possible = @($item.PossibleValues)

        Log "${name} CurrentValue: $current"
        Log "${name} PossibleValues: $($possible -join ',')"

        if ($possible.Count -eq 0) {
            throw "${name} has no PossibleValues exposed at '$p'."
        }

        if ($possible -notcontains $desired) {
            throw "${name} desired '$desired' invalid. Allowed: $($possible -join ',')"
        }

        if ($current -eq $desired) {
            Log "${name} already compliant."
            $already += "${name} already $desired"
            continue
        }

        Log "Setting ${name}: '$current' -> '$desired'"
        Set-Item -Path $p -Value $desired -ErrorAction Stop

        $verify = [string](Get-Item -Path $p -ErrorAction Stop).CurrentValue
        Log "${name} Verify readback: $verify"

        if ($verify -ne $desired) {
            throw "${name} set attempted ($current -> $desired) but verify returned '$verify'"
        }

        Log "${name} updated successfully."
        $changed += "${name} $current -> $verify"
    }

    if ($changed.Count -gt 0) {
        Finish ("RESULT | Updated: " + ($changed -join "; "))
    } else {
        Finish ("NO_ACTION | " + ($already -join "; "))
    }
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Finish ("RESULT | ERROR ($($_.Exception.Message))")
}
