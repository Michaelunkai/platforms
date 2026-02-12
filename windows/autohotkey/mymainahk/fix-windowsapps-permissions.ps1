# Fix WindowsApps folder permissions permanently
# Run this script as Administrator

$windowsAppsPath = "C:\Program Files\WindowsApps"
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

Write-Host "Fixing permissions for: $windowsAppsPath" -ForegroundColor Cyan
Write-Host "Current user: $currentUser" -ForegroundColor Cyan

try {
    # Step 1: Take ownership of the folder
    Write-Host "`n[1/3] Taking ownership..." -ForegroundColor Yellow
    takeown /F "$windowsAppsPath" /R /D Y | Out-Null

    # Step 2: Grant full control to current user
    Write-Host "[2/3] Granting permissions..." -ForegroundColor Yellow
    icacls "$windowsAppsPath" /grant "${currentUser}:(OI)(CI)F" /T /C /Q | Out-Null

    # Step 3: Verify specific app folders
    Write-Host "[3/3] Verifying app folders..." -ForegroundColor Yellow

    $todoistPath = Get-ChildItem "$windowsAppsPath" -Filter "*Todoist*" -Directory | Select-Object -First 1 -ExpandProperty FullName
    $slackPath = Get-ChildItem "$windowsAppsPath" -Filter "*Slack*" -Directory | Select-Object -First 1 -ExpandProperty FullName

    if ($todoistPath) {
        icacls "$todoistPath" /grant "${currentUser}:(OI)(CI)F" /T /C /Q | Out-Null
        Write-Host "  ✓ Todoist permissions fixed" -ForegroundColor Green
    }

    if ($slackPath) {
        icacls "$slackPath" /grant "${currentUser}:(OI)(CI)F" /T /C /Q | Out-Null
        Write-Host "  ✓ Slack permissions fixed" -ForegroundColor Green
    }

    Write-Host "`n✓ WindowsApps permissions fixed successfully!" -ForegroundColor Green
    Write-Host "You can now run Todoist and Slack directly from their paths." -ForegroundColor Green

} catch {
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure you're running this script as Administrator!" -ForegroundColor Yellow
}

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
