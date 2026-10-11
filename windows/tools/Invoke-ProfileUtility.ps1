<#
    .SYNOPSIS
        Shared profile utility dispatcher (restored).
    .DESCRIPTION
        Target of Invoke-CodexWindowsProfileUtility. Dispatches -Action values
        to the real implementations under Platforms/windows/tools.
        Restored 2026-09-17 to fix `unlock` and `endtask` (both candidate paths were missing).
        2026-09-21: restored `GetChocolatey` (getcho) which the 09-17 restore dropped.
        2026-09-21: added `RemoveGameBar` so `rmgamebar` no longer throws
        "Unknown profile utility action: RemoveGameBar".
        2026-09-22: added `Downloads` (gdownloads) restoring the Downloads
        folder to F:\Downloads. The original gdownloads body was replaced by a
        dispatcher call but the action case was never added.
    #>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Action,
    [object[]]$Arguments = @()
)

$toolsRoot = Split-Path -Parent $PSCommandPath
switch ($Action) {
    'Unlock' {
        $script = Join-Path $toolsRoot 'unlock\unlock.ps1'
        if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
            throw "Unlock implementation is missing: $script"
        }
        & $script @Arguments
    }
    'GetChocolatey' {
        $candidates = @(
            (Join-Path $toolsRoot '..\setups\chocolatey\getcho.ps1'),
            (Join-Path $toolsRoot '..\setups\getcho\getcho.ps1'),
            'C:\Users\Admin\Documents\WindowsPowerShell\Platforms\windows\setups\chocolatey\getcho.ps1',
            'C:\Users\Admin\Documents\WindowsPowerShell\Platforms\windows\setups\getcho\getcho.ps1'
        )
        $script = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if (-not $script) {
            throw ("GetChocolatey implementation is missing. Checked: " + ($candidates -join '; '))
        }
        & $script @Arguments
    }
    'EndTask' {
        $script = Join-Path $toolsRoot 'endtask\endtask.ps1'
        if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
            throw "EndTask implementation is missing: $script"
        }
        & $script @Arguments
    }
    'Downloads' {
        New-Item -Path 'F:\Downloads' -ItemType Directory -Force | Out-Null
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name '{374DE290-123F-4565-9164-39C4925E467B}' -Value 'F:\Downloads'
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' -Name '{374DE290-123F-4565-9164-39C4925E467B}' -Value 'F:\Downloads'
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process
    }
    'RemoveGameBar' {
        $candidates = @(
            (Join-Path $toolsRoot 'rmgamebar\rmgamebar.ps1'),
            (Join-Path $toolsRoot 'RemoveGameBar\RemoveGameBar.ps1'),
            (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Shells\powershell\scripts\remove\rmgamebar\rmgamebar.ps1'),
            (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Shells\powershell\scripts\misc\rmgamebar\rmgamebar.ps1'),
            'F:\study\repos\shells\powershell\scripts\remove\rmgamebar\rmgamebar.ps1',
            'F:\study\repos\shells\powershell\scripts\misc\rmgamebar\rmgamebar.ps1'
        )
        $script = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if ($script) {
            & $script @Arguments
        }
        else {
            Get-AppxPackage -Name '*Microsoft.XboxGamingOverlay*' | Remove-AppxPackage -ErrorAction SilentlyContinue
        }
    }
    default {
        throw "Unknown profile utility action: $Action"
    }
}
