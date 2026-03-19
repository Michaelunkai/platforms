<#
.SYNOPSIS
    coolmin
#>
Set-CoolingMode -ThrottleMode "Silent" -PowerPlan "Balanced" -CPUMin 5 -CPUMax 30 -KillHeavyProcesses $false -Label "COOLMIN (Silent - Minimum Heat)" -Color "Green"
