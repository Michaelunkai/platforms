<#
.SYNOPSIS
    grambox - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$latest = (Invoke-RestMethod "https://api.github.com/repos/ramboxapp/download/releases/latest").assets | Where-Object {$_.name -like "*win-x64.exe"}; $ramboxDir = "F:\backup\windowsapps\installed\Rambox"; New-Item -ItemType Directory -Path $ramboxDir -Force; Invoke-WebRequest -Uri $latest.browser_download_url -OutFile "$ramboxDir\Rambox.exe"; Start-Process "$ramboxDir\Rambox.exe"
