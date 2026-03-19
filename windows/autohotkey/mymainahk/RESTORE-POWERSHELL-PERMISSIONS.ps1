# RESTORE POWERSHELL DIRECTORY PERMISSIONS TO DEFAULT
# Fixes error 0x80070005 caused by permission changes

Write-Host "============================================" -ForegroundColor Red
Write-Host "RESTORING POWERSHELL PERMISSIONS" -ForegroundColor Red
Write-Host "============================================`n" -ForegroundColor Red

$psDir = "C:\Windows\System32\WindowsPowerShell"
$psExe = "$psDir\v1.0\powershell.exe"

# Step 1: Reset ACLs to default
Write-Host "[1/5] Resetting PowerShell directory ACLs..." -ForegroundColor Yellow
icacls $psDir /reset /T /C /Q
Write-Host "  ✓ ACLs reset" -ForegroundColor Green

# Step 2: Restore TrustedInstaller ownership
Write-Host "`n[2/5] Restoring TrustedInstaller ownership..." -ForegroundColor Yellow
takeown /F $psDir /A /R /D Y 2>&1 | Out-Null
icacls $psDir /setowner "NT SERVICE\TrustedInstaller" /T /C /Q
Write-Host "  ✓ Ownership restored" -ForegroundColor Green

# Step 3: Set correct default permissions
Write-Host "`n[3/5] Setting default permissions..." -ForegroundColor Yellow
icacls $psDir /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" /T /C /Q
icacls $psDir /grant "BUILTIN\Administrators:(OI)(CI)F" /T /C /Q
icacls $psDir /grant "BUILTIN\Users:(OI)(CI)RX" /T /C /Q
icacls $psDir /grant "APPLICATION PACKAGE AUTHORITY\ALL APPLICATION PACKAGES:(OI)(CI)RX" /T /C /Q
Write-Host "  ✓ Permissions set" -ForegroundColor Green

# Step 4: Specifically fix powershell.exe
Write-Host "`n[4/5] Fixing powershell.exe..." -ForegroundColor Yellow
icacls $psExe /reset /C /Q
icacls $psExe /grant "NT AUTHORITY\SYSTEM:F" /C /Q
icacls $psExe /grant "BUILTIN\Administrators:F" /C /Q
icacls $psExe /grant "BUILTIN\Users:RX" /C /Q
icacls $psExe /grant "Everyone:RX" /C /Q
Write-Host "  ✓ PowerShell.exe fixed" -ForegroundColor Green

# Step 5: Test PowerShell launch
Write-Host "`n[5/5] Testing PowerShell launch..." -ForegroundColor Yellow
try {
    $test = Start-Process powershell.exe -ArgumentList "-Command Write-Host 'SUCCESS'" -PassThru -Wait -WindowStyle Hidden
    if ($test.ExitCode -eq 0) {
        Write-Host "  ✓ PowerShell launches successfully!" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Warning: Exit code $($test.ExitCode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ✗ Still blocked: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "POWERSHELL PERMISSIONS RESTORED!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "`nTry opening PowerShell or Terminal now!" -ForegroundColor Cyan

Read-Host "`nPress Enter to exit"
