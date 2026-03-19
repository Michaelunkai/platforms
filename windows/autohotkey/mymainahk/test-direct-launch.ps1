# Test the direct cmd method that AHK will use

Write-Host "Testing Todoist launch..." -ForegroundColor Cyan
cmd /c start shell:AppsFolder\88449BC3.TodoistPlannerCalendarMSIX_71ef4824z52ta!App

Start-Sleep -Seconds 2

Write-Host "Testing Slack launch..." -ForegroundColor Cyan
cmd /c start shell:AppsFolder\91750D7E.Slack_8she8kybcnzg4!App

Start-Sleep -Seconds 2

Write-Host "`nChecking if apps launched..." -ForegroundColor Yellow

$todoist = Get-Process | Where-Object { $_.ProcessName -like '*Todoist*' }
$slack = Get-Process | Where-Object { $_.ProcessName -like '*Slack*' }

if ($todoist) {
    Write-Host "SUCCESS - Todoist is running!" -ForegroundColor Green
} else {
    Write-Host "FAILED - Todoist not running" -ForegroundColor Red
}

if ($slack) {
    Write-Host "SUCCESS - Slack is running!" -ForegroundColor Green
} else {
    Write-Host "FAILED - Slack not running" -ForegroundColor Red
}
