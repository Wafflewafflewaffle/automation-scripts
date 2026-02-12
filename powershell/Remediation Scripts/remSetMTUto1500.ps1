$ErrorActionPreference = "SilentlyContinue"

$adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" }

foreach ($adapter in $adapters) {
    Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -NlMtuBytes 1500 -Confirm:$false -ErrorAction SilentlyContinue
}

exit 0
