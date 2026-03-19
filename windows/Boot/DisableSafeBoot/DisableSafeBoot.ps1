<#
.SYNOPSIS
    DisableSafeBoot
#>
# Requires admin privileges
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "ERROR: This function requires Administrator privileges. Please restart PowerShell as Administrator."
        return
    }
    try {
        Write-Output "Removing Safe Mode boot configuration..." -ForegroundColor Cyan
        $result1 = bcdedit /deletevalue '{current}' safeboot
        $result2 = bcdedit /deletevalue '{current}' safebootalternateshell 2>$null
        Write-Output "Operation results: $result1, $result2"
        Write-Output "Safe Mode boot configuration has been removed. System will boot normally on next restart." -ForegroundColor Green
        $confirm = Read-Host "Do you want to restart the computer now? (Y/N)"
        if ($confirm -eq "Y" -or $confirm -eq "y") {
            Write-Output "Restarting system in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            shutdown.exe /r /t 0
        }
    } catch {
        Write-Error "ERROR: An error occurred: $_"
    }
