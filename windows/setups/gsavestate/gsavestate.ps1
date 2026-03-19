<#
.SYNOPSIS
    gsavestate - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$latest = (Invoke-RestMethod "https://api.github.com/repos/Matteo842/SaveState/releases/latest").assets | Where-Object {$_.name -like "*win.rar"}; $appDir = "F:\backup\windowsapps\installed\SaveState"; New-Item -ItemType Directory -Path $appDir -Force; Invoke-WebRequest -Uri $latest.browser_download_url -OutFile "$appDir\SaveState.rar"
