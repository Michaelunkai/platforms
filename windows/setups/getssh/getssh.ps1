<#
.SYNOPSIS
    getssh - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Set-Service -Name sshd -StartupType Automatic; Start-Service sshd; if (-not (Get-NetFirewallRule -Name 'sshd' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -Name 'sshd' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 }
