<#
.SYNOPSIS
    curr
#>
# Schedule FULL chkdsk /R scan at next boot (10+ minute deep scan)
    # The /R flag includes /F and also scans for bad sectors
    Write-Host "Scheduling full disk scans for next boot..." -ForegroundColor Cyan
    
    foreach ($drive in 'C:','D:','E:','F:') {
        if (Test-Path $drive) {
            Write-Host "  Scheduling $drive for full scan..." -ForegroundColor Yellow
            # Set dirty bit to ensure scan runs
            fsutil dirty set $drive 2>$null
            # Schedule the /R scan (answers Y to the prompt automatically)
            echo Y | chkdsk $drive /R 2>$null
        }
    }
    
    Write-Host "`nAll drives scheduled for FULL scan at next boot." -ForegroundColor Green
    Write-Host "Use 'shutdown /r /t 0' for a clean reboot (not restart from Start menu)." -ForegroundColor Yellow
    Write-Host "The scan will run before Windows loads and may take 10-30 minutes per drive." -ForegroundColor Yellow
