param()

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')

function Assert-UniDismQueryTest {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

Assert-UniDismQueryTest ([bool](Get-Command Invoke-UniDismPackageQuery -CommandType Function -ErrorAction SilentlyContinue)) 'Missing retrying DISM package-query helper.'

$fixture=Join-Path ([IO.Path]::GetTempPath()) ('uni-dism-query-test-'+[Guid]::NewGuid().ToString('N'))
$fakeDism=Join-Path $fixture 'fake-dism.cmd'
$counter=Join-Path $fixture 'attempt.txt'
$env:UNI_DISM_QUERY_TEST_COUNTER=$counter
$fakeBody=@'
@echo off
if not exist "%UNI_DISM_QUERY_TEST_COUNTER%" (
  >"%UNI_DISM_QUERY_TEST_COUNTER%" echo 1
  echo Error: transient servicing contention 1>&2
  exit /b 5
)
set /p UNI_ATTEMPT=<"%UNI_DISM_QUERY_TEST_COUNTER%"
if "%UNI_ATTEMPT%"=="1" (
  >"%UNI_DISM_QUERY_TEST_COUNTER%" echo 2
  echo Error: transient servicing contention 1>&2
  exit /b 32
)
echo State : Installed
echo The operation completed successfully.
exit /b 0
'@

try {
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    [IO.File]::WriteAllText($fakeDism,$fakeBody,[Text.Encoding]::ASCII)
    $result=Invoke-UniDismPackageQuery -PackageName 'Contoso-Package' -DismPath $fakeDism -Attempts 3 -DelayMilliseconds 1
    Assert-UniDismQueryTest ($result.ExitCode -eq 0) 'Retrying DISM query did not return exit code zero.'
    Assert-UniDismQueryTest ($result.AttemptsUsed -eq 3) 'Retrying DISM query did not use the expected third attempt.'
    Assert-UniDismQueryTest (@($result.Output|Where-Object{[string]$_ -match '^State\s*:\s*Installed\s*$'}).Count -eq 1) 'Retrying DISM query lost the successful package state.'

    [IO.File]::Delete($counter)
    $failed=$false
    try {[void](Invoke-UniDismPackageQuery -PackageName 'Contoso-Package' -DismPath $fakeDism -Attempts 2 -DelayMilliseconds 1)} catch {$failed=$_.Exception.Message -match 'exit 32' -and $_.Exception.Message -match 'transient servicing contention'}
    Assert-UniDismQueryTest $failed 'Exhausted DISM query retries did not fail closed with the final exit code and diagnostic.'
}
finally {
    Remove-Item Env:UNI_DISM_QUERY_TEST_COUNTER -ErrorAction SilentlyContinue
    if([IO.Directory]::Exists($fixture)){[IO.Directory]::Delete($fixture,$true)}
}

'UNI_DISM_PACKAGE_QUERY_TEST_OK'
