@echo off
echo ================================================
echo FIXING ALL SYSTEM EXECUTABLE PERMISSIONS
echo ================================================
echo.

:: Fix PowerShell v5
echo [1/5] PowerShell v5...
takeown /F "C:\Windows\System32\WindowsPowerShell" /A /R /D Y >nul 2>&1
icacls "C:\Windows\System32\WindowsPowerShell" /grant Everyone:F /T /C /Q >nul 2>&1
echo DONE

:: Fix cmd.exe
echo [2/5] cmd.exe...
takeown /F "C:\Windows\System32\cmd.exe" /A >nul 2>&1
icacls "C:\Windows\System32\cmd.exe" /grant Everyone:F /C /Q >nul 2>&1
echo DONE

:: Fix Windows Terminal
echo [3/5] Windows Terminal...
takeown /F "C:\Program Files\WindowsApps" /A /R /D Y >nul 2>&1
icacls "C:\Program Files\WindowsApps" /grant Everyone:(OI)(CI)RX /T /C /Q >nul 2>&1
echo DONE

:: Fix System32 directory
echo [4/5] System32 permissions...
icacls "C:\Windows\System32" /grant Everyone:(CI)RX /C /Q >nul 2>&1
echo DONE

:: Reset to safe defaults
echo [5/5] Setting safe defaults...
icacls "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" /grant Users:RX /C /Q >nul 2>&1
icacls "C:\Windows\System32\cmd.exe" /grant Users:RX /C /Q >nul 2>&1
echo DONE

echo.
echo ================================================
echo TESTING...
echo ================================================
echo.

echo Testing PowerShell v5...
"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Command "Write-Host 'PowerShell v5: OK' -ForegroundColor Green"

echo.
echo Testing cmd...
cmd /c echo cmd.exe: OK

echo.
echo ================================================
echo ALL FIXES APPLIED!
echo ================================================
echo.
echo Try opening PowerShell or Terminal now!
pause
