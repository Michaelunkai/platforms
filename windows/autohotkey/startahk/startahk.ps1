<#
.SYNOPSIS
    startahk
#>
$ahk='F:\study\Platforms\windows\AutoHotkey\myMainAHK\current.ahk';$lnk="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\AutoRun_$([IO.Path]::GetFileNameWithoutExtension($ahk)).lnk";$ws=New-Object -ComObject WScript.Shell;$s=$ws.CreateShortcut($lnk);$s.TargetPath='C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe';$s.Arguments="`"$ahk`"";$s.WorkingDirectory=Split-Path $ahk;$s.Save()
