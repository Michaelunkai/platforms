@echo off
echo Testing Todoist launch...
start shell:AppsFolder\88449BC3.TodoistPlannerCalendarMSIX_71ef4824z52ta!App
echo.
echo Todoist should have launched!
echo.
timeout /t 2 >nul
echo Testing Slack launch...
start shell:AppsFolder\91750D7E.Slack_8she8kybcnzg4!App
echo.
echo Slack should have launched!
echo.
pause
