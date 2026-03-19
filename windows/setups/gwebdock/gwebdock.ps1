<#
.SYNOPSIS
    gwebdock - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$dir = 'C:\Program Files\Webdock.io'; if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir }; Invoke-WebRequest -Uri 'https://cli-src.webdock.tech/dl/windows/webdock.exe' -OutFile "$dir\webdock.exe"; $path = [Environment]::GetEnvironmentVariable('Path', 'Machine'); if ($path -notlike "*$dir*") { [Environment]::SetEnvironmentVariable('Path', "$path;$dir", 'Machine') }; $env:PATH += ";$dir"; webdock init --token ab452097d2e918ca745c41f02cd40bcccf759558f9bffe4b24951592ffb5c6c3 ; webdock servers list
