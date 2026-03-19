<#
.SYNOPSIS
    sss
#>
param (
        [int]$seconds
    )
    # Command to send rtcwake with the specified seconds
    $command = "ssh root@192.168.1.222 `"nohup sudo rtcwake -m mem -s $seconds >/dev/null 2>&1 &`""
    Invoke-Expression $command
