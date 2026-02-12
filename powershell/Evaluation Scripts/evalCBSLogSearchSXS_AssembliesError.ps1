# Define the source path for the CBS log
$sourcePath = "$($env:windir)\Logs\CBS\CBS.log"

# Check if the CBS log exists
if (Test-Path $sourcePath) {
    try {
        # Read the CBS log file and search for lines containing 'ERROR_SXS_ASSEMBLY_MISSING'
        $logContents = Get-Content -Path $sourcePath
        $errorEntries = $logContents | Select-String -Pattern 'ERROR_SXS_ASSEMBLY_MISSING'

        # Check if any entries were found
        if ($errorEntries) {
            Write-Host "Found the following 'ERROR_SXS_ASSEMBLY_MISSING' entries in CBS.log:"
            $errorEntries | ForEach-Object { Write-Host $_ }
        } else {
            Write-Host "No 'ERROR_SXS_ASSEMBLY_MISSING' entries were found in CBS.log."
        }
    } catch {
        Write-Host "An error occurred while reading the CBS log: $_"
    }
} else {
    Write-Host "CBS log does not exist at the specified location."
}
