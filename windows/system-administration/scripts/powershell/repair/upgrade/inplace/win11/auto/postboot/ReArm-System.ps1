# ReArm-System.ps1 - PSv5: re-creates post-boot AtLogOn triggers lost across upgrade reboots.
$ErrorActionPreference = 'Continue'
$completedMarker = Join-Path $PSScriptRoot 'upgrade-completed.marker'
if (-not (Test-Path -LiteralPath $completedMarker)) { exit 0 }
$setupState = Get-ItemProperty 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue
if ($setupState.SystemSetupInProgress -or $setupState.OOBEInProgress) { exit 0 }
$runnerPath = Join-Path $PSScriptRoot 'Run-Terminal-WindowsOld-Cleanup.cmd'
$runValueName = 'WinSetupPostBootWindowsOldCleanup'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runOnceKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$rearmTaskName = 'WinSetupPostBootReArmSystem'
$desktopReadyMarker = Join-Path $PSScriptRoot 'desktop-ready.marker'
$checkPath = Join-Path $PSScriptRoot 'rearm-check.json'
$taskNames = @('WinSetupPostBootWindowsOldCleanup', 'WinSetupPostBootWindowsOldCleanupRetry')
$taskResults = @()
foreach ($taskName in $taskNames) {
    $query = schtasks.exe /Query /TN $taskName /FO LIST 2>$null
    $exists = ($LASTEXITCODE -eq 0 -and $query)
    if (-not $exists) {
        schtasks.exe /Create /TN $taskName /TR "`"$runnerPath`"" /SC ONLOGON /RL HIGHEST /F >$null 2>$null
        $query = schtasks.exe /Query /TN $taskName /FO LIST 2>$null
        $exists = ($LASTEXITCODE -eq 0 -and $query)
    }
    $taskResults += [ordered]@{ Name = $taskName; Present = [bool]$exists }
}
$runValue = Get-ItemProperty -Path $runKey -Name $runValueName -ErrorAction SilentlyContinue
$runOnceValue = Get-ItemProperty -Path $runOnceKey -Name $runValueName -ErrorAction SilentlyContinue
if (-not $runValue) {
    New-ItemProperty -Path $runKey -Name $runValueName -Value "`"$runnerPath`"" -PropertyType String -Force | Out-Null
}
if (-not $runOnceValue) {
    New-ItemProperty -Path $runOnceKey -Name $runValueName -Value "`"$runnerPath`"" -PropertyType String -Force | Out-Null
}
$runPresent = [bool](Get-ItemProperty -Path $runKey -Name $runValueName -ErrorAction SilentlyContinue)
$runOncePresent = [bool](Get-ItemProperty -Path $runOnceKey -Name $runValueName -ErrorAction SilentlyContinue)
$rearmRemoved = $false
if (Test-Path -LiteralPath $desktopReadyMarker) {
    schtasks.exe /Delete /TN $rearmTaskName /F >$null 2>$null
    $rearmRemoved = $true
}
$check = [ordered]@{
    Timestamp = (Get-Date -Format s)
    CompletedMarker = (Test-Path -LiteralPath $completedMarker)
    Tasks = $taskResults
    RunPresent = $runPresent
    RunOncePresent = $runOncePresent
    DesktopReady = (Test-Path -LiteralPath $desktopReadyMarker)
    RearmTaskRemoved = $rearmRemoved
}
$check | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $checkPath -Encoding ASCII -Force
exit 0
