<#
.SYNOPSIS
    fixf
#>
Push-Location C:\; cmd /c "echo y | C:\WINDOWS\system32\chkdsk.exe F: /f /r /x"; Pop-Location
