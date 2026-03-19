<#
.SYNOPSIS
    fixwinget
#>
(Get-Content $PROFILE) | Where-Object { $_ -notmatch 'Microsoft\.DesktopAppInstaller.*winget\.exe' } | Set-Content $PROFILE
