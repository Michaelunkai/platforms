<#
.SYNOPSIS
    gobs - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$latest = (Invoke-RestMethod "https://api.github.com/repos/obsproject/obs-studio/releases/latest").assets | Where-Object {$_.name -like "*Windows.zip"}; $obsDir = "F:\backup\windowsapps\installed\OBS-Studio"; New-Item -ItemType Directory -Path $obsDir -Force; Invoke-WebRequest -Uri $latest.browser_download_url -OutFile "$obsDir\obs.zip"; Expand-Archive -Path "$obsDir\obs.zip" -DestinationPath $obsDir -Force; Remove-Item "$obsDir\obs.zip"; Start-Process "$obsDir\bin\64bit\obs64.exe"
