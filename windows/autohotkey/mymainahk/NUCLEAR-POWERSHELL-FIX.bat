@echo off
echo ================================================
echo NUCLEAR POWERSHELL FIX - GRANTS ALL PERMISSIONS
echo ================================================
echo.
echo This will grant EVERYONE full access to PowerShell
echo.

:: Take ownership
takeown /F "C:\Windows\System32\WindowsPowerShell" /R /D Y

:: Grant everyone full access
icacls "C:\Windows\System32\WindowsPowerShell" /grant Everyone:F /T /C /Q
icacls "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" /grant Everyone:F /C /Q

:: Reset execution policy
powershell -Command "Set-ExecutionPolicy Bypass -Scope LocalMachine -Force"
powershell -Command "Set-ExecutionPolicy Bypass -Scope CurrentUser -Force"

:: Disable WDAC if active
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v "Enabled" /t REG_DWORD /d 0 /f

:: Disable AppLocker
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\SrpV2" /v "ExecutionPolicy" /t REG_DWORD /d 0 /f

echo.
echo ================================================
echo DONE - Try PowerShell now!
echo ================================================
pause
