<#
.SYNOPSIS
    dislog - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$User=(Get-WmiObject -Class Win32_ComputerSystem).UserName;$Pwd="123456";$Reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";Set-ItemProperty -Path $Reg -Name "AutoAdminLogon" -Value "1";Set-ItemProperty -Path $Reg -Name "DefaultUserName" -Value $User;Set-ItemProperty -Path $Reg -Name "DefaultPassword" -Value $Pwd
