<#
.SYNOPSIS
    cool4
#>
Set-CoolingMode -ThrottleMode "Performance" -PowerPlan "Balanced" -CPUMin 20 -CPUMax 80 -KillHeavyProcesses $false -Label "COOL4 (Performance - Balanced)" -Color "DarkYellow"
