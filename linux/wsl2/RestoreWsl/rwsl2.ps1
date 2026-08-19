# Restores the localai distribution from the fast VHD archive, then opens it.
function rwsl2 {
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param(
        [string] $Distribution = 'localai',
        [string] $InstallRoot = 'C:\wsl2\localai',
        [string] $ArchivePath = 'F:\backup\linux\wsl\localai.vhd',
        [switch] $Force,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]] $Arguments
    )

    if (-not $PSCmdlet.ShouldProcess($Distribution, "Unregister, restore from '$ArchivePath', and open the WSL distribution")) {
        return
    }

    rws2 -Distribution $Distribution -InstallRoot $InstallRoot -ArchivePath $ArchivePath -Force
    $wslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
    & $wslExe -d $Distribution @Arguments
}

if ($MyInvocation.InvocationName -ne '.') {
    & 'rwsl2' @args
}
