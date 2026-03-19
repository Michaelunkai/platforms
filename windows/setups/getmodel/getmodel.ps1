<#
.SYNOPSIS
    getmodel - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model
