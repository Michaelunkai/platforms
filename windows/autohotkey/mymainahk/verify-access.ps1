# Wait and verify access
Start-Sleep -Seconds 15

Write-Host "Verifying C Drive Access..." -ForegroundColor Cyan

# Test 1: Can we access WindowsApps?
$windowsApps = "C:\Program Files\WindowsApps"
try {
    $items = Get-ChildItem $windowsApps -ErrorAction Stop
    Write-Host "SUCCESS - WindowsApps accessible - Found $($items.Count) items" -ForegroundColor Green
} catch {
    Write-Host "FAILED - WindowsApps still blocked: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Can we run Todoist?
$todoistPath = Get-ChildItem "$windowsApps" -Filter "*Todoist*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if ($todoistPath) {
    $todoistExe = Join-Path $todoistPath "app\Todoist.exe"
    Write-Host "Testing Todoist launch from: $todoistExe" -ForegroundColor Yellow

    try {
        $process = Start-Process $todoistExe -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 2
        if ($process -and !$process.HasExited) {
            Write-Host "SUCCESS! Todoist launched directly!" -ForegroundColor Green
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "FAILED - Todoist still blocked: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test 3: Can we run Slack?
$slackPath = Get-ChildItem "$windowsApps" -Filter "*Slack*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if ($slackPath) {
    $slackExe = Join-Path $slackPath "app\Slack.exe"
    Write-Host "Testing Slack launch from: $slackExe" -ForegroundColor Yellow

    try {
        $process = Start-Process $slackExe -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 2
        if ($process -and !$process.HasExited) {
            Write-Host "SUCCESS! Slack launched directly!" -ForegroundColor Green
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "FAILED - Slack still blocked: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Verification complete!" -ForegroundColor Cyan
