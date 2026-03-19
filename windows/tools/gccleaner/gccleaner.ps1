<#
.SYNOPSIS
    gccleaner - PowerShell utility script
.NOTES
    Original function: gccleaner
    Extracted: 2026-02-19 20:20
#>
# Step 1: Kill all running CCleaner processes
    Get-Process -Name "CCleaner64", "CCleaner" -ErrorAction SilentlyContinue | Stop-Process -Force
    # Step 2: Remove old folder
    $ccleanerPath = 'F:\backup\windowsapps\installed\ccleaner'
    Remove-Item -LiteralPath $ccleanerPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    # Step 3: Restore using Docker
    $TAG = "ccleaner"
    docker run --rm -it -e TAG=$TAG -v /f/backup/windowsapps/installed:/f michadockermisha/backup:$TAG `
        sh -c 'apk add --no-cache rsync ; rsync -av /home /f ; mv /f/home "/f/${TAG}"'
    Start-Sleep 5
    # Step 4: Wait for CCleaner64.exe to appear
    $exePath = Join-Path $ccleanerPath "CCleaner64.exe"
    $timeout = 0
    while (!(Test-Path $exePath) -and $timeout -lt 20) {
        Start-Sleep -Seconds 1
        $timeout++
    }
    # Step 5: Run CCleaner if available
    if (Test-Path $exePath) {
        & $exePath
    } else {
        Write-Warning "CCleaner64.exe was not found after waiting 20 seconds."
    }
    # Step 6: Final cleanup command
    dkill
