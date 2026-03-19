<#
.SYNOPSIS
    grovo - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
Invoke-WebRequest -Uri https://acli.atlassian.com/windows/latest/acli_windows_amd64/acli.exe -OutFile "$env:USERPROFILE\acli.exe"; $env:PATH += ";$env:USERPROFILE"; [Environment]::SetEnvironmentVariable("PATH", $env:PATH, "User"); echo 'ATATT3xFfGF0qSsOObJuTKcDC9_hhMtzRAVw3Gh_ncv9qZHU5UA7zn9iWQkCrY3tcRXcESdg-P5sdyh4fR5-WFEedanVu4pCNC4LQcTzh-7gJc_iT9rnSQv_NM-_PFVh5xhlKkKfla7c25Kawzlcc58Sx3ysdoCOnxCs26JJq96gbi7bhLz2b_o=A1CE43FC' | & "$env:USERPROFILE\acli.exe" rovodev auth login --email 'mishaelovsky5@gmail.com' --token; acli rovodev run --yolo
