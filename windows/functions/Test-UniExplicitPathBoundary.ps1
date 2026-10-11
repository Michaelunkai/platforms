$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')
$link=Join-Path $env:TEMP ('uni-boundary-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -Path $link -ItemType Junction -Target (Join-Path $env:WINDIR 'Temp') -Force | Out-Null
    if(Test-UniSafeRoot $link){throw 'Junction was incorrectly classified as a safe C: root'}
    $threw=$false
    try { uni $link '--dry-run' } catch { $threw=$true; if($_.Exception.Message -notlike 'Unsafe explicit app path:*'){throw} }
    if(-not $threw){throw 'Unsafe C: explicit path was accepted instead of rejected'}
    Write-Output 'UNI_EXPLICIT_PATH_BOUNDARY_TEST_OK'
} finally {
    if(Test-Path -LiteralPath $link){[IO.Directory]::Delete($link,$false)}
}
