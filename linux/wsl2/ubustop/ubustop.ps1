<#
.SYNOPSIS
    ubustop
#>
$ErrorActionPreference="SilentlyContinue"; Write-Host "=== FULL WSL2 HARD RESTART + UBUNTU AUTO-REPAIR ===" -ForegroundColor Cyan; taskkill /F /IM "wsl.exe" /T 2>$null; taskkill /F /IM "vmmem.exe" /T 2>$null; taskkill /F /IM "vmwp.exe" /T 2>$null; net stop LxssManager 2>$null; net stop vmcompute 2>$null; net start vmcompute 2>$null; net start LxssManager 2>$null; Start-Sleep -Seconds 1; wsl --shutdown 2>$null; $hasUbuntu=(wsl -l -q 2>$null | Select-String -Pattern '^ubuntu$'); if(-not $hasUbuntu){ Write-Host "Ubuntu distro missing or broken - reimporting..." -ForegroundColor Yellow; if(Test-Path 'C:\wsl2\ubuntu\'){ Remove-Item 'C:\wsl2\ubuntu\' -Recurse -Force }; wsl --import ubuntu 'C:\wsl2\ubuntu\' 'F:\backup\linux\wsl\ubuntu.tar' }; wsl -l -v; wsl -d ubuntu -e echo 'Ubuntu is OK' 2>$null; Write-Host "=== WSL2 + UBUNTU READY ===" -ForegroundColor Green
