<#
.SYNOPSIS
    cool7
#>
Set-CoolingMode -ThrottleMode "Turbo" -PowerPlan "UltimatePerfA" -CPUMin 80 -CPUMax 100 -KillHeavyProcesses $false -Label "COOL7 (Turbo - Aggressive Fans)" -Color "Blue"
