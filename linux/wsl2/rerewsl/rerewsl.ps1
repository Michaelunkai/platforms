<#
.SYNOPSIS
    rerewsl - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
dism.exe /Online /Disable-Feature:Microsoft-Windows-Subsystem-Linux /NoRestart ; dism.exe /Online /Disable-Feature:VirtualMachinePlatform /NoRestart ; wsl --unregister --all ; wsl --shutdown ; reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages\Microsoft-Windows-Subsystem-Linux*" /f ; reg delete "HKLM\SYSTEM\CurrentControlSet\Services\wslservice" /f ; reg delete "HKLM\SYSTEM\CurrentControlSet\Services\wslfs" /f ; del /Q /F /S "%SystemRoot%\System32\wsl*" ; del /Q /F /S "%ProgramFiles%\WSL" ; free "dism.exe /Online /Enable-Feature:Microsoft-Windows-Subsystem-Linux /All /NoRestart ; dism.exe /Online /Enable-Feature:VirtualMachinePlatform /All /NoRestart ; wsl --update ; wsl --set-default- version 2"
