<#
.SYNOPSIS
    update - PowerShell utility script
.DESCRIPTION
    Extracted from PowerShell profile for modular organization
.NOTES
    Original function: update
    Location: F:\study\Platforms\windows\Updates\update-script\update.ps1
    Extracted: 2026-02-19 20:05
#>
param()
    $ErrorActionPreference = "Stop"
    
    try {
        # Check if PSWindowsUpdate module is available
        $module = Get-Module PSWindowsUpdate -ListAvailable
        if (-not $module) {
            Write-Host "PSWindowsUpdate module not found. Installing..." -ForegroundColor Yellow
            Install-Module PSWindowsUpdate -Force -Scope AllUsers -AllowClobber
            Write-Host "PSWindowsUpdate module installed successfully." -ForegroundColor Green
        }
        
        # Import the module with error handling
        Write-Host "Loading PSWindowsUpdate module..." -ForegroundColor Cyan
        Import-Module PSWindowsUpdate -Force
        
        # Verify module loaded correctly
        $importedModule = Get-Module PSWindowsUpdate
        if (-not $importedModule) {
            throw "Failed to import PSWindowsUpdate module"
        }
        
        Write-Host "Module loaded successfully. Version: $($importedModule.Version)" -ForegroundColor Green
        
        # Check for available updates
        Write-Host "Checking for Windows Updates..." -ForegroundColor Cyan
        $updates = Get-WindowsUpdate
        
        if ($updates) {
            Write-Host "Found $($updates.Count) update(s). Installing..." -ForegroundColor Yellow
            Install-WindowsUpdate -AcceptAll -AutoReboot
        } else {
            Write-Host "No updates available." -ForegroundColor Green
        }
        
    } catch {
        Write-Error "Update function failed: $($_.Exception.Message)"
        Write-Host "`nTroubleshooting steps:" -ForegroundColor Yellow
        Write-Host "1. Run PowerShell as Administrator" -ForegroundColor White
        Write-Host "2. Run: fixupdate" -ForegroundColor White
        Write-Host "3. Try update function again" -ForegroundColor White
        return $false
    } finally {
        $ErrorActionPreference = "Continue"
    }
    
    return $true
