$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('gmenu-functions-test-'+[guid]::NewGuid().ToString('N'))
$savedUserProfile=$env:USERPROFILE
$savedGMenuStateRoot=$env:GMENU_STATE_ROOT
$savedGgmRepository=$env:HERMES_MMENU_REPOSITORY_OVERRIDE
$savedGgmTag=$env:HERMES_MMENU_TAG_OVERRIDE
$savedLastExitCodeVariable=Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
$savedLastExitCodeExists=[bool]$savedLastExitCodeVariable
$savedLastExitCode=if($savedLastExitCodeVariable){$savedLastExitCodeVariable.Value}else{$null}
$savedErrorActionPreference=$ErrorActionPreference
$savedGmAlias=Get-Command gm -CommandType Alias -ErrorAction SilentlyContinue | Select-Object -First 1
$savedGlobalFunctions=@{}
foreach($functionEntry in @(Get-ChildItem -LiteralPath Function:\global: -ErrorAction SilentlyContinue)) {
    $savedGlobalFunctions[[string]$functionEntry.Name]=$functionEntry.ScriptBlock
}
$fixtureGlobalNames=@('GGMFixtureCalls','GGMFixtureLastCall','GGMFixtureOverridesCleared','GGMFixtureHistory','GGMFixtureExitCode')
$savedFixtureGlobals=@{}
foreach($fixtureGlobalName in $fixtureGlobalNames) {
    $existingVariable=Get-Variable -Name $fixtureGlobalName -Scope Global -ErrorAction SilentlyContinue
    if($existingVariable){$savedFixtureGlobals[$fixtureGlobalName]=[pscustomobject]@{Exists=$true;Value=$existingVariable.Value}}
    else {$savedFixtureGlobals[$fixtureGlobalName]=[pscustomobject]@{Exists=$false;Value=$null}}
}
$savedHermesPush=Get-Command Invoke-HermesDockerChunkedBackupPush -CommandType Function -ErrorAction SilentlyContinue
$passed=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Condition,[string]$Name) {
    if(-not $Condition){throw "FAILED: $Name"}
    [void]$passed.Add($Name)
}
try {
    [void][IO.Directory]::CreateDirectory($root)
    $env:USERPROFILE=$root
    $env:GMENU_STATE_ROOT=Join-Path $root '.gmenu'
    . (Join-Path $PSScriptRoot 'GMenuFunctions.ps1')
    Check ($null -ne (Get-Command gm -CommandType Function -ErrorAction SilentlyContinue)) 'gm is registered as a function after loading the GMenu profile source'
    Check ($null -ne (Get-Command ggm -CommandType Function -ErrorAction SilentlyContinue)) 'ggm is registered as a function after loading the GMenu profile source'
    $gmRecoveryFolder=Join-Path $root 'gm self-healing [folder]';[void][IO.Directory]::CreateDirectory($gmRecoveryFolder)
    [IO.File]::WriteAllText((Join-Path $gmRecoveryFolder 'data.txt'),'gm')
    Remove-Item -LiteralPath Function:\global:Invoke-GMenuCommand -Force
    $gmRecoveryPlan=@(gm $gmRecoveryFolder -Plan)
    Check ((Get-Command Invoke-GMenuCommand -CommandType Function -ErrorAction SilentlyContinue) -and $gmRecoveryPlan.Count -eq 1 -and $gmRecoveryPlan[0].Source -eq [IO.Path]::GetFullPath($gmRecoveryFolder)) 'gm reloads its durable backend and plans the folder after Invoke-GMenuCommand disappears'
    $backupRoot=Join-Path $root '.gmenu\CommandBackups'
    [void][IO.Directory]::CreateDirectory($backupRoot)
    $backup=Join-Path $backupRoot 'gfixture.ps1'
    $text=@'
# GMENU GENERATED RESTORE COMMAND - PRIVATE RECOVERY KEY INCLUDED. Do not publish this script.
[CmdletBinding()]
param([string]$Value)
Write-Output ('GMENU_FIXTURE '+$Value)
'@
    [IO.File]::WriteAllText($backup,$text,(New-Object Text.UTF8Encoding($false)))
    Set-GMenuSavedCommandFunction 'gfixture' $backup
    $first=@(Invoke-GMenuSavedCommand -Name 'gfixture' -Arguments @('two words'))
    Check ($first.Count -eq 1 -and $first[0] -eq 'GMENU_FIXTURE two words') 'missing live command restores from protected backup'
    $commandPath=Join-Path $root '.gmenu\Commands\gfixture.ps1'
    Check (Test-Path -LiteralPath $commandPath -PathType Leaf) 'recovered command is installed at the live path'
    Remove-Item -LiteralPath $commandPath -Force
    $second=@(gfixture 'again')
    Check ($second[0] -eq 'GMENU_FIXTURE again' -and (Test-Path -LiteralPath $commandPath -PathType Leaf)) 'generated function self-heals after command deletion'
    $fallbackRoot=Join-Path $env:GMENU_STATE_ROOT 'Fallback'
    $fallbackBackupRoot=Join-Path $fallbackRoot 'CommandBackups'
    [void][IO.Directory]::CreateDirectory($fallbackBackupRoot)
    Copy-Item -LiteralPath $backup -Destination (Join-Path $fallbackBackupRoot 'gfixture.ps1') -Force
    Remove-Item -LiteralPath $commandPath,$backup -Force
    $third=@(gfixture 'fallback')
    Check ($third[0] -eq 'GMENU_FIXTURE fallback' -and (Test-Path -LiteralPath $commandPath -PathType Leaf)) 'missing .gmenu state self-heals from the independent fallback mirror'
    Remove-Item -LiteralPath $commandPath,(Join-Path $fallbackBackupRoot 'gfixture.ps1') -Force
    $rejectedOutput=@(Invoke-GMenuSavedCommand -Name 'gfixture' 6>&1 2>&1 | ForEach-Object {[string]$_}) -join ' '
    Check ($rejectedOutput -match 'protected backup' -and $global:LASTEXITCODE -eq 1 -and $rejectedOutput -notmatch 'CommandNotFoundException') 'missing private artifact reports a controlled repair message'
    $invalidOutput=@(Invoke-GMenuSavedCommand -Name '../escape' 6>&1 2>&1 | ForEach-Object {[string]$_}) -join ' '
    Check ($invalidOutput -match 'Invalid GMenu command name' -and $global:LASTEXITCODE -eq 1) 'path-like generated command names are rejected'
    $gmMultiPaths=@(
        (Join-Path $root "GM Multi First O'Brien [space]"),
        (Join-Path $root ('GM Multi '+[string][char]0x4E8C+' [unicode]')),
        (Join-Path $root '[GM] Multi Third folder')
    )
    foreach($gmMultiPath in $gmMultiPaths) {
        [void][IO.Directory]::CreateDirectory($gmMultiPath)
        [IO.File]::WriteAllText((Join-Path $gmMultiPath 'launch.cmd'),'@echo off')
        [IO.File]::WriteAllText((Join-Path $gmMultiPath 'data.txt'),'gm fixture')
    }
    $gmTwoPaths=@($gmMultiPaths[0],$gmMultiPaths[1])
    $gmTwoResults=@(gm @gmTwoPaths -Plan -Launcher 'launch.cmd')
    $gmTwoExpected=@($gmTwoPaths | ForEach-Object {[IO.Path]::GetFullPath($_)})
    $gmTwoActual=@($gmTwoResults | ForEach-Object {[string]$_.Source})
    $gmTwoOrdered=$gmTwoActual.Count -eq $gmTwoExpected.Count
    if($gmTwoOrdered) {
        for($gmIndex=0;$gmIndex -lt $gmTwoExpected.Count;$gmIndex++) {
            if($gmTwoActual[$gmIndex] -ine $gmTwoExpected[$gmIndex]){$gmTwoOrdered=$false;break}
        }
    }
    Check ($gmTwoOrdered -and @($gmTwoResults | Where-Object {$_.Launcher -ne 'launch.cmd'}).Count -eq 0 -and $global:LASTEXITCODE -eq 0) 'gm processes two special-character folder paths in order and applies shared Plan and Launcher options without publishing'
    $gmMultiResults=@(gm @gmMultiPaths -Plan -Launcher 'launch.cmd')
    $gmMultiExpected=@($gmMultiPaths | ForEach-Object {[IO.Path]::GetFullPath($_)})
    $gmMultiActual=@($gmMultiResults | ForEach-Object {[string]$_.Source})
    $gmMultiOrdered=$gmMultiActual.Count -eq $gmMultiExpected.Count
    if($gmMultiOrdered) {
        for($gmIndex=0;$gmIndex -lt $gmMultiExpected.Count;$gmIndex++) {
            if($gmMultiActual[$gmIndex] -ine $gmMultiExpected[$gmIndex]){$gmMultiOrdered=$false;break}
        }
    }
    Check ($gmMultiOrdered -and @($gmMultiResults | Where-Object {$_.Launcher -ne 'launch.cmd'}).Count -eq 0 -and $global:LASTEXITCODE -eq 0) 'gm processes three folder paths in input order and applies shared Plan and Launcher options without publishing'
    $gmDirectResults=@(gm $gmMultiPaths[0] $gmMultiPaths[1] $gmMultiPaths[2] -Plan -Launcher 'launch.cmd')
    $gmDirectExpected=@($gmMultiPaths | ForEach-Object {[IO.Path]::GetFullPath($_)})
    $gmDirectActual=@($gmDirectResults | ForEach-Object {[string]$_.Source})
    $gmDirectOrdered=$gmDirectActual.Count -eq $gmDirectExpected.Count
    if($gmDirectOrdered) {
        for($gmIndex=0;$gmIndex -lt $gmDirectExpected.Count;$gmIndex++) {
            if($gmDirectActual[$gmIndex] -ine $gmDirectExpected[$gmIndex]){$gmDirectOrdered=$false;break}
        }
    }
    Check ($gmDirectOrdered -and @($gmDirectResults | Where-Object {$_.Launcher -ne 'launch.cmd'}).Count -eq 0 -and $global:LASTEXITCODE -eq 0) 'gm accepts direct three-path positional syntax and applies shared options without publishing'
    $gmInvalidFile=Join-Path $root 'gm-invalid-file-not-folder.txt'
    [IO.File]::WriteAllText($gmInvalidFile,'not a folder')
    $gmMixedPaths=@($gmMultiPaths[0],$gmInvalidFile,$gmMultiPaths[2])
    $gmMixedResults=@(gm @gmMixedPaths -Plan -Launcher 'launch.cmd')
    $gmMixedExpected=@([IO.Path]::GetFullPath($gmMultiPaths[0]),[IO.Path]::GetFullPath($gmMultiPaths[2]))
    $gmMixedActual=@($gmMixedResults | ForEach-Object {[string]$_.Source})
    $gmMixedOrdered=$gmMixedActual.Count -eq $gmMixedExpected.Count
    if($gmMixedOrdered) {
        for($gmIndex=0;$gmIndex -lt $gmMixedExpected.Count;$gmIndex++) {
            if($gmMixedActual[$gmIndex] -ine $gmMixedExpected[$gmIndex]){$gmMixedOrdered=$false;break}
        }
    }
    Check ($gmMixedOrdered -and $global:LASTEXITCODE -eq 1) 'gm continues after a non-folder input, processes later folders, and aggregates a nonzero result'
    $ggmFolder=Join-Path $root "GGM Special [A] O'Brien";[void][IO.Directory]::CreateDirectory($ggmFolder)
    $ggmUnicode=Join-Path $root ([string][char]0x732b);[void][IO.Directory]::CreateDirectory($ggmUnicode)
    $ggmThird=Join-Path $root 'GGM Multi Third [space]';[void][IO.Directory]::CreateDirectory($ggmThird)
    $ggmLong=Join-Path $root 'GGM Deep Folder'
    for($segment=0;$segment -lt 4;$segment++){$ggmLong=Join-Path $ggmLong ('segment'+$segment+'-'+('x'*45))}
    $ggmLongExtended='\\?\'+$ggmLong
    [void][IO.Directory]::CreateDirectory($ggmLongExtended)
    [IO.File]::WriteAllText(('\\?\'+(Join-Path $ggmLong 'data.txt')),'deep')
    $global:GGMFixtureCalls=0;$global:GGMFixtureLastCall=$null;$global:GGMFixtureOverridesCleared=$false
    $global:GGMFixtureHistory=New-Object 'Collections.Generic.List[object]'
    $global:GGMFixtureExitCode=7
    function global:Invoke-HermesDockerChunkedBackupPush {
        [CmdletBinding()]
        param([string]$Path,[int64]$TargetLayerMiB,[string]$EntryPoint,[switch]$PreflightOnly,[switch]$TarPreflightOnly,[switch]$BuildPreflightOnly)
        $global:GGMFixtureCalls++
        $global:GGMFixtureLastCall=[pscustomobject]@{Path=$Path;TargetLayerMiB=$TargetLayerMiB;EntryPoint=$EntryPoint;PreflightOnly=$PreflightOnly;TarPreflightOnly=$TarPreflightOnly;BuildPreflightOnly=$BuildPreflightOnly}
        [void]$global:GGMFixtureHistory.Add($global:GGMFixtureLastCall)
        $global:GGMFixtureOverridesCleared=(-not $env:HERMES_MMENU_REPOSITORY_OVERRIDE -and -not $env:HERMES_MMENU_TAG_OVERRIDE)
        $global:LASTEXITCODE=[int]$global:GGMFixtureExitCode
    }
    $env:HERMES_MMENU_REPOSITORY_OVERRIDE='caller/repository'
    $env:HERMES_MMENU_TAG_OVERRIDE='caller-tag'
    $ggmOriginalErrorActionPreference=$ErrorActionPreference
    Push-Location $root
    $ggmExpectedLocation=(Get-Location).Path
    try {
        ggm ".\GGM Special [A] O'Brien" -PreflightOnly -TargetLayerMiB 1024
        Check ($global:GGMFixtureLastCall.Path -eq $ggmFolder -and $global:GGMFixtureLastCall.EntryPoint -eq 'mmenu' -and $global:GGMFixtureLastCall.TargetLayerMiB -eq 1024 -and $global:GGMFixtureLastCall.PreflightOnly) 'ggm forwards arbitrary relative folder paths and requested options to mmenu'
        Check ($global:GGMFixtureCalls -eq 1) 'ggm preserves its existing one-path invocation behavior'
        Check ($global:GGMFixtureOverridesCleared -and $env:HERMES_MMENU_REPOSITORY_OVERRIDE -eq 'caller/repository' -and $env:HERMES_MMENU_TAG_OVERRIDE -eq 'caller-tag') 'ggm clears private routing overrides during dispatch and restores caller environment'
        Check ($global:LASTEXITCODE -eq 7 -and (Get-Location).Path -eq $ggmExpectedLocation -and $ErrorActionPreference -eq $ggmOriginalErrorActionPreference) 'ggm preserves backend status and restores PowerShell location and error policy'
        ggm $ggmUnicode -TarPreflightOnly -TargetLayerMiB 512
        Check ($global:GGMFixtureLastCall.Path -eq $ggmUnicode -and $global:GGMFixtureLastCall.TarPreflightOnly -and $global:GGMFixtureLastCall.TargetLayerMiB -eq 512) 'ggm accepts a Unicode folder name and forwards the requested tar preflight'
        ggm $ggmLong -BuildPreflightOnly -TargetLayerMiB 1024
        Check ($ggmLong.Length -gt 260 -and $global:GGMFixtureLastCall.Path -eq $ggmLong -and $global:GGMFixtureLastCall.BuildPreflightOnly) 'ggm forwards a valid deep path longer than MAX_PATH without truncation'
        ggm $ggmLongExtended -TarPreflightOnly -TargetLayerMiB 512
        Check ($global:GGMFixtureLastCall.Path -eq $ggmLongExtended -and $global:GGMFixtureLastCall.TarPreflightOnly) 'ggm accepts extended-length drive paths and preserves the long-path prefix'
        $callsBeforeInvalid=$global:GGMFixtureCalls
        ggm (Join-Path $root 'missing folder')
        Check ($global:LASTEXITCODE -eq 1 -and $global:GGMFixtureCalls -eq $callsBeforeInvalid) 'missing ggm folders fail cleanly before dispatch'
        $filePath=Join-Path $root 'not-a-folder.txt';[IO.File]::WriteAllText($filePath,'fixture')
        ggm $filePath
        Check ($global:LASTEXITCODE -eq 1 -and $global:GGMFixtureCalls -eq $callsBeforeInvalid) 'ggm rejects files instead of treating them as folders'
        ggm 'C:\'
        Check ($global:LASTEXITCODE -eq 1 -and $global:GGMFixtureCalls -eq $callsBeforeInvalid) 'ggm rejects drive roots before backup dispatch'
        ggm '\\server\share'
        Check ($global:LASTEXITCODE -eq 1 -and $global:GGMFixtureCalls -eq $callsBeforeInvalid) 'ggm rejects UNC share roots before backup dispatch'
        $ggmMultiPaths=@($ggmFolder,$ggmUnicode,$ggmThird)
        $global:GGMFixtureExitCode=0
        $global:GGMFixtureHistory.Clear()
        $ggmTwoPaths=@($ggmMultiPaths[0],$ggmMultiPaths[1])
        ggm @ggmTwoPaths -PreflightOnly -TargetLayerMiB 256
        $ggmTwoExpected=@($ggmTwoPaths | ForEach-Object {[IO.Path]::GetFullPath($_)})
        $ggmTwoActual=@($global:GGMFixtureHistory | ForEach-Object {[string]$_.Path})
        $ggmTwoOrdered=$ggmTwoActual.Count -eq $ggmTwoExpected.Count
        if($ggmTwoOrdered) {
            for($ggmIndex=0;$ggmIndex -lt $ggmTwoExpected.Count;$ggmIndex++) {
                if($ggmTwoActual[$ggmIndex] -ine $ggmTwoExpected[$ggmIndex]){$ggmTwoOrdered=$false;break}
            }
        }
        $ggmTwoOptionsForwarded=@($global:GGMFixtureHistory | Where-Object {-not $_.PreflightOnly -or $_.TargetLayerMiB -ne 256 -or $_.EntryPoint -ne 'mmenu'}).Count -eq 0
        Check ($ggmTwoOrdered -and $ggmTwoOptionsForwarded -and $global:LASTEXITCODE -eq 0) 'ggm dispatches two special-character paths in order and applies shared preflight options to every call without publishing'
        $global:GGMFixtureHistory.Clear()
        ggm @ggmMultiPaths -TarPreflightOnly -TargetLayerMiB 512
        $ggmMultiExpected=@($ggmMultiPaths | ForEach-Object {[IO.Path]::GetFullPath($_)})
        $ggmMultiActual=@($global:GGMFixtureHistory | ForEach-Object {[string]$_.Path})
        $ggmMultiOrdered=$ggmMultiActual.Count -eq $ggmMultiExpected.Count
        if($ggmMultiOrdered) {
            for($ggmIndex=0;$ggmIndex -lt $ggmMultiExpected.Count;$ggmIndex++) {
                if($ggmMultiActual[$ggmIndex] -ine $ggmMultiExpected[$ggmIndex]){$ggmMultiOrdered=$false;break}
            }
        }
        $ggmOptionsForwarded=@($global:GGMFixtureHistory | Where-Object {-not $_.TarPreflightOnly -or $_.TargetLayerMiB -ne 512 -or $_.EntryPoint -ne 'mmenu'}).Count -eq 0
        Check ($ggmMultiOrdered -and $ggmOptionsForwarded -and $global:LASTEXITCODE -eq 0) 'ggm dispatches three folders in input order and applies shared tar-preflight options to every call without publishing'
        $global:GGMFixtureHistory.Clear()
        ggm $ggmMultiPaths[0] $ggmMultiPaths[1] $ggmMultiPaths[2] -TarPreflightOnly -TargetLayerMiB 512
        $ggmDirectExpected=@($ggmMultiPaths | ForEach-Object {[IO.Path]::GetFullPath($_)})
        $ggmDirectActual=@($global:GGMFixtureHistory | ForEach-Object {[string]$_.Path})
        $ggmDirectOrdered=$ggmDirectActual.Count -eq $ggmDirectExpected.Count
        if($ggmDirectOrdered) {
            for($ggmIndex=0;$ggmIndex -lt $ggmDirectExpected.Count;$ggmIndex++) {
                if($ggmDirectActual[$ggmIndex] -ine $ggmDirectExpected[$ggmIndex]){$ggmDirectOrdered=$false;break}
            }
        }
        $ggmDirectOptionsForwarded=@($global:GGMFixtureHistory | Where-Object {-not $_.TarPreflightOnly -or $_.TargetLayerMiB -ne 512 -or $_.EntryPoint -ne 'mmenu'}).Count -eq 0
        Check ($ggmDirectOrdered -and $ggmDirectOptionsForwarded -and $global:LASTEXITCODE -eq 0) 'ggm accepts direct three-path positional syntax and applies shared options without publishing'
        $global:GGMFixtureHistory.Clear()
        $ggmMixedPaths=@($ggmFolder,(Join-Path $root 'missing ggm folder'),$ggmThird)
        ggm @ggmMixedPaths -TarPreflightOnly -TargetLayerMiB 512
        $ggmMixedExpected=@([IO.Path]::GetFullPath($ggmFolder),[IO.Path]::GetFullPath($ggmThird))
        $ggmMixedActual=@($global:GGMFixtureHistory | ForEach-Object {[string]$_.Path})
        $ggmMixedOrdered=$ggmMixedActual.Count -eq $ggmMixedExpected.Count
        if($ggmMixedOrdered) {
            for($ggmIndex=0;$ggmIndex -lt $ggmMixedExpected.Count;$ggmIndex++) {
                if($ggmMixedActual[$ggmIndex] -ine $ggmMixedExpected[$ggmIndex]){$ggmMixedOrdered=$false;break}
            }
        }
        Check ($ggmMixedOrdered -and $global:LASTEXITCODE -eq 1) 'ggm continues after a missing folder, runs later folders, and aggregates a nonzero result'
    } finally {Pop-Location}
    $global:LASTEXITCODE=0
    [pscustomobject]@{Status='PASSED';PowerShell=$PSVersionTable.PSVersion.ToString();Tests=$passed.Count;Cases=$passed.ToArray()} | ConvertTo-Json -Depth 5
} finally {
    $env:USERPROFILE=$savedUserProfile
    if($null -eq $savedGMenuStateRoot){Remove-Item Env:GMENU_STATE_ROOT -ErrorAction SilentlyContinue}else{$env:GMENU_STATE_ROOT=$savedGMenuStateRoot}
    if($null -eq $savedGgmRepository){Remove-Item Env:HERMES_MMENU_REPOSITORY_OVERRIDE -ErrorAction SilentlyContinue}else{$env:HERMES_MMENU_REPOSITORY_OVERRIDE=$savedGgmRepository}
    if($null -eq $savedGgmTag){Remove-Item Env:HERMES_MMENU_TAG_OVERRIDE -ErrorAction SilentlyContinue}else{$env:HERMES_MMENU_TAG_OVERRIDE=$savedGgmTag}
    if(Test-Path -LiteralPath $root){try{[IO.Directory]::Delete(('\\?\'+$root),$true)}catch{Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}}
    if($savedHermesPush){Set-Item -LiteralPath Function:\Invoke-HermesDockerChunkedBackupPush -Value $savedHermesPush.Definition -Force}
    else {Remove-Item -LiteralPath Function:\Invoke-HermesDockerChunkedBackupPush -Force -ErrorAction SilentlyContinue}
    foreach($functionEntry in @(Get-ChildItem -LiteralPath Function:\global: -ErrorAction SilentlyContinue)) {
        if(-not $savedGlobalFunctions.ContainsKey([string]$functionEntry.Name)) {
            Remove-Item -LiteralPath $functionEntry.PSPath -Force -ErrorAction SilentlyContinue
        }
    }
    foreach($functionName in $savedGlobalFunctions.Keys) {
        Set-Item -LiteralPath ("Function:\global:{0}" -f $functionName) -Value $savedGlobalFunctions[$functionName] -Force
    }
    if($savedGmAlias) {
        Set-Alias -Name gm -Value $savedGmAlias.Definition -Option $savedGmAlias.Options -Scope Global -Force
    } else {
        Remove-Item -LiteralPath Alias:\global:gm -Force -ErrorAction SilentlyContinue
    }
    foreach($fixtureGlobalName in $fixtureGlobalNames) {
        $savedFixture=$savedFixtureGlobals[$fixtureGlobalName]
        if($savedFixture.Exists) {Set-Variable -Name $fixtureGlobalName -Scope Global -Value $savedFixture.Value -Force}
        else {Remove-Variable -Name $fixtureGlobalName -Scope Global -ErrorAction SilentlyContinue}
    }
    if($savedLastExitCodeExists){Set-Variable -Name LASTEXITCODE -Scope Global -Value $savedLastExitCode -Force}
    else {Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue}
    $ErrorActionPreference=$savedErrorActionPreference
}
