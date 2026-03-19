<#
.SYNOPSIS
    sss2
#>
[CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$WakeTime
    )
    # Construct the remote command.
    # The remote command should look like:
    #   nohup sudo rtcwake -m mem -t $(date -d 'HH:MM' +%s) >/dev/null 2>&1 &
    #
    # We use single quotes for the PowerShell string and concatenate in $WakeTime.
    $remoteCommand = 'nohup sudo rtcwake -m mem -t $(date -d ''' + $WakeTime + ''' +%s) >/dev/null 2>&1 &'
    # Execute the SSH command using the constructed remote command.
    ssh root@192.168.1.222 $remoteCommand
