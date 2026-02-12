@echo off
echo FIXING POWERSHELL V5 PERMANENTLY...
echo.

:: Take ownership of entire PowerShell directory
takeown /F "C:\Windows\System32\WindowsPowerShell" /A /R /D Y

:: Grant EVERYONE full access
icacls "C:\Windows\System32\WindowsPowerShell" /grant Everyone:F /T /C /Q
icacls "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" /grant Everyone:F /C /Q
icacls "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" /grant Users:F /C /Q
icacls "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" /grant "Authenticated Users":F /C /Q

:: Remove inheritance restrictions
icacls "C:\Windows\System32\WindowsPowerShell" /inheritance:e /T /C /Q

echo.
echo TESTING POWERSHELL V5...
"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Command "Write-Host 'POWERSHELL V5 WORKS!' -ForegroundColor Green"

echo.
echo DONE!
pause
