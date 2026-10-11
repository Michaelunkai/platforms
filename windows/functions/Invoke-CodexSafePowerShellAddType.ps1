# Repair an inherited Windows PowerShell-only module path before resolving the
# module-qualified Add-Type cmdlet.  This also makes the helper safe under
# -NoProfile and in worker processes started by other functions.
if($PSVersionTable.PSEdition -eq 'Core' -and $PSHOME){
    $codexCoreModules=[IO.Path]::Combine([string]$PSHOME,'Modules')
    $codexModulePath=[string]$env:PSModulePath
    if($codexModulePath.IndexOf($codexCoreModules,[StringComparison]::OrdinalIgnoreCase) -lt 0){$env:PSModulePath=$codexCoreModules+';'+$codexModulePath}
}

# Keep PowerShell's C# compiler away from redirected, virtualized, or otherwise
# user-mapped TEMP directories.  Add-Type ultimately delegates to CodeDOM/Roslyn,
# which creates short-lived source and response files below TEMP even when the
# caller did not request an output file.
function global:Get-CodexSafeCompilerTempDirectory {
    $baseCandidates = @(
        $env:LOCALAPPDATA,
        [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    )
    if($env:USERPROFILE){$baseCandidates += [IO.Path]::Combine($env:USERPROFILE,'AppData\Local')}
    if($env:SystemRoot){$baseCandidates += [IO.Path]::Combine($env:SystemRoot,'Temp')}

    foreach($base in $baseCandidates) {
        if([string]::IsNullOrWhiteSpace([string]$base)){continue}
        $root=[IO.Path]::Combine(([string]$base).TrimEnd('\'), 'CodexPowerShellCompiler')
        $probe=$null
        $probeStream=$null
        try {
            [void][IO.Directory]::CreateDirectory($root)
            $probe=[IO.Path]::Combine($root, '.probe-'+[guid]::NewGuid().ToString('N')+'.tmp')
            $probeStream=[IO.File]::Open($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
            $probeStream.Dispose()
            $probeStream=$null
            [IO.File]::Delete($probe)
            $callDirectory=[IO.Path]::Combine($root, [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($callDirectory)
            return $callDirectory
        } catch {
            if($probeStream){try{$probeStream.Dispose()}catch{}}
            if($probe -and [IO.File]::Exists($probe)){try{[IO.File]::Delete($probe)}catch{}}
        }
    }
    throw 'No writable, non-redirected PowerShell compiler temporary directory is available.'
}

function global:Invoke-CodexSafeAddType {
    param([object[]]$Arguments)
    if(-not $global:CodexSafeAddTypeLock){$global:CodexSafeAddTypeLock=New-Object System.Object}
    $lock=$global:CodexSafeAddTypeLock
    [Threading.Monitor]::Enter($lock)
    $compilerTemp=$null
    $oldTemp=$null
    $oldTmp=$null
    try {
        $oldTemp=[Environment]::GetEnvironmentVariable('TEMP',[EnvironmentVariableTarget]::Process)
        $oldTmp=[Environment]::GetEnvironmentVariable('TMP',[EnvironmentVariableTarget]::Process)
        $compilerTemp=Get-CodexSafeCompilerTempDirectory
        [Environment]::SetEnvironmentVariable('TEMP',$compilerTemp,[EnvironmentVariableTarget]::Process)
        [Environment]::SetEnvironmentVariable('TMP',$compilerTemp,[EnvironmentVariableTarget]::Process)
        & Microsoft.PowerShell.Utility\Add-Type @Arguments
    } finally {
        if($null -eq $oldTemp){[Environment]::SetEnvironmentVariable('TEMP',$null,[EnvironmentVariableTarget]::Process)}else{[Environment]::SetEnvironmentVariable('TEMP',$oldTemp,[EnvironmentVariableTarget]::Process)}
        if($null -eq $oldTmp){[Environment]::SetEnvironmentVariable('TMP',$null,[EnvironmentVariableTarget]::Process)}else{[Environment]::SetEnvironmentVariable('TMP',$oldTmp,[EnvironmentVariableTarget]::Process)}
        if($compilerTemp -and [IO.Directory]::Exists($compilerTemp)) {
            try {[IO.Directory]::Delete($compilerTemp,$true)} catch {}
        }
        [Threading.Monitor]::Exit($lock)
    }
}

# A simple function intentionally leaves all Add-Type arguments in $args,
# including dynamic parameters such as -TypeDefinition and -PassThru.
function global:Add-Type {
    Invoke-CodexSafeAddType -Arguments $args
}

# Repair already-running parent shells that inherited the historical bad value
# before the persistent user-environment setting was corrected.
$codexStandardTemp=[IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),'Temp')
if([IO.Directory]::Exists($codexStandardTemp) -and
   ($env:TEMP -ieq 'C:\Temp' -or $env:TMP -ieq 'C:\Temp')) {
    $env:TEMP=$codexStandardTemp
    $env:TMP=$codexStandardTemp
}
