<#
.SYNOPSIS
    cool3
#>
Set-CoolingMode -ThrottleMode "Silent" -PowerPlan "Balanced" -CPUMin 10 -CPUMax 70 -KillHeavyProcesses $false -Label "COOL3 (Silent - Moderate)" -Color "Yellow"
