<#
.SYNOPSIS
    cool5
#>
Set-CoolingMode -ThrottleMode "Performance" -PowerPlan "Balanced" -CPUMin 50 -CPUMax 90 -KillHeavyProcesses $false -Label "COOL5 (Performance - Standard)" -Color "Cyan"
