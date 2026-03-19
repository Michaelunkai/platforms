@echo off
echo ================================================
echo TESTING WITH CORRECT AppUserModelIds
echo ================================================
echo.
echo Launching Todoist...
start shell:AppsFolder\88449BC3.TodoistPlannerCalendarMSIX_71ef4824z52ta!BC3.TodoistPlannerCalendarMSIX
echo Done!
echo.
timeout /t 3 >nul
echo Launching Slack...
start shell:AppsFolder\91750D7E.Slack_8she8kybcnzg4!Slack
echo Done!
echo.
echo ================================================
echo Both apps should have launched successfully!
echo Check your screen to verify.
echo ================================================
pause
