<#
.SYNOPSIS
    rescode - restores all ZCode data from F:\backup\ai\zcode (latest backup)
.DESCRIPTION
    Thin launcher for the standalone engine that travels with the backup
    (F:\backup\ai\zcode\rescode.ps1), so restore works even on a freshly
    reformatted Windows 11. Add -SelfTest to verify backup integrity only.
#>
& 'F:\backup\ai\zcode\rescode.ps1' @args
