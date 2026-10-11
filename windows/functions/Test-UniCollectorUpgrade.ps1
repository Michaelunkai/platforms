$__codexSafeAddTypePath = 'F:\study\Platforms\windows\functions\Invoke-CodexSafePowerShellAddType.ps1'
if ([IO.File]::Exists($__codexSafeAddTypePath)) { . $__codexSafeAddTypePath }
$ErrorActionPreference='Stop'
# Reproduce a Verge/PowerShell host that already loaded the previous collector
# and its shared stream-hit result type before this script was updated.
Add-Type -TypeDefinition 'public static class UniSweepCollectV12 { } public sealed class UniSweepStreamHitV1 { }' -ErrorAction Stop
. (Join-Path $PSScriptRoot 'uni.ps1')
$root='C:\Windows\Temp\uni-collector-upgrade-'+[Guid]::NewGuid().ToString('N')
$file=Join-Path $root 'LongUnrelatedResidue.bin'
try {
    [IO.Directory]::CreateDirectory($root) | Out-Null
    [IO.File]::WriteAllText($file,'probe')
    & fsutil.exe file setshortname $file 'VERGE~1' | Out-Null
    if($LASTEXITCODE -ne 0){throw 'fsutil could not assign a deterministic 8.3 alias'}
    Ensure-UniSweepCollect
    if($script:UniSweepCollectorType.Name -ne 'UniSweepCollectV13'){throw ('collector was not upgraded: '+$script:UniSweepCollectorType.FullName)}
    if(-not (Test-UniSweepCandidateName $file '^VERGE~1$')){throw 'upgraded collector missed the 8.3 alias'}
    'UNI_COLLECTOR_UPGRADE_TEST_OK'
} finally {if(Test-Path -LiteralPath $root -ErrorAction SilentlyContinue){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}}
