@echo off
echo ================================================
echo TESTING POWERSHELL V5 LAUNCH
echo ================================================
echo.
echo Test 1: Launch PowerShell v5...
"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Command "Write-Host 'PowerShell v5 works!' -ForegroundColor Green; $PSVersionTable"
echo.
if %ERRORLEVEL% EQU 0 (
    echo SUCCESS - No errors!
) else (
    echo FAILED - Error code: %ERRORLEVEL%
)
echo.
echo ================================================
pause
