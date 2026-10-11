$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')
$script:UniFailed=New-Object 'System.Collections.Generic.List[string]'
$script:UniProtectedReferences=@()
$script:UniOtherRoots=@()
$script:UniOwnedRoots=@()
$script:UniOwnedFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$script:UniAggressiveSweep=$true
$root=Join-Path $env:TEMP ('uni-hardlink-'+[guid]::NewGuid().ToString('N'))
$original=Join-Path $root 'VergePayload.bin'
$alias=Join-Path $root 'VergePayload-alias.bin'
$taskFile=Join-Path $root 'fixture.job'
$taskAlias=Join-Path $root 'fixture-alias.job'
try {
    New-Item -Path $root -ItemType Directory -Force | Out-Null
    [IO.File]::WriteAllBytes($original,[byte[]](1,2,3,4))
    New-Item -ItemType HardLink -Path $alias -Target $original -Force | Out-Null
    $count=Get-UniHardLinkCount $original
    if($count -lt 2){throw ('Hard-link fixture was not reported with two links: '+$count)}
    if(Test-UniHardLinkSafe $original){throw 'Hard-linked target was incorrectly marked safe'}
    if(-not @($script:UniFailed | Where-Object {$_ -like '*Hard-linked target file*'}).Count){throw 'Hard-link refusal was not recorded'}
    [void]$script:UniOwnedFiles.Add($original)
    if(Remove-UniTarget $original){throw 'Remove-UniTarget incorrectly deleted a hard-linked file'}
    if(-not (Test-Path -LiteralPath $original) -or -not (Test-Path -LiteralPath $alias)){throw 'Hard-link refusal did not preserve both pathnames'}
    [IO.File]::WriteAllText($taskFile,'fixture')
    New-Item -ItemType HardLink -Path $taskAlias -Target $taskFile -Force | Out-Null
    $script:UniTaskStoreRoot=$root
    $entry=[pscustomobject]@{Path='\UniHardLinkFixture';File=$taskFile}
    if(Invoke-UniTaskStoreDeletion $entry){throw 'Scheduled-task fixture deletion ignored a hard link'}
    if(-not (Test-Path -LiteralPath $taskFile) -or -not (Test-Path -LiteralPath $taskAlias)){throw 'Scheduled-task hard-link refusal did not preserve both pathnames'}
    Write-Output 'UNI_HARDLINK_COVERAGE_TEST_OK'
} finally {
    if(Test-Path -LiteralPath $alias){Remove-Item -LiteralPath $alias -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $original){Remove-Item -LiteralPath $original -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
