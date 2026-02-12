# REMEDIATION-Chrome Update (SIMPLE - MSI + authoritative latest comparator, fraction=1 ONLY)
# Output token only; exit codes ignored (always exit 0)
# Logs: C:\Temp\Chrome_Update.log
# Tokens: RESULT: UPDATED | NO_ACTION | NOT_INSTALLED | ERROR

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogPath  = "C:\Temp\Chrome_Update.log"
$TempDir  = "C:\Temp"
$MsiUrl   = "https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi"
$MsiPath  = Join-Path $TempDir "googlechromestandaloneenterprise64.msi"

$Platform = "win"
$Channel  = "stable"

function Ensure-Temp {
    if (-not (Test-Path $TempDir)) { New-Item -Path $TempDir -ItemType Directory -Force | Out-Null }
}

function Log([string]$msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Ensure-Temp
    Add-Content -Path $LogPath -Value "$ts [ChromeFix] $msg"
}

function Finish([string]$result, [string]$reason) {
    if ($reason) { Log "REASON: $reason" }
    Log "RESULT: $result"
    Write-Output "RESULT: $result"
    exit 0
}

function Get-InstalledChromeVersion {
    $paths = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Log "Found chrome.exe at: $p"
            $v = (Get-Item $p).VersionInfo.ProductVersion
            $v = ($v -as [string]).Trim()
            if ($v) { return $v }
        }
    }
    return $null
}

function Get-LatestStableFromVersionHistory {
    $url = "https://versionhistory.googleapis.com/v1/chrome/platforms/$Platform/channels/$Channel/versions/all/releases" +
           "?filter=fraction=1&order_by=version%20desc&pageSize=1"

    try {
        Log "Querying VersionHistory releases (fraction=1 ONLY): $url"
        $r = Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 60

        if ($r -and $r.releases -and $r.releases.Count -ge 1 -and $r.releases[0].name) {
            $m = [regex]::Match($r.releases[0].name, "/versions/([0-9\.]+)/")
            if ($m.Success) { return $m.Groups[1].Value }
        }

        Log "No usable version returned from releases endpoint."
        return $null
    } catch {
        Log "ERROR: VersionHistory releases call failed: $($_.Exception.Message)"
        return $null
    }
}

function Kill-Chrome {
    Log "Stopping chrome.exe (if any)..."
    Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Download-Msi {
    Log "Downloading Enterprise MSI..."
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop

    $bytes = (Get-Item $MsiPath -ErrorAction Stop).Length
    Log "MSI bytes: $bytes"
    if ($bytes -lt 5MB) { throw "MSI download too small ($bytes bytes)" }
}

function Install-Msi {
    Log "Installing MSI silently..."
    $args = "/i `"$MsiPath`" /qn /norestart"
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -PassThru -ErrorAction Stop
    Log "msiexec exit code: $($p.ExitCode)"
    return $p.ExitCode
}

try {
    Ensure-Temp
    Log "============================================================"
    Log "Starting Chrome remediation (MSI + VersionHistory comparator, fraction=1 ONLY)..."

    $installed = Get-InstalledChromeVersion
    if (-not $installed) {
        Finish "NOT_INSTALLED" "chrome.exe not found; will not install Chrome."
    }

    Log "Installed Chrome version (pre): $installed"

    $latest = Get-LatestStableFromVersionHistory
    if (-not $latest) {
        Finish "ERROR" "Could not determine latest stable (fraction=1) from VersionHistory API."
    }

    Log "Latest stable (API, fraction=1): $latest"

    try {
        $installedV = [version]$installed
        $latestV    = [version]$latest
    } catch {
        Finish "ERROR" "Version parse failed. Installed='$installed' Latest='$latest'"
    }

    if ($installedV -ge $latestV) {
        Finish "NO_ACTION" "Already meets/exceeds latest stable ($installedV >= $latestV)."
    }

    Kill-Chrome
    Download-Msi

    $exitCode = Install-Msi
    if ($exitCode -ne 0) {
        Finish "ERROR" "msiexec failed with exit code $exitCode"
    }

    Start-Sleep -Seconds 5
    $after = Get-InstalledChromeVersion
    if (-not $after) {
        Finish "ERROR" "Chrome missing after install (unexpected)."
    }

    Log "Installed Chrome version (post): $after"

    try {
        $afterV  = [version]$after
        $latestV = [version]$latest
    } catch {
        Finish "ERROR" "Post version parse failed. Post='$after' Latest='$latest'"
    }

    if ($afterV -ge $latestV) {
        Finish "UPDATED" "Updated to $afterV (>= latest stable $latestV)."
    }

    # If this happens, it's not Early Stable anymore (we filtered it out).
    # This means the installer didn't move the needle (locked down endpoint, broken updater, etc.).
    Finish "ERROR" "Install completed but still below latest stable ($afterV < $latestV)."
}
catch {
    Finish "ERROR" "Unhandled exception: $($_.Exception.Message)"
}
