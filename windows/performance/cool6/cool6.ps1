<#
.SYNOPSIS
    cool6
#>
Set-CoolingMode -ThrottleMode "Performance" -PowerPlan "UltimatePerfA" -CPUMin 70 -CPUMax 100 -KillHeavyProcesses $false -Label "COOL6 (Performance - High)" -Color "DarkCyan"
