# =========================================
# OpenVPN Community Deployment Script (ZIP Support Added)
# =========================================

$ErrorActionPreference = 'Stop'

# Ensure staging directory exists
$path = "C:\MME\CS"
if (!(Test-Path $path)) {
    New-Item -ItemType Directory -Path $path | Out-Null
}

# -------------------------------------
# Extract client.zip if present
# -------------------------------------

$zip = "C:\MME\CS\client.zip"
$clientPath = "C:\MME\CS\client"

if (Test-Path $zip) {
    Write-Output "ZIP detected: $zip"

    if (Test-Path $clientPath) {
        Write-Output "Clearing existing client folder"
        Remove-Item "$clientPath\*" -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Output "Extracting ZIP"
    Expand-Archive -Path $zip -DestinationPath "C:\MME\CS" -Force

    Start-Sleep 2

    # Handle nested folder issue
    $nested = "C:\MME\CS\client\client"
    if (Test-Path $nested) {
        Write-Output "Nested folder detected, flattening"
        Move-Item "$nested\*" $clientPath -Force
        Remove-Item $nested -Recurse -Force
    }

    Write-Output "ZIP extraction complete"
}
else {
    Write-Output "No ZIP found, assuming files already present"
}

# -------------------------------------
# Download OpenVPN Community Edition
# -------------------------------------

$url = "https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.10-I001-amd64.msi"
$file = "C:\MME\CS\OpenVPN-2.6.10-I001-amd64.msi"

Invoke-WebRequest $url -OutFile $file

# Install silently
if (!(Test-Path $file)) {
    Write-Error "Installer not found: $file"
    exit 1
}

Start-Process $file -ArgumentList "/qn /norestart" -Wait

# -------------------------------------
# Edit OVPN file
# -------------------------------------

$folder = "C:\MME\CS\client"

$ovpnPath = Join-Path $folder "client.ovpn"
$caPath   = Join-Path $folder "ca.crt"
$crtPath  = Join-Path $folder "client.crt"
$keyPath  = Join-Path $folder "client.pem"
$outPath  = Join-Path $folder "client_inline.ovpn"

# Validate required files exist
if (!(Test-Path $ovpnPath)) { throw "Missing file: $ovpnPath" }
if (!(Test-Path $caPath))   { throw "Missing file: $caPath" }
if (!(Test-Path $crtPath))  { throw "Missing file: $crtPath" }
if (!(Test-Path $keyPath))  { throw "Missing file: $keyPath" }

# Load file contents
$ovpn = Get-Content $ovpnPath -Raw
$ca   = Get-Content $caPath   -Raw
$crt  = Get-Content $crtPath  -Raw
$key  = Get-Content $keyPath  -Raw

# Remove external certificate/key directives
$ovpn = $ovpn -replace '(?im)^\s*ca\s+.+\r?\n?', ''
$ovpn = $ovpn -replace '(?im)^\s*cert\s+.+\r?\n?', ''
$ovpn = $ovpn -replace '(?im)^\s*key\s+.+\r?\n?', ''

# Ensure cipher compatibility
if ($ovpn -notmatch '(?im)^\s*data-ciphers\s+') {

$cipherBlock = @"
cipher AES-256-CBC
data-ciphers AES-256-GCM:AES-256-CBC
data-ciphers-fallback AES-256-CBC

"@

    $ovpn = $cipherBlock + $ovpn
}

$ovpn = $ovpn.TrimEnd()

$inlineBlock = @"

<ca>
$($ca.Trim())
</ca>

<cert>
$($crt.Trim())
</cert>

<key>
$($key.Trim())
</key>
"@

$final = $ovpn + "`r`n" + $inlineBlock.TrimStart()

Set-Content -Path $outPath -Value $final -Encoding ascii

Write-Output "Created: $outPath"

# -------------------------------------
# Import into OpenVPN GUI
# -------------------------------------

Copy-Item $outPath "C:\Program Files\OpenVPN\config\client.ovpn" -Force

Start-Process "C:\Program Files\OpenVPN\bin\openvpn-gui.exe"

Start-Sleep 3

& "C:\Program Files\OpenVPN\bin\openvpn-gui.exe" --connect client.ovpn
