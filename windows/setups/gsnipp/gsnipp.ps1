<#
.SYNOPSIS
    gsnipp - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip.exe; reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ScreenSketch" /v DisableScreenshotBorder /t REG_DWORD /d 1 /f; reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ScreenSketch" /v DefaultSnipType /t REG_DWORD /d 3 /f
