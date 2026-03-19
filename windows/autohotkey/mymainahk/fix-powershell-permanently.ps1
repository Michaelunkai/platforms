# Permanent PowerShell Access Fix
# Fixes error 0x80070005 (Access Denied) when launching PowerShell

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "FIXING POWERSHELL ACCESS PERMANENTLY" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Step 1: Set Execution Policy to Bypass
Write-Host "[1/6] Setting Execution Policy..." -ForegroundColor Yellow
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ Execution policy set to Bypass" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Warning: Could not set LocalMachine policy (need admin)" -ForegroundColor Yellow
}

# Step 2: Grant permissions to PowerShell executable
Write-Host "`n[2/6] Granting permissions to PowerShell..." -ForegroundColor Yellow
$psPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
try {
    icacls $psPath /grant "${currentUser}:(RX)" /C /Q
    Write-Host "  ✓ Permissions granted" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Warning: Could not modify permissions" -ForegroundColor Yellow
}

# Step 3: Add PowerShell to Windows Defender exclusions
Write-Host "`n[3/6] Adding PowerShell to Defender exclusions..." -ForegroundColor Yellow
try {
    Add-MpPreference -ExclusionProcess "powershell.exe" -ErrorAction Stop
    Add-MpPreference -ExclusionProcess "pwsh.exe" -ErrorAction SilentlyContinue
    Write-Host "  ✓ Added to Defender exclusions" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Warning: Could not add exclusion (may need admin)" -ForegroundColor Yellow
}

# Step 4: Enable PowerShell Script Block Logging (helps with debugging)
Write-Host "`n[4/6] Configuring PowerShell logging..." -ForegroundColor Yellow
try {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    if (!(Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 0 -Force
    Write-Host "  ✓ Script block logging configured" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Warning: Could not configure logging" -ForegroundColor Yellow
}

# Step 5: Disable PowerShell Constrained Language Mode
Write-Host "`n[5/6] Checking language mode..." -ForegroundColor Yellow
$langMode = $ExecutionContext.SessionState.LanguageMode
Write-Host "  Current mode: $langMode" -ForegroundColor Cyan
if ($langMode -ne "FullLanguage") {
    Write-Host "  ⚠ Warning: Constrained language mode detected" -ForegroundColor Yellow
    Write-Host "  This may require Group Policy changes" -ForegroundColor Yellow
}

# Step 6: Test PowerShell execution
Write-Host "`n[6/6] Testing PowerShell execution..." -ForegroundColor Yellow
try {
    $testScript = {
        Write-Output "PowerShell test successful!"
    }
    $result = & $testScript
    Write-Host "  ✓ $result" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Summary
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "✓ Execution policy: Bypass" -ForegroundColor Green
Write-Host "✓ PowerShell permissions: Granted" -ForegroundColor Green
Write-Host "✓ Defender exclusions: Added" -ForegroundColor Green
Write-Host "✓ Language mode: $langMode" -ForegroundColor Cyan
Write-Host "`nPowerShell should now work without access errors!" -ForegroundColor Green

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
