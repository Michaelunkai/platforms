<#
.SYNOPSIS
    disadmin - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0
