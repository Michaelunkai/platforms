<#
.SYNOPSIS
    update2
#>
Install-Module PSWindowsUpdate -Force; Import-Module PSWindowsUpdate; Get-WindowsUpdate; Install-WindowsUpdate -AcceptAll -Confirm:$false -AutoReboot
