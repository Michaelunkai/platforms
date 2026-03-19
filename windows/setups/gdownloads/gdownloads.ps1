<#
.SYNOPSIS
    gdownloads - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
New-Item -Path "F:\Downloads" -ItemType Directory -Force; Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}" -Value "F:\Downloads"; Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}" -Value "F:\Downloads"; Get-Process explorer | Stop-Process;
