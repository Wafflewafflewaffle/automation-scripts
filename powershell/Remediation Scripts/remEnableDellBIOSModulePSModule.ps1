<#
MINI-SCRIPT - Install DellBIOSProvider (FIXED)

Purpose:
  Installs NuGet provider and DellBIOSProvider module silently.

Safe to run repeatedly.

Output:
  RESULT    | Module installed
  NO_ACTION | Module already present
  RESULT    | ERROR (...)
#>

$ErrorActionPreference = "Stop"

try {
    # --- Force TLS 1.2 ---
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # --- Ensure NuGet provider exists ---
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Force -Scope AllUsers -Confirm:$false | Out-Null
    }

    # --- Ensure PowerShellGet exists (older boxes sometimes need this) ---
    if (-not (Get-Module -ListAvailable -Name PowerShellGet)) {
        # If this fails on very old PS versions, we’ll handle in the next step
        Install-Module -Name PowerShellGet -Scope AllUsers -Force -Confirm:$false -ErrorAction SilentlyContinue
    }

    # --- Trust PSGallery ---
    $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($repo -and $repo.InstallationPolicy -ne "Trusted") {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    # --- Install DellBIOSProvider if missing ---
    if (-not (Get-Module -ListAvailable -Name DellBIOSProvider)) {
        Install-Module -Name DellBIOSProvider -Scope AllUsers -Force -Confirm:$false
        Write-Output "RESULT | Module installed"
    }
    else {
        Write-Output "NO_ACTION | Module already present"
    }
}
catch {
    Write-Output "RESULT | ERROR ($($_.Exception.Message))"
}
