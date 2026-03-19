Write-Host "Waiting 5 seconds for Todoist to launch..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$todoist = Get-Process | Where-Object { $_.ProcessName -like '*Todoist*' }

if ($todoist) {
    Write-Host "`nSUCCESS! Todoist is running!" -ForegroundColor Green
    Write-Host "Process count: $($todoist.Count)" -ForegroundColor Cyan
    $todoist | Select-Object ProcessName, Id | Format-Table -AutoSize
} else {
    Write-Host "`nTodoist did not launch or crashed." -ForegroundColor Red
}
