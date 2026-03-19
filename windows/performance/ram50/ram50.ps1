<#
.SYNOPSIS
    ram50
#>
Get-Process | Sort-Object -Property WS -Descending | Select-Object -First 50 Name, @{N='Memory(MB)';E={[math]::Round($_.WS/1MB,2)}}
