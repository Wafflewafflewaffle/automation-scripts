# =========================================
# OpenVPN Community Deployment Script
# MME Automation / Remediation Playbook-Aligned
# =========================================

$ErrorActionPreference = 'Stop'

# -------------------------------------
# Paths / Variables
# -------------------------------------

$StagePath    = "C:\MME\CS"
$ClientPath   = Join-Path $StagePath "client"
$LogPath      = "C:\MME\AutoLogs"
$LogFile      = Join-Path $LogPath "OpenVPN_Deployment.log"

$DownloadUrl  = "https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.10-I001-amd64.msi"
$Installer    = Join-Path $StagePath "OpenVPN-2.6.10-I001-amd64.msi"

$TapCtl       = "C:\Program Files\OpenVPN\bin\tapctl.exe"
$Gui          = "C:\Program Files\OpenVPN\bin\openvpn-gui.exe"
$ConfigDir    = "C:\Program Files\OpenVPN\config"
$DeployedOvpn = Join-Path $ConfigDir "client.ovpn"

$OvpnPath     = Join-Path $ClientPath "client.ovpn"
$CaPath       = Join-Path $ClientPath "ca.crt"
$CrtPath      = Join-Path $ClientPath "client.crt"
$KeyPath      = Join-Path $ClientPath "client.pem"
$OutPath      = Join-Path $ClientPath "client_inline.ovpn"

# -------------------------------------
# Functions
# -------------------------------------

function Write-Log {
    param([string]$Message)

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Line = "$Timestamp  $Message"

    Write-Output $Line
    $Line | Out-File -FilePath $LogFile -Append -Encoding utf8
}

function Ensure-Directory {
    param([string]$Path)

    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# -------------------------------------
# Execution
# -------------------------------------

try {
    Ensure-Directory -Path $StagePath
    Ensure-Directory -Path $ClientPath
    Ensure-Directory -Path $LogPath

    Write-Log "---- OpenVPN Deployment Starting ----"

    # -------------------------------------
    # Download OpenVPN Community Installer
    # -------------------------------------

    Write-Log "Downloading OpenVPN Community installer"
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $Installer

    if (!(Test-Path $Installer)) {
        throw "Download failed: installer not found at $Installer"
    }

    Write-Log "Installer downloaded: $Installer"

    # -------------------------------------
    # Install OpenVPN Community
    # -------------------------------------

    Write-Log "Installing OpenVPN Community"
    Start-Process "msiexec.exe" -ArgumentList "/i `"$Installer`" /qn /norestart" -Wait

    Write-Log "OpenVPN installation completed"

    # -------------------------------------
    # Ensure TAP Adapter Exists
    # -------------------------------------

    if (!(Test-Path $TapCtl)) {
        throw "tapctl.exe not found: $TapCtl"
    }

    $Tap = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceDescription -like "*TAP*" -and
        $_.Status -ne "Not Present"
    }

    if (!$Tap) {
        Write-Log "No working TAP adapter found. Creating one."
        & $TapCtl create | Out-Null
        Start-Sleep -Seconds 3
        Write-Log "TAP adapter created"
    }
    else {
        Write-Log "Existing TAP adapter detected"
    }

    # -------------------------------------
    # Extract Client Package (ZIP → client folder)
    # -------------------------------------

    $ZipPath = Join-Path $StagePath "client.zip"

    if (Test-Path $ZipPath) {
        Write-Log "Client ZIP detected: $ZipPath"

        if (Test-Path $ClientPath) {
            Write-Log "Removing existing client directory"
            Remove-Item $ClientPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        New-Item -ItemType Directory -Path $ClientPath -Force | Out-Null

        Write-Log "Extracting ZIP directly to $ClientPath"
        Expand-Archive -Path $ZipPath -DestinationPath $ClientPath -Force

        Start-Sleep -Seconds 2

        $NestedClient = Join-Path $ClientPath "client"

        if (Test-Path $NestedClient) {
            Write-Log "Nested folder detected. Flattening"
            Move-Item "$NestedClient\*" $ClientPath -Force
            Remove-Item $NestedClient -Recurse -Force
        }

        Write-Log "ZIP extraction complete"
    }
    else {
        Write-Log "No client ZIP found. Assuming files already present"
    }

    # -------------------------------------
    # Validate Transferred Client Files
    # -------------------------------------

    Write-Log "Validating transferred client OVPN files"

    if (!(Test-Path $OvpnPath)) { throw "Missing file: $OvpnPath" }
    if (!(Test-Path $CaPath))   { throw "Missing file: $CaPath" }
    if (!(Test-Path $CrtPath))  { throw "Missing file: $CrtPath" }
    if (!(Test-Path $KeyPath))  { throw "Missing file: $KeyPath" }

    Write-Log "All required client files found"

    # -------------------------------------
    # Generate Inline OVPN Profile
    # -------------------------------------

    Write-Log "Generating inline VPN profile"

    $Ovpn = Get-Content $OvpnPath -Raw
    $Ca   = Get-Content $CaPath   -Raw
    $Crt  = Get-Content $CrtPath  -Raw
    $Key  = Get-Content $KeyPath  -Raw

    $Ovpn = $Ovpn -replace '(?im)^\s*ca\s+.+\r?\n?', ''
    $Ovpn = $Ovpn -replace '(?im)^\s*cert\s+.+\r?\n?', ''
    $Ovpn = $Ovpn -replace '(?im)^\s*key\s+.+\r?\n?', ''

    if ($Ovpn -notmatch '(?im)^\s*data-ciphers\s+') {
        $CipherBlock = @"
cipher AES-256-CBC
data-ciphers AES-256-GCM:AES-256-CBC
data-ciphers-fallback AES-256-CBC

"@
        $Ovpn = $CipherBlock + $Ovpn
    }

    $Ovpn = $Ovpn.TrimEnd()

    $InlineBlock = @"

<ca>
$($Ca.Trim())
</ca>

<cert>
$($Crt.Trim())
</cert>

<key>
$($Key.Trim())
</key>
"@

    $Final = $Ovpn + "`r`n" + $InlineBlock.TrimStart()
    Set-Content -Path $OutPath -Value $Final -Encoding ascii

    Write-Log "Inline VPN profile created: $OutPath"

    # -------------------------------------
    # Deploy Profile to OpenVPN
    # -------------------------------------

    Ensure-Directory -Path $ConfigDir
    Copy-Item $OutPath $DeployedOvpn -Force

    Write-Log "VPN profile deployed to: $DeployedOvpn"

    # -------------------------------------
    # Launch GUI
    # -------------------------------------

    if (!(Test-Path $Gui)) {
        throw "OpenVPN GUI missing: $Gui"
    }

    Write-Log "Launching OpenVPN GUI"
    Start-Process $Gui

    Start-Sleep -Seconds 3

    # -------------------------------------
    # Trigger Connection
    # -------------------------------------

    Write-Log "Triggering VPN connection"
    & $Gui --connect client.ovpn

    Write-Log "---- OpenVPN Deployment Complete ----"
    Write-Output "SUCCESS"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "ERROR"
    exit 1
}