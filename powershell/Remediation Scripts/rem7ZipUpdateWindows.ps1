<#
REMEDIATION - 7-Zip Update to Latest + Cleanup Older Versions (Windows) [PS 5.1 SAFE]
Logs: C:\MME\AutoLogs\7Zip_Remediation.log
Output: RESULT | ...   NO_ACTION | ...   RESULT | ERROR (...)
Exit: Always 0

MME Standard Behavior (UPDATED):
- Always log to C:\MME\AutoLogs
- Always exit 0
- Tokens: RESULT | ..., NO_ACTION | ..., RESULT | ERROR (...)
- Ninja fields:
  - lastRemediationDate (overwrite) ALWAYS
  - remediationSummary  (append + line-cap + optional de-dupe) NO hard char-cap
#>

$ErrorActionPreference = "Stop"

$LogDir  = "C:\MME\AutoLogs"
$LogFile = Join-Path $LogDir "7Zip_Remediation.log"
$DownloadPage = "https://www.7-zip.org/download.html"
$DownloadDir  = "C:\MME\AutoLogs"

# UPDATED STANDARD: no hard char-cap
$LedgerLineCap = 60

function Ensure-Dir([string]$p) {
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

function Log([string]$m) {
    Ensure-Dir $LogDir
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$ts [7Zip] $m"
}

function Resolve-NinjaCli {
    $candidates = @(
        "C:\ProgramData\NinjaRMMAgent\ninjarmm-cli.exe",
        "$env:ProgramFiles\NinjaRMMAgent\ninjarmm-cli.exe",
        "$env:ProgramFiles(x86)\NinjaRMMAgent\ninjarmm-cli.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

function Set-NinjaField([string]$name, [string]$value) {
    # Best-effort, but designed to actually work in mixed Ninja environments.
    try {
        if (Get-Command ninja-property-set -ErrorAction SilentlyContinue) {
            ninja-property-set $name "$value" | Out-Null
            Log "Ninja field set via ninja-property-set: $name = $value"
            return $true
        }

        $cli = Resolve-NinjaCli
        if ($cli) {
            & $cli set $name "$value" | Out-Null
            Log "Ninja field set via ninjarmm-cli: $name = $value"
            return $true
        }

        Log "WARN: No Ninja field setter found (ninja-property-set missing; ninjarmm-cli missing). Field not set: $name"
    } catch {
        Log "WARN: Failed setting Ninja field '$name' (ignored): $($_.Exception.Message)"
    }
    return $false
}

function Get-NinjaField([string]$name) {
    try {
        if (Get-Command ninja-property-get -ErrorAction SilentlyContinue) {
            return (ninja-property-get $name 2>$null | Out-String).Trim()
        }

        $cli = Resolve-NinjaCli
        if ($cli) {
            return ((& $cli get $name 2>$null) | Out-String).Trim()
        }
    } catch {}
    return $null
}

function Append-RemediationSummary([string]$entry) {
    try {
        $existing = Get-NinjaField "remediationSummary"
        $lines = @()

        if (-not [string]::IsNullOrWhiteSpace($existing)) {
            $lines = $existing -split "(\r\n|\n|\r)" | Where-Object { $_ -and $_.Trim() -ne "" }
        }

        $newLine = $entry.Trim()

        # Optional de-dupe: don't append if identical to last line
        if ($lines.Count -gt 0 -and $lines[-1].Trim() -eq $newLine) {
            Log "RemediationSummary: last entry identical; skipping duplicate append."
            return
        }

        $lines += $newLine

        # UPDATED STANDARD: line cap only (no hard char-cap)
        if ($lines.Count -gt $LedgerLineCap) {
            $lines = $lines[-$LedgerLineCap..-1]
        }

        $combined = ($lines -join "`r`n").Trim()
        $ok = Set-NinjaField "remediationSummary" $combined
        if ($ok) { Log "RemediationSummary updated (line-capped=$LedgerLineCap)." }
        else { Log "WARN: remediationSummary not updated (setter unavailable)." }
    } catch {
        Log "WARN: remediationSummary append failed (ignored): $($_.Exception.Message)"
    }
}

function Finish([string]$out, [string]$ledgerLine = $null) {
    try {
        $iso = (Get-Date).ToString("yyyy-MM-dd")
        $ok1 = Set-NinjaField "lastRemediationDate" $iso
        if (-not $ok1) { Log "WARN: lastRemediationDate not updated (setter unavailable)." }

        if ($ledgerLine) { Append-RemediationSummary $ledgerLine }
    } catch {
        Log "WARN: Ledger update failed in Finish (ignored): $($_.Exception.Message)"
    }

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

    $url = if ($href -match '^https?://') { $href } else { "https://www.7-zip.org/" + ($href.TrimStart('/')) }

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

    if ($cmd -match 'msiexec(\.exe)?\s') {
        $cmd = $cmd -replace '\s/I\s', ' /X '
        $cmd = $cmd -replace '\s/i\s', ' /X '
        if ($cmd -notmatch '/qn') { $cmd += " /qn" }
        if ($cmd -notmatch '/norestart') { $cmd += " /norestart" }
    } else {
        if ($cmd -notmatch '(/S|/s|/quiet|/qn|--silent|--quiet)') { $cmd += " /S" }
    }

    Log "Uninstall command: $cmd"
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -PassThru
    Log "Uninstall exit code: $($p.ExitCode) (ignored)"
}

try {
    Ensure-Dir $LogDir
    Log "==================== START ===================="

    # Quick visibility: which Ninja setter is available?
    Log ("Ninja setter availability: ninja-property-set=" + [bool](Get-Command ninja-property-set -EA SilentlyContinue) +
         " ; ninjarmm-cli=" + [bool](Resolve-NinjaCli))

    $latestInfo = Get-Latest7Zip
    $latest = $latestInfo.Version

    $entries = Get-7ZipEntries
    if (-not $entries -or $entries.Count -eq 0) {
        Finish "NO_ACTION | 7-Zip not installed"
    }

    $installedVersions = $entries | Where-Object { $_.DisplayVersion } | ForEach-Object { $_.DisplayVersion }
    $highest = ($installedVersions | Sort-Object { [version]$_ } -Descending | Select-Object -First 1)

    Log "Installed highest: $highest ; Latest: $latest"

    if ([version]$highest -ge [version]$latest) {
        Finish "NO_ACTION | 7-Zip already current ($highest)"
    }

    foreach ($e in $entries) {
        if (-not $e.DisplayVersion) { continue }
        if ([version]$e.DisplayVersion -lt [version]$latest) {
            Log "Removing older 7-Zip: $($e.DisplayName) v$($e.DisplayVersionRaw) view=$($e.View)"
            $cmd = $e.QuietUninstallString
            if (-not $cmd) { $cmd = $e.UninstallString }
            Run-UninstallCmd $cmd
        }
    }

    Ensure-Dir $DownloadDir
    $msiName = Split-Path $latestInfo.Url -Leaf
    $msiPath = Join-Path $DownloadDir $msiName

    Log "Downloading MSI to $msiPath"
    Invoke-WebRequest -Uri $latestInfo.Url -OutFile $msiPath -UseBasicParsing -TimeoutSec 120
    if (!(Test-Path $msiPath)) { throw "Download failed; MSI missing at $msiPath" }

    Log "Installing latest 7-Zip via msiexec (no reboot)..."
    $args = "/i `"$msiPath`" /qn /norestart"
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -PassThru
    Log "msiexec exit code: $($p.ExitCode) (ignored)"

    $entries2 = Get-7ZipEntries
    $installedVersions2 = $entries2 | Where-Object { $_.DisplayVersion } | ForEach-Object { $_.DisplayVersion }
    $highest2 = ($installedVersions2 | Sort-Object { [version]$_ } -Descending | Select-Object -First 1)

    Log "Post highest: $highest2 ; Latest: $latest"

    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $ledgerLine = "$ts - 7-Zip UPDATED ($highest -> $latest) | PostHighest=$highest2"

    if ($highest2 -and ([version]$highest2 -ge [version]$latest)) {
        Finish "RESULT | UPDATED 7-Zip ($highest -> $latest)" $ledgerLine
    } else {
        Finish "RESULT | ERROR (Update attempted but version did not confirm; pre=$highest post=$highest2 latest=$latest)" `
            "$ts - 7-Zip ERROR (Update attempted but did not confirm; pre=$highest post=$highest2 latest=$latest)"
    }
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Finish "RESULT | ERROR (7-Zip remediation failed: $($_.Exception.Message))" `
        "$ts - 7-Zip ERROR (Remediation failed: $($_.Exception.Message))"
}
