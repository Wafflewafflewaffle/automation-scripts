$ErrorActionPreference = "Stop"

try {
    Import-Module DellBIOSProvider -Force

    $p = "DellSMBIOS:\PowerManagement\WakeOnLan"
    $item = Get-Item -Path $p -ErrorAction Stop

    if ($item.CurrentValue -eq "LanOnly") {
        Write-Output "NO_ACTION | WakeOnLan already LanOnly"
        exit 0
    }

    Set-Item -Path $p -Value "LanOnly" -ErrorAction Stop

    $verify = (Get-Item -Path $p -ErrorAction Stop).CurrentValue
    if ($verify -eq "LanOnly") {
        Write-Output "RESULT | WakeOnLan set to LanOnly"
    } else {
        Write-Output "RESULT | ERROR (Set attempted, but verify read back as '$verify')"
    }
}
catch {
    Write-Output "RESULT | ERROR ($($_.Exception.Message))"
}
