<#
REMEDIATION - 7-Zip Update to Latest + Cleanup Older Versions (Windows) [PS 5.1 SAFE]
Logs: C:\MME\AutoLogs\7Zip_Remediation.log
Output: RESULT | ...   NO_ACTION | ...   RESULT | ERROR (...)
Exit: Always 0
#>

$ErrorActionPreference = "Stop"

$LogDir  = "C:\MME\AutoLogs"
$LogFile = Join-Path $LogDir "7Zip_Remediation.log"
$DownloadPage = "https://www.7-zip.org/download.html"
$DownloadDir  = "C:\MME\AutoLogs"
$LedgerCharCap = 4000
$LedgerLineCap = 60

function Ensure-Dir([string]$p) {
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

function Log([string]$m) {
    Ensure-Dir $LogDir
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$ts [7Zip] $m"
}

function Finish([string]$out) {
    Log "FINAL: $out"
    Write-Output $out
    exit 0
}

function Normalize-Version([string]$raw) {
    if (-not $raw) { return $null }
    $m = [regex]::Match($raw.Trim(), '(\d+)\.(\d+)')
    if (!$m.Success) { return $null }
    return ("{0}.{1:D2}" -f [int]$m.Groups[1].Value, [int]$m.Groups[2].Value)
}

function Get-Latest7Zip {
    Log "Fetching latest 7-Zip from $DownloadPage"
    $html = Invoke-WebRequest -Uri $DownloadPage -UseBasicParsing -TimeoutSec 30
    $c = $html.Content

    $m = [regex]::Match($c, 'href="(?<href>[^"]*7z(?<ver>\d{4})-x64\.msi)"', 'IgnoreCase')
    if (!$m.Success) { throw "Could not find x64 MSI link on download page." }

    $href = $m.Groups['href'].Value
    $digits = $m.Groups['ver'].Value
    if ($digits -notmatch '^\d{4}$') { throw "Parsed version digits invalid: $digits" }

    $maj = [int]$digits.Substring(0,2)
    $min = [int]$digits.Substring(2,2)
    $ver = ("{0}.{1:D2}" -f $maj, $min)

    if ($href -match '^https?://') {
        $url = $href
    } else {
        $url = "https://www.7-zip.org/" + ($href.TrimStart('/'))
    }

    Log "Latest parsed: $ver ; MSI: $url"
    return [pscustomobject]@{ Version = $ver; Url = $url }
}

function Get-7ZipEntries {
    $out = @()
    $views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)

    foreach ($view in $views) {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $u = $base.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
            if (-not $u) { continue }

            foreach ($name in $u.GetSubKeyNames()) {
                $k = $u.OpenSubKey($name)
                if (-not $k) { continue }

                $dn = [string]$k.GetValue("DisplayName","")
                if ($dn -notmatch '^7-Zip\b') { continue }

                $dvRaw = [string]$k.GetValue("DisplayVersion","")
                if (-not $dvRaw) { continue }

                $out += [pscustomobject]@{
                    DisplayName = $dn
                    DisplayVersionRaw = $dvRaw
                    DisplayVersion = (Normalize-Version $dvRaw)
                    QuietUninstallString = [string]$k.GetValue("QuietUninstallString","")
                    UninstallString = [string]$k.GetValue("UninstallString","")
                    View = $view.ToString()
                }
            }
        } catch {
            Log "Enum failed for $view : $($_.Exception.Message)"
        }
    }

    return $out
}

function Run-UninstallCmd([string]$cmd) {
    if (-not $cmd) { return }
    $cmd = $cmd.Trim()

    # If MSI, ensure /X + /qn + /norestart
    if ($cmd -match 'msiexec(\.exe)?\s') {
        $cmd = $cmd -replace '\s/I\s', ' /X '
        $cmd = $cmd -replace '\s/i\s', ' /X '
        if ($cmd -notmatch '/qn') { $cmd += " /qn" }
        if ($cmd -notmatch '/norestart') { $cmd += " /norestart" }
    } else {
        # EXE best-effort silent flag
        if ($cmd -notmatch '(/S|/s|/quiet|/qn|--silent|--quiet)') { $cmd += " /S" }
    }

    Log "Uninstall command: $cmd"
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -PassThru
    Log "Uninstall exit code: $($p.ExitCode) (ignored)"
}

function Try-UpdateLedger([string]$line) {
    # Best-effort Ninja field updates; do not fail remediation if CLI differs
    try {
        $cli = $null
        $c1 = "$env:ProgramFiles\NinjaRMMAgent\ninjarmm-cli.exe"
        $c2 = "$env:ProgramFiles(x86)\NinjaRMMAgent\ninjarmm-cli.exe"
        if (Test-Path $c1) { $cli = $c1 }
        elseif (Test-Path $c2) { $cli = $c2 }

        if (-not $cli) { Log "Ninja CLI not found; skipping ledger."; return }

        $iso = (Get-Date).ToString("yyyy-MM-dd")
        & $cli set lastRemediationDate $iso | Out-Null

        $existing = (& $cli get remediationSummary 2>$null | Out-String).Trim()
        $lines = @()
        if ($existing) { $lines = $existing -split "`r?`n" }

        if (!($lines -contains $line)) { $lines += $line }

        if ($lines.Count -gt $LedgerLineCap) { $lines = $lines[-$LedgerLineCap..-1] }

        $newText = ($lines -join "`r`n")
        if ($newText.Length -gt $LedgerCharCap) { $newText = $newText.Substring($newText.Length - $LedgerCharCap) }

        & $cli set remediationSummary $newText | Out-Null
        Log "Ledger updated."
    } catch {
        Log "Ledger update failed (ignored): $($_.Exception.Message)"
    }
}

try {
    Log "==================== START ===================="

    $latestInfo = Get-Latest7Zip
    $latest = $latestInfo.Version

    $entries = Get-7ZipEntries
    if (-not $entries -or $entries.Count -eq 0) {
        Finish "NO_ACTION | 7-Zip not installed"
    }

    # Determine highest installed version we can see
    $installedVersions = $entries | Where-Object { $_.DisplayVersion } | ForEach-Object { $_.DisplayVersion }
    $highest = ($installedVersions | Sort-Object { [version]$_ } -Descending | Select-Object -First 1)

    Log "Installed highest: $highest ; Latest: $latest"

    if ([version]$highest -ge [version]$latest) {
        Finish "NO_ACTION | 7-Zip already current ($highest)"
    }

    # Uninstall older-than-latest entries
    foreach ($e in $entries) {
        if (-not $e.DisplayVersion) { continue }
        if ([version]$e.DisplayVersion -lt [version]$latest) {
            Log "Removing older 7-Zip: $($e.DisplayName) v$($e.DisplayVersionRaw) view=$($e.View)"
            $cmd = $e.QuietUninstallString
            if (-not $cmd) { $cmd = $e.UninstallString }
            Run-UninstallCmd $cmd
        }
    }

    # Download latest MSI
    Ensure-Dir $DownloadDir
    $msiName = Split-Path $latestInfo.Url -Leaf
    $msiPath = Join-Path $DownloadDir $msiName

    Log "Downloading MSI to $msiPath"
    Invoke-WebRequest -Uri $latestInfo.Url -OutFile $msiPath -UseBasicParsing -TimeoutSec 120
    if (!(Test-Path $msiPath)) { throw "Download failed; MSI missing at $msiPath" }

    # Install
    Log "Installing latest 7-Zip via msiexec (no reboot)..."
    $args = "/i `"$msiPath`" /qn /norestart"
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -PassThru
    Log "msiexec exit code: $($p.ExitCode) (ignored)"

    # Verify
    $entries2 = Get-7ZipEntries
    $installedVersions2 = $entries2 | Where-Object { $_.DisplayVersion } | ForEach-Object { $_.DisplayVersion }
    $highest2 = ($installedVersions2 | Sort-Object { [version]$_ } -Descending | Select-Object -First 1)
    Log "Post highest: $highest2 ; Latest: $latest"

    $ts = (Get-Date).ToString("yyyy-MM-dd")
    $ledgerLine = "$ts UPDATED 7-Zip ($highest -> $latest)"
    Try-UpdateLedger $ledgerLine

    if ($highest2 -and ([version]$highest2 -ge [version]$latest)) {
        Finish "RESULT | UPDATED 7-Zip ($highest -> $latest)"
    } else {
        Finish "RESULT | ERROR (Update attempted but version did not confirm; pre=$highest post=$highest2 latest=$latest)"
    }
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Finish "RESULT | ERROR (7-Zip remediation failed: $($_.Exception.Message))"
}
