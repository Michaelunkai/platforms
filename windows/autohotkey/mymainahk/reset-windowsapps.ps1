# Reset WindowsApps permissions to default to fix UWP apps

Write-Host "Resetting WindowsApps permissions to default..." -ForegroundColor Cyan

$windowsApps = "C:\Program Files\WindowsApps"

# Reset permissions to default using icacls /reset
Write-Host "Resetting ACLs..." -ForegroundColor Yellow
icacls "$windowsApps" /reset /T /C /Q

# Restore TrustedInstaller ownership
Write-Host "Restoring TrustedInstaller ownership..." -ForegroundColor Yellow
icacls "$windowsApps" /setowner "NT SERVICE\TrustedInstaller" /T /C /Q

# Set default WindowsApps permissions
Write-Host "Setting default permissions..." -ForegroundColor Yellow
icacls "$windowsApps" /inheritance:r /C /Q
icacls "$windowsApps" /grant "NT SERVICE\TrustedInstaller:(F)" /T /C /Q
icacls "$windowsApps" /grant "NT AUTHORITY\SYSTEM:(OI)(CI)(F)" /T /C /Q
icacls "$windowsApps" /grant "BUILTIN\Administrators:(RX)" /T /C /Q
icacls "$windowsApps" /grant "BUILTIN\Users:(RX)" /T /C /Q
icacls "$windowsApps" /grant "APPLICATION PACKAGE AUTHORITY\ALL APPLICATION PACKAGES:(RX)" /T /C /Q
icacls "$windowsApps" /grant "APPLICATION PACKAGE AUTHORITY\ALL RESTRICTED APPLICATION PACKAGES:(RX)" /T /C /Q

Write-Host "`nWindowsApps permissions restored to default!" -ForegroundColor Green
Write-Host "UWP apps should now work correctly." -ForegroundColor Green

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
