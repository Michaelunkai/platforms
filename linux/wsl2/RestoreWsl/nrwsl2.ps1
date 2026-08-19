# Exports (syncs) the current WSL distribution to the localai archive first,
# then restores and opens it (same as rwsl2, but with an export up front).
function nrwsl2 {
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param(
        [string] $Distribution = 'localai',
        [string] $InstallRoot = 'C:\wsl2\localai',
        [string] $ArchivePath = 'F:\backup\linux\wsl\localai.tar',
        [switch] $Force,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]] $Arguments
    )

    if (-not $PSCmdlet.ShouldProcess($Distribution, "Export current state, then unregister, restore from '$ArchivePath', and open the WSL distribution")) {
        return
    }

    $progressId = 7562
    try {
        Write-Progress -Id $progressId -Activity 'WSL export then restore and open' -Status 'Exporting current state' -PercentComplete 5
        nrws2 -Distribution $Distribution -ArchivePath $ArchivePath -Force
        Write-Progress -Id $progressId -Activity 'WSL export then restore and open' -Status 'Restoring distribution' -PercentComplete 45
        rwsl2 -Distribution $Distribution -InstallRoot $InstallRoot -ArchivePath $ArchivePath -Force @Arguments
    } finally {
        Write-Progress -Id $progressId -Completed
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    & 'nrwsl2' @args
}
