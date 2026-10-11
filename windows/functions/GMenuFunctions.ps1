# Keep the command available even when a new shell starts before the F: drive is
# mounted.  The fallback is a byte-for-byte local copy refreshed with the
# canonical sources; the first existing candidate always wins.
function global:Invoke-GMenuCommand {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]$Path,
        [Parameter(Position=1)][string]$Launcher,
        [Parameter(Position=2)][string[]]$LaunchArguments=@(),
        [Parameter(Position=3)][string[]]$DataPath=@(),
        [Parameter(Position=4)][switch]$Plan,
        [Parameter(Position=5)][switch]$NoRestore,
        [Parameter(Position=6)][switch]$VerifyRestore,
        [Parameter(Position=7)][switch]$PassThru
    )
    $invokeParameters=@{}
    if($PSBoundParameters.ContainsKey('Path')){$invokeParameters.Path=$Path}
    if($PSBoundParameters.ContainsKey('Launcher')){$invokeParameters.Launcher=$Launcher}
    if($PSBoundParameters.ContainsKey('LaunchArguments') -and @($LaunchArguments).Count){$invokeParameters.LaunchArguments=@($LaunchArguments)}
    if($PSBoundParameters.ContainsKey('DataPath') -and @($DataPath).Count){$invokeParameters.DataPath=@($DataPath)}
    foreach($gmSwitchName in @('Plan','NoRestore','VerifyRestore','PassThru')) {
        if($PSBoundParameters.ContainsKey($gmSwitchName) -and [bool]$PSBoundParameters[$gmSwitchName]){$invokeParameters[$gmSwitchName]=$true}
    }
    $errorCountBefore=$global:Error.Count
    $entryCandidates=@(
        'F:\study\Platforms\windows\functions\gmenu.ps1',
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\GMenuFallback\gmenu.ps1'),
        'F:\backup\windowsapps\GMenuState\gmenu.ps1'
    )
    $entry=$null
    foreach($entryCandidate in $entryCandidates) {
        if(-not (Test-Path -LiteralPath $entryCandidate -PathType Leaf -ErrorAction Ignore)){continue}
        $entryRoot=Split-Path -Parent $entryCandidate
        $requiredBackendFiles=@(
            (Join-Path $entryRoot 'GMenuRuntime.ps1'),
            (Join-Path $entryRoot 'GMenuPayload.cs'),
            (Join-Path $entryRoot 'Resume-GMenuPublication.ps1'),
            (Join-Path $entryRoot 'mmenu_chunked_push.ps1')
        )
        if(@($requiredBackendFiles | Where-Object {-not (Test-Path -LiteralPath $_ -PathType Leaf -ErrorAction Ignore)}).Count){continue}
        $entry=$entryCandidate
        break
    }
    if(-not $entry) {
        Write-Host '[gm] UNAVAILABLE: no canonical or fallback backend exists; returning to PowerShell without an exception.' -ForegroundColor Red
        $global:LASTEXITCODE=127
        return
    }
    $previousErrorActionPreference=$ErrorActionPreference
    $locationPushed=$false
    $entryExitCode=0
    try {
        Push-Location
        $locationPushed=$true
        $ErrorActionPreference='Stop'
        $global:LASTEXITCODE=0
        & $entry @invokeParameters
        $entryExitCode=if($null -eq $global:LASTEXITCODE){0}else{[int]$global:LASTEXITCODE}
    } catch {
        $message=if($_.Exception -and $_.Exception.Message){$_.Exception.Message}else{[string]$_}
        Write-Host ("[gm] FAILED: {0}; returning to PowerShell without an exception dump." -f $message) -ForegroundColor Red
        $entryExitCode=1
    } finally {
        $ErrorActionPreference=$previousErrorActionPreference
        if($locationPushed){try{Pop-Location -ErrorAction Stop}catch{}}
        try{while($global:Error.Count -gt $errorCountBefore){$global:Error.RemoveAt(0)}}catch{}
        $global:LASTEXITCODE=$entryExitCode
    }
}

# Keep the former name as a compatibility entry point while making `gm` the
# canonical public command. PowerShell ships `gm` as an AllScope Get-Member
# alias, so use a real function instead of an alias whose target can disappear
# during a profile/module refresh.
function global:gmenu {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Position=0,ValueFromRemainingArguments=$true)][Alias('Path')][string[]]$Paths=@(),
        [string]$Launcher,
        [string[]]$LaunchArguments=@(),
        [string[]]$DataPath=@(),
        [switch]$Plan,
        [switch]$NoRestore,
        [switch]$VerifyRestore,
        [switch]$PassThru
    )
    gm @PSBoundParameters
}
try {
    for($gmAliasRemovalAttempt=0;$gmAliasRemovalAttempt -lt 8;$gmAliasRemovalAttempt++) {
        if(-not (Get-Command gm -CommandType Alias -ErrorAction Ignore)){break}
        try { $ExecutionContext.SessionState.InvokeProvider.Item.Remove(@('Alias:\gm'),$false,$true,$true) } catch {}
    }
} catch {}
function global:gm {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Position=0,ValueFromRemainingArguments=$true)][Alias('Path')][string[]]$Paths=@(),
        [string]$Launcher,
        [string[]]$LaunchArguments=@(),
        [string[]]$DataPath=@(),
        [switch]$Plan,
        [switch]$NoRestore,
        [switch]$VerifyRestore,
        [switch]$PassThru
    )
    $gmTarget=Get-Command Invoke-GMenuCommand -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $gmTarget) {
        # A profile refresh can leave the public wrapper in memory after its
        # backend was replaced or omitted. Try each durable source until the
        # complete command backend is available.
        $gmBootstrapCandidates=@(
            'F:\study\Platforms\windows\functions\GMenuFunctions.ps1',
            (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\GMenuFallback\GMenuFunctions.ps1'),
            'F:\backup\windowsapps\GMenuState\GMenuFunctions.ps1'
        )
        foreach($gmBootstrapSource in @($gmBootstrapCandidates | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf -ErrorAction SilentlyContinue})) {
            try { . $gmBootstrapSource } catch {}
            $gmTarget=Get-Command Invoke-GMenuCommand -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
            if($gmTarget){break}
        }
    }
    if(-not $gmTarget) {
        Write-Host '[gm] UNAVAILABLE: GMenu command backend is not loaded; returning to PowerShell without an exception.' -ForegroundColor Red
        $global:LASTEXITCODE=127
        return
    }
    $gmCommonParameters=@{}
    if($PSBoundParameters.ContainsKey('Launcher')){$gmCommonParameters.Launcher=$Launcher}
    if($PSBoundParameters.ContainsKey('LaunchArguments') -and @($LaunchArguments).Count){$gmCommonParameters.LaunchArguments=@($LaunchArguments)}
    if($PSBoundParameters.ContainsKey('DataPath') -and @($DataPath).Count){$gmCommonParameters.DataPath=@($DataPath)}
    foreach($gmSwitchName in @('Plan','NoRestore','VerifyRestore','PassThru')) {
        if($PSBoundParameters.ContainsKey($gmSwitchName) -and [bool]$PSBoundParameters[$gmSwitchName]){$gmCommonParameters[$gmSwitchName]=$true}
    }
    $gmBatchPaths=@($Paths)
    if(-not $gmBatchPaths.Count) {
        Write-Host '[gm] no folder path supplied; use gm <folder> or gmall.' -ForegroundColor Yellow
        $global:LASTEXITCODE=2
        return
    }
    $gmBatchCount=$gmBatchPaths.Count
    $gmBatchFailureCount=0
    $gmBatchExitCode=0
    for($gmBatchIndex=0;$gmBatchIndex -lt $gmBatchCount;$gmBatchIndex++) {
        $gmOneParameters=@{}
        if($gmBatchPaths.Count){$gmOneParameters.Path=[string]$gmBatchPaths[$gmBatchIndex]}
        foreach($gmParameterName in $gmCommonParameters.Keys){$gmOneParameters[$gmParameterName]=$gmCommonParameters[$gmParameterName]}
        if($gmBatchCount -gt 1){Write-Host ("[gm] Batch {0}/{1}: {2}" -f ($gmBatchIndex+1),$gmBatchCount,$gmBatchPaths[$gmBatchIndex]) -ForegroundColor Cyan}
        $global:LASTEXITCODE=0
        try {
            Invoke-GMenuCommand @gmOneParameters
            $gmItemExitCode=if($null -eq $global:LASTEXITCODE){0}else{[int]$global:LASTEXITCODE}
        } catch {
            $gmMessage=if($_.Exception -and $_.Exception.Message){$_.Exception.Message}else{[string]$_}
            Write-Host ("[gm] FAILED for '{0}': {1}; continuing with the remaining folders." -f $(if($gmBatchPaths.Count){$gmBatchPaths[$gmBatchIndex]}else{'(interactive)'}),$gmMessage) -ForegroundColor Red
            $gmItemExitCode=1
        }
        if($gmItemExitCode -ne 0) {
            $gmBatchFailureCount++
            if($gmBatchExitCode -eq 0){$gmBatchExitCode=$gmItemExitCode}
        }
        if($gmBatchCount -gt 1) {
            if($gmItemExitCode -eq 0){Write-Host ("[gm] Batch {0}/{1} completed." -f ($gmBatchIndex+1),$gmBatchCount) -ForegroundColor Green}
            else{Write-Host ("[gm] Batch {0}/{1} failed with exit code {2}; continuing." -f ($gmBatchIndex+1),$gmBatchCount,$gmItemExitCode) -ForegroundColor Yellow}
        }
    }
    if($gmBatchCount -gt 1){
        if($gmBatchFailureCount){Write-Host ("[gm] Batch finished: {0} folder(s), {1} failed; overall exit code {2}." -f $gmBatchCount,$gmBatchFailureCount,$gmBatchExitCode) -ForegroundColor Yellow}
        else{Write-Host ("[gm] Batch finished successfully: {0} folder(s)." -f $gmBatchCount) -ForegroundColor Green}
    }
    $global:LASTEXITCODE=$gmBatchExitCode
}

# Resolve a user-supplied folder using PowerShell's filesystem provider so
# relative paths, home paths, UNC paths, and names with literal metacharacters
# all have one consistent interpretation. A bare folder name keeps the legacy
# E:\games and installed-app lookup after checking the current directory.
function global:Resolve-GGMFolderPath([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path)){throw 'A source folder path is required.'}
    $exactPath=[IO.Path]::IsPathRooted($Path) -or $Path -match '[\\/]' -or $Path.StartsWith('~') -or $Path -in @('.','..') -or $Path -match '^[^\\/:]+:'
    $candidates=New-Object 'Collections.Generic.List[string]'
    if($exactPath) {
        $candidates.Add($Path)
    } else {
        if((Get-Location).Provider.Name -eq 'FileSystem'){$candidates.Add((Join-Path (Get-Location).ProviderPath $Path))}
        $candidates.Add((Join-Path 'E:\games' $Path))
        $candidates.Add((Join-Path 'F:\backup\windowsapps\installed' $Path))
    }
    foreach($candidate in $candidates) {
        try {
            $provider=$null;$drive=$null
            $full=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($candidate,[ref]$provider,[ref]$drive)
            if(-not $provider -or $provider.Name -ne 'FileSystem'){throw 'Use a filesystem folder for ggm.'}
            $full=[IO.Path]::GetFullPath($full)
            $root=[IO.Path]::GetPathRoot($full)
            if([string]::IsNullOrWhiteSpace($root)){throw "ggm could not resolve a filesystem root for: $candidate"}
            if($full.TrimEnd('\','/') -ieq $root.TrimEnd('\','/')){throw 'ggm requires a folder below a drive or network-share root.'}
            $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $resolved=$false
            for($hop=0;$hop -lt 128;$hop++) {
                $root=[IO.Path]::GetPathRoot($full)
                $relative=$full.Substring($root.Length).TrimStart([char]'\',[char]'/')
                $parts=@(($relative -split '[\\/]+') | Where-Object {$_})
                $cursor=$root
                $redirected=$false
                for($index=0;$index -lt $parts.Count;$index++) {
                    $cursor=[IO.Path]::Combine($cursor,$parts[$index])
                    $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
                    if(-not $item){continue}
                    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                        if(-not $seen.Add([string]$item.FullName)){throw "Cyclic filesystem path cannot be resolved: $($item.FullName)"}
                        $target=@($item.Target | Select-Object -First 1)
                        if(-not $target -or [string]::IsNullOrWhiteSpace([string]$target[0])){throw "The redirected folder has no readable target: $($item.FullName)"}
                        $targetPath=[string]$target[0]
                        if(-not [IO.Path]::IsPathRooted($targetPath)){$targetPath=Join-Path (Split-Path -Parent $item.FullName) $targetPath}
                        $targetPath=[IO.Path]::GetFullPath($targetPath)
                        if($index+1 -lt $parts.Count){$targetPath=[IO.Path]::Combine($targetPath,($parts[($index+1)..($parts.Count-1)] -join '\'))}
                        $full=[IO.Path]::GetFullPath($targetPath)
                        if([IO.Path]::GetPathRoot($full).TrimEnd('\','/') -ieq $full.TrimEnd('\','/')){throw 'ggm requires a folder below a drive or network-share root.'}
                        $redirected=$true
                        break
                    }
                    if(-not $item.PSIsContainer -and $index -lt ($parts.Count-1)){throw "A path component is not a folder: $($item.FullName)"}
                }
                if(-not $redirected){$resolved=$true;break}
            }
            if(-not $resolved){throw 'Filesystem path contains more than 128 nested directory links.'}
            $item=Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
            if($item -and $item.PSIsContainer){return [string]$item.FullName}
        } catch {
            if($exactPath){throw}
        }
    }
    throw "ggm source folder does not exist or is not accessible: $Path"
}

# BEGIN GGM DURABLE WRAPPER
function global:Invoke-GGMCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromRemainingArguments=$true)][Alias('Path')][string[]]$Paths,
        [switch]$PreflightOnly,
        [switch]$TarPreflightOnly,
        [switch]$BuildPreflightOnly,
        [ValidateRange(128,4096)][int64]$TargetLayerMiB=4096
    )
    $ggmBatchPaths=@($Paths)
    $ggmBatchFailureCount=0
    $ggmBatchExitCode=0
    for($ggmBatchIndex=0;$ggmBatchIndex -lt $ggmBatchPaths.Count;$ggmBatchIndex++) {
        $ggmPath=[string]$ggmBatchPaths[$ggmBatchIndex]
        $ggmErrorCountBefore=$global:Error.Count
        $ggmPreviousErrorActionPreference=$ErrorActionPreference
        $ggmPreviousRepository=$env:HERMES_MMENU_REPOSITORY_OVERRIDE
        $ggmPreviousTag=$env:HERMES_MMENU_TAG_OVERRIDE
        $ggmLocationPushed=$false
        $ggmExitCode=0
        if($ggmBatchPaths.Count -gt 1){Write-Host ("[ggm] Batch {0}/{1}: {2}" -f ($ggmBatchIndex+1),$ggmBatchPaths.Count,$ggmPath) -ForegroundColor Cyan}
        $global:LASTEXITCODE=0
        try {
            Push-Location
            $ggmLocationPushed=$true
            $ErrorActionPreference='Stop'
            $ggmResolved=Resolve-GGMFolderPath $ggmPath
            # A genuine mmenu invocation already selects exactly
            # michadockermisha/backup:<folder-slug>.  Clear both private gmenu
            # overrides while it runs so a caller's environment cannot turn this
            # into a menu/gmenu publication or leave an invalid half-pair.
            Remove-Item Env:HERMES_MMENU_REPOSITORY_OVERRIDE -ErrorAction SilentlyContinue
            Remove-Item Env:HERMES_MMENU_TAG_OVERRIDE -ErrorAction SilentlyContinue
            $ggmParameters=@{Path=$ggmResolved;TargetLayerMiB=$TargetLayerMiB;EntryPoint='mmenu'}
            if($PreflightOnly){$ggmParameters.PreflightOnly=$true}
            if($TarPreflightOnly){$ggmParameters.TarPreflightOnly=$true}
            if($BuildPreflightOnly){$ggmParameters.BuildPreflightOnly=$true}
            Invoke-HermesDockerChunkedBackupPush @ggmParameters
            $ggmExitCode=if($null -eq $global:LASTEXITCODE){0}else{[int]$global:LASTEXITCODE}
        } catch {
            $ggmMessage=if($_.Exception -and $_.Exception.Message){$_.Exception.Message}else{[string]$_}
            Write-Host ("[ggm] FAILED for '{0}': {1}; continuing with the remaining folders." -f $ggmPath,$ggmMessage) -ForegroundColor Red
            $ggmExitCode=1
        } finally {
            if($null -eq $ggmPreviousRepository){Remove-Item Env:HERMES_MMENU_REPOSITORY_OVERRIDE -ErrorAction SilentlyContinue}else{$env:HERMES_MMENU_REPOSITORY_OVERRIDE=$ggmPreviousRepository}
            if($null -eq $ggmPreviousTag){Remove-Item Env:HERMES_MMENU_TAG_OVERRIDE -ErrorAction SilentlyContinue}else{$env:HERMES_MMENU_TAG_OVERRIDE=$ggmPreviousTag}
            $ErrorActionPreference=$ggmPreviousErrorActionPreference
            if($ggmLocationPushed){try{Pop-Location -ErrorAction Stop}catch{$ggmExitCode=1}}
            try{while($global:Error.Count -gt $ggmErrorCountBefore){$global:Error.RemoveAt(0)}}catch{}
        }
        if($ggmExitCode -ne 0) {
            $ggmBatchFailureCount++
            if($ggmBatchExitCode -eq 0){$ggmBatchExitCode=$ggmExitCode}
        }
        if($ggmBatchPaths.Count -gt 1) {
            if($ggmExitCode -eq 0){Write-Host ("[ggm] Batch {0}/{1} completed." -f ($ggmBatchIndex+1),$ggmBatchPaths.Count) -ForegroundColor Green}
            else{Write-Host ("[ggm] Batch {0}/{1} failed with exit code {2}; continuing." -f ($ggmBatchIndex+1),$ggmBatchPaths.Count,$ggmExitCode) -ForegroundColor Yellow}
        }
    }
    if($ggmBatchPaths.Count -gt 1){
        if($ggmBatchFailureCount){Write-Host ("[ggm] Batch finished: {0} folder(s), {1} failed; overall exit code {2}." -f $ggmBatchPaths.Count,$ggmBatchFailureCount,$ggmBatchExitCode) -ForegroundColor Yellow}
        else{Write-Host ("[ggm] Batch finished successfully: {0} folder(s)." -f $ggmBatchPaths.Count) -ForegroundColor Green}
    }
    $global:LASTEXITCODE=$ggmBatchExitCode
}
function global:ggm {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Position=0,ValueFromRemainingArguments=$true)][Alias('Path')][object[]]$Paths=@(),
        [switch]$PreflightOnly,
        [switch]$TarPreflightOnly,
        [switch]$BuildPreflightOnly,
        [object]$TargetLayerMiB=4096
    )
    $rawPaths=@($Paths | ForEach-Object {[string]$_} | Where-Object {-not [string]::IsNullOrWhiteSpace($_)})
    if(-not $rawPaths.Count) {
        Write-Host '[ggm] no source folder path supplied; use ggm <folder>.' -ForegroundColor Yellow
        $global:LASTEXITCODE=2
        return
    }
    $parsedTarget=0L
    try {$parsedTarget=[int64]$TargetLayerMiB} catch {
        Write-Host ("[ggm] invalid target layer size '{0}'; expected 128..4096 MiB." -f $TargetLayerMiB) -ForegroundColor Yellow
        $global:LASTEXITCODE=2
        return
    }
    if($parsedTarget -lt 128 -or $parsedTarget -gt 4096) {
        Write-Host ("[ggm] invalid target layer size {0}; expected 128..4096 MiB." -f $parsedTarget) -ForegroundColor Yellow
        $global:LASTEXITCODE=2
        return
    }
    $forward=@{Paths=$rawPaths;TargetLayerMiB=$parsedTarget}
    if($PreflightOnly){$forward.PreflightOnly=$true}
    if($TarPreflightOnly){$forward.TarPreflightOnly=$true}
    if($BuildPreflightOnly){$forward.BuildPreflightOnly=$true}
    try {
        Invoke-GGMCommand @forward
        $global:LASTEXITCODE=if($null -eq $global:LASTEXITCODE){0}else{[int]$global:LASTEXITCODE}
    } catch {
        $message=if($_.Exception -and $_.Exception.Message){$_.Exception.Message}else{[string]$_}
        Write-Host ("[ggm] FAILED: {0}; returning to PowerShell without an exception dump." -f $message) -ForegroundColor Red
        $global:LASTEXITCODE=1
    }
}
# END GGM DURABLE WRAPPER


function Get-GMenuStateRoot {
    if(-not [string]::IsNullOrWhiteSpace($env:GMENU_STATE_ROOT)) {
        return [IO.Path]::GetFullPath($env:GMENU_STATE_ROOT)
    }
    if(Test-Path -LiteralPath 'F:\' -PathType Container -ErrorAction Ignore){return 'F:\backup\windowsapps\GMenuState'}
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if([string]::IsNullOrWhiteSpace($local)){$local=[IO.Path]::GetTempPath()}
    if([string]::IsNullOrWhiteSpace($local)){throw 'No writable transient root is available for GMenu.'}
    return (Join-Path $local 'GMenuState')
}

function Get-GMenuSavedCommandRoot {
    return (Join-Path (Get-GMenuStateRoot) 'Commands')
}

function Get-GMenuFallbackRoot {
    return (Join-Path (Get-GMenuStateRoot) 'Fallback')
}

function Get-GMenuFallbackCommandRoots {
    $root=Get-GMenuFallbackRoot
    return @((Join-Path $root 'Commands'),(Join-Path $root 'CommandBackups'))
}

function Test-GMenuGeneratedCommand([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)) {return $false}
    try {
        $reader=New-Object IO.StreamReader($Path,$false)
        try {$firstLine=$reader.ReadLine()}finally {$reader.Dispose()}
        return $firstLine -eq '# GMENU GENERATED RESTORE COMMAND - PRIVATE RECOVERY KEY INCLUDED. Do not publish this script.'
    } catch {return $false}
}

function Restore-GMenuSavedCommand([string]$Name,[string]$Destination) {
    $commandRoot=Get-GMenuSavedCommandRoot
    $stateRoot=Split-Path -Parent $commandRoot
    $backupRoot=Join-Path $stateRoot 'CommandBackups'
    $historyRoot=Join-Path $stateRoot ('CommandHistory\'+$Name)
    $candidates=New-Object 'Collections.Generic.List[string]'
    $backup=Join-Path $backupRoot ($Name+'.ps1')
    if(Test-GMenuGeneratedCommand $backup){$candidates.Add($backup)}
    if(Test-Path -LiteralPath $historyRoot -PathType Container) {
        foreach($history in Get-ChildItem -LiteralPath $historyRoot -Filter '*.ps1' -File -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) {
            if(Test-GMenuGeneratedCommand $history.FullName){$candidates.Add($history.FullName)}
        }
    }
    foreach($fallbackRoot in Get-GMenuFallbackCommandRoots) {
        $fallback=Join-Path $fallbackRoot ($Name+'.ps1')
        if(Test-GMenuGeneratedCommand $fallback){$candidates.Add($fallback)}
    }
    if(-not $candidates.Count){return $false}
    [void][IO.Directory]::CreateDirectory($commandRoot)
    foreach($candidate in $candidates) {
        $temporary=$Destination+'.repair-'+[guid]::NewGuid().ToString('N')+'.tmp'
        try {
            [IO.File]::Copy($candidate,$temporary,$true)
            Move-Item -LiteralPath $temporary -Destination $Destination -Force -ErrorAction Stop
            return $true
        } catch {
            if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
        }
    }
    return $false
}

function Get-GMenuInstalledRestoreFallback([string]$Name) {
    $catalogCandidates=@()
    if($PSScriptRoot){$catalogCandidates+=(Join-Path $PSScriptRoot 'InstalledAppRestoreCatalog.json')}
    $catalogCandidates+=(Join-Path (Get-GMenuFallbackRoot) 'InstalledAppRestoreCatalog.json')
    $catalogCandidates+='F:\study\Platforms\windows\functions\InstalledAppRestoreCatalog.json'
    $catalogPath=$catalogCandidates | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
    if(-not $catalogPath){return}
    try {$entries=Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json}catch{return}
    $entry=$entries | Where-Object {
        $_.Folder -and ('g'+([string]$_.Folder -replace '[^A-Za-z0-9]','')) -ieq $Name
    } | Select-Object -First 1
    if(-not $entry){return}
    $helperCandidates=@()
    if($PSScriptRoot){$helperCandidates+=(Join-Path $PSScriptRoot 'Invoke-InstalledAppDockerRestoreAndLaunch.ps1')}
    $helperCandidates+=(Join-Path (Get-GMenuFallbackRoot) 'Invoke-InstalledAppDockerRestoreAndLaunch.ps1')
    $helperCandidates+='F:\study\Platforms\windows\functions\Invoke-InstalledAppDockerRestoreAndLaunch.ps1'
    $helper=$helperCandidates | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
    if(-not $helper){return}
    return [pscustomobject]@{Folder=[string]$entry.Folder;Helper=[string]$helper}
}

function Invoke-GMenuSavedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Position=1)][object[]]$Arguments=@()
    )
    $errorCountBefore=$global:Error.Count
    $previousErrorActionPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Stop'
        if($Name -notmatch '^g[a-zA-Z0-9]+$' -or $Name -in @('gm','gmenu')) {throw "Invalid GMenu command name: $Name"}
        $commandRoot=Get-GMenuSavedCommandRoot
        $stateRoot=Split-Path -Parent $commandRoot
        $commandPath=Join-Path $commandRoot ($Name+'.ps1')
        $valid=Test-GMenuGeneratedCommand $commandPath
        if(-not $valid) {$valid=Restore-GMenuSavedCommand $Name $commandPath}
        if(-not $valid) {
            $receiptCandidates=@(
                (Join-Path $commandRoot ($Name+'.receipt.json')),
                (Join-Path (Get-GMenuFallbackRoot) ('Commands\'+$Name+'.receipt.json'))
            )
            $sourceHint=$null
            foreach($receipt in $receiptCandidates) {
                if(Test-Path -LiteralPath $receipt -PathType Leaf) {
                    try {$sourceHint=[string]((Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json).Source)}catch{}
                    if($sourceHint){break}
                }
            }
            $catalogFallback=Get-GMenuInstalledRestoreFallback $Name
            if($catalogFallback) {
                if(@($Arguments).Count) {
                    throw "GMenu catalog restore '$Name' is available, but its protected command is missing and it accepts no passthrough arguments. Re-run gm to recreate the protected command."
                }
                Write-Host ("GMENU catalog-restore-fallback function={0} folder={1}" -f $Name,$catalogFallback.Folder) -ForegroundColor Yellow
                & $catalogFallback.Helper -Folder $catalogFallback.Folder
                $fallbackExit=$LASTEXITCODE
                if($null -ne $fallbackExit){$global:LASTEXITCODE=$fallbackExit}
                return
            }
            $fallbackRoot=Get-GMenuFallbackRoot
            $hint=if($sourceHint){" Re-run gm for the recorded source '$sourceHint' to recreate the protected command."}else{' Re-run gm for the application to recreate the protected command.'}
            if(Test-Path -LiteralPath $commandPath -PathType Leaf) {
                throw (("GMenu command '{0}' failed its generated-command integrity check and no protected backup is available under '{1}' or '{2}'." -f $Name,$stateRoot,$fallbackRoot)+$hint)
            }
            throw (("GMenu command '{0}' is registered but its restore script is missing and no protected backup is available under '{1}' or '{2}'." -f $Name,$stateRoot,$fallbackRoot)+$hint)
        }
        & $commandPath @Arguments
        $exitCode=$LASTEXITCODE
        if($null -ne $exitCode){$global:LASTEXITCODE=$exitCode}
    } catch {
        $message=if($_.Exception -and $_.Exception.Message){$_.Exception.Message}else{[string]$_}
        Write-Host ("[{0}] FAILED: {1}; returning to PowerShell without an exception dump." -f $Name,$message) -ForegroundColor Red
        $global:LASTEXITCODE=1
    } finally {
        $ErrorActionPreference=$previousErrorActionPreference
        try{while($global:Error.Count -gt $errorCountBefore){$global:Error.RemoveAt(0)}}catch{}
    }
}

function Set-GMenuSavedCommandFunction([string]$Name,[string]$CommandPath) {
    if($Name -notmatch '^g[a-zA-Z0-9]+$' -or $Name -in @('gm','gmenu')){return}
    $gmenuDefinition=[scriptblock]::Create(("Invoke-GMenuSavedCommand -Name '{0}' -Arguments `$args" -f $Name))
    Set-Item -LiteralPath ('Function:\global:'+$Name) -Value $gmenuDefinition -Force
}

$gmenuCommandRoot=Get-GMenuSavedCommandRoot
# Importing the profile helper must be read-only.  In particular, `uni gmenu`
# is allowed to remove this exact state tree; a later PowerShell startup must
# not recreate an empty recovery directory before the next cleanup can verify
# that it stayed gone.  Writers create the state root at the point they publish
# or restore a command.
$gmenuStateRoot=Split-Path -Parent $gmenuCommandRoot
$gmenuCommandRoots=@($gmenuCommandRoot,(Join-Path $gmenuStateRoot 'CommandBackups'))+(Get-GMenuFallbackCommandRoots)
foreach($gmenuRoot in $gmenuCommandRoots) {
    if(-not (Test-Path -LiteralPath $gmenuRoot -PathType Container)){continue}
    foreach($gmenuCommand in Get-ChildItem -LiteralPath $gmenuRoot -Filter 'g*.ps1' -File -Force -ErrorAction SilentlyContinue) {
        if($gmenuCommand.BaseName -notmatch '^g[a-zA-Z0-9]+$' -or $gmenuCommand.BaseName -in @('gm','gmenu')){continue}
        if(-not (Test-GMenuGeneratedCommand $gmenuCommand.FullName)){continue}
        Set-GMenuSavedCommandFunction $gmenuCommand.BaseName $gmenuCommand.FullName
    }
}
