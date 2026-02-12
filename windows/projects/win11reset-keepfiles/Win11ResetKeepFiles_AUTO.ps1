#Requires -RunAsAdministrator
# Windows 11 Reset - Keep Files - ISO-BASED AUTOMATIC
# Uses: E:\isos\Windows.iso
# Keeps personal files, removes all programs and settings

$ErrorActionPreference = "Stop"
$isoPath = "E:\isos\Windows.iso"
$logFile = "$PSScriptRoot\reset_log_auto.txt"

function Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') - $msg"
    Write-Host $line -ForegroundColor Cyan
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

# Clear old log
Remove-Item $logFile -Force -ErrorAction SilentlyContinue

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  Windows 11 RESET - Keep Files Only" -ForegroundColor Yellow  
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "`n  KEEPS: Personal files" -ForegroundColor Green
Write-Host "  REMOVES: All programs" -ForegroundColor Red
Write-Host "  REMOVES: All settings`n" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Yellow

Log "=== Windows 11 Reset (Keep Files) ==="
Log "Using ISO: $isoPath"

# Verify ISO exists
if (-not (Test-Path $isoPath)) {
    Log "ERROR: ISO not found at $isoPath"
    Write-Host "`nERROR: Windows ISO not found!" -ForegroundColor Red
    Write-Host "Expected location: $isoPath" -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    exit 1
}

$isoSizeGB = [math]::Round((Get-Item $isoPath).Length/1GB, 2)
Log "ISO verified: $isoSizeGB GB"

# Mount the ISO
Log "Mounting ISO..."
Write-Host "Mounting Windows ISO..." -ForegroundColor Cyan

try {
    # Dismount if already mounted
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    
    # Mount the ISO
    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
    Start-Sleep -Milliseconds 500
    
    # Get drive letter
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    if (-not $driveLetter) {
        $driveLetter = (Get-DiskImage -ImagePath $isoPath | Get-Volume).DriveLetter
    }
    
    if (-not $driveLetter) {
        throw "Could not determine drive letter after mounting"
    }
    
    Log "Mounted to: ${driveLetter}:"
    Write-Host "ISO mounted to ${driveLetter}:" -ForegroundColor Green
    
} catch {
    Log "ERROR mounting ISO: $($_.Exception.Message)"
    Write-Host "`nERROR: Failed to mount ISO" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    exit 1
}

# Verify setup.exe exists
$setupPath = "${driveLetter}:\setup.exe"
if (-not (Test-Path $setupPath)) {
    Log "ERROR: setup.exe not found at $setupPath"
    Write-Host "`nERROR: setup.exe not found in ISO!" -ForegroundColor Red
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    exit 1
}

Log "Found: $setupPath"

# Launch Windows Setup with reset flags
# /auto clean = Factory reset (removes programs, keeps files)
# /dynamicupdate disable = Skip updates during setup
# /eula accept = Auto-accept license
# /telemetry disable = Disable telemetry
# /compat ignorewarning = Skip compatibility warnings
Log "Launching Windows Setup (Reset mode)..."
$setupArgs = "/auto clean /dynamicupdate disable /eula accept /telemetry disable /compat ignorewarning"
Log "Args: $setupArgs"

Write-Host "`nLaunching Windows Setup..." -ForegroundColor Cyan
Write-Host "Mode: Reset (Keep Files)" -ForegroundColor Yellow

try {
    $process = Start-Process -FilePath $setupPath -ArgumentList $setupArgs -PassThru
    Log "Setup launched! PID: $($process.Id)"
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  RESET STARTED!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Process ID: $($process.Id)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Your PC will restart automatically." -ForegroundColor Yellow
    Write-Host "Personal files will be kept." -ForegroundColor Green
    Write-Host "All programs will be removed." -ForegroundColor Red
    Write-Host ""
    Write-Host "DO NOT turn off your computer!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Green
    
    Log "Reset process initiated successfully"
    Log "Keeping this window open for reference..."
    
    # Keep window open for 30 seconds so user can see the status
    Start-Sleep -Seconds 30
    
} catch {
    Log "ERROR launching setup: $($_.Exception.Message)"
    Write-Host "`nERROR: Failed to launch setup" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    exit 1
}

# Note: We don't dismount the ISO because setup.exe needs it
Log "Script complete. Setup is running."
