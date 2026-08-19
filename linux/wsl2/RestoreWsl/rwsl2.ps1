# Generated for the localai.tar variant of rwsl (2026-08-19).
function rwsl2 {
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param(
        [string] $Distribution = 'localai',
        [string] $InstallRoot = 'C:\wsl2\localai',
        [string] $ArchivePath = 'F:\backup\linux\wsl\localai.tar',
        [switch] $Force,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]] $Arguments
    )

    if (-not $PSCmdlet.ShouldProcess($Distribution, "Unregister, restore from '$ArchivePath', and open the WSL distribution")) {
        return
    }

    $progressId = 7542
    try {
        Write-Progress -Id $progressId -Activity 'WSL restore and open' -Status 'Restoring distribution' -PercentComplete 5
        rws2 -Distribution $Distribution -InstallRoot $InstallRoot -ArchivePath $ArchivePath -Force
        Write-Progress -Id $progressId -Activity 'WSL restore and open' -Status 'Opening restored distribution' -PercentComplete 90
        $wslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
        & $wslExe -d $Distribution @Arguments
    } finally {
        Write-Progress -Id $progressId -Completed
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    & 'rwsl2' @args
}
