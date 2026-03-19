<#
.SYNOPSIS
    ws2
#>
param (
        [string]$Command
    )
    wsl --distribution ubuntu --user root -- bash -lic "$Command";     wsl --distribution ubuntu2 --user root -- bash -lic "$Command"
