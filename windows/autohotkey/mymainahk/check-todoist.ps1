$todoist = Get-Process | Where-Object { $_.ProcessName -like '*Todoist*' }
if ($todoist) {
    Write-Host "SUCCESS - Todoist is running!" -ForegroundColor Green
    $todoist | Select-Object ProcessName, Id | Format-Table
} else {
    Write-Host "Todoist is not running" -ForegroundColor Yellow
}
