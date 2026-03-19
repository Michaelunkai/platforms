<#
.SYNOPSIS
    fixupdate
#>
# Emergency fix function for PSWindowsUpdate corruption
    Write-Host "Fixing PSWindowsUpdate module corruption..." -ForegroundColor Yellow
    
    try {
        # Force remove corrupted module
        Get-Module PSWindowsUpdate | Remove-Module -Force -ErrorAction SilentlyContinue
        Get-InstalledModule PSWindowsUpdate -ErrorAction SilentlyContinue | Uninstall-Module -Force -ErrorAction SilentlyContinue
        Remove-Item -Path 'C:\Program Files\WindowsPowerShell\Modules\PSWindowsUpdate' -Recurse -Force -ErrorAction SilentlyContinue
        
        # Clean cache
        Remove-Item -Path "$env:TEMP\PSGet*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:LOCALAPPDATA\PackageManagement\NuGet\Cache" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Reinstall fresh
        Write-Host "Reinstalling PSWindowsUpdate module..." -ForegroundColor Cyan
        Install-Module -Name PSWindowsUpdate -Force -AllowClobber -Scope AllUsers
        Import-Module PSWindowsUpdate -Force
        
        Write-Host "PSWindowsUpdate module fixed successfully!" -ForegroundColor Green
        Write-Host "You can now run 'update' again." -ForegroundColor White
        
    } catch {
        Write-Error "Failed to fix PSWindowsUpdate: $($_.Exception.Message)"
        Write-Host "Manual fix required. Run as Administrator:" -ForegroundColor Red
        Write-Host "1. Uninstall-Module PSWindowsUpdate -Force" -ForegroundColor White
        Write-Host "2. Install-Module PSWindowsUpdate -Force" -ForegroundColor White
    }
