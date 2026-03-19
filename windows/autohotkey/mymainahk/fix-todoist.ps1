# Fix Todoist specifically with nuclear permissions

$windowsApps = "C:\Program Files\WindowsApps"
$todoistPath = Get-ChildItem $windowsApps -Filter "*Todoist*" -Directory | Select-Object -First 1 -ExpandProperty FullName
$todoistExe = Join-Path $todoistPath "app\Todoist.exe"
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

Write-Host "Fixing Todoist: $todoistExe" -ForegroundColor Cyan

# Method 1: Take ownership recursively
takeown /F "$todoistPath" /R /A /D Y

# Method 2: Reset ACLs completely
icacls "$todoistPath" /reset /T /C /Q

# Method 3: Grant EVERYONE full access (nuclear option)
icacls "$todoistPath" /grant Everyone:F /T /C /Q
icacls "$todoistPath" /grant $currentUser`:F /T /C /Q
icacls "$todoistPath" /grant Administrators:F /T /C /Q
icacls "$todoistPath" /grant SYSTEM:F /T /C /Q

# Method 4: Specific exe file permissions
icacls "$todoistExe" /grant Everyone:F /C /Q
icacls "$todoistExe" /grant $currentUser`:F /C /Q

# Method 5: Remove ALL restrictions
icacls "$todoistExe" /remove:d Everyone /C /Q
icacls "$todoistExe" /grant Everyone:F /C /Q

Write-Host "`nTesting Todoist launch..." -ForegroundColor Yellow

try {
    $process = Start-Process $todoistExe -PassThru -ErrorAction Stop
    Start-Sleep -Seconds 2
    if ($process -and !$process.HasExited) {
        Write-Host "SUCCESS! Todoist works!" -ForegroundColor Green
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nThis is a UWP app protection issue. The exe cannot run outside its app container." -ForegroundColor Yellow
    Write-Host "Even with full permissions, Windows blocks UWP .exe files from direct execution." -ForegroundColor Yellow
}
