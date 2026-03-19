Start-Sleep -Seconds 5
try {
    Start-Process 'C:\Program Files\WindowsApps\88449BC3.TodoistPlannerCalendarMSIX_9.26.2.0_x64__71ef4824z52ta\app\Todoist.exe' -ErrorAction Stop
    Write-Host 'SUCCESS - Todoist launched!' -ForegroundColor Green
} catch {
    Write-Host "Still blocked: $($_.Exception.Message)" -ForegroundColor Red
}
