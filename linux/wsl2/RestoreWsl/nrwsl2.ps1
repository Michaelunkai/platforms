# Exports (syncs) the current distribution to the fast VHD archive first,
# then restores and opens it (same as rwsl2, but with an export up front).
function nrwsl2 {
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param(
        [string] $Distribution = 'localai',
        [string] $InstallRoot = 'C:\wsl2\localai',
        [string] $ArchivePath = 'F:\backup\linux\wsl\localai.vhd',
        [switch] $Force,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]] $Arguments
    )

    if (-not $PSCmdlet.ShouldProcess($Distribution, "Export current state, then unregister, restore from '$ArchivePath', and open the WSL distribution")) {
        return
    }

    nrws2 -Distribution $Distribution -ArchivePath $ArchivePath -Force
    rwsl2 -Distribution $Distribution -InstallRoot $InstallRoot -ArchivePath $ArchivePath -Force @Arguments
}

if ($MyInvocation.InvocationName -ne '.') {
    & 'nrwsl2' @args
}
