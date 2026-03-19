<#
.SYNOPSIS
    winchk - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
# Fix chkdsk issues - 1 minute
    Start-Process -FilePath "F:\study\Platforms\windows\projects\win11reset\FIX_CHKDSK.bat" -Verb RunAs
