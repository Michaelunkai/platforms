<#
.SYNOPSIS
    geverything - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $dir = "F:\backup\windowsapps\installed\Everything"; New-Item $dir -ItemType Directory -Force | Out-Null; iwr "https://www.voidtools.com/Everything-1.4.1.1026.x64.zip" -OutFile "$dir.zip"; Expand-Archive "$dir.zip" $dir -Force; Remove-Item "$dir.zip"; Start-Process "$dir\Everything.exe" -Verb RunAs
