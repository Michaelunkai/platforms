@echo off
REM Paragon Disk Check Automation Launcher
REM Double-click this file to run the complete automation
REM WARNING: This will restart your computer!

title Paragon Disk Check Automation
color 0E

echo ========================================================================
echo    PARAGON HARD DISK MANAGER - AUTOMATED DISK CHECK
echo ========================================================================
echo.
echo    WARNING: This script will RESTART YOUR COMPUTER automatically!
echo    Save all work before continuing.
echo.
echo ========================================================================
echo.

pause

echo.
echo Starting automation...
echo.

python "%~dp0run_paragon_disk_check.py"

if errorlevel 1 (
    echo.
    echo ========================================================================
    echo    ERROR: Automation failed!
    echo ========================================================================
    pause
    exit /b 1
)

exit /b 0
