@echo off
title Windows 11 Reset - Keep Files
color 0E
echo.
echo  ==========================================
echo   WINDOWS 11 RESET - KEEP FILES
echo  ==========================================
echo.
echo  This will reset Windows 11:
echo  [✓] KEEPS: Personal files
echo  [✗] REMOVES: All programs
echo  [✗] REMOVES: All settings
echo.
echo  Launching as Administrator...
echo.
powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%~dp0Win11ResetKeepFiles.ps1\"' -Verb RunAs"