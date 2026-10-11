# Hardware-aware maximum-performance power-plan configuration.
# Every setting is capability-checked before it is applied, so Windows builds
# that omit a legacy setting do not emit powercfg errors.
[CmdletBinding()]
param([switch]$SelfTest)

$powerCfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
if (-not (Test-Path -LiteralPath $powerCfg -PathType Leaf)) {
    throw "powercfg.exe was not found: $powerCfg"
}

function Invoke-PowerCfgChecked {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    $output = @(& $powerCfg @Arguments 2>&1)
    $code = [int]$LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFailure) {
        throw ("powercfg {0} failed with exit code {1}: {2}" -f ($Arguments -join ' '), $code, (($output | ForEach-Object { [string]$_ }) -join ' '))
    }
    [pscustomobject]@{ ExitCode = $code; Output = @($output) }
}

$schemes = (Invoke-PowerCfgChecked -Arguments @('/list')).Output -join "`n"
$preferred = @(
    'e9a42b02-d5df-448d-aa00-03f14749eb61',
    '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c',
    '381b4222-f694-41f0-9685-ff5bb260df2e'
)
$schemeGuid = $preferred | Where-Object { $schemes -match [regex]::Escape($_) } | Select-Object -First 1
if (-not $schemeGuid) { throw 'No usable Windows power scheme was found.' }

$query = (Invoke-PowerCfgChecked -Arguments @('/query', $schemeGuid)).Output -join "`n"
$settings = @(
    @{ Label = 'Processor minimum'; Subgroup = '54533251-82be-4824-96c1-47b60b740d00'; Setting = '893dee8e-2bef-41e0-89c6-b55d0929964c'; Value = 100 },
    @{ Label = 'Processor maximum'; Subgroup = '54533251-82be-4824-96c1-47b60b740d00'; Setting = 'bc5038f7-23e-4960-96da-33abaf5935ec'; Value = 100 },
    @{ Label = 'System cooling policy'; Subgroup = '54533251-82be-4824-96c1-47b60b740d00'; Setting = '94d3a615-a899-4ac5-ae2b-e4d8f634367f'; Value = 1 },
    @{ Label = 'PCIe link-state power management'; Subgroup = '501a4d13-42af-4429-9fd1-a8218c268e20'; Setting = 'ee12f906-d277-404b-b6da-e5fa1a576df5'; Value = 0 },
    @{ Label = 'USB selective suspend'; Subgroup = '2a737441-1930-4402-8d77-b2bebba308a3'; Setting = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'; Value = 0 },
    @{ Label = 'Disk idle timeout'; Subgroup = '0012ee47-9041-4b5d-9b77-535fba8b1442'; Setting = '6738e2c4-e8a5-4a42-b16a-e040e769756e'; Value = 0 }
)

if ($SelfTest) {
    $supported = @($settings | Where-Object { $query -match [regex]::Escape($_.Setting) }).Count
    Write-Output ("POWERPLANS_SELFTEST_OK executable=[{0}] scheme=[{1}] supported_settings={2}/{3}" -f $powerCfg, $schemeGuid, $supported, $settings.Count)
    $global:LASTEXITCODE = 0
    return
}

Write-Host 'MAXIMUM PERFORMANCE MODE - APPLYING SUPPORTED SETTINGS' -ForegroundColor Red
Invoke-PowerCfgChecked -Arguments @('/setactive', $schemeGuid) | Out-Null

foreach ($timeout in @('monitor-timeout-ac','monitor-timeout-dc','standby-timeout-ac','standby-timeout-dc','hibernate-timeout-ac','hibernate-timeout-dc','disk-timeout-ac','disk-timeout-dc')) {
    $result = Invoke-PowerCfgChecked -Arguments @('/change', $timeout, '0') -AllowFailure
    if ($result.ExitCode -ne 0) {
        Write-Host ("  [SKIP] {0}: unsupported on this Windows build" -f $timeout) -ForegroundColor DarkYellow
    }
}

foreach ($setting in $settings) {
    if ($query -notmatch [regex]::Escape($setting.Setting)) {
        Write-Host ("  [SKIP] {0}: setting is not exposed by this power scheme" -f $setting.Label) -ForegroundColor DarkYellow
        continue
    }
    Invoke-PowerCfgChecked -Arguments @('/setacvalueindex', $schemeGuid, $setting.Subgroup, $setting.Setting, [string]$setting.Value) | Out-Null
    Invoke-PowerCfgChecked -Arguments @('/setdcvalueindex', $schemeGuid, $setting.Subgroup, $setting.Setting, [string]$setting.Value) | Out-Null
    Write-Host ("  [OK] {0}" -f $setting.Label) -ForegroundColor Green
}

Invoke-PowerCfgChecked -Arguments @('/setactive', $schemeGuid) | Out-Null
$active = (Invoke-PowerCfgChecked -Arguments @('/getactivescheme')).Output -join ' '
if ($active -notmatch [regex]::Escape($schemeGuid)) {
    throw "Power plan activation could not be verified: expected $schemeGuid"
}
Write-Host ("POWERPLANS_OK active_scheme={0}" -f $schemeGuid) -ForegroundColor Green
$global:LASTEXITCODE = 0
