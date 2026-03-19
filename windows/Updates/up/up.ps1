<#
.SYNOPSIS
    up - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
ccpatch; Start-Process cleanmgr.exe; Start-Process "ms-settings:storagesense"; Start-Process "$env:SystemRoot\System32\dfrgui.exe"; cd C:\users\micha\desktop\cleanup; $shortcuts = Get-ChildItem -Filter *.lnk; $shortcuts | ForEach-Object { Start-Process $_.FullName }; Write-Output "Total processes started: $($shortcuts.Count)";  irm "https://christitus.com/win" | iex
