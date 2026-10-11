$ErrorActionPreference='Stop'
$modulePath=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)) 'WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('gmenu-dispatch-test-'+[guid]::NewGuid().ToString('N'))
$savedDockerBuildKit=$env:DOCKER_BUILDKIT
$savedBuildKitProgress=$env:BUILDKIT_PROGRESS
$savedComposeProgress=$env:COMPOSE_PROGRESS
$savedComposeTimeout=$env:COMPOSE_HTTP_TIMEOUT
$savedLastExitCode=$global:LASTEXITCODE
$savedCandidates=Get-Command Get-HermesDockerChunkedBackupPushScriptCandidates -CommandType Function -ErrorAction SilentlyContinue
$savedFastLine=Get-Command Invoke-HermesDockerAllFastLine -CommandType Function -ErrorAction SilentlyContinue
$savedDispatcher=Get-Command Invoke-HermesDockerChunkedBackupPush -CommandType Function -ErrorAction SilentlyContinue
$passed=New-Object 'Collections.Generic.List[string]'
$dispatcherCleanupTarget='C:\Temp\hermes-docker-realtime-helper'
if(Test-Path -LiteralPath $dispatcherCleanupTarget){
    throw "Refusing to run the real dispatcher regression because its finally block would recursively remove the existing folder: $dispatcherCleanupTarget"
}

function Check([bool]$Condition,[string]$Name) {
    if(-not $Condition){throw "FAILED: $Name"}
    [void]$passed.Add($Name)
}

try {
    if(-not (Test-Path -LiteralPath $modulePath -PathType Leaf)){throw "Profile module is missing: $modulePath"}
    Import-Module -Name $modulePath -DisableNameChecking -Global -Force -ErrorAction Stop
    Initialize-CodexProfileFunctions

    $fallbackDirectory=Join-Path $testRoot 'GMenuFallback'
    $sourceDirectory=Join-Path $testRoot 'source folder [fixture]'
    [void][IO.Directory]::CreateDirectory($fallbackDirectory)
    [void][IO.Directory]::CreateDirectory($sourceDirectory)
    $missingActive=Join-Path $testRoot 'active publisher\mmenu_chunked_push.ps1'
    $fallbackScript=Join-Path $fallbackDirectory 'mmenu_chunked_push.ps1'
    $fixture=@'
[CmdletBinding()]
param(
    [string]$Path,
    [int64]$TargetLayerMiB,
    [string]$EntryPoint,
    [switch]$PreflightOnly,
    [switch]$TarPreflightOnly,
    [switch]$BuildPreflightOnly
)
$global:GGMDispatcherFixtureResult=[pscustomobject]@{
    HelperPath=$MyInvocation.MyCommand.Path
    Path=$Path
    TargetLayerMiB=$TargetLayerMiB
    EntryPoint=$EntryPoint
    PreflightOnly=$PreflightOnly
    TarPreflightOnly=$TarPreflightOnly
    BuildPreflightOnly=$BuildPreflightOnly
}
$global:LASTEXITCODE=0
'@
    [IO.File]::WriteAllText($fallbackScript,$fixture,(New-Object Text.UTF8Encoding($false)))
    $global:GGMDispatcherCandidates=@($missingActive,$fallbackScript)

    # Replace only the candidate provider and progress reporter. The resolver,
    # dispatcher, and lazy profile proxy remain the real implementations.
    Set-Item -LiteralPath Function:\global:Get-HermesDockerChunkedBackupPushScriptCandidates -Value {
        return @($global:GGMDispatcherCandidates)
    } -Force
    Set-Item -LiteralPath Function:\global:Invoke-HermesDockerAllFastLine -Value {
        param([string]$EntryPoint,[string]$Message)
    } -Force

    Check (-not (Test-Path -LiteralPath $missingActive -PathType Leaf) -and (Test-Path -LiteralPath $fallbackScript -PathType Leaf)) 'fixture simulates an absent active publisher and present local fallback'
    Invoke-HermesDockerChunkedBackupPush -Path $sourceDirectory -PreflightOnly -TarPreflightOnly -BuildPreflightOnly -TargetLayerMiB 512 -EntryPoint 'mmenu'
    $result=$global:GGMDispatcherFixtureResult
    Check ($result -and $result.HelperPath -eq [IO.Path]::GetFullPath($fallbackScript)) 'fresh lazy dispatcher selects the fallback publisher when the active candidate is missing'
    Check ($result.Path -eq [IO.Path]::GetFullPath($sourceDirectory) -and $result.EntryPoint -eq 'mmenu' -and $result.TargetLayerMiB -eq 512 -and $result.PreflightOnly -and $result.TarPreflightOnly -and $result.BuildPreflightOnly) 'dispatcher preserves source path, mmenu entry point, layer size, and all preflight switches'
    Check ($global:LASTEXITCODE -eq 0) 'fixture preflight returns success without invoking a real publisher or Docker'

    [pscustomobject]@{Status='PASSED';PowerShell=$PSVersionTable.PSVersion.ToString();Tests=$passed.Count;Cases=$passed.ToArray()} | ConvertTo-Json -Depth 4
} finally {
    $env:DOCKER_BUILDKIT=$savedDockerBuildKit
    $env:BUILDKIT_PROGRESS=$savedBuildKitProgress
    $env:COMPOSE_PROGRESS=$savedComposeProgress
    $env:COMPOSE_HTTP_TIMEOUT=$savedComposeTimeout
    $global:LASTEXITCODE=$savedLastExitCode
    Remove-Variable -Name GGMDispatcherCandidates,GGMDispatcherFixtureResult -Scope Global -ErrorAction SilentlyContinue
    foreach($name in @('Get-HermesDockerChunkedBackupPushScriptCandidates','Invoke-HermesDockerAllFastLine','Invoke-HermesDockerChunkedBackupPush')){
        Remove-Item -LiteralPath ("Function:\global:{0}" -f $name) -Force -ErrorAction SilentlyContinue
    }
    if($savedCandidates){Set-Item -LiteralPath Function:\global:Get-HermesDockerChunkedBackupPushScriptCandidates -Value $savedCandidates.Definition -Force}
    if($savedFastLine){Set-Item -LiteralPath Function:\global:Invoke-HermesDockerAllFastLine -Value $savedFastLine.Definition -Force}
    if($savedDispatcher){Set-Item -LiteralPath Function:\global:Invoke-HermesDockerChunkedBackupPush -Value $savedDispatcher.Definition -Force}
    Remove-Module -Name CodexProfileFunctions -Force -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $testRoot){try{[IO.Directory]::Delete(('\\?\'+$testRoot),$true)}catch{Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}}
}
