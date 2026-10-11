$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')
$root='C:\Windows\Temp\uni-short-alias-'+[Guid]::NewGuid().ToString('N')
$file=Join-Path $root 'LongUnrelatedResidue.bin'
try {
    [IO.Directory]::CreateDirectory($root) | Out-Null
    [IO.File]::WriteAllText($file,'probe')
    & fsutil.exe file setshortname $file 'VERGE~1' | Out-Null
    if($LASTEXITCODE -ne 0){throw 'fsutil could not assign a deterministic 8.3 alias'}
    Ensure-UniSweepCollect
    if(-not [UniSweepCollectV12]::PathNameMatches($file,'^VERGE~1$')){throw 'collector alias matcher missed VERGE~1'}
    if(-not (Ensure-UniShortAliasMatcher)){throw ('fallback alias matcher unavailable: '+$script:UniShortAliasMatcherError)}
    if(-not [UniShortAliasMatcherV1]::Matches($file,'^VERGE~1$')){throw 'fallback alias matcher missed VERGE~1'}
    if(-not (Test-UniSweepCandidateName $file '^VERGE~1$')){throw 'authorization gate discarded an 8.3-only candidate'}
    'UNI_SHORT_ALIAS_COVERAGE_TEST_OK'
} finally {
    if(Test-Path -LiteralPath $root -ErrorAction SilentlyContinue){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
