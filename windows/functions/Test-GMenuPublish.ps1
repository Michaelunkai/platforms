$ErrorActionPreference='Stop'
$script:GMenuPayloadSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuPayload.cs'))
. (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
Initialize-GMenuRuntime
$root=Join-Path $PSScriptRoot ('.gmenu-work-'+[guid]::NewGuid().ToString('N'))
Protect-GMenuDirectory $root
$savedUser=$env:USERPROFILE;$savedMode=$env:HERMES_MMENU_GMENU;$savedLabelPath=$env:HERMES_MMENU_SOURCE_LABEL_PATH_OVERRIDE;$savedGMenuStateRoot=$env:GMENU_STATE_ROOT
$savedData=@{APPDATA=$env:APPDATA;LOCALAPPDATA=$env:LOCALAPPDATA;ProgramData=$env:ProgramData}
$passed=New-Object 'Collections.Generic.List[string]'
$skipped=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAILED: $Name"};$passed.Add($Name)}
try {
    $fixtureCode=Join-Path $root 'code';[void][IO.Directory]::CreateDirectory($fixtureCode)
    foreach($name in @('gmenu.ps1','GMenuRuntime.ps1','GMenuPayload.cs','Invoke-InstalledAppDockerRestoreAndLaunch.ps1','InstalledAppRestoreCatalog.json')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $fixtureCode}
    # [Environment]::GetFolderPath(MyDocuments) is tied to the real logon
    # profile and ignores a process-level USERPROFILE override. Redirect only
    # this disposable fixture copy so registration cannot touch host profiles.
    $fixtureRuntimePath=Join-Path $fixtureCode 'GMenuRuntime.ps1'
    $fixtureRuntime=[IO.File]::ReadAllText($fixtureRuntimePath)
    $documentsLookup='$documents=[Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)'
    if(-not $fixtureRuntime.Contains($documentsLookup)){throw 'Could not isolate the fixture Documents path from the real host profile.'}
    $fixtureRuntime=$fixtureRuntime.Replace($documentsLookup,'$documents=Join-Path $env:USERPROFILE ''Documents''')
    [IO.File]::WriteAllText($fixtureRuntimePath,$fixtureRuntime,(New-Object Text.UTF8Encoding($false)))
    $override=@'
function Get-GMenuOwnedProcess {return @()}
function Stop-GMenuApp {}
function Get-GMenuServiceManifest {return @()}
function Get-GMenuLocalHubCredential {return $null}
function Get-GMenuHubToken {return 'fixture-token'}
function Get-GMenuManifest {return [pscustomobject]@{Digest=('sha256:'+('1'*64))}}
function Register-GMenuPortableCommand($Ticket,[string]$SourceScript,[switch]$UpgradeExisting) {
    if(-not (Test-Path -LiteralPath $SourceScript)){throw 'Missing generated command'}
    $commandContent=[IO.File]::ReadAllText($SourceScript)
    Save-GMenuFunctionDefinition $Ticket.Function (Join-Path $env:USERPROFILE 'saved-profile.ps1') $commandContent -UpgradeExisting:$UpgradeExisting
}
function Invoke-GMenuRestore {throw 'Automatic restore must not run in the publish-only test'}
'@
    Add-Content -LiteralPath (Join-Path $fixtureCode 'GMenuRuntime.ps1') -Value $override
$publisherPreflight=@'
[CmdletBinding()]
param([string]$Path,[int]$TargetLayerMiB=256,[string]$EntryPoint='mmenu',[switch]$PreflightOnly)
if($EntryPoint -ne 'gm'){throw 'Unexpected fixture publisher entry point.'}
if(-not (Test-Path -LiteralPath $Path -PathType Container)){throw 'Fixture source folder is missing.'}
if($PreflightOnly){$global:GMenuTestPublisherPreflightCalls++;$global:LASTEXITCODE=0;return}
$global:GMenuTestPushCalls++
if($env:HERMES_MMENU_GMENU -ne '1'){throw 'Missing scoped live progress mode'}
if([IO.Path]::GetFullPath($env:HERMES_MMENU_SOURCE_LABEL_PATH_OVERRIDE) -ine [IO.Path]::GetFullPath($global:GMenuTestSource)){throw 'Missing installed-target source label override'}
if(-not @(Get-ChildItem -LiteralPath $Path -Filter 'gmenu-payload-*.bin').Count){throw 'Missing encrypted parts'}
if(@(Get-ChildItem -LiteralPath $Path | Where-Object Extension -ne '.bin').Count){throw 'Unencrypted file reached publish directory'}
if($global:GMenuTestDropResume){Remove-Item -LiteralPath Function:\Resume-GMenuServices -Force -ErrorAction SilentlyContinue;$global:GMenuTestDropResume=$false}
$global:LASTEXITCODE=if($global:GMenuTestFailPush){1}else{0}
'@
    [IO.File]::WriteAllText((Join-Path $fixtureCode 'mmenu_chunked_push.ps1'),$publisherPreflight,(New-Object Text.UTF8Encoding($false)))
    $global:GMenuTestPublisherPreflightCalls=0
    $env:USERPROFILE=Join-Path $root 'user';[void][IO.Directory]::CreateDirectory($env:USERPROFILE)
    $env:GMENU_STATE_ROOT=Join-Path $env:USERPROFILE '.gmenu'
    Check ((Get-GMenuStateRoot) -eq [IO.Path]::GetFullPath($env:GMENU_STATE_ROOT)) 'runtime and dispatcher honor the same explicit isolated GMenu state root'
    foreach($variable in $savedData.Keys){$value=Join-Path $env:USERPROFILE $variable;[void][IO.Directory]::CreateDirectory($value);[Environment]::SetEnvironmentVariable($variable,$value,'Process')}
    $app=Join-Path $root 'FixturePublish';[void][IO.Directory]::CreateDirectory($app)
    [IO.File]::WriteAllText((Join-Path $app 'FixturePublish.exe'),'synthetic executable, never launched')
    [IO.File]::WriteAllText((Join-Path $app 'Start-FixturePublish.exe'),'synthetic portable launcher, never launched')
    [IO.File]::WriteAllText((Join-Path $app 'state.txt'),'fake session fixture')
    $maestroFixture=Join-Path $root 'Maestro';$maestroTemp=Join-Path $maestroFixture 'state\tmp'
    [void][IO.Directory]::CreateDirectory($maestroTemp)
    $maestroLog=Join-Path $maestroTemp 'adb.log'
    $lockedMaestroLog=[IO.File]::Open($maestroLog,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $lockedMaestroLog.WriteByte(77);$lockedMaestroLog.Flush()
        $maestroPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $maestroFixture -Plan 6>$null
        $adbPlanWarning=@($maestroPlan.PortableStateWarnings | Where-Object {$_.Path -ieq 'state/tmp/adb.log' -and $_.Reason -match 'sharing or lock violation'})
        Check ($maestroPlan.Files -eq 1 -and $maestroPlan.Bytes -eq 1 -and $adbPlanWarning.Count -eq 1) 'gm plan measures the transient ADB log and warns that only a persistent sharing lock may omit it'
    } finally {$lockedMaestroLog.Dispose()}
    $global:GMenuTestSource=$app
    $global:GMenuTestPushCalls=0;$global:GMenuTestFailPush=$false;$global:GMenuTestDropResume=$false
    $messages=New-Object 'Collections.Generic.List[string]'
    function gFixturePublish { 'original restore command' }
    $plan=& (Join-Path $fixtureCode 'gmenu.ps1') $app -Plan 6>$null
    Check ($plan.Launcher -eq 'Start-FixturePublish.exe') 'portable app startup launcher takes precedence over same-name CLI'
    $renamedApp=Join-Path $root 'deepseekharness'
    [void][IO.Directory]::CreateDirectory($renamedApp)
    [IO.File]::WriteAllText((Join-Path $renamedApp 'Start DeepSeek Harness.cmd'),'fixture; never executed')
    [IO.File]::WriteAllText((Join-Path $renamedApp 'launch_dsh.ps1'),'fixture; never executed')
    [IO.File]::WriteAllText((Join-Path $renamedApp 'node.exe'),'fixture; never executed')
    $renamedPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $renamedApp -Plan 6>$null
    Check ($renamedPlan.Launcher -eq 'Start DeepSeek Harness.cmd' -and $renamedPlan.LaunchKind -eq 'Command') 'normalized folder names retain the spaced portable startup wrapper'
    $buzz=Join-Path $root 'Buzz';[void][IO.Directory]::CreateDirectory($buzz)
    foreach($file in @('Start Buzz.cmd','Start Buzz.bat','Start Buzz.ps1','buzz.exe','buzz-desktop.exe')) {
        [IO.File]::WriteAllText((Join-Path $buzz $file),'fixture; never executed')
    }
    $buzzPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $buzz -Plan 6>$null
    Check ($buzzPlan.Launcher -eq 'Start Buzz.cmd' -and $buzzPlan.LaunchKind -eq 'Command') 'same-name shell launchers prefer cmd over bat and PowerShell and internal executables'
    $buzzOverride=& (Join-Path $fixtureCode 'gmenu.ps1') $buzz -Launcher 'Start Buzz.ps1' -Plan 6>$null
    Check ($buzzOverride.Launcher -eq 'Start Buzz.ps1' -and $buzzOverride.LaunchKind -eq 'PowerShell') 'explicit launcher overrides shell format preference'
    foreach($case in @(
        @('Jackett','Start-JackettPortable.ps1','HttpScript'),
        @('Prowlarr','Start-ProwlarrPortable.ps1','HttpScript'),
        @('FlareSolverr','Start-FlareSolverrPortable.ps1','HttpScript'),
        @('BleachBitAutoClean','Invoke-BleachAutoClean.ps1','PowerShell'),
        @('scoop','shims\scoop.cmd','Command'),
        @('qBittorrentSearchPluginsWiki','Home.md','Content'),
        @('Process Lasso','ProcessLassoLauncher.exe','Exe')
    )) {
        $caseRoot=Join-Path $root $case[0];$caseFile=Join-Path $caseRoot $case[1]
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($caseFile));[IO.File]::WriteAllText($caseFile,'fixture; never executed')
        $casePlan=& (Join-Path $fixtureCode 'gmenu.ps1') $caseRoot -Plan 6>$null
        Check ($casePlan.Launcher -eq $case[1] -and $casePlan.LaunchKind -eq $case[2]) ('registered '+$case[0]+' preserves its launcher kind')
        if($case[0] -eq 'BleachBitAutoClean'){Check ($casePlan.Arguments -contains '-SelfTest') 'catalog arguments prevent unintended default maintenance actions'}
    }
    $plugins=Join-Path $root 'qBittorrentSearchPlugins';[void][IO.Directory]::CreateDirectory($plugins);[IO.File]::WriteAllText((Join-Path $plugins 'plugin.py'),'fixture')
    $pluginPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $plugins -Plan 6>$null
    Check ($pluginPlan.LaunchKind -eq 'Directory') 'registered plugin content is restored as content without inventing an executable'
    $special=Join-Path $root "Spaced App [1] O'Brien";[void][IO.Directory]::CreateDirectory($special);[IO.File]::WriteAllText((Join-Path $special 'Run.ps1'),'fixture')
    Push-Location $root
    try {
        $specialPlan=& (Join-Path $fixtureCode 'gmenu.ps1') ".\Spaced App [1] O'Brien" -Launcher 'Run.ps1' -LaunchArguments @('two words','literal&value') -Plan 6>$null
        Check ($specialPlan.Source -eq $special -and $specialPlan.LaunchKind -eq 'PowerShell' -and $specialPlan.Arguments[1] -eq 'literal&value') 'relative paths with spaces brackets and apostrophes preserve explicit script arguments'
        Check ((Resolve-GMenuFolderPath ".\Spaced App [1] O'Brien") -eq $special) 'literal special-character paths resolve as filesystem folders'
        Check ((Resolve-GMenuFolderPath '.\new destination' -AllowMissing) -eq (Join-Path $root 'new destination')) 'relative restore paths resolve against PowerShell location'
    }finally{Pop-Location}
    Check ((ConvertTo-GMenuExtendedPath '\\server\share\folder with spaces') -eq '\\?\UNC\server\share\folder with spaces') 'UNC paths receive the correct extended-length prefix'
    Check ((ConvertFrom-GMenuExtendedPath '\\?\UNC\server\share\folder with spaces') -eq '\\server\share\folder with spaces') 'extended UNC paths round-trip without losing the server/share boundary'
    Check ((Test-GMenuPathIsRoot '\\server\share') -and (Test-GMenuPathIsRoot 'C:\')) 'drive roots and UNC share roots are identified and kept out of folder operations'
    $alias=Join-Path $root 'special-folder-link'
    $junctionOutput=& $env:ComSpec /d /c ('mklink /J "'+$alias+'" "'+$special+'"') 2>&1
    if($LASTEXITCODE -eq 0) {
        try { Check ((Resolve-GMenuFolderPath $alias) -eq $special) 'a junction used as the selected folder resolves to its real target' }
        finally {
            & $env:ComSpec /d /c ('rmdir "'+$alias+'"') | Out-Null
            Check ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $special -PathType Container)) 'junction fixture cleanup removes only the link and preserves its target'
        }
    } else { Check $false ('the fixture junction could not be created: '+($junctionOutput -join ' ')) }
    $unicodeName=[string][char]0x96ea
    $unicodeFolder=Join-Path $root $unicodeName;[void][IO.Directory]::CreateDirectory($unicodeFolder)
    $unicodePlan=& (Join-Path $fixtureCode 'gmenu.ps1') $unicodeFolder -Plan 6>$null
    Check ($unicodePlan.Function -match '^gFolder_[a-f0-9]{12}$' -and $unicodePlan.Repository -match '/folder-[a-f0-9]{12}$') 'Unicode-only folder names receive stable non-colliding restore and repository identifiers'
    $menuFolder=Join-Path $root 'menu';[void][IO.Directory]::CreateDirectory($menuFolder)
    $menuPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $menuFolder -Plan 6>$null
    Check ($menuPlan.Function -ne 'gmenu' -and $menuPlan.Function -match '^gmenu_[a-f0-9]{12}$') 'reserved public command names do not block valid folder names'
    $longName=('L' * 120);$longFolder=Join-Path $root $longName;[void][IO.Directory]::CreateDirectory($longFolder)
    $longPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $longFolder -Plan 6>$null
    Check (($longPlan.Function.Length -le 96) -and (($longPlan.Repository -split '/')[-1].Length -le 100)) 'long valid folder names are mapped to bounded restore names and repository slugs'
    $deepFolder=Join-Path $root 'Deep Path'
    for($segment=0;$segment -lt 4;$segment++){$deepFolder=Join-Path $deepFolder ('segment'+$segment+'-'+('x'*45))}
    $deepFolderExtended=ConvertTo-GMenuExtendedPath $deepFolder
    [void][IO.Directory]::CreateDirectory($deepFolderExtended)
    [IO.File]::WriteAllText((ConvertTo-GMenuExtendedPath (Join-Path $deepFolder 'data.txt')),'deep')
    $deepPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $deepFolder -Plan 6>$null
    $deepExtendedPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $deepFolderExtended -Plan 6>$null
    Check ($deepFolder.Length -gt 260 -and $deepPlan.Files -eq 1 -and $deepPlan.Bytes -eq 4 -and $deepExtendedPlan.Files -eq 1 -and $deepExtendedPlan.Bytes -eq 4) 'gm inventories plain and extended deep folder paths beyond MAX_PATH without truncation'
    $global:LASTEXITCODE=0
    & (Join-Path $fixtureCode 'gmenu.ps1') $special -Launcher '..\FixturePublish\FixturePublish.exe' -Plan 6>$null | Out-Null
    Check ($global:LASTEXITCODE -eq 1 -and $global:GMenuTestPushCalls -eq 0) 'launcher outside source is rejected with failure status before backup or publication'
    $tv=Join-Path $root 'tv';$tvRelative='tizen\moonlight-setup-guardian\bin\MoonlightSetupGuardian.exe'
    $tvExe=Join-Path $tv $tvRelative;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($tvExe));[IO.File]::WriteAllText($tvExe,'synthetic GUI, never launched')
    [IO.File]::WriteAllText((Join-Path $tv 'unrelated-helper.exe'),'synthetic helper')
    $tvPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $tv -Plan 6>$null
    Check ($tvPlan.Launcher -eq $tvRelative) 'TV uses registered GUI launcher despite different name and setup substring'
    $tvCommand=Join-Path $env:USERPROFILE '.gmenu\Commands\gtv.ps1';[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($tvCommand))
    [IO.File]::WriteAllText($tvCommand,"# GMENU GENERATED RESTORE COMMAND - fixture`r`nthrow 'Catalog lookup executed restore'")
    [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.gmenu\Commands\gtv.receipt.json'),'{}')
    $entry=& (Join-Path $fixtureCode 'Invoke-InstalledAppDockerRestoreAndLaunch.ps1') -Folder tv -CatalogOnly
    Check ($entry.Path -eq $tvRelative) 'catalog lookup never invokes an already registered restore command'
    $whisper=Join-Path $root 'Whisper';[void][IO.Directory]::CreateDirectory($whisper);[IO.File]::WriteAllText((Join-Path $whisper 'WhisperSTT.exe'),'synthetic GUI');[IO.File]::WriteAllText((Join-Path $whisper 'other.exe'),'synthetic helper')
    $whisperPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $whisper -Plan 6>$null
    Check ($whisperPlan.Launcher -eq 'WhisperSTT.exe') 'registered launcher selection also covers other app names'
    $nested=Join-Path $root 'NestedApp'
    foreach($relative in @('App\4.6.8\NestedApp.exe','App\4.5.1\NestedApp.exe','App\4.6.8\helper.exe','App\4.6.8\console.exe','Archive\NestedApp.exe','downloads\NestedApp.exe')) {
        $file=Join-Path $nested $relative;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file));[IO.File]::WriteAllText($file,'fixture, never launched')
    }
    $nestedPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $nested -Plan 6>$null
    Check ($nestedPlan.Launcher -eq 'App\4.6.8\NestedApp.exe') 'nested launcher uses newest release and ignores archived and downloaded copies'
    $explicitPlan=& (Join-Path $fixtureCode 'gmenu.ps1') $nested -Plan -Launcher 'App\4.5.1\NestedApp.exe' 6>$null
    Check ($explicitPlan.Launcher -eq 'App\4.5.1\NestedApp.exe') 'explicit launcher selection overrides automatic release selection'
    $other=Join-Path $nested 'Other\NestedApp.exe';[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($other));[IO.File]::WriteAllText($other,'fixture')
    $global:LASTEXITCODE=0
    & (Join-Path $fixtureCode 'gmenu.ps1') $nested -Plan 6>$null | Out-Null
    Check ($global:LASTEXITCODE -eq 1) 'unrelated duplicate launcher is rejected with failure status rather than selected arbitrarily'
    [IO.File]::WriteAllText((Join-Path $env:USERPROFILE 'saved-profile.ps1'),"function global:gFixturePublish { 'original restore command' }; function untouched { 'keep' }")
    $global:GMenuTestFailPush=$true;$global:LASTEXITCODE=0
    $failedPublishOutput=@(& (Join-Path $fixtureCode 'gmenu.ps1') $app 6>&1 | ForEach-Object {[string]$_}) -join ' | '
    Check ($global:LASTEXITCODE -eq 1 -and (gFixturePublish) -eq 'original restore command' -and [IO.File]::ReadAllText((Join-Path $env:USERPROFILE 'saved-profile.ps1')).Contains('original restore command')) 'failed first publish returns failure status and preserves legacy function and saved profile'
    $retainedWork=@(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.gmenu') -Filter '.gmenu-work-*' -Directory)
    $retainedPending=@(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.gmenu') -Filter 'Pending-*.json' -File)
    $retainedPartCount=0
    if($retainedWork.Count){$retainedPartCount=@(Get-ChildItem -LiteralPath (Join-Path $retainedWork[0].FullName 'FixturePublish') -Filter 'gmenu-payload-*.bin' -ErrorAction SilentlyContinue).Count}
    Check ($retainedWork.Count -eq 1 -and $retainedPending.Count -eq 1 -and $retainedPartCount -gt 0) ('failed publish retains encrypted payload and pending ticket (work={0}, pending={1}, parts={2}, pushCalls={3}, output={4})' -f $retainedWork.Count,$retainedPending.Count,$retainedPartCount,$global:GMenuTestPushCalls,$failedPublishOutput)
    Remove-GMenuWork $retainedWork[0].FullName (Join-Path $env:USERPROFILE '.gmenu')
    Remove-Item -LiteralPath $retainedPending[0].FullName -Force
    $global:GMenuTestPushCalls=0;$global:GMenuTestFailPush=$false
    $messageCountBeforePublish=$messages.Count
    $result=@(& (Join-Path $fixtureCode 'gmenu.ps1') $app -PassThru 6>&1 | ForEach-Object {if($_ -is [Management.Automation.InformationRecord]){$messages.Add($_.ToString())}else{$_}})
    $resultFunction=if($result.Count){[string]$result[-1].Function}else{''}
    $recentGMenuFailure=@($messages | Select-Object -Skip $messageCountBeforePublish | Where-Object {$_ -match '\[gm\] FAILED:'})
    $lastGMenuFailure=if($recentGMenuFailure.Count){$recentGMenuFailure[-1]}else{''}
    Check ($global:GMenuTestPushCalls -eq 1 -and $resultFunction -eq 'gFixturePublish') ('actual gmenu entry point invokes mmenu and returns the generated function receipt (pushCalls={0}, preflights={1}, exit={2}, resultCount={3}, function={4}, failure={5})' -f $global:GMenuTestPushCalls,$global:GMenuTestPublisherPreflightCalls,$global:LASTEXITCODE,$result.Count,$resultFunction,$lastGMenuFailure)
    Check (-not $result[-1].VerifiedRestore) 'default publish completes without invoking restore'
    $savedProfileAfterPublish=[IO.File]::ReadAllText((Join-Path $env:USERPROFILE 'saved-profile.ps1'))
    Check ($savedProfileAfterPublish.Contains('function global:gFixturePublish') -or $savedProfileAfterPublish.Contains('function gFixturePublish')) 'publish saves a discoverable function definition before returning'
    $savedProfile=[IO.File]::ReadAllText((Join-Path $env:USERPROFILE 'saved-profile.ps1'))
    $durableProfilePaths=@(
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
        (Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\ProfileSources\ps5-profile-portable\legacy-safe-functions\profile-wrappers.ps1')
    )
    $durableProfileCopies=@($durableProfilePaths | Where-Object { [IO.File]::Exists($_) -and [IO.File]::ReadAllText($_).Contains('GMENU_EMBEDDED_COMMAND_V2') })
    Check ($savedProfile.Contains('function untouched') -and -not $savedProfile.Contains('original restore command') -and $durableProfileCopies.Count -eq $durableProfilePaths.Count) 'legacy global function upgrades in fixture-contained durable profile sources while unrelated functions are preserved'
    Check (@($messages | Where-Object {$_ -match '^GMENU complete 100\.0000% .*elapsed_ms='}).Count -eq 1) 'completion progress follows successful publish and registration with four-decimal elapsed progress'
    Check (-not @($messages | Where-Object {$_ -match 'GMENU_HEARTBEAT'}).Count) 'generic heartbeat output is removed'
    Check (@(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.gmenu') -Filter '.gmenu-work-*').Count -eq 0) 'publish returns after removing its temporary payload work'
    Check (($env:HERMES_MMENU_GMENU -eq $savedMode) -and ($env:HERMES_MMENU_SOURCE_LABEL_PATH_OVERRIDE -eq $savedLabelPath)) 'publish restores caller environment settings'
    $global:GMenuTestDropResume=$true;$dropResult=@(& (Join-Path $fixtureCode 'gmenu.ps1') $app -PassThru 6>$null | Where-Object {$_ -isnot [Management.Automation.ErrorRecord]})
    Check ($dropResult[-1].Function -eq 'gFixturePublish') 'publish cleanup survives dispatcher module refresh that removes the named resume command'
    $command=Join-Path $env:USERPROFILE 'saved-profile.ps1';$before=[GMenuPayload20260916V2]::Hash($command)
    $global:GMenuTestFailPush=$true;$global:LASTEXITCODE=0
    & (Join-Path $fixtureCode 'gmenu.ps1') $app 6>$null | Out-Null
    Check ($global:LASTEXITCODE -eq 1 -and [GMenuPayload20260916V2]::Hash($command) -eq $before) 'failed push returns failure status and preserves the previously saved restore command'
    $dispatch=Join-Path $env:USERPROFILE '.gmenu\Commands\gDispatchFixture.ps1'
    [IO.File]::WriteAllText($dispatch,"# GMENU GENERATED RESTORE COMMAND - synthetic fixture`r`n'NEW_MANAGED_BACKUP'")
    [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.gmenu\Commands\gDispatchFixture.receipt.json'),'{}')
    $route=& (Join-Path $PSScriptRoot 'Invoke-InstalledAppDockerRestoreAndLaunch.ps1') -Folder DispatchFixture
    Check ($route -eq 'NEW_MANAGED_BACKUP') 'legacy cached wrapper dispatches to newly registered gmenu backup'
    $managed=Join-Path $env:USERPROFILE '.gmenu\Commands\gtailscale.ps1'
    [IO.File]::WriteAllText($managed,"# GMENU GENERATED RESTORE COMMAND - synthetic fixture`r`n'MANAGED_LOADER_ROUTE'")
    [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.gmenu\Commands\gtailscale.receipt.json'),'{}')
    . (Join-Path $PSScriptRoot 'InstalledAppRestoreFunctions.ps1')
    Check ((gtailscale) -eq 'MANAGED_LOADER_ROUTE') 'installed-app loader preserves the managed restore function during profile reload'

    # Execute production upload orchestration with deterministic workers. One fails;
    # its healthy peer must complete without being cancelled or restarted.
    $mmenuPath=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\mmenu_chunked_push.ps1'
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($mmenuPath,[ref]$tokens,[ref]$errors)
    foreach($name in @('Test-MmenuCPythonCandidate','Get-MmenuCCommandPath','Convert-MmenuCSlug','ConvertTo-MmenuCExtendedPath','ConvertFrom-MmenuCExtendedPath','ConvertTo-MmenuCFolderTag','Get-MmenuCSourceStats','Test-MmenuCTempRootWritable','Get-MmenuCTempRoot')) {
        $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}.GetNewClosure(),$true)
        Check ($null -ne $node) ('publication exposes path/identity helper '+$name)
        . ([scriptblock]::Create($node.Extent.Text))
    }
    $verifiedPython=Get-MmenuCCommandPath @('py.exe','python.exe','python')
    Check (-not [string]::IsNullOrWhiteSpace($verifiedPython) -and (Test-MmenuCPythonCandidate $verifiedPython) -and $verifiedPython -notmatch '(?i)\\Microsoft\\WindowsApps\\') 'mmenu discovers a verified Python 3 interpreter instead of trusting the Store execution alias'
    $syntheticUnc='\\server\share\sample folder'
    $extendedSyntheticUnc=ConvertTo-MmenuCExtendedPath $syntheticUnc
    Check (($extendedSyntheticUnc -eq '\\?\UNC\server\share\sample folder') -and (ConvertFrom-MmenuCExtendedPath $extendedSyntheticUnc) -eq $syntheticUnc) 'Docker source scanner conversion handles UNC paths without treating UNC as a local drive'
    $unicodeTagA=ConvertTo-MmenuCFolderTag ([string][char]0x96ea) 128
    $unicodeTagB=ConvertTo-MmenuCFolderTag ([string][char]0x732b) 128
    Check ($unicodeTagA -ne $unicodeTagB -and $unicodeTagA -match '^folder-[a-f0-9]{12}$') 'Unicode-only mmenu tags are stable and distinct instead of colliding on backup'
    $longTag=ConvertTo-MmenuCFolderTag ('a' * 140) 128
    Check ($longTag.Length -eq 128 -and $longTag -match '-[a-f0-9]{12}$') 'overlength mmenu tags retain bounded length and a collision-resistant suffix'
    $sourceStats=Get-MmenuCSourceStats -Root $special
    Check ($sourceStats.Files -eq 1 -and $sourceStats.TotalBytes -eq ([IO.File]::ReadAllBytes((Join-Path $special 'Run.ps1')).Length) -and $sourceStats.Bad.Count -eq 0) 'source inventory handles spaces, brackets, apostrophes, and correct relative paths'
    $deepSourceStats=Get-MmenuCSourceStats -Root $deepFolder
    Check ($deepSourceStats.Files -eq 1 -and $deepSourceStats.TotalBytes -eq 4 -and $deepSourceStats.Bad.Count -eq 0) 'mmenu source inventory measures deep folder paths beyond MAX_PATH without losing files'
    $savedTempOverride=$env:HERMES_MMENU_TEMP_ROOT;$savedMmenuTempRoot=$script:MmenuCTempRoot
    try {
        $env:HERMES_MMENU_TEMP_ROOT=Join-Path $root 'controlled temp root';$script:MmenuCTempRoot=$null
        $controlledTemp=Get-MmenuCTempRoot -SourcePath $special
        Check ($controlledTemp -eq $env:HERMES_MMENU_TEMP_ROOT -and (Test-MmenuCTempRootWritable $controlledTemp)) 'mmenu verifies that its selected staging root is writable before use'
    } finally {
        if($null -eq $savedTempOverride){Remove-Item Env:HERMES_MMENU_TEMP_ROOT -ErrorAction SilentlyContinue}else{$env:HERMES_MMENU_TEMP_ROOT=$savedTempOverride}
        $script:MmenuCTempRoot=$savedMmenuTempRoot
    }
    $startupNode=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Ensure-MmenuCDockerVmmReady'},$true)
    if($null -eq $startupNode){$skipped.Add('optional Docker VMM cold-start helper is absent from this mmenu revision')}
    else {
      Check $true 'publication provides a bounded Docker VMM cold-start readiness path'
      & {
        . ([scriptblock]::Create($startupNode.Extent.Text))
        $starter=Join-Path $root 'start-fixture.ps1'
        [IO.File]::WriteAllText($starter,'$global:GMenuStartupFixture.Starts++; $global:GMenuStartupFixture.Desktop=$true')
        $global:GMenuStartupFixture=@{Starts=0;Desktop=$false;Vmm=$false;Ready=$true;Waits=0}
        function Get-Process {param($Name)if(($Name -contains 'com.docker.sailor' -and $global:GMenuStartupFixture.Vmm) -or ($Name -contains 'Docker Desktop' -and $global:GMenuStartupFixture.Desktop)){[pscustomobject]@{Id=123}}}
        function Wait-MenuCDockerEngineReady {param($DockerExe)$global:GMenuStartupFixture.Waits++;if($global:GMenuStartupFixture.Ready){$global:GMenuStartupFixture.Vmm=$true};return $global:GMenuStartupFixture.Ready}
        function Write-MmenuC {}
        Ensure-MmenuCDockerVmmReady -DockerExe 'fixture.exe' -StarterPath $starter
        Check ($global:GMenuStartupFixture.Starts -eq 1 -and $global:GMenuStartupFixture.Waits -eq 1) 'stopped Docker starts once and waits for engine readiness'
        $global:GMenuStartupFixture.Vmm=$false
        Ensure-MmenuCDockerVmmReady -DockerExe 'fixture.exe' -StarterPath $starter
        Check ($global:GMenuStartupFixture.Starts -eq 1 -and $global:GMenuStartupFixture.Waits -eq 2) 'already-starting Docker is awaited without a duplicate launch'
        $global:GMenuStartupFixture.Ready=$false
        $rejected=$false;try{Ensure-MmenuCDockerVmmReady -DockerExe 'fixture.exe' -StarterPath $starter}catch{$rejected=$_.Exception.Message -like '*did not become ready*'}
        Check $rejected 'Docker readiness failure prevents publication'
        $global:GMenuStartupFixture.Vmm=$false
        function Wait-MenuCDockerEngineReady {param($DockerExe)return $true}
        $rejected=$false;try{Ensure-MmenuCDockerVmmReady -DockerExe 'fixture.exe' -StarterPath $starter}catch{$rejected=$_.Exception.Message -like '*VMM*'}
        Check $rejected 'a ready engine without Docker VMM is rejected'
        Remove-Variable -Name GMenuStartupFixture -Scope Global
      }
    }
    foreach($name in @('Ensure-MmenuCLayerIntegrity','Invoke-MmenuCCurlRegistryPushLayersUntilSuccess','Write-MmenuCDashboard')) {
        $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}.GetNewClosure(),$true)
        . ([scriptblock]::Create($node.Extent.Text))
    }
    $layerPushAst=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-MmenuCCurlRegistryPushLayersUntilSuccess'},$true)
    Check ($layerPushAst.Extent.Text -notmatch 'overallDeadline|Registry upload deadline exceeded') 'large multilayer registry push has no fixed wall-clock cutoff while byte-progress guards remain active'
    $env:HERMES_MMENU_GMENU='1';$EntryPoint='fixture';$global:GMenuFixtureTokenCalls=0;$global:GMenuFixtureUploadStarts=@{};$global:GMenuFixtureCancelledHealthy=0
    [IO.File]::WriteAllText((Join-Path $root 'docker-credential-desktop.exe'),'fixture')
    $layerA=Join-Path $root 'a.tar';$layerB=Join-Path $root 'b.tar'
    [IO.File]::WriteAllText($layerA,'a');[IO.File]::WriteAllText($layerB,'bb')
    function Get-MmenuCWindowsRoot {return $env:SystemRoot}
    function Split-MmenuCImageRef {return @{Repository='fixture/test';Tag='fixture'}}
    function Get-MmenuCFileSha256WithProgress {param($FilePath)return 'sha256:'+([GMenuPayload20260916V2]::Hash($FilePath))}
    function Get-MmenuCDockerHubToken {$global:GMenuFixtureTokenCalls++;$script:MmenuCTokenRefreshAt=(Get-Date).AddMinutes(1);return 'fixture-token'}
    function Test-MmenuCRegistryBlobExists {return $false}
    function Start-MmenuCRegistryUpload {return 'https://registry.invalid/upload'}
    function Add-MmenuCRegistryDigestQuery {return 'https://registry.invalid/upload'}
    function Start-MmenuCRegistryCurlUploadProcess {
        param($CurlExe,$UploadUri,$Token,$FilePath,$LayerName)
        if(-not $global:GMenuFixtureUploadStarts.ContainsKey($LayerName)){$global:GMenuFixtureUploadStarts[$LayerName]=0};$global:GMenuFixtureUploadStarts[$LayerName]++
        $exitCode=if($LayerName -eq 'b.tar' -and $global:GMenuFixtureUploadStarts[$LayerName] -eq 1){22}else{0}
        $process=[pscustomobject]@{HasExited=$true;ExitCode=$exitCode;StandardError=(New-Object IO.StringReader('fixture 401'))}
        return [pscustomobject]@{Process=$process;FileSize=(Get-Item $FilePath).Length;LastReadBytes=0;BaselineRead=0;LayerName=$LayerName}
    }
    function Get-MmenuCProcessReadBytes {return 0}
    function Update-MmenuCLowSpeedGuard {return $false}
    function Remove-MmenuCRegistryCurlUploadProcessFiles {param($Upload)if($Upload.LayerName -eq 'a.tar' -and $global:GMenuFixtureUploadStarts['b.tar'] -eq 1 -and $Upload.Process.ExitCode -ne 0){$global:GMenuFixtureCancelledHealthy++}}
    function Invoke-MmenuCRegistryPutBlobBytes {return @{Digest=('sha256:'+('2'*64));Size=1}}
    function Invoke-MmenuCRegistryWebRequest {}
    function Write-MmenuC {}
    $code=Invoke-MmenuCCurlRegistryPushLayersUntilSuccess -DockerExe (Join-Path $root 'docker.exe') -LayerPaths @($layerA,$layerB) -ImageRef 'fixture/test:fixture' -Labels @{} 6>$null
    Check ($code -eq 0 -and $global:GMenuFixtureUploadStarts['b.tar'] -eq 2 -and $global:GMenuFixtureUploadStarts['a.tar'] -eq 1 -and $global:GMenuFixtureCancelledHealthy -eq 0) 'failed layer retries without restarting healthy parallel upload'
    Check ($global:GMenuFixtureTokenCalls -ge 3) '401 upload failure refreshes the token before retry'
    $display=(& {Write-MmenuCDashboard -Name 'fixture' -Phase 'test' -Started (Get-Date).AddSeconds(-1) -DoneBytes 1 -TotalBytes 3} 6>&1 | Out-String)
    Check ($display -match '33\.333%.*MiB/s') 'mmenu upload dashboard reports fractional percent and byte-rate progress'
    $largeDisplay=(& {Write-MmenuCDashboard -Name 'fixture' -Phase 'large-test' -Started (Get-Date).AddSeconds(-1) -DoneBytes 3GB -TotalBytes 4GB} 6>&1 | Out-String)
    Check ($largeDisplay -match '75\.000%') 'progress accepts payload sizes above the 32-bit integer limit'
    [pscustomobject]@{Status='PASSED';PowerShell=$PSVersionTable.PSVersion.ToString();Tests=$passed.Count;Cases=$passed.ToArray();Skipped=$skipped.ToArray();Transport='isolated fixture; no app backup or registry mutation'} | ConvertTo-Json -Depth 5
}finally {
    $env:USERPROFILE=$savedUser;$env:HERMES_MMENU_GMENU=$savedMode;$env:HERMES_MMENU_SOURCE_LABEL_PATH_OVERRIDE=$savedLabelPath
    if($null -eq $savedGMenuStateRoot){Remove-Item Env:GMENU_STATE_ROOT -ErrorAction SilentlyContinue}else{$env:GMENU_STATE_ROOT=$savedGMenuStateRoot}
    foreach($variable in $savedData.Keys){[Environment]::SetEnvironmentVariable($variable,$savedData[$variable],'Process')}
    Remove-Item -LiteralPath 'Function:\gFixturePublish' -ErrorAction SilentlyContinue
    Remove-GMenuWork $root $PSScriptRoot
}
