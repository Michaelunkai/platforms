# Read-only regression checks: does not start Windows Setup or cleanup.
$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'repair-upgrade.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors -join [Environment]::NewLine) }
foreach ($name in @('New-SetupUpgradeArguments', 'Convert-RepairUpgradeExitCodeToHex', 'Get-RepairUpgradeBlueBoxSnapshot')) {
    $definition = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | Where-Object Name -eq $name
    Invoke-Expression $definition.Extent.Text
}
$script:RepairUpgradePostBootRoot = Join-Path $PSScriptRoot 'postboot'
$arguments = New-SetupUpgradeArguments
if ('/Quiet' -in $arguments) { throw 'Default must show the real full-screen Windows Setup UI: /Quiet must be absent.' }
if ('/PostOOBE' -notin $arguments -or '/Auto' -notin $arguments) { throw 'Unattended upgrade arguments missing.' }
$quietArguments = New-SetupUpgradeArguments -Quiet
if ('/Quiet' -notin $quietArguments) { throw '-Quiet must add /Quiet for opt-in silent mode.' }
if ((Convert-RepairUpgradeExitCodeToHex -2147024883) -ne '0x8007000D') { throw 'Signed Setup error conversion failed.' }
$snapshot = Get-RepairUpgradeBlueBoxSnapshot -Since (Get-Date).AddDays(1)
if ($snapshot.MainHrHex -or $snapshot.ProcessExitHex -or $snapshot.DynamicUpdateDetected) { throw 'Old log entries leaked into a new attempt.' }
# Exercise the Windows process API used for a launcher that exits immediately.
$process = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList '/d /c exit 13' -WindowStyle Hidden -PassThru
$null = $process.Handle
$process.WaitForExit()
if ($process.ExitCode -ne 13) { throw 'Fast native process exit code was lost.' }
foreach ($file in (Get-ChildItem -LiteralPath $script:RepairUpgradePostBootRoot -Filter '*.ps1')) {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors) { throw "$($file.Name): $errors" }
}
Write-Output 'PASS: unattended arguments, signed errors, stale-log isolation, immediate exit codes, generated script parsing.'
