<#
.SYNOPSIS
    cool2
#>
Set-CoolingMode -ThrottleMode "Silent" -PowerPlan "Balanced" -CPUMin 5 -CPUMax 50 -KillHeavyProcesses $false -Label "COOL2 (Silent - Low Power)" -Color "DarkGreen"
