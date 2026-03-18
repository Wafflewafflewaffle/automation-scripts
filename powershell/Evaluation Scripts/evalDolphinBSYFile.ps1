# =========================================
# Dolphin BSY Detection - Eval
# MME Automation Playbook Aligned
# One-Off Custom Log/Report Path
# =========================================

$ErrorActionPreference = 'Stop'

# -------------------------------------
# Paths / Variables
# -------------------------------------

$WorkDir    = "C:\MME\DolphinBSYLog"
$LogFile    = Join-Path $WorkDir "Dolphin_BSY_Eval.log"
$OutputFile = Join-Path $WorkDir "Dolphin_BSY_Report.txt"

# -------------------------------------
# Logging Function (non-lethal)
# -------------------------------------

function Write-Log {
    param ([string]$Message)
    try {
        $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $LogFile -Value "$Timestamp | $Message"
    } catch {}
}

# -------------------------------------
# Ensure Working Directory Exists
# -------------------------------------

try {
    if (-not (Test-Path $WorkDir)) {
        New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
    }
}
catch {
    Write-Output "ERROR"
    exit 1
}

# -------------------------------------
# Main
# -------------------------------------

try {
    Write-Log "Starting Dolphin BSY eval"

    # -------------------------------------
    # Locate Dolphin.ini
    # -------------------------------------

    $IniPath = $null
    $IniContent = $null

    $KnownPaths = @(
        "C:\Dolphin\Dolphin.ini",
        "C:\Windows\Dolphin.ini"
    )

    foreach ($path in $KnownPaths) {
        if (Test-Path $path) {
            $IniPath = $path
            Write-Log "INI found: $IniPath"
            break
        }
    }

    # -------------------------------------
    # Attempt to read INI (non-fatal)
    # -------------------------------------

    if ($IniPath) {
        try {
            $stream = [System.IO.File]::Open($IniPath, 'Open', 'Read', 'ReadWrite')
            $reader = New-Object System.IO.StreamReader($stream)
            $IniRaw = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()

            if (-not [string]::IsNullOrWhiteSpace($IniRaw)) {
                $IniContent = $IniRaw -split "`r?`n"
                Write-Log "INI read successfully"
            }
            else {
                Write-Log "INI is blank"
            }
        }
        catch {
            Write-Log "INI read failed (non-fatal): $_"
        }
    }
    else {
        Write-Log "INI not found, using fallback paths"
    }

    # -------------------------------------
    # Determine Working Folder
    # -------------------------------------

    $WorkingFolder = $null

    if ($IniContent) {
        $InEnvironmentSection = $false

        foreach ($line in $IniContent) {
            $trimLine = $line.Trim()

            if ($trimLine -match '^\[environment\]$') {
                $InEnvironmentSection = $true
                continue
            }

            if ($trimLine -match '^\[.*\]$' -and $trimLine -notmatch '^\[environment\]$') {
                $InEnvironmentSection = $false
            }

            if ($InEnvironmentSection -and $trimLine -match '^Working\s*=') {
                $WorkingFolder = ($trimLine -split '=', 2)[1].Trim()
                break
            }
        }

        if ($WorkingFolder) {
            Write-Log "Working folder from INI: $WorkingFolder"
        }
        else {
            Write-Log "Working not found in INI"
        }
    }

    # -------------------------------------
    # Fallback Paths
    # -------------------------------------

    if (-not $WorkingFolder) {
        Write-Log "Using fallback working paths"

        $FallbackPaths = @(
            "D:\Data\Dolphin\Working",
            "C:\Data\Dolphin\Working"
        )

        foreach ($path in $FallbackPaths) {
            if (Test-Path $path) {
                $WorkingFolder = $path
                Write-Log "Fallback path selected: $WorkingFolder"
                break
            }
        }
    }

    # -------------------------------------
    # Normalize UNC → Local
    # -------------------------------------

    if ($WorkingFolder -like "\\*") {
        Write-Log "UNC detected, converting to local"

        $parts = $WorkingFolder -replace '^\\\\[^\\]+\\', ''

        foreach ($candidate in @("D:\$parts", "C:\$parts")) {
            if (Test-Path $candidate) {
                $WorkingFolder = $candidate
                Write-Log "Resolved UNC to local: $WorkingFolder"
                break
            }
        }
    }

    # -------------------------------------
    # Validate Working Folder
    # -------------------------------------

    if (-not $WorkingFolder -or -not (Test-Path $WorkingFolder)) {
        Write-Log "No valid working folder found"
        Write-Output "ERROR"
        exit 1
    }

    Write-Log "Final working folder: $WorkingFolder"

    # -------------------------------------
    # Scan for .bsy Files (clean + resilient)
    # -------------------------------------

    $ScanErrors = @()

    try {
        $Files = Get-ChildItem -Path $WorkingFolder -Filter *.bsy -File -Recurse `
            -ErrorAction Continue `
            -ErrorVariable +ScanErrors `
            2>$null
    }
    catch {
        Write-Log "Unexpected scan failure: $_"
        Write-Output "ERROR"
        exit 1
    }

    # Log scan errors quietly
    if ($ScanErrors.Count -gt 0) {
        Write-Log "Scan encountered $($ScanErrors.Count) error(s):"

        foreach ($err in $ScanErrors) {
            $errPath = $err.TargetObject
            Write-Log "SCAN ERROR | Path: $errPath | Message: $($err.Exception.Message)"
        }
    }

    $Files = @($Files)

    if (-not $Files -or $Files.Count -eq 0) {
        "No .bsy files found in $WorkingFolder" | Out-File $OutputFile -Force
        Write-Log "No .bsy files found"
        Write-Output "NO_ACTION"
        exit 0
    }

    Write-Log "$($Files.Count) .bsy file(s) found"

    $Report = $Files |
        Select-Object FullName, CreationTime, LastWriteTime |
        Format-Table -AutoSize | Out-String

    $Report | Out-File $OutputFile -Force

    Write-Log "Report written to $OutputFile"

    Write-Output "TRIGGER"
    exit 0
}
catch {
    Write-Log "FATAL ERROR: $_"
    Write-Output "ERROR"
    exit 1
}