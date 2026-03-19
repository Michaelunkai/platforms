<#
.SYNOPSIS
    gsniff - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $dir = "F:\backup\windowsapps\installed\SpaceSniffer"; New-Item $dir -ItemType Directory -Force | Out-Null; iwr "https://github.com/redtrillix/SpaceSniffer/releases/download/v1.3.0.2/spacesniffer_1_3_0_2.zip" -OutFile "$dir.zip"; Expand-Archive "$dir.zip" $dir -Force; Remove-Item "$dir.zip"; Start-Process "$dir\SpaceSniffer.exe" -Verb RunAs
