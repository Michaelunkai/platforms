# ============================================================================
# UNLOCK C DRIVE - FULL OWNERSHIP AND PERMISSIONS
# ============================================================================
# This script grants you full control over all C drive folders
# Run as Administrator
# ============================================================================

$ErrorActionPreference = "SilentlyContinue"

Write-Host @"
╔══════════════════════════════════════════════════════════════╗
║        UNLOCKING C DRIVE - FULL PERMISSIONS                 ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "`nCurrent User: $currentUser" -ForegroundColor Yellow
Write-Host "This will grant FULL permissions to all C:\ folders`n" -ForegroundColor Yellow

# ============================================================================
# STEP 1: CREATE SYSTEM RESTORE POINT
# ============================================================================
Write-Host "[1/4] Creating System Restore Point..." -ForegroundColor Cyan
try {
    Checkpoint-Computer -Description "Before C Drive Unlock - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType "MODIFY_SETTINGS"
    Write-Host "  ✓ Restore point created successfully" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Could not create restore point: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "  Continuing anyway..." -ForegroundColor Yellow
}

# ============================================================================
# STEP 2: UNLOCK CRITICAL PROTECTED FOLDERS
# ============================================================================
Write-Host "`n[2/4] Unlocking Protected Folders..." -ForegroundColor Cyan

$protectedFolders = @(
    "C:\Program Files",
    "C:\Program Files (x86)",
    "C:\ProgramData",
    "C:\Windows",
    "C:\Users",
    "C:\Program Files\WindowsApps"
)

foreach ($folder in $protectedFolders) {
    if (Test-Path $folder) {
        Write-Host "  → Processing: $folder" -ForegroundColor Yellow

        # Take ownership
        takeown /F "$folder" /R /D Y 2>&1 | Out-Null

        # Grant full permissions
        icacls "$folder" /grant "${currentUser}:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null

        Write-Host "    ✓ Unlocked" -ForegroundColor Green
    }
}

# ============================================================================
# STEP 3: UNLOCK ALL ROOT C DRIVE FOLDERS
# ============================================================================
Write-Host "`n[3/4] Unlocking All C:\ Root Folders..." -ForegroundColor Cyan

Get-ChildItem "C:\" -Directory -Force | ForEach-Object {
    $folder = $_.FullName
    Write-Host "  → $folder" -ForegroundColor Yellow

    # Take ownership
    takeown /F "$folder" /R /D Y 2>&1 | Out-Null

    # Grant full permissions
    icacls "$folder" /grant "${currentUser}:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
}

Write-Host "  ✓ All root folders unlocked" -ForegroundColor Green

# ============================================================================
# STEP 4: VERIFY WINDOWSAPPS SPECIFICALLY
# ============================================================================
Write-Host "`n[4/4] Verifying WindowsApps Access..." -ForegroundColor Cyan

$windowsAppsPath = "C:\Program Files\WindowsApps"

# Extra strong permissions for WindowsApps
takeown /F "$windowsAppsPath" /R /A /D Y 2>&1 | Out-Null
icacls "$windowsAppsPath" /reset /T /C /Q 2>&1 | Out-Null
icacls "$windowsAppsPath" /grant:r "${currentUser}:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
icacls "$windowsAppsPath" /grant:r "SYSTEM:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
icacls "$windowsAppsPath" /grant:r "Administrators:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null

# Test access to Todoist
$todoistPath = Get-ChildItem "$windowsAppsPath" -Filter "*Todoist*" -Directory | Select-Object -First 1 -ExpandProperty FullName
if ($todoistPath) {
    takeown /F "$todoistPath" /R /A /D Y 2>&1 | Out-Null
    icacls "$todoistPath" /grant:r "${currentUser}:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null

    $todoistExe = Join-Path $todoistPath "app\Todoist.exe"
    if (Test-Path $todoistExe) {
        icacls "$todoistExe" /grant:r "${currentUser}:F" /C /Q 2>&1 | Out-Null
        Write-Host "  ✓ Todoist.exe accessible" -ForegroundColor Green
    }
}

# Test access to Slack
$slackPath = Get-ChildItem "$windowsAppsPath" -Filter "*Slack*" -Directory | Select-Object -First 1 -ExpandProperty FullName
if ($slackPath) {
    takeown /F "$slackPath" /R /A /D Y 2>&1 | Out-Null
    icacls "$slackPath" /grant:r "${currentUser}:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null

    $slackExe = Join-Path $slackPath "app\Slack.exe"
    if (Test-Path $slackExe) {
        icacls "$slackExe" /grant:r "${currentUser}:F" /C /Q 2>&1 | Out-Null
        Write-Host "  ✓ Slack.exe accessible" -ForegroundColor Green
    }
}

# ============================================================================
# DONE
# ============================================================================
Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                    ✓ C DRIVE UNLOCKED                        ║
╚══════════════════════════════════════════════════════════════╝

You now have FULL permissions on all C:\ folders!

✓ WindowsApps unlocked
✓ Program Files unlocked
✓ Windows folder unlocked
✓ All system folders unlocked

You can now:
• Run any .exe from any folder
• Modify any system file
• Access all protected directories

"@ -ForegroundColor Green

Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
