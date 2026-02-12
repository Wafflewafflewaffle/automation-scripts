<#
Install WatchGuard ProxyCA certificate via default gateway
Logic identical to working script, but gateway is auto-detected.
#>

$ErrorActionPreference = "Stop"

function Write-Log { param([string]$m) Write-Output "[WatchGuardCert] $m" }

# ---- Detect default gateway ----
$Gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
            Sort-Object RouteMetric |
            Select-Object -First 1).NextHop

if (-not $Gateway) {
    Write-Log "ERROR: No gateway detected."
    exit 1
}

Write-Log "Gateway detected: $Gateway"

# ---- Build working WatchGuard cert URL ----
$Url = "http://$Gateway`:4126/ProxyCA.cer"
Write-Log "Downloading: $Url"

try {
    $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 60
}
catch {
    Write-Log "ERROR downloading cert: $($_.Exception.Message)"
    exit 1
}

# Guardrail: portal page instead of cert
$ct = $resp.Headers["Content-Type"]
if ($ct -and $ct -match "text/html") {
    Write-Log "ERROR: Received HTML instead of certificate."
    exit 1
}

# Get raw bytes
try {
    $bytes = [byte[]]$resp.Content
}
catch {
    $wc = New-Object System.Net.WebClient
    $bytes = $wc.DownloadData($Url)
}

# ---- Parse certificate ----
try {
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $cert.Import($bytes)
}
catch {
    Write-Log "ERROR: Downloaded content is not a valid certificate."
    exit 1
}

Write-Log ("Thumbprint: {0}" -f $cert.Thumbprint)

# ---- Import if missing ----
$storePath = "Cert:\LocalMachine\Root"

$existing = Get-ChildItem -Path $storePath |
            Where-Object { $_.Thumbprint -eq $cert.Thumbprint }

if ($existing) {
    Write-Log "Certificate already present."
    exit 0
}

$tmp = Join-Path $env:TEMP "wg_proxyca.cer"
[IO.File]::WriteAllBytes($tmp, $cert.RawData)

Import-Certificate -FilePath $tmp -CertStoreLocation $storePath | Out-Null
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

Write-Log "Certificate imported successfully."
exit 0
