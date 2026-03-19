<#
.SYNOPSIS
    fixtaskbar
#>
Stop-Process -Name explorer -Force; Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*.db","$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache*.db","$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue; ie4uinit.exe -show; Start-Process explorer.exe
