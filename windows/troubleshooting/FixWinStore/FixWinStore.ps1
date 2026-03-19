<#
.SYNOPSIS
    FixWinStore
#>
Write-Output "`n=== Repairing Microsoft Store ===`n" -ForegroundColor Cyan
    try {
        Stop-Service -Name 'BITS','wuauserv' -Force -ErrorAction Stop
        Get-AppxPackage -AllUsers -Name Microsoft.WindowsStore | Remove-AppxPackage -ErrorAction SilentlyContinue
        Start-Process 'wsreset.exe' -Wait             # no /silent switch; wait until it closes
        Get-ChildItem 'C:\Program Files\WindowsApps' -Filter '*WindowsStore*' -Directory |
            ForEach-Object {
                Add-AppxPackage -DisableDevelopmentMode -Register "$($_.FullName)\AppXManifest.xml" -Verbose
            }
    }
    finally {
        Start-Service -Name 'BITS','wuauserv'
    }
    Write-Output "`n? Microsoft Store reinstalled - reboot Windows to finish.`n" -ForegroundColor Green
