[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Path,
    [string]$Launcher,
    [string[]]$LaunchArguments=@(),
    [string[]]$DataPath=@(),
    [switch]$Plan,
    [switch]$NoRestore,
    [switch]$VerifyRestore,
    [switch]$PassThru
)
$ErrorActionPreference='Stop'
trap {
    $handledError=$_
    if($_.Exception -is [System.Management.Automation.PipelineStoppedException]){
        $global:LASTEXITCODE=130
        try{if($global:Error.Count -and [object]::ReferenceEquals($global:Error[0],$handledError)){$global:Error.RemoveAt(0)}}catch{}
        return
    }
    $message=if($_.Exception -and $_.Exception.Message){$_.Exception.Message}else{[string]$_}
    Write-Host ("[gm] FAILED: {0}; returning to PowerShell without an exception dump." -f $message) -ForegroundColor Red
    $global:LASTEXITCODE=1
    try{if($global:Error.Count -and [object]::ReferenceEquals($global:Error[0],$handledError)){$global:Error.RemoveAt(0)}}catch{}
    return
}
$gmenuStateRoot=if(-not [string]::IsNullOrWhiteSpace([string]$env:GMENU_STATE_ROOT)){
    [IO.Path]::GetFullPath([string]$env:GMENU_STATE_ROOT)
}elseif(Test-Path -LiteralPath 'F:\' -PathType Container -ErrorAction Ignore){
    'F:\backup\windowsapps\GMenuState'
}else{
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if([string]::IsNullOrWhiteSpace($local)){$local=[IO.Path]::GetTempPath()}
    if([string]::IsNullOrWhiteSpace($local)){throw 'No writable transient root is available for gm.'}
    Join-Path $local 'GMenuState'
}
$script:GMenuPayloadSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuPayload.cs'))
. (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
Initialize-GMenuRuntime
if(-not (Get-Command Test-GMenuGeneratedCommand -CommandType Function -ErrorAction Ignore)) {
    function Test-GMenuGeneratedCommand([string]$CandidatePath) {
        if(-not (Test-Path -LiteralPath $CandidatePath -PathType Leaf)) {return $false}
        try {
            $reader=New-Object IO.StreamReader($CandidatePath,$false)
            try {$firstLine=$reader.ReadLine()}finally {$reader.Dispose()}
            return $firstLine -eq '# GMENU GENERATED RESTORE COMMAND - PRIVATE RECOVERY KEY INCLUDED. Do not publish this script.'
        } catch {return $false}
    }
}
# The profile dispatcher can hot-reload its module while mmenu is running.
# Keep a private copy of the runtime resume body so a module refresh cannot
# make the cleanup path lose the service recovery command.
$gmenuResumeServicesBody = ${function:Resume-GMenuServices}
if(-not $gmenuResumeServicesBody){throw 'GMenu runtime did not provide its service recovery handler.'}
$gmenuEnsureResumeServices = {
    if(-not (Get-Command Resume-GMenuServices -CommandType Function -ErrorAction Ignore)) {
        Set-Item -LiteralPath Function:\Resume-GMenuServices -Value $gmenuResumeServicesBody -Force
    }
}
& $gmenuEnsureResumeServices
if($NoRestore -and $VerifyRestore){throw 'Use either -NoRestore or -VerifyRestore, not both.'}
Write-GMenuProgress 'prepare' 0 1 'resolving application and publisher'
if(-not $Path) {$Path=Read-Host 'Application folder to back up'}
if(-not (Test-Path -LiteralPath $Path -PathType Container) -and -not [IO.Path]::IsPathRooted($Path) -and $Path -notmatch '[\\/]' -and $Path -notmatch '^~') {
    $Path=Join-Path 'F:\backup\windowsapps\installed' $Path
}
$intendedSource=Resolve-GMenuFolderPath $Path -AllowMissing
$sourceExists=Test-Path -LiteralPath $intendedSource -PathType Container
$folder=[IO.Path]::GetFileName($intendedSource)
$folderHashAlgorithm=[Security.Cryptography.SHA256]::Create()
try {$folderHash=[BitConverter]::ToString($folderHashAlgorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($folder))).Replace('-','').ToLowerInvariant().Substring(0,12)}finally{$folderHashAlgorithm.Dispose()}
$name='g'+($folder -replace '[^a-zA-Z0-9]','')
if($name -in @('g','gm','gmenu') -or $name.Length -gt 96) {
    $nameBase=($folder -replace '[^a-zA-Z0-9]','')
    if(-not $nameBase){$nameBase='Folder'}
    if($nameBase.Length -gt 80){$nameBase=$nameBase.Substring(0,80)}
    $name='g'+$nameBase+'_'+$folderHash
}
$slug=($folder.ToLowerInvariant() -replace '[^a-z0-9._-]+','-' -replace '^[._-]+|[._-]+$','')
if(-not $slug){$slug='folder-'+$folderHash}
if($slug.Length -gt 100) {
    $slugSuffix='-'+$folderHash
    $slug=$slug.Substring(0,100-$slugSuffix.Length).TrimEnd('-','_','.')+$slugSuffix
}
$repository='michadockermisha/'+$slug
$stateRoot=$gmenuStateRoot
if(-not $Plan){
    $pendingMatches=@(Get-ChildItem -LiteralPath $stateRoot -Filter 'Pending-*.json' -File -ErrorAction Ignore | Where-Object {
        try {
            $candidateTicket=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            [string]$candidateTicket.Target -ieq $intendedSource
        } catch { $false }
    } | Sort-Object LastWriteTimeUtc -Descending)
    if($pendingMatches.Count){
        & (Join-Path $PSScriptRoot 'Resume-GMenuPublication.ps1') -PendingPath $pendingMatches[0].FullName -VerifyRestore:$VerifyRestore -PassThru:$PassThru
        return
    }
}
$commandRoot=Join-Path $stateRoot 'Commands'
$fallbackRoot=Join-Path $stateRoot 'Fallback'
$protectedCandidates=@(
    (Join-Path $commandRoot ($name+'.ps1')),
    (Join-Path $stateRoot ('CommandBackups\'+$name+'.ps1')),
    (Join-Path $fallbackRoot ('Commands\'+$name+'.ps1')),
    (Join-Path $fallbackRoot ('CommandBackups\'+$name+'.ps1'))
)
$protectedScript=$protectedCandidates | Where-Object {Test-GMenuGeneratedCommand $_} | Select-Object -First 1
$embeddedCommand=Get-Command $name -CommandType Function -ErrorAction Ignore | Where-Object {$_.Definition -like '*GMENU_EMBEDDED_COMMAND_V2*'} | Select-Object -First 1
if(-not $sourceExists) {
    if($Plan) {
        [pscustomobject]@{Function=$name;Source=$intendedSource;Repository=$repository;Status='Missing';ProtectedRestoreAvailable=[bool]($embeddedCommand -or $protectedScript);RestoreRequiresDocker=[bool]($embeddedCommand -or $protectedScript)}
        $global:LASTEXITCODE=0
        return
    }
    Write-GMenuProgress 'missing-source' 0 1 'application folder is absent; checking protected restore'
    if($embeddedCommand) {
        Write-GMenuProgress 'missing-source' 0 1 'restoring the self-contained saved profile function'
        & $embeddedCommand
        $restoreExit=$LASTEXITCODE
        if($null -ne $restoreExit){$global:LASTEXITCODE=$restoreExit}
        if($restoreExit -and $restoreExit -ne 0){throw "Embedded GMenu restore exited with code $restoreExit."}
        Write-GMenuProgress 'missing-source' 1 1 'protected restore completed'
        return
    } elseif($protectedScript) {
        Write-GMenuProgress 'missing-source' 0 1 'restoring the last verified protected image'
        & $protectedScript
        $restoreExit=$LASTEXITCODE
        if($null -ne $restoreExit){$global:LASTEXITCODE=$restoreExit}
        if($restoreExit -and $restoreExit -ne 0){throw "Protected GMenu restore exited with code $restoreExit."}
        Write-GMenuProgress 'missing-source' 1 1 'protected restore completed'
        return
    }
    Write-GMenuProgress 'missing-source' 1 1 'application folder is absent and no protected restore is available'
    Write-Host ("GMENU_MISSING_SOURCE path={0} function={1} action=restore-from-a-registered-protected-command-or-recreate-the-folder" -f $intendedSource,$name) -ForegroundColor Yellow
    $global:LASTEXITCODE=2
    return
}
$source=Assert-GMenuPath ((Get-Item -LiteralPath $intendedSource -Force).FullName)
$launch=Get-GMenuLaunchSpec $source $folder $Launcher
$relativeLauncher=$launch.Path
$launcherPath=Join-Path $source $relativeLauncher
$isDirectoryBackup=([string]$launch.Kind -eq 'Directory')
if(-not $PSBoundParameters.ContainsKey('LaunchArguments')){$LaunchArguments=@($launch.Arguments)}
$commandPath=Join-Path $commandRoot ($name+'.ps1')
$receiptPath=Join-Path $commandRoot ($name+'.receipt.json')
$existing=Get-Command $name -ErrorAction Ignore | Select-Object -First 1
if($existing -and $existing.CommandType -ne 'Function' -and -not (Test-Path -LiteralPath $receiptPath)) {throw "Existing command $name is a $($existing.CommandType), not an app restore function."}
$upgradeExisting=[bool]($existing -and -not (Test-Path -LiteralPath $receiptPath))
if($upgradeExisting){Write-Host ("GMENU upgrade-function name={0}; previous definition retained until publish succeeds" -f $name)}
if(Test-Path -LiteralPath $receiptPath) {
    $old=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if($old.Source -ine $source) {throw "$name belongs to a different source folder."}
}
Write-GMenuProgress 'prepare' 1 1 'application metadata resolved'
$links=@()
$sourceFiles=New-Object 'Collections.Generic.List[IO.FileInfo]'
$scanClock=[Diagnostics.Stopwatch]::StartNew();$scanCount=0
Write-GMenuProgress 'scan-files'
Get-GMenuFileSystemEntry $source | ForEach-Object {
    $link=$_
    $scanCount++
    if($scanClock.ElapsedMilliseconds -ge 250){Write-GMenuProgress 'scan-files' $scanCount;$scanClock.Restart()}
    if(-not ($link.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        if(-not $link.PSIsContainer){$sourceFiles.Add($link)}
        return
    }
    $record=Get-GMenuLinkRecord $source $link
    if($record){$links+=$record}
}
$roots=@($source)
$dataRoots=@()
$dataCandidates=@($DataPath)
foreach($environmentName in @('APPDATA','LOCALAPPDATA','ProgramData')) {
    $base=[Environment]::GetEnvironmentVariable($environmentName)
    if($base) {
        $auto=Join-Path $base $folder
        if(Test-Path -LiteralPath $auto -PathType Container) {$dataCandidates+=$auto}
    }
}
foreach($candidate in $dataCandidates | Select-Object -Unique) {
    if([string]::IsNullOrWhiteSpace([string]$candidate)){continue}
    $isExplicitDataPath=$false
    foreach($explicitCandidate in @($DataPath)) {
        if([string]$explicitCandidate -ieq [string]$candidate){$isExplicitDataPath=$true;break}
    }
    $logicalDataPath=$null
    try {
        $logicalProvider=$null;$logicalDrive=$null
        $logicalDataPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath([string]$candidate,[ref]$logicalProvider,[ref]$logicalDrive)
        if(-not $logicalProvider -or $logicalProvider.Name -ne 'FileSystem'){throw 'External data path must use the filesystem provider.'}
        $logicalDataPath=[IO.Path]::GetFullPath($logicalDataPath)
    } catch {
        if($isExplicitDataPath){throw "Explicit external data path could not be resolved: $candidate. $($_.Exception.Message)"}
        Write-GMenuProgress 'data-skip' 1 1 ("automatic data path skipped before use: {0}" -f $candidate)
        continue
    }
    try {
        # Resolve links before Assert-GMenuPath sees them.  A missing automatic
        # link target is stale state, not a reason to abort the application
        # backup; an explicitly supplied data path remains fail-closed.
        $data=Resolve-GMenuFolderPath $candidate -AllowMissing
    } catch {
        if($isExplicitDataPath){throw "Explicit external data path could not be resolved: $candidate. $($_.Exception.Message)"}
        Write-GMenuProgress 'data-skip' 1 1 ("automatic data path skipped because its target could not be resolved: {0}" -f $candidate)
        continue
    }
    if(-not (Test-Path -LiteralPath $data -PathType Container)) {
        if($isExplicitDataPath){throw 'External data path must be an existing app-specific folder, not an ancestor of the application.'}
        Write-GMenuProgress 'data-skip' 1 1 ("automatic data path skipped because its resolved target is missing: {0}" -f $candidate)
        continue
    }
    $data=Assert-GMenuPath $data
    if($data -eq $source -or $data.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) {continue}
    if($source.StartsWith($data+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'External data path must be an existing app-specific folder, not an ancestor of the application.'}
    $binding=$null
    foreach($environmentName in @('APPDATA','LOCALAPPDATA','ProgramData','USERPROFILE')) {
        $base=[Environment]::GetEnvironmentVariable($environmentName)
        if($base -and $logicalDataPath.StartsWith($base.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) {
            $binding=[pscustomobject]@{Environment=$environmentName;Relative=$logicalDataPath.Substring($base.TrimEnd('\').Length+1)}
            break
        }
    }
    if(-not $binding) {throw 'External data must be below the user profile or ProgramData so it can map to a fresh Windows account.'}
    if($roots -contains $data) {continue}
    foreach($link in Get-GMenuFileSystemEntry $data | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){$record=Get-GMenuLinkRecord $data $link $dataRoots.Count;if($record){$links+=$record}}
    $roots+=$data;$dataRoots+=$binding
}
$scanClock=[Diagnostics.Stopwatch]::StartNew();$scanCount=0
$files=@($sourceFiles.ToArray())+@(foreach($r in $roots | Select-Object -Skip 1){Get-GMenuFileSystemEntry $r | ForEach-Object {
    if($_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){return}
    $scanCount++
    if($scanClock.ElapsedMilliseconds -ge 250){Write-GMenuProgress 'scan-files' $scanCount;$scanClock.Restart()}
    $_
}})
Write-GMenuProgress 'scan-files' $files.Count ([Math]::Max(1,$files.Count))
$bytes=[long]0
foreach($file in $files) {
    # Get-ChildItem can return stale FileInfo.Length metadata for a file that
    # is still open for exclusive writes (for example, Maestro's adb.log).
    # Refresh before measuring so the plan and encrypted-payload inventory
    # report the actual on-disk size instead of silently reporting zero.
    try {$file.Refresh()} catch {throw "Could not refresh source-file metadata: $($file.FullName): $($_.Exception.Message)"}
    if(-not $file.Exists) {throw "Source file disappeared while measuring the backup: $($file.FullName)"}
    $bytes += [long]$file.Length
}
$portableStateWarnings=@()
$portableSourceRoot=ConvertFrom-GMenuExtendedPath $source
$portableSourcePrefix=$portableSourceRoot.TrimEnd('\','/')+'\'
foreach($file in $files) {
    $portableFilePath=ConvertFrom-GMenuExtendedPath ([string]$file.FullName)
    if(-not $portableFilePath.StartsWith($portableSourcePrefix,[StringComparison]::OrdinalIgnoreCase)){continue}
    $portableRelativePath=$portableFilePath.Substring($portableSourcePrefix.Length).Replace('\','/')
    if($portableRelativePath -ieq 'state/tmp/adb.log') {
        $portableStateWarnings += [pscustomobject]@{Path=$portableRelativePath;Reason='Transient ADB log: included when readable; omitted only if shared-read retries end in a Windows sharing or lock violation. Other source read failures stop the backup.'}
    }
}
$manifest=[ordered]@{Schema=1;Folder=$folder;Launcher=$relativeLauncher;LaunchKind=$launch.Kind;ReadinessUri=$launch.Uri;Arguments=$LaunchArguments;DataRoots=$dataRoots;Links=$links;WindowsKeys=@();PortableStateWarnings=$portableStateWarnings;DaymarkSyncKey=$null;Source=$source}
if($Plan) {
    [pscustomobject]@{Function=$name;Source=$source;Repository=$repository;Launcher=$relativeLauncher;LaunchKind=$launch.Kind;ReadinessUri=$launch.Uri;Arguments=$LaunchArguments;Files=$files.Count;Bytes=$bytes;Junctions=$links.Count;ExternalData=$dataRoots;PortableStateWarnings=$portableStateWarnings;Encrypted=$true;RestoreRequiresDocker=$false;SessionPortability='Windows Electron keys can be rewrapped; arbitrary app/server credentials are not universally portable'}
    $global:LASTEXITCODE=0
    return
}
$mmenuPublisherCandidates=@(
    (Join-Path $PSScriptRoot 'mmenu_chunked_push.ps1'),
    'F:\study\Platforms\windows\functions\mmenu_chunked_push.ps1',
    'F:\backup\windowsapps\GMenuState\mmenu_chunked_push.ps1'
)
$mmenuPublisher=$mmenuPublisherCandidates | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
if(-not $mmenuPublisher) {throw 'The gm publisher is missing from its local fallback and canonical source locations.'}
$preflightOldRepo=$env:HERMES_MMENU_REPOSITORY_OVERRIDE
$preflightOldTag=$env:HERMES_MMENU_TAG_OVERRIDE
$preflightOldProgress=$env:HERMES_MMENU_GMENU
try {
    $env:HERMES_MMENU_REPOSITORY_OVERRIDE=$repository
    $env:HERMES_MMENU_TAG_OVERRIDE='gmenu-20000101000000-00000000'
    $env:HERMES_MMENU_GMENU='1'
    $global:LASTEXITCODE=0
    & $mmenuPublisher -Path $source -TargetLayerMiB 256 -EntryPoint 'gm' -PreflightOnly | Out-Host
    if($LASTEXITCODE -ne 0){throw 'gm publisher preflight failed before snapshot creation.'}
} finally {
    $env:HERMES_MMENU_REPOSITORY_OVERRIDE=$preflightOldRepo
    $env:HERMES_MMENU_TAG_OVERRIDE=$preflightOldTag
    $env:HERMES_MMENU_GMENU=$preflightOldProgress
}
Protect-GMenuDirectory $stateRoot
Protect-GMenuDirectory $commandRoot
$id=[guid]::NewGuid().ToString('N')
$parent=[IO.Path]::GetDirectoryName($source)
$workParent=$stateRoot
$work=Join-Path $workParent ('.gmenu-work-'+$id)
if($env:GMENU_RESUME_WORK) {
    $resume=Assert-GMenuPath $env:GMENU_RESUME_WORK
    if([IO.Path]::GetDirectoryName($resume) -ne $workParent -or [IO.Path]::GetFileName($resume) -notmatch '^\.gmenu-work-[a-f0-9]{32}$' -or
       @(Get-ChildItem -LiteralPath $resume -Force | Where-Object Name -NotMatch '^snapshot-[0-9]+$').Count) {throw 'Only an unpublished snapshot workspace can be resumed.'}
    $work=$resume
}
Protect-GMenuDirectory $work
$pending=Join-Path $stateRoot ('Pending-'+$id+'.json')
$wasRunning=if($isDirectoryBackup){$false}else{@(Get-GMenuOwnedProcess $source).Count -gt 0}
$published=$false;$completed=$false;$payloadCreated=$false
$appWasStopped=$false;$appWasRestarted=$false
try {
    if($isDirectoryBackup) {
        # A directory/collection target has no unambiguous application owner.
        # Snapshot it without stopping descendant processes or inspecting
        # machine-bound application state. This is intentionally a data-safe
        # backup mode; explicit -Launcher keeps the normal app-consistent path.
        Write-GMenuProgress 'capture' 0 1 'capturing folder contents without stopping applications'
        $manifest.WindowsServices=@()
    } else {
        Write-GMenuProgress 'capture' 0 1 'stopping app and capturing portable state'
        $manifest.WindowsServices=@(Get-GMenuServiceManifest $source)
        Stop-GMenuApp $source
        $appWasStopped=$true
        foreach($file in $files | Where-Object { $_.Name -eq 'Local State' -and -not $_.FullName.StartsWith($source+'\Archive\',[StringComparison]::OrdinalIgnoreCase) }) {
            $protected=$null;$clear=$null
            try {
                $state=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
                if($state.os_crypt -and $state.os_crypt.app_bound_encrypted_key) {throw 'machine-bound application encryption cannot be rewrapped for another Windows account'}
                if($state.os_crypt -and $state.os_crypt.encrypted_key) {
                    $protected=[Convert]::FromBase64String([string]$state.os_crypt.encrypted_key)
                    if($protected.Length -le 5 -or [Text.Encoding]::ASCII.GetString($protected,0,5) -ne 'DPAPI') {throw 'the saved Windows session key is not a supported DPAPI record'}
                    $clear=[Security.Cryptography.ProtectedData]::Unprotect($protected[5..($protected.Length-1)],$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
                    $keyPath=$null
                    for($rootIndex=0;$rootIndex -lt $roots.Count;$rootIndex++) {
                        if($file.FullName.StartsWith($roots[$rootIndex]+'\',[StringComparison]::OrdinalIgnoreCase)) {
                            $prefix=if($rootIndex -eq 0){'app\'}else{'data'+($rootIndex-1)+'\'}
                            $keyPath=$prefix+$file.FullName.Substring($roots[$rootIndex].Length+1);break
                        }
                    }
                    if(-not $keyPath){throw 'the Windows session key could not be mapped into the backup'}
                    $manifest.WindowsKeys += [pscustomobject]@{Path=$keyPath;Key=[Convert]::ToBase64String($clear)}
                }
            } catch {
                $relativeState=if($file.FullName.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){$file.FullName.Substring($source.Length+1)}else{$file.FullName}
                $warningMessage=$_.Exception.Message
                $manifest.PortableStateWarnings += [pscustomobject]@{Path=$relativeState;Reason=$warningMessage}
                Write-Warning ("GMenu kept '{0}' in the payload but skipped non-portable session-key extraction: {1}." -f $relativeState,$warningMessage)
            } finally {
                if($clear){[Array]::Clear($clear,0,$clear.Length)}
                if($protected){[Array]::Clear($protected,0,$protected.Length)}
            }
        }
        if($folder -ieq 'daymark') {
            $capture=Join-Path $work 'daymark-session.json'
            $node=Get-Command node.exe -CommandType Application -ErrorAction Ignore | Select-Object -First 1 -ExpandProperty Source
            if(-not $node) {$node=Join-Path $env:ProgramFiles 'nodejs\node.exe'}
            & $node --no-warnings (Join-Path $PSScriptRoot 'GMenuDaymarkCapture.cjs') (Join-Path $source 'UserData') $capture | Out-Host
            if($LASTEXITCODE -ne 0) {throw 'Daymark session capture failed.'}
            $session=Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
            $manifest.DaymarkSyncKey=$session.SyncKey
            Remove-Item -LiteralPath $capture -Force
        }
    }
    Write-GMenuProgress 'capture' 1 1 'portable state captured'
    $key=[GMenuPayload20260916V2]::Random(32);$iv=[GMenuPayload20260916V2]::Random(16);$macKey=[GMenuPayload20260916V2]::Random(32)
    $publishRoot=Join-Path $work $folder
    [void][IO.Directory]::CreateDirectory($publishRoot)
    Write-GMenuProgress 'pack' 0 1 'creating encrypted payload with live byte progress'
    $progress=[Action[string,long,long]]{param($phase,$done,$total) Write-GMenuProgress $phase $done $total}
    $packed=[GMenuPayload20260916V2]::PackParts([string[]]$roots,($manifest | ConvertTo-Json -Depth 100 -Compress),$publishRoot,$key,$iv,$macKey,256MB,$progress)
    foreach($skippedFile in @($packed.SkippedFiles)) {
        Write-Warning ("GMenu omitted only the transient file '{0}' after a persistent Windows sharing/lock violation." -f $skippedFile)
    }
    Write-GMenuProgress 'pack' 1 1 'encrypted payload complete'
    $tag='gmenu-'+(Get-Date -Format 'yyyyMMddHHmmss')+'-'+$id.Substring(0,8)
    $ticket=[ordered]@{Schema=1;Function=$name;Folder=$folder;Target=$source;Repository=$repository;Tag=$tag;Digest=$null;Files=$packed.Files;Bytes=$packed.Bytes;SkippedFiles=@($packed.SkippedFiles);PortableStateWarnings=@($manifest.PortableStateWarnings);Key=[Convert]::ToBase64String($key);IV=[Convert]::ToBase64String($iv);MacKey=[Convert]::ToBase64String($macKey);Mac=$packed.Mac;Parts=@($packed.Parts)}
    [IO.File]::WriteAllText($pending,($ticket | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    $payloadCreated=$true
    & $gmenuResumeServicesBody $source
    if($wasRunning){& $gmenuEnsureResumeServices;[void](Start-GMenuApp $source $manifest -NoWait);$appWasRestarted=$true}
    $oldRepo=$env:HERMES_MMENU_REPOSITORY_OVERRIDE;$oldTag=$env:HERMES_MMENU_TAG_OVERRIDE
    $oldProgress=$env:HERMES_MMENU_GMENU
    $oldLabelPath=$env:HERMES_MMENU_SOURCE_LABEL_PATH_OVERRIDE
    try {
        $env:HERMES_MMENU_REPOSITORY_OVERRIDE=$repository
        $env:HERMES_MMENU_TAG_OVERRIDE=$tag
        $env:HERMES_MMENU_GMENU='1'
        # mmenu builds from the encrypted staging folder, but restore must
        # validate against the real installed-app target.  Keep that
        # provenance explicit for every GMenu-generated image.
        $env:HERMES_MMENU_SOURCE_LABEL_PATH_OVERRIDE=$source
        Write-GMenuProgress 'publish' 0 1 'publishing and verifying remote layers'
        $global:LASTEXITCODE=0
        & $mmenuPublisher -Path $publishRoot -TargetLayerMiB 256 -EntryPoint 'gm' | Out-Host
        if($LASTEXITCODE -ne 0) {throw 'gm publisher failed; no restore function was registered.'}
    } finally {$env:HERMES_MMENU_REPOSITORY_OVERRIDE=$oldRepo;$env:HERMES_MMENU_TAG_OVERRIDE=$oldTag;$env:HERMES_MMENU_GMENU=$oldProgress;$env:HERMES_MMENU_SOURCE_LABEL_PATH_OVERRIDE=$oldLabelPath}
    Write-GMenuProgress 'verify-published-manifest' 0 1 'reading remote manifest'
    $credential=Get-GMenuLocalHubCredential
    $token=Get-GMenuHubToken $repository $credential
    $remote=Get-GMenuManifest $repository $tag $work $token
    Write-GMenuProgress 'verify-published-manifest' 1 1 'remote manifest digest verified'
    $ticket.Digest=$remote.Digest
    Write-GMenuProgress 'publish' 1 1 'remote manifest verified'
    $published=$true
    [IO.File]::WriteAllText($pending,($ticket | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    $ticketBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($ticket | ConvertTo-Json -Depth 20 -Compress)))
    $sourceBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script:GMenuPayloadSource))
    $runtime=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuRuntime.ps1'))
    $header=@'
# GMENU GENERATED RESTORE COMMAND - PRIVATE RECOVERY KEY INCLUDED. Do not publish this script.
[CmdletBinding()]
param([string]$Destination,[pscredential]$Credential,[switch]$RestoreOnly)
$ErrorActionPreference='Stop'
'@
    $text=$header+[Environment]::NewLine+
        ('$script:GMenuPayloadSource=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$sourceBase64+'''))')+[Environment]::NewLine+
        ('$script:GMenuTicket=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$ticketBase64+''')) | ConvertFrom-Json')+[Environment]::NewLine+
        $runtime+[Environment]::NewLine+
        'Invoke-GMenuRestore -Ticket $script:GMenuTicket -Destination $Destination -Credential $Credential -RestoreOnly:$RestoreOnly'
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    if($errors.Count) {throw 'Generated restore command failed parser validation.'}
    $generatedPath=Join-Path $work ($name+'.generated.ps1')
    [IO.File]::WriteAllText($generatedPath,$text,(New-Object Text.UTF8Encoding($false)))
    Write-GMenuProgress 'save-function' 0 1 'writing durable restore command'
    Register-GMenuPortableCommand -Ticket ([pscustomobject]$ticket) -SourceScript $generatedPath -UpgradeExisting
    $receipt=[pscustomobject]@{Function=$name;Source=$source;Repository=$repository;Tag=$tag;Digest=$ticket.Digest;Files=$ticket.Files;Bytes=$ticket.Bytes;CreatedAt=(Get-Date).ToString('o');Script='embedded-in-profile';VerifiedRestore=$false}
    Write-GMenuProgress 'save-function' 1 1 'durable restore command registered'
    if($VerifyRestore) {
        $restoreResult=& $generatedPath -Credential $credential
        $restoreResult | Out-Host
        $receipt.VerifiedRestore=[bool](@($restoreResult | Where-Object {$_.Status -eq 'RESTORE_LAUNCHED'}).Count)
    }
    $completed=$true
} finally {
    Write-GMenuProgress 'cleanup' 0 1 'restoring service state and removing temporary files'
    & $gmenuResumeServicesBody $source
    if($wasRunning -and $appWasStopped -and -not $appWasRestarted -and (Test-Path -LiteralPath $launcherPath)) {
        try {& $gmenuEnsureResumeServices;[void](Start-GMenuApp $source $manifest -NoWait)}catch{Write-Warning 'Original app did not reopen; its files remain available.'}
    }
    $cleanupIssues=New-Object 'Collections.Generic.List[string]'
    $cleanupNow=$completed -or -not $payloadCreated
    if($cleanupNow) {
        if([IO.File]::Exists($pending)) {
            try {[IO.File]::Delete($pending)} catch {[void]$cleanupIssues.Add(('pending ticket: '+$_.Exception.Message))}
        }
        if([IO.Directory]::Exists($work)) {
            try {Remove-GMenuWork $work $workParent} catch {[void]$cleanupIssues.Add(('encrypted workspace: '+$_.Exception.Message))}
        }
    }
    if(-not $cleanupNow) {
        Write-Host ("GMENU_RECOVERY_SAVED pending={0} work={1}" -f $pending,$work) -ForegroundColor Yellow
        Write-GMenuProgress 'cleanup' 1 1 'failed publication retained for verified resume; no encrypted bytes were discarded'
    } elseif([IO.File]::Exists($pending) -or [IO.Directory]::Exists($work)) {
        Write-Warning ('GMenu temporary cleanup was incomplete: '+($cleanupIssues -join '; '))
    } else {
        Write-GMenuProgress 'cleanup' 1 1 'all temporary payload and ticket files removed'
        if($completed -and [IO.Directory]::Exists($stateRoot)) {
            $emptyDirectories=@(Get-ChildItem -LiteralPath $stateRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object {$_.FullName.Length} -Descending)
            foreach($emptyDirectory in $emptyDirectories){if(-not @(Get-ChildItem -LiteralPath $emptyDirectory.FullName -Force -ErrorAction SilentlyContinue).Count){try{[IO.Directory]::Delete($emptyDirectory.FullName)}catch{}}}
            if(-not @(Get-ChildItem -LiteralPath $stateRoot -Force -ErrorAction SilentlyContinue).Count){try{[IO.Directory]::Delete($stateRoot)}catch{}}
        }
    }
}
Write-GMenuProgress 'complete' 1 1
Write-Host ("GMENU_SAVED function={0} image={1}:{2}" -f $name,$repository,$tag)
$global:LASTEXITCODE=0
if($PassThru){$receipt}
