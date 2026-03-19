<#
.SYNOPSIS
    gsystemd - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
wsl --shutdown; wsl --update; wsl -d ubuntu -- bash -c "echo -e '[boot]\nsystemd=true' | sudo tee /etc/wsl.conf"; wsl --shutdown
