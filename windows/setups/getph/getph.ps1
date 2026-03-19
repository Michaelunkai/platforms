<#
.SYNOPSIS
    getph - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$cs = Get-WmiObject -Class Win32_ComputerSystem -EnableAllPrivileges; $cs.AutomaticManagedPagefile = $true; $cs.Put()
