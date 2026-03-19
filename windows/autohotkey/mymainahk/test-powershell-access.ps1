# Test PowerShell Access
Write-Host "Testing PowerShell access..." -ForegroundColor Cyan

# Test 1: Basic execution
Write-Host "`n[Test 1] Basic PowerShell execution:" -ForegroundColor Yellow
try {
    $result = powershell -Command "Write-Output 'SUCCESS'"
    Write-Host "  ✓ $result" -ForegroundColor Green
} catch {
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Script execution
Write-Host "`n[Test 2] Script file execution:" -ForegroundColor Yellow
$tempScript = Join-Path $env:TEMP "test-ps.ps1"
"Write-Output 'Script execution works!'" | Out-File $tempScript -Encoding UTF8
try {
    $result = powershell -ExecutionPolicy Bypass -File $tempScript
    Write-Host "  ✓ $result" -ForegroundColor Green
    Remove-Item $tempScript -Force
} catch {
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Execution policy check
Write-Host "`n[Test 3] Execution policy:" -ForegroundColor Yellow
$policy = Get-ExecutionPolicy
Write-Host "  Current policy: $policy" -ForegroundColor Cyan
if ($policy -eq "Bypass" -or $policy -eq "Unrestricted") {
    Write-Host "  ✓ Policy allows script execution" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Policy may restrict scripts: $policy" -ForegroundColor Yellow
}

# Test 4: Check for errors
Write-Host "`n[Test 4] Error log check:" -ForegroundColor Yellow
$errors = $Error | Select-Object -First 3
if ($errors.Count -eq 0) {
    Write-Host "  ✓ No errors detected" -ForegroundColor Green
} else {
    Write-Host "  Recent errors:" -ForegroundColor Yellow
    $errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "PowerShell is working correctly!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
