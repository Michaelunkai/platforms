#Requires -RunAsAdministrator
# Windows 11 Reset - Keep Files Only (One Level Lower than Repair)
# Removes all programs and settings but keeps personal files

$ErrorActionPreference = "Stop"
$logFile = "$PSScriptRoot\reset_log.txt"

function Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') - $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

# Clear old log
Remove-Item $logFile -Force -ErrorAction SilentlyContinue

Log "=== Windows 11 Reset - Keep Files ==="
Log "This will remove ALL programs and settings"
Log "Personal files will be preserved"

# Display warning
$warning = @"

============================================
          FINAL WARNING
============================================
This will:
✓ KEEP: Documents, Pictures, Videos, etc.
✗ REMOVE: All installed programs
✗ REMOVE: All Windows settings
✗ REMOVE: All drivers (will reinstall defaults)
============================================

"@

Write-Host $warning -ForegroundColor Yellow
Write-Host "Are you SURE you want to continue? (Y/N): " -NoNewline -ForegroundColor Red
$confirm = Read-Host

if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Log "Reset cancelled by user"
    Write-Host "`nReset cancelled." -ForegroundColor Green
    Start-Sleep -Seconds 3
    exit 0
}

Log "User confirmed reset"

# Create backup reminder
$backupReminder = @"
BACKUP REMINDERS:
- Browser bookmarks and passwords
- Game saves not in Documents
- Application settings you want to keep
- License keys for paid software
"@

Write-Host "`n$backupReminder" -ForegroundColor Cyan
Write-Host "`nPress any key when ready to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Log "Starting Windows Reset with Keep Files..."

try {
    # Method 1: Using systemreset.exe with parameters
    # -factoryreset = Perform factory reset
    # -keepuserdata = Keep user files
    # -quiet = Suppress prompts (automated)
    
    Log "Launching systemreset..."
    $resetArgs = "-factoryreset", "-keepuserdata", "-quiet"
    
    Start-Process -FilePath "systemreset.exe" -ArgumentList $resetArgs -Wait -ErrorAction Stop
    
} catch {
    Log "Primary method failed, trying alternative..."
    
    # Method 2: Using Reset-Computer cmdlet (if available)
    try {
        if (Get-Command Reset-Computer -ErrorAction SilentlyContinue) {
            Reset-Computer -KeepUserData -Confirm:$false
        } else {
            # Method 3: Direct WMI call
            Log "Using WMI method..."
            $resetNamespace = "root\wmi"
            $resetClass = Get-WmiObject -Namespace $resetNamespace -Class SystemRestore -List
            
            if ($resetClass) {
                $resetClass.Reset($true) # $true = keep user data
            } else {
                throw "No reset method available"
            }
        }
    } catch {
        Log "ERROR: $($_.Exception.Message)"
        
        # Fallback: Open Windows Settings to Reset page
        Log "Opening Windows Settings Reset page..."
        Start-Process "ms-settings:recovery"
        
        Write-Host "`nAutomatic reset failed. Please use the Windows Settings page that just opened." -ForegroundColor Red
        Write-Host "Click 'Reset this PC' and choose 'Keep my files'" -ForegroundColor Yellow
        Start-Sleep -Seconds 10
    }
}

Log "Reset process initiated"
Write-Host "`nWindows Reset has been initiated. Your PC will restart shortly." -ForegroundColor Green
Write-Host "The reset process will take 30-60 minutes." -ForegroundColor Cyan
Start-Sleep -Seconds 5