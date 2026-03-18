# OpenVPN Community - Eval
# MME Automation Playbook Compliant
# Output: TRIGGER / NO_ACTION
# Always exit 0 unless script execution fails

$ErrorActionPreference = 'Stop'

try {
    # --- CONFIG ---
    $DownloadURL = "https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.10-I001-amd64.msi"

    # --- EXTRACT TARGET VERSION FROM URL ---
    $FileName = Split-Path $DownloadURL -Leaf

    if ($FileName -match '^OpenVPN-([^-]+)-') {
        $TargetVersion = $Matches[1]
    } else {
        Write-Output "TRIGGER"
        exit 0
    }

    # --- SEARCH REGISTRY FOR INSTALLED APPS ---
    $RegPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $CommunityApps = foreach ($Path in $RegPaths) {
        Get-ItemProperty $Path -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -and
            $_.DisplayName -match '^OpenVPN($|[\s-])' -and
            $_.DisplayName -notmatch 'Connect'
        }
    }

    # --- NOT INSTALLED ---
    if (-not $CommunityApps) {
        Write-Output "TRIGGER"
        exit 0
    }

    # --- GET HIGHEST INSTALLED VERSION ---
    $InstalledVersionRaw = ($CommunityApps |
        Where-Object { $_.DisplayVersion } |
        Sort-Object { [version]($_.DisplayVersion -replace '[^0-9\.].*','') } -Descending |
        Select-Object -First 1
    ).DisplayVersion

    if (-not $InstalledVersionRaw) {
        Write-Output "TRIGGER"
        exit 0
    }

    $InstalledVersion = ($InstalledVersionRaw -replace '[^0-9\.].*','')

    # --- COMPARE VERSIONS ---
    if ([version]$InstalledVersion -lt [version]$TargetVersion) {
        Write-Output "TRIGGER"
        exit 0
    }

    # --- CURRENT ---
    Write-Output "NO_ACTION"
    exit 0
}
catch {
    # Only true failure should land here
    Write-Output "ERROR"
    exit 1
}
