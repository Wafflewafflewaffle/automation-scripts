<#
MINI-SCRIPT - Import DellBIOSProvider and Verify SMBIOS (Targeted WOL Probe + CSV)

Purpose:
  Imports DellBIOSProvider, verifies DellSMBIOS PSDrive exists,
  probes known Dell paths for Wake-on-LAN,
  prints CurrentValue + PossibleValues,
  and exports full tree to CSV for review.

CSV Output Path:
  C:\MME\CS\DellSMBIOS_Menu_<timestamp>.csv

Output:
  RESULT | MENU_OK
  RESULT | ERROR (...)
#>

$ErrorActionPreference = "Stop"

try {
    Write-Output "RUN_MARKER | SMBIOS_MENU | START"

    # Import module in THIS session
    Import-Module DellBIOSProvider -Force

    # Verify PSDrive exists
    $drive = Get-PSDrive -Name DellSMBIOS -ErrorAction SilentlyContinue
    if (-not $drive) {
        throw "DellSMBIOS drive not found after Import-Module. (Ensure 64-bit PowerShell + running as admin/system.)"
    }

    Write-Output ("INFO | DriveRoot=" + $drive.Root)
    Write-Output ("INFO | Provider=" + $drive.Provider.Name)

    # --- Targeted probes (reliable across models vs blind recursion) ---
    Write-Output "INFO | TargetedProbe: Wake-on-LAN"

    $wolCandidates = @(
        "DellSMBIOS:\PowerManagement\WakeOnLan",
        "DellSMBIOS:\PowerManagement\WakeOnLAN",   # casing variants seen in the wild
        "DellSMBIOS:\PowerManagement\WakeOnWlan"   # sometimes split
    )

    $foundAny = $false
    foreach ($p in $wolCandidates) {
        $item = Get-Item -Path $p -ErrorAction SilentlyContinue
        if ($item) {
            $foundAny = $true
            Write-Output ("INFO | Found: " + $p)
            Write-Output ("INFO | Attribute=" + $item.Attribute)
            Write-Output ("INFO | CurrentValue=" + $item.CurrentValue)
            Write-Output ("INFO | PossibleValues=" + ($item.PossibleValues -join ","))
        }
    }

    if (-not $foundAny) {
        Write-Output "INFO | TargetedProbe: NO_WOL_PATHS_FOUND"
    }

    # --- Optional fuzzy search (fallback / discovery) ---
    Write-Output "INFO | LiveSearch (wake|wol|lan|nic|pxe):"

    $hits = Get-ChildItem "DellSMBIOS:\" -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.PSPath -match 'wake|wol|lan|nic|pxe') -or
            ($_.PSObject.Properties.Name -contains 'Attribute' -and $_.Attribute -match 'wake|wol|lan|nic|pxe')
        } |
        Select-Object PSPath, Attribute, CurrentValue, PossibleValues

    if (-not $hits -or $hits.Count -eq 0) {
        Write-Output "INFO | LiveSearch: NO_MATCHES"
    }
    else {
        $hits | ForEach-Object {
            Write-Output ("  - {0} | {1} | {2} | {3}" -f $_.PSPath, $_.Attribute, $_.CurrentValue, $_.PossibleValues)
        }
    }

    # --- CSV Export to C:\MME\CS ---
    $exportDir = "C:\MME\CS"
    if (-not (Test-Path $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }

    $csv = Join-Path $exportDir ("DellSMBIOS_Menu_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".csv")

    Get-ChildItem "DellSMBIOS:\" -Recurse -ErrorAction SilentlyContinue |
        Select-Object PSPath, Name, Attribute, CurrentValue, PossibleValues |
        Export-Csv $csv -NoTypeInformation

    Write-Output ("INFO | CSV=" + $csv)

    Write-Output "RESULT | MENU_OK"
}
catch {
    Write-Output "RESULT | ERROR ($($_.Exception.Message))"
}
finally {
    Write-Output "RUN_MARKER | SMBIOS_MENU | END"
}
