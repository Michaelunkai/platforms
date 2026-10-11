#Requires -Version 5.0
<#
.SYNOPSIS
    dkill - destructive Docker reset with a verified daemon, tray, and off-C engine disk.

.DESCRIPTION
    The default operation deletes Docker engine data, including every known
    C-drive Docker engine disk, then recreates Docker on the canonical VMM
    backend with its mandatory VM disk under F:\DockerDesktopVMM. It returns
    only after the daemon, Docker Desktop tray, empty engine state, configured
    data location, and absence of C-drive engine VHDX files are verified.
    The installed Docker Desktop program is left untouched, but all prior
    engine data, user settings, sign-in files, and Docker credential-helper
    entries are removed. A new anonymous minimum settings store is then created
    solely to pin the replacement empty VMM disk off C: and start Docker.

    Use -Preserve for a bounded non-destructive VMM restart.

.PARAMETER NoRestart
    Stop only; do not start Docker Desktop at the end.

.PARAMETER Preserve
    Restart or stop Docker without deleting engine data.

.PARAMETER FactoryReset
    Compatibility switch. Destructive reset is now the default.

.PARAMETER SelfTest
    Print diagnostics and exit without changing anything.
#>
[CmdletBinding()]
param(
    [switch]$NoRestart,
    [switch]$Preserve,
    [switch]$FactoryReset,
    [string]$ConfirmFactoryReset = '',
    [switch]$SelfTest,
    [Parameter(DontShow = $true)]
    [switch]$Worker,
    [Parameter(DontShow = $true)]
    [switch]$NativeHost,
    [Parameter(DontShow = $true)]
    [string]$OwnerSid = '',
    [Parameter(DontShow = $true)]
    [ValidateRange(1, 10)]
    [int]$MaxSeconds = 9
)
# dkill is also called directly by wrappers, scheduled tasks, and fresh
# Windows PowerShell processes.  Do not assume the interactive profile already
# loaded the safe compiler-temp helper used by the native AppData probe.
if (-not (Get-Command Get-CodexSafeCompilerTempDirectory -CommandType Function -ErrorAction SilentlyContinue)) {
    $dkillCompilerHelper = Join-Path (Split-Path -Parent $PSCommandPath) 'Invoke-CodexSafePowerShellAddType.ps1'
    if (Test-Path -LiteralPath $dkillCompilerHelper -PathType Leaf) {
        . $dkillCompilerHelper
    }
}
if ([string]::IsNullOrWhiteSpace($OwnerSid)) {
    $OwnerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}
try { $OwnerSid = ([Security.Principal.SecurityIdentifier]::new($OwnerSid)).Value }
catch { throw 'dkill could not validate the invoking Windows account SID.' }
$dockerNativeContextAvailable = [bool]('DockerNativeContextV4' -as [type])
if (-not $dockerNativeContextAvailable) {
 try {
  $dockerNativeCompileTemp = Get-CodexSafeCompilerTempDirectory
  $dockerNativePreviousTemp = $env:TEMP
  $dockerNativePreviousTmp = $env:TMP
  try {
   $env:TEMP = $dockerNativeCompileTemp
   $env:TMP = $dockerNativeCompileTemp
   Add-Type -TypeDefinition 'using System; using System.IO; using System.Text; using System.Runtime.InteropServices; public static class DockerNativeContextV4 { [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern uint GetFinalPathNameByHandle(IntPtr h,StringBuilder b,uint n,uint f); public static bool IsRedirected() { string p=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),".codex-docker-context-"+Guid.NewGuid().ToString("N")+".tmp"); using(var file=new FileStream(p,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.ReadWrite|FileShare.Delete,1,FileOptions.DeleteOnClose)) { var b=new StringBuilder(32768); if(GetFinalPathNameByHandle(file.SafeFileHandle.DangerousGetHandle(),b,32768,0)==0) throw new IOException("Cannot identify AppData write path"); return b.ToString().IndexOf("\\Packages\\",StringComparison.OrdinalIgnoreCase)>=0; } } }' -ErrorAction Stop
   $dockerNativeContextAvailable = $true
  } finally {
   $env:TEMP = $dockerNativePreviousTemp
   $env:TMP = $dockerNativePreviousTmp
   if($dockerNativeCompileTemp -and [IO.Directory]::Exists($dockerNativeCompileTemp)){try{[IO.Directory]::Delete($dockerNativeCompileTemp,$true)}catch{}}
  }
 } catch {
  if(-not $SelfTest){ throw 'dkill could not establish the native AppData context boundary; refusing operational cleanup.' }
 }
}
$dockerNativeContextRedirected = $false
if($dockerNativeContextAvailable){
 try { $dockerNativeContextRedirected = [DockerNativeContextV4]::IsRedirected() }
 catch {
  if(-not $SelfTest){ throw 'dkill could not determine the native AppData context; refusing operational cleanup.' }
 }
}
# Elevation does not disable packaged-file virtualization. Always cross into
# the native host when the caller's AppData view is redirected; otherwise the
# cleanup worker and Docker Desktop can see different settings-store.json files.
if ($dockerNativeContextRedirected -and -not $Worker -and -not $NativeHost) {
 $nativeParameters = @{}
 foreach ($key in $PSBoundParameters.Keys) { $nativeParameters[$key] = $PSBoundParameters[$key] }
 $nativeParameters['NativeHost'] = $true
 $nativeParameters['OwnerSid'] = $OwnerSid
 # The native relay must outlive the synchronous worker. The foreground speed
 # target is reported separately and must never cause a false early success.
 $nativeTimeoutSeconds = 300
 & 'F:\study\Platforms\windows\functions\Invoke-DockerNativeScript.ps1' -ScriptPath 'F:\study\Platforms\windows\functions\dkill.ps1' -Parameters $nativeParameters -TimeoutSeconds $nativeTimeoutSeconds
 if (-not $?) { exit 1 }
 return
}


$ErrorActionPreference = 'Stop'
$ConfirmPreference = 'None'
$script:DKillVmmDataRoot = 'F:\DockerDesktopVMM'
$script:DKillMaintenanceRoot = 'F:\DockerMaintenance'
$script:DKillWorkerTimeoutSeconds = 240
$script:DKillReadyTimeoutSeconds = 90
$script:DKillOwnerSid = $OwnerSid
$script:LogPath = Join-Path $script:DKillMaintenanceRoot 'dkill.log'
$script:WatchdogTask = 'DockerDesktopWatchdog'
$script:DKillCDriveEngineDisks = @(
    (Join-Path $env:LOCALAPPDATA 'Docker\vm-data\DockerDesktop.vhdx'),
    (Join-Path $env:ProgramData 'DockerDesktop\vm-data\DockerDesktop.vhdx'),
    (Join-Path $env:LOCALAPPDATA 'Docker\wsl\data\ext4.vhdx'),
    (Join-Path $env:LOCALAPPDATA 'Docker\wsl\disk\docker_data.vhdx')
)
$script:DKillExtraDataRoots=@(
 (Join-Path $env:LOCALAPPDATA 'DockerSocketRecovery'),
 (Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Docker'),
 (Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\DockerSocketRecovery'),
 (Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\docker-secrets-engine'),
 (Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Roaming\Docker'),
 (Join-Path $env:APPDATA 'Docker Desktop'),
 (Join-Path $env:APPDATA 'docker-secrets-engine')
)

function Assert-DKillDedicatedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RequiredLeaf
    )
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $volumeRoot = [IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($volumeRoot) -or $full -ieq $volumeRoot.TrimEnd('\')) {
        throw "Docker dedicated path is not a safe child directory: $full"
    }
    if ([IO.Path]::GetFileName($full) -cne $RequiredLeaf) {
        throw "Docker dedicated path has an unexpected leaf name: $full"
    }
    if ($volumeRoot -ieq 'C:\') {
        throw "Docker engine and maintenance data must not use the C drive: $full"
    }
    $drive = [IO.DriveInfo]::new($volumeRoot)
    if (-not $drive.IsReady -or $drive.DriveType -ne [IO.DriveType]::Fixed -or $drive.DriveFormat -ine 'NTFS') {
        throw "Docker dedicated path requires a ready fixed NTFS volume: $full"
    }
    $cursor = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    while ($cursor -and $cursor.FullName.TrimEnd('\') -ine $volumeRoot.TrimEnd('\')) {
        if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Docker dedicated path refuses a reparse point: $($cursor.FullName)"
        }
        $cursor = $cursor.Parent
    }
    return $full
}

function Initialize-DKillMaintenanceRoot {
    $root = Assert-DKillDedicatedPath -Path $script:DKillMaintenanceRoot -RequiredLeaf 'DockerMaintenance'
    [void][IO.Directory]::CreateDirectory($root)
}

function Remove-DKillStaleWorkerArtifacts {
    $removed = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $script:DKillMaintenanceRoot -File -Force -ErrorAction SilentlyContinue)) {
        if ($file.Name -notmatch '^dkill-(?:worker-[0-9a-f]+\.(?:out|err)|(?:out|err)-[0-9a-f]+\.log)$') { continue }
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
        $removed++
    }
    if ($removed -gt 0) { Write-DLine ("stale dkill worker artifacts removed: {0}" -f $removed) 'Green' }
}

function Write-DLine {
    param([string]$Message, [string]$Color = 'Cyan')
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    # Keep status text off the success stream. Several helpers return Boolean
    # values; pipeline log strings previously turned `$false` into a truthy
    # array and allowed incomplete deletion to be reported as successful.
    $Host.UI.WriteLine(("[dkill] {0}" -f $Message))
    try {
        [IO.File]::AppendAllText(
            $script:LogPath,
            (("[{0}] {1}" -f $stamp, $Message) + [Environment]::NewLine),
            [Text.UTF8Encoding]::new($false)
        )
    } catch { }
}

$script:WorkerMutex = $null
$script:WorkerMutexOwned = $false
function Test-DKillWorkerActive {
    $probe = New-Object Threading.Mutex($false, 'Global\Codex-DKill-ActiveWorker')
    $owned = $false
    try { $owned = $probe.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if ($owned) { try { $probe.ReleaseMutex() } catch { } }
    try { $probe.Dispose() } catch { }
    return (-not $owned)
}
function Get-DKillActiveWorkerLog {
    $files = @(Get-ChildItem -LiteralPath $script:DKillMaintenanceRoot -Filter 'dkill-worker-*.out' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($file in $files) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -notmatch '(?im)^\[dkill\].*=== DKILL (?:COMPLETE|FAILED)|^\[dkill\].*=== DKILL VMM RESTART COMPLETE') {
            return $file.FullName
        }
    }
    return $null
}
function Write-DKillActiveWorkerHandoff {
    $activeLog = Get-DKillActiveWorkerLog
    if ($activeLog) {
        Write-DLine ("ERROR another dkill worker is still active; log: {0}" -f $activeLog) 'Red'
    } else {
        Write-DLine 'ERROR another dkill worker is still active' 'Red'
    }
    throw 'dkill refuses to report success while another reset is unfinished.'
}
if ($Worker) {
    $script:WorkerMutex = New-Object Threading.Mutex($false, 'Global\Codex-DKill-ActiveWorker')
    try { $script:WorkerMutexOwned = $script:WorkerMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $script:WorkerMutexOwned = $true }
    if (-not $script:WorkerMutexOwned) { throw 'A detached dkill worker is already active.' }
}

function Test-DAdmin {
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Invoke-Bounded {
    param([string]$FilePath, [string[]]$ArgumentList, [int]$Milliseconds = 5000)
    $result = [pscustomobject]@{ ExitCode = 1; Stdout = ''; Stderr = ''; TimedOut = $false }
    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -LiteralPath $FilePath)) {
        $result.Stderr = 'executable not found'
        return $result
    }
    $tempRoot = $script:DKillMaintenanceRoot
    try { if (-not (Test-Path -LiteralPath $tempRoot)) { New-Item -ItemType Directory -Path $tempRoot -Force -ErrorAction Stop | Out-Null } } catch { }
    $outFile = Join-Path $tempRoot ('dkill-out-' + [guid]::NewGuid().ToString('N') + '.log')
    $errFile = Join-Path $tempRoot ('dkill-err-' + [guid]::NewGuid().ToString('N') + '.log')
    $process = $null
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WindowStyle Hidden -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
        if (-not $process.WaitForExit([Math]::Max(250, $Milliseconds))) {
            try { $process.Kill() } catch { }
            try { $null = $process.WaitForExit(1000) } catch { }
            $result.ExitCode = 124
            $result.TimedOut = $true
            $result.Stderr = 'timed out'
            return $result
        }
        # Start-Process redirects directly to files. The bounded wait above is
        # sufficient; a second unbounded WaitForExit can hang if a descendant
        # inherits a redirected file handle.
        $result.ExitCode = [int]$process.ExitCode
        try { $result.Stdout = (Get-Content -LiteralPath $outFile -Raw -ErrorAction Stop).Trim() } catch { }
        try { $result.Stderr = (Get-Content -LiteralPath $errFile -Raw -ErrorAction Stop).Trim() } catch { }
        return $result
    } catch {
        $result.Stderr = $_.Exception.Message
        return $result
    } finally {
        if ($process) { try { $process.Dispose() } catch { } }
        foreach ($file in @($outFile, $errFile)) {
            for ($attempt = 1; $attempt -le 5 -and [IO.File]::Exists($file); $attempt++) {
                try { [IO.File]::Delete($file) } catch { }
                if ([IO.File]::Exists($file)) { Start-Sleep -Milliseconds 20 }
            }
            if ([IO.File]::Exists($file)) { throw "Docker probe temporary file remains after handle closure: $file" }
        }
    }
}

function Test-DaemonReady {
    param([string]$DockerExe, [int]$Milliseconds = 1000)
    if ([string]::IsNullOrWhiteSpace($DockerExe) -or -not (Test-Path -LiteralPath $DockerExe)) { return $false }
    if (-not (Test-Path -LiteralPath '\\.\pipe\dockerDesktopLinuxEngine')) { return $false }
    $r = Invoke-Bounded -FilePath $DockerExe -ArgumentList @('version', '--format', '{{.Server.Version}}') -Milliseconds $Milliseconds
    if ($r.TimedOut -or $r.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($r.Stdout)) { return $false }
    if ($r.Stderr -match '(?i)failed to connect|daemon is not running|error during connect|cannot find') { return $false }
    $script:DKillLastServerVersion = $r.Stdout
    return $true
}

function Test-DockerFrontendReady {
    return (@(Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue).Count -gt 0)
}

function Find-DockerExe {
    $candidates = @((Join-Path ${env:ProgramFiles} 'Docker\Docker\resources\bin\docker.exe'))
    $cmd = Get-Command docker.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { $candidates += $cmd.Source }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

function Get-DKillDockerCredentialHelpers {
    $bin = Join-Path ${env:ProgramFiles} 'Docker\Docker\resources\bin'
    return @(
        (Join-Path $bin 'docker-credential-desktop.exe'),
        (Join-Path $bin 'docker-credential-wincred.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique
}

function Get-DKillDockerCredentialInventory {
    param([Parameter(Mandatory)][string]$HelperPath)
    $rawLines = @(& $HelperPath list 2>$null)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        return [pscustomobject]@{ Valid = $false; Servers = @() }
    }
    $raw = ($rawLines -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ Valid = $true; Servers = @() }
    }
    try {
        $inventory = $raw | ConvertFrom-Json -ErrorAction Stop
        $servers = @($inventory.PSObject.Properties | ForEach-Object { [string]$_.Name })
        return [pscustomobject]@{ Valid = $true; Servers = $servers }
    } catch {
        return [pscustomobject]@{ Valid = $false; Servers = @() }
    }
}

function Test-DKillDockerCredentialsCleared {
    $helpers = @(Get-DKillDockerCredentialHelpers)
    if ($helpers.Count -eq 0) { return $false }
    foreach ($helper in $helpers) {
        $inventory = Get-DKillDockerCredentialInventory -HelperPath $helper
        if (-not $inventory.Valid -or @($inventory.Servers).Count -ne 0) { return $false }
    }
    return $true
}

function Test-DKillDockerIdentityCleared {
    if (-not (Test-DKillDockerCredentialsCleared)) { return $false }

    # A nonempty login-info.json is Docker Desktop account/session state. A
    # clean anonymous launch does not need it.
    $loginInfo = Join-Path $env:APPDATA 'Docker\login-info.json'
    if (Test-Path -LiteralPath $loginInfo -PathType Leaf) {
        try {
            if ((Get-Item -LiteralPath $loginInfo -Force -ErrorAction Stop).Length -gt 0) { return $false }
        } catch { return $false }
    }

    # Docker may recreate a CLI config for its context. Permit that fresh
    # plumbing, but reject any actual inline registry authentication payload.
    $clientConfig = Join-Path $env:USERPROFILE '.docker\config.json'
    if (Test-Path -LiteralPath $clientConfig -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $clientConfig -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($config.auths) {
                foreach ($authEntry in @($config.auths.PSObject.Properties)) {
                    if ($null -ne $authEntry.Value -and @($authEntry.Value.PSObject.Properties).Count -gt 0) { return $false }
                }
            }
        } catch { return $false }
    }
    return $true
}

function Clear-DKillDockerCredentials {
    $helpers = @(Get-DKillDockerCredentialHelpers)
    if ($helpers.Count -eq 0) {
        Write-DLine 'ERROR Docker credential helpers were not found; stored credentials cannot be verified empty' 'Red'
        return $false
    }
    $eraseAttempts = 0
    foreach ($helper in $helpers) {
        $inventory = Get-DKillDockerCredentialInventory -HelperPath $helper
        if (-not $inventory.Valid) {
            Write-DLine ("ERROR could not inventory Docker credentials with {0}" -f [IO.Path]::GetFileName($helper)) 'Red'
            continue
        }
        foreach ($server in @($inventory.Servers)) {
            # Helper values can contain account names, so never echo helper JSON
            # or the erase response into the dkill log.
            $eraseOutput = @(([string]$server) | & $helper erase 2>&1)
            $eraseExitCode = $LASTEXITCODE
            $eraseAttempts++
            if ($eraseExitCode -ne 0) {
                Write-DLine ("WARN Docker credential erase attempt failed in {0}; final inventory will decide success" -f [IO.Path]::GetFileName($helper)) 'DarkYellow'
            }
        }
    }
    $cleared = Test-DKillDockerCredentialsCleared
    Write-DLine ("Docker credential-store entries erased={0}; verified_empty={1}" -f $eraseAttempts, $cleared) $(if ($cleared) { 'Green' } else { 'Red' })
    return $cleared
}

function Remove-DKillLegacyDockerVirtualizationData {
    $complete = $true
    $wslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
    if (Test-Path -LiteralPath $wslExe -PathType Leaf) {
        $rawDistributions = @(& $wslExe --list --quiet 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $dockerDistributions = @($rawDistributions | ForEach-Object {
                (([string]$_) -replace ([string][char]0), '').Trim()
            } | Where-Object { $_ -match '^(?i:docker-desktop|docker-desktop-data)$' } | Select-Object -Unique)
            foreach ($distribution in $dockerDistributions) {
                $result = Invoke-Bounded -FilePath $wslExe -ArgumentList @('--unregister', $distribution) -Milliseconds 30000
                if ($result.TimedOut -or $result.ExitCode -ne 0) { $complete = $false }
            }
            $remainingRaw = @(& $wslExe --list --quiet 2>$null)
            $remainingDocker = @($remainingRaw | ForEach-Object {
                (([string]$_) -replace ([string][char]0), '').Trim()
            } | Where-Object { $_ -match '^(?i:docker-desktop|docker-desktop-data)$' })
            if ($remainingDocker.Count -gt 0) { $complete = $false }
            Write-DLine ("legacy Docker WSL distributions removed={0}; remaining={1}" -f $dockerDistributions.Count, $remainingDocker.Count) $(if ($complete) { 'Green' } else { 'Red' })
        }
    }

    $getVmCommand = Get-Command Get-VM -ErrorAction SilentlyContinue
    if ($getVmCommand) {
        $dockerVm = Get-VM -Name 'DockerDesktopVM' -ErrorAction SilentlyContinue
        if ($dockerVm) {
            Stop-VM -VM $dockerVm -TurnOff -Force -ErrorAction SilentlyContinue
            Remove-VM -VM $dockerVm -Force -ErrorAction SilentlyContinue
            if (Get-VM -Name 'DockerDesktopVM' -ErrorAction SilentlyContinue) { $complete = $false }
            else { Write-DLine 'legacy DockerDesktopVM removed' 'Green' }
        }
    }

    # Scheduled elevation can give HKCU a service-host view. Address the
    # original caller's loaded HKEY_USERS hive through the registry API so a
    # space in "Docker Inc." cannot be misparsed as a second process argument.
    $registryCleared = $false
    $softwareKey = $null
    $verifyKey = $null
    try {
        $softwareKey = [Microsoft.Win32.Registry]::Users.OpenSubKey(($script:DKillOwnerSid + '\Software'), $true)
        if ($softwareKey) { $softwareKey.DeleteSubKeyTree('Docker Inc.', $false) }
        if ($softwareKey) { $softwareKey.Dispose(); $softwareKey = $null }
        $verifyKey = [Microsoft.Win32.Registry]::Users.OpenSubKey(($script:DKillOwnerSid + '\Software\Docker Inc.'), $false)
        $registryCleared = $null -eq $verifyKey
    } catch {
        $registryCleared = $false
    } finally {
        if ($softwareKey) { $softwareKey.Dispose() }
        if ($verifyKey) { $verifyKey.Dispose() }
    }
    if (-not $registryCleared) { $complete = $false }
    Write-DLine ("Docker per-user registry state verified_empty={0}" -f $registryCleared) $(if ($registryCleared) { 'Green' } else { 'Red' })
    return $complete
}

function Set-DockerVmmSettings {
    param([switch]$Fresh)
    $vmmDataRoot = Assert-DKillDedicatedPath -Path $script:DKillVmmDataRoot -RequiredLeaf 'DockerDesktopVMM'
    $settingsPath = Join-Path $env:APPDATA 'Docker\settings-store.json'
    $parent = Split-Path -Parent $settingsPath
    New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    $settings = $null
    if (-not $Fresh -and (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        try { $settings = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
    }
    if (-not $settings) {
        $settings = [pscustomobject][ordered]@{
            AutoStart = $false
            DisplayedOnboarding = $true
            EnableIntegrationWithDefaultWslDistro = $false
            FilesharingDirectories = @($env:USERPROFILE)
            MemoryMiB = 33792
            OpenUIOnStartupDisabled = $true
            SettingsVersion = 45
        }
    }
    function Set-DockerVmmProperty {
        param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name, $Value)
        $property = $Object.PSObject.Properties[$Name]
        if ($property) { $property.Value = $Value } else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
    }
    Set-DockerVmmProperty -Object $settings -Name 'AllowBetaFeatures' -Value $true
    Set-DockerVmmProperty -Object $settings -Name 'LicenseTermsVersion' -Value 2
    Set-DockerVmmProperty -Object $settings -Name 'DisplayedOnboarding' -Value $true
    Set-DockerVmmProperty -Object $settings -Name 'MemoryMiB' -Value 33792
    Set-DockerVmmProperty -Object $settings -Name 'UseLibkrun' -Value $true
    Set-DockerVmmProperty -Object $settings -Name 'UseResourceSaver' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'UseVirtualizationFramework' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'WslEngineEnabled' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'UseContainerdSnapshotter' -Value $true
    Set-DockerVmmProperty -Object $settings -Name 'EnableIntegrationWithDefaultWslDistro' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'AutoStart' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'OpenUIOnStartupDisabled' -Value $true
    Set-DockerVmmProperty -Object $settings -Name 'ShowInstallScreen' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'DisplayRestartDialog' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'ShowAnnouncementNotifications' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'ShowGeneralNotifications' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'ShowPromotionalNotifications' -Value $false
    Set-DockerVmmProperty -Object $settings -Name 'ShowSurveyNotifications' -Value $false
    # Docker Desktop 4.90 exposes this as vm.resources.sailorDataFolder for
    # the docker-vmm engine. Pinning it off C: prevents the required fresh VHDX
    # from immediately consuming C-drive space after every destructive reset.
    Set-DockerVmmProperty -Object $settings -Name 'SailorDataFolder' -Value $vmmDataRoot
    $driveShares = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName })
    $shares = @(@($settings.FilesharingDirectories) + @($env:USERPROFILE, 'C:\Temp', 'F:\study') + @($driveShares) | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and
        (Test-Path -LiteralPath ([string]$_) -PathType Container)
    } | Select-Object -Unique)
    $shares = @($shares | ForEach-Object { ([string]$_).Replace('\','/') } | Select-Object -Unique)
    Set-DockerVmmProperty -Object $settings -Name 'FilesharingDirectories' -Value $shares
    $temporary = Join-Path $parent ('.settings-store.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, ($settings | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $settingsPath -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
    Write-DLine ("Docker VMM settings enforced; fresh={0}; data_root={1}; explicit shares={2}" -f [bool]$Fresh, $vmmDataRoot, $shares.Count) 'Green'
}

function Test-DockerVmmConfigured {
    $settingsPath = Join-Path $env:APPDATA 'Docker\settings-store.json'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { return $false }
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $expectedRoot = [IO.Path]::GetFullPath($script:DKillVmmDataRoot).TrimEnd('\')
        $configuredRoot = [IO.Path]::GetFullPath([string]$settings.SailorDataFolder).TrimEnd('\')
        return [bool]$settings.UseLibkrun -and
            -not [bool]$settings.WslEngineEnabled -and
            -not [bool]$settings.UseVirtualizationFramework -and
            $configuredRoot -ieq $expectedRoot
    } catch { return $false }
}

function Stop-DockerWindowsService {
    $ErrorActionPreference = 'Stop'
    $service = Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue
    if ($null -eq $service) { return }
    if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::StopPending) { $service.Stop() }
        $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(3))
        $service.Refresh()
        if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) { throw 'Docker Windows service did not stop.' }
    }
}
function Stop-AllDocker {
    # Stop the optional Windows helper too; Docker VMM does not require it.
    Stop-DockerWindowsService
    $dockerNames = @('Docker Desktop', 'Docker Desktop Installer', 'com.docker.backend', 'com.docker.proxy', 'com.docker.sailor', 'com.docker.build', 'com.docker.dev-envs', 'com.docker.cli', 'com.docker.vpnkit', 'docker', 'dockerd', 'vpnkit', 'docker-agent', 'docker-sandbox', 'containerd')
    $taskKill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    # Close only root Docker process trees. Calling taskkill once for every
    # Chromium/tray child serializes several 1.2-second waits and defeats the
    # fast restart target; /T on each root already reaches every descendant.
    $processSnapshot = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $dockerProcessSnapshot = @($processSnapshot | Where-Object {
        [IO.Path]::GetFileNameWithoutExtension($_.Name) -in $dockerNames
    })
    $dockerProcessIds = @($dockerProcessSnapshot | ForEach-Object { [int]$_.ProcessId })
    $dockerTreeRoots = @($dockerProcessSnapshot | Where-Object {
        $dockerProcessIds -notcontains [int]$_.ParentProcessId
    })
    foreach ($root in $dockerTreeRoots) {
        $terminated = $false
        if (Test-Path -LiteralPath $taskKill -PathType Leaf) {
            $taskKillResult = Invoke-Bounded -FilePath $taskKill -ArgumentList @('/PID', [string]$root.ProcessId, '/T', '/F') -Milliseconds 1200
            $terminated = -not $taskKillResult.TimedOut -and $taskKillResult.ExitCode -eq 0
        }
        if (-not $terminated) {
            try { (Get-Process -Id $root.ProcessId -ErrorAction Stop).Kill() } catch { }
        }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        $remaining = @()
        foreach ($name in $dockerNames) {
            foreach ($proc in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
                $remaining += $proc
                try { $proc.Kill() } catch { }
            }
        }
        if ($remaining.Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    $remaining = @(
        foreach ($name in $dockerNames) {
            Get-Process -Name $name -ErrorAction SilentlyContinue
        }
    )
    if ($remaining.Count -gt 0) {
        $details = @($remaining | ForEach-Object { "{0}({1})" -f $_.ProcessName, $_.Id }) -join ', '
        throw "Docker did not fully stop within five seconds; socket cleanup was not attempted. Remaining: $details"
    }

    & 'F:\study\Platforms\windows\functions\Repair-DockerRuntimeSockets.ps1'
    if (-not $?) { throw 'Docker socket repair failed; reset stopped.' }
}

function Remove-DockerPath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $allowedRoots = @(
        (Join-Path $env:ProgramData 'DockerDesktop'), (Join-Path $env:ProgramData 'Docker'),
        (Join-Path $env:LOCALAPPDATA 'Docker'), (Join-Path $env:LOCALAPPDATA 'Docker Desktop'), (Join-Path $env:LOCALAPPDATA 'docker-secrets-engine'),
        (Join-Path $env:APPDATA 'Docker'), (Join-Path $env:USERPROFILE '.docker'),
        (Join-Path $env:USERPROFILE '.docker-desktop'),
        $script:DKillVmmDataRoot
    )
    $allowedRoots += $script:DKillExtraDataRoots
    $approved = @($allowedRoots | Where-Object {$full -ieq $_ -or $full.StartsWith($_+'\',[StringComparison]::OrdinalIgnoreCase)})
    if($approved.Count -ne 1){throw "Docker deletion target outside approved roots: $full"}
    $cursor=Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    while($cursor){
        if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Docker deletion refuses a reparse point: $($cursor.FullName)"}
        $cursor=$cursor.Parent
    }

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $true }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    # Fast path: as an elevated admin we normally own everything here - just delete.
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            if ($item.PSIsContainer) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
            else { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
        } catch { }
        if (-not (Test-Path -LiteralPath $Path)) { break }
        Start-Sleep -Milliseconds 500
    }
    # Escalation path (rare): take ownership, grant access, clear attributes, retry.
    if (Test-Path -LiteralPath $Path) {
        $takeown = Join-Path $env:SystemRoot 'System32\takeown.exe'
        $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
        $attrib = Join-Path $env:SystemRoot 'System32\attrib.exe'
        if ($item -and $item.PSIsContainer) {
            if (Test-Path -LiteralPath $takeown) { $null = Invoke-Bounded -FilePath $takeown -ArgumentList @('/F', $Path, '/A', '/R', '/D', 'Y') -Milliseconds 15000 }
            if (Test-Path -LiteralPath $icacls) { $null = Invoke-Bounded -FilePath $icacls -ArgumentList @($Path, '/grant', 'Administrators:(OI)(CI)F', '/T', '/C', '/Q') -Milliseconds 20000 }
            if (Test-Path -LiteralPath $attrib) { $null = Invoke-Bounded -FilePath $attrib -ArgumentList @('-R', '-S', '-H', $Path, '/S', '/D') -Milliseconds 10000 }
        } else {
            if (Test-Path -LiteralPath $takeown) { $null = Invoke-Bounded -FilePath $takeown -ArgumentList @('/F', $Path, '/A') -Milliseconds 10000 }
            if (Test-Path -LiteralPath $icacls) { $null = Invoke-Bounded -FilePath $icacls -ArgumentList @($Path, '/grant', 'Administrators:F', '/C', '/Q') -Milliseconds 10000 }
            if (Test-Path -LiteralPath $attrib) { $null = Invoke-Bounded -FilePath $attrib -ArgumentList @('-R', '-S', '-H', $Path) -Milliseconds 5000 }
        }
        try {
            if ($item.PSIsContainer) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue }
            else { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    if (Test-Path -LiteralPath $Path) {
        Write-DLine ("WARN could not delete {0}" -f $Path) 'DarkYellow'
        return $false
    }
    Write-DLine ("deleted {0}" -f $Path) 'Green'
    return $true
}

function Remove-DKillCDriveTransientArtifacts {
    $specifications = @(
        [pscustomobject]@{ Root = 'C:\Temp'; Pattern = '^(?i:dkill(?:-.+)?\.(?:log|out|err)|docker-native-[0-9a-f]+\.(?:log|exit)|Docker-WSL-HealthFix\.lock)$' },
        [pscustomobject]@{ Root = (Join-Path $env:LOCALAPPDATA 'Temp'); Pattern = '^(?i:Docker(?:Desktop)?(?:[-_.].*)?|com\.docker(?:[-_.].*)?|dkill-.+|docker-native-.+)$' },
        [pscustomobject]@{ Root = (Join-Path $env:windir 'Temp'); Pattern = '^(?i:Docker(?:Desktop)?(?:[-_.].*)?|com\.docker(?:[-_.].*)?)$' },
        [pscustomobject]@{ Root = (Join-Path $env:LOCALAPPDATA 'CrashDumps'); Pattern = '^(?i:Docker Desktop|com\.docker|docker|dockerd|containerd|vpnkit).*\.dmp$' }
    )
    $removed = 0
    $complete = $true
    foreach ($specification in $specifications) {
        if (-not (Test-Path -LiteralPath $specification.Root -PathType Container)) { continue }
        foreach ($entry in @(Get-ChildItem -LiteralPath $specification.Root -Force -ErrorAction SilentlyContinue)) {
            if ($entry.Name -notmatch $specification.Pattern) { continue }
            if ([IO.Path]::GetDirectoryName($entry.FullName).TrimEnd('\') -ine ([IO.Path]::GetFullPath($specification.Root)).TrimEnd('\')) {
                throw "Docker transient cleanup target escaped its root: $($entry.FullName)"
            }
            for ($attempt = 1; $attempt -le 5 -and (Test-Path -LiteralPath $entry.FullName); $attempt++) {
                try {
                    if ($entry.PSIsContainer) {
                        [IO.Directory]::Delete($entry.FullName, $true)
                    } else {
                        [IO.File]::Delete($entry.FullName)
                    }
                } catch {
                    try {
                        if ($entry.PSIsContainer) { Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop }
                        else { Remove-Item -LiteralPath $entry.FullName -Force -ErrorAction Stop }
                    } catch { }
                }
                if (Test-Path -LiteralPath $entry.FullName) { Start-Sleep -Milliseconds 250 }
            }
            if (Test-Path -LiteralPath $entry.FullName) {
                $complete = $false
                Write-DLine ("ERROR Docker transient artifact remains: {0}" -f $entry.FullName) 'Red'
            } else {
                $removed++
            }
        }
    }
    Write-DLine ("C-drive Docker transient artifacts removed: {0}" -f $removed) 'Green'
    return $complete
}

function Get-DKillEngineUsage {
    param([Parameter(Mandatory)][string]$DockerExe)
    $usage = [ordered]@{ Valid = $false; Empty = $false; Containers = -1; Images = -1; Volumes = -1; BuildCache = -1 }
    # Keep the template free of spaces because Windows PowerShell 5.1's
    # Start-Process flattens ArgumentList before CreateProcess receives it.
    $result = Invoke-Bounded -FilePath $DockerExe -ArgumentList @('system', 'df', '--format', '{{.Type}}|{{.TotalCount}}') -Milliseconds 5000
    if ($result.ExitCode -ne 0 -or $result.TimedOut) { return [pscustomobject]$usage }
    $seen = @{}
    foreach ($line in @($result.Stdout -split "[`r`n]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if ($line -notmatch '^(Images|Containers|Local Volumes|Build Cache)\|([0-9]+)$') { continue }
        $type = $Matches[1]
        $count = -1
        if (-not [int]::TryParse($Matches[2], [ref]$count)) { continue }
        switch ($type) {
            'Containers' { $usage.Containers = $count; $seen['Containers'] = $true }
            'Images' { $usage.Images = $count; $seen['Images'] = $true }
            'Local Volumes' { $usage.Volumes = $count; $seen['Volumes'] = $true }
            'Build Cache' { $usage.BuildCache = $count; $seen['BuildCache'] = $true }
        }
    }
    $usage.Valid = @('Containers','Images','Volumes','BuildCache').Count -eq @($seen.Keys).Count
    $usage.Empty = $usage.Valid -and $usage.Containers -eq 0 -and $usage.Images -eq 0 -and $usage.Volumes -eq 0 -and $usage.BuildCache -eq 0
    return [pscustomobject]$usage
}

function Start-PrivateService {
    param([string]$ServiceName = 'com.docker.service')
    $sc = Join-Path $env:SystemRoot 'System32\sc.exe'
    if (-not (Test-Path -LiteralPath $sc)) { return $false }
    $query = Invoke-Bounded -FilePath $sc -ArgumentList @('query', $ServiceName) -Milliseconds 5000
    if ($query.ExitCode -eq 0 -and $query.Stdout -match '(?im)^\s*STATE\s*:\s*4\s+RUNNING') { return $true }
    $null = Invoke-Bounded -FilePath $sc -ArgumentList @('start', $ServiceName) -Milliseconds 10000
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        Start-Sleep -Milliseconds 750
        $query2 = Invoke-Bounded -FilePath $sc -ArgumentList @('query', $ServiceName) -Milliseconds 5000
        if ($query2.ExitCode -eq 0 -and $query2.Stdout -match '(?im)^\s*STATE\s*:\s*4\s+RUNNING') {
            Write-DLine ("privileged helper service running: {0}" -f $ServiceName) 'Green'
            return $true
        }
    }
    Write-DLine ("WARN privileged helper service did not start: {0}" -f $ServiceName) 'Yellow'
    return $false
}

function Start-DockerVmmWithTray {
    $backendExe = Join-Path ${env:ProgramFiles} 'Docker\Docker\resources\com.docker.backend.exe'
    $desktopExe = Join-Path ${env:ProgramFiles} 'Docker\Docker\Docker Desktop.exe'
    if (-not (Test-Path -LiteralPath $backendExe -PathType Leaf) -or -not (Test-Path -LiteralPath $desktopExe -PathType Leaf)) {
        Write-DLine 'ERROR Docker VMM backend or Docker Desktop tray executable was not found' 'Red'
        return $false
    }
    try {
        # Docker Desktop must own startup. A backend created with
        # -with-frontend=false rejects a later tray attachment and makes the
        # Desktop process exit even though the daemon remains healthy.
        & 'F:\study\Platforms\windows\functions\Start-DockerVmmDesktop.ps1' -SettingsAlreadyEnforced | Out-Host
        Write-DLine 'Docker VMM and system-tray frontend launched unattended' 'Cyan'
        return $true
    } catch {
        Write-DLine ("ERROR Docker VMM/tray launch failed: {0}" -f $_.Exception.Message) 'Red'
        return $false
    }
}

function Wait-ForDaemon {
    param([string]$DockerExe, [int]$Seconds = 120)
    $deadline = (Get-Date).AddSeconds([Math]::Max(5, $Seconds))
    $lastRemainingBucket = -1
    while ((Get-Date) -lt $deadline) {
        if (Test-DaemonReady -DockerExe $DockerExe -Milliseconds 500) { return $true }
        $remaining = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalSeconds)
        $remainingBucket = [int][Math]::Ceiling($remaining / 15)
        if ($remainingBucket -ne $lastRemainingBucket) {
            Write-DLine ("waiting for Docker daemon; timeout remaining={0}s" -f $remaining) 'DarkCyan'
            $lastRemainingBucket = $remainingBucket
        }
        Start-Sleep -Milliseconds 100
    }
    return (Test-DaemonReady -DockerExe $DockerExe -Milliseconds 1000)
}

function Stop-DKillWorker {
    param([Diagnostics.Process]$Process)
    if ($null -eq $Process) { return }
    $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if (Test-Path -LiteralPath $taskkill -PathType Leaf) {
        try {
            $killer = Start-Process -FilePath $taskkill -ArgumentList @('/PID', [string]$Process.Id, '/T', '/F') -WindowStyle Hidden -PassThru -ErrorAction Stop
            $null = $killer.WaitForExit(400)
        } catch { }
    }
    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            $Process.Kill()
            $null = $Process.WaitForExit(400)
        }
    } catch { }
}

# ---------------------------------------------------------------------------
# SelfTest
# ---------------------------------------------------------------------------
if ($SelfTest) {
    $validatedDataRoot = Assert-DKillDedicatedPath -Path $script:DKillVmmDataRoot -RequiredLeaf 'DockerDesktopVMM'
    $validatedMaintenanceRoot = Assert-DKillDedicatedPath -Path $script:DKillMaintenanceRoot -RequiredLeaf 'DockerMaintenance'
    Write-DLine ("elevated={0}" -f (Test-DAdmin)) 'Cyan'
    Write-DLine ("docker.exe={0}" -f (Find-DockerExe)) 'Cyan'
    Write-DLine ("default_mode={0}" -f $(if ($Preserve) { 'PRESERVING_VMM_RESTART' } else { 'DESTRUCTIVE_VMM_RESET' })) 'Cyan'
    Write-DLine ("docker_vmm_configured={0}" -f (Test-DockerVmmConfigured)) 'Cyan'
    Write-DLine ("native_context_probe_available={0}" -f $dockerNativeContextAvailable) 'Cyan'
    $dockerExe = Find-DockerExe
    if ($dockerExe) {
        $selfTestDaemonReady = Test-DaemonReady -DockerExe $dockerExe -Milliseconds 4000
        Write-DLine ("daemon_ready={0}" -f $selfTestDaemonReady) 'Cyan'
        if ($selfTestDaemonReady) {
            $selfTestUsage = Get-DKillEngineUsage -DockerExe $dockerExe
            Write-DLine ("engine_usage_audit_valid={0}; empty={1}" -f $selfTestUsage.Valid, $selfTestUsage.Empty) 'Cyan'
            if (-not $selfTestUsage.Valid) { throw 'Docker engine usage audit self-test failed.' }
        }
    }
    Write-DLine ("tray_frontend_ready={0}" -f (Test-DockerFrontendReady)) 'Cyan'
    Write-DLine ("vmm_data_root={0}" -f $validatedDataRoot) 'Cyan'
    Write-DLine ("maintenance_root={0}" -f $validatedMaintenanceRoot) 'Cyan'
    Write-DLine ("speed_target_seconds={0}" -f $MaxSeconds) 'Cyan'
    Write-DLine ("synchronous_worker_timeout_seconds={0}" -f $script:DKillWorkerTimeoutSeconds) 'Cyan'
    Write-DLine 'returns_before_ready=false' 'Cyan'
    Write-DLine 'SELFTEST_OK' 'Green'
    exit 0
}

# Keep operational work isolated in a child so internal `exit` calls cannot
# close the caller's shell. Unlike the previous implementation, the supervisor
# remains synchronous and never reports success before the worker is finished.
Initialize-DKillMaintenanceRoot
if (-not $Worker) {
    $outer = [System.Diagnostics.Stopwatch]::StartNew()
    $outerStartedUtc = [DateTime]::UtcNow
    $mutex = New-Object Threading.Mutex($false, 'Global\Codex-DKill-BoundedSupervisor')
    $mutexOwned = $false
    try { $mutexOwned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $mutexOwned = $true }
    if (-not $mutexOwned) {
        $mutex.Dispose()
        Write-DKillActiveWorkerHandoff
        return
    }
    if (Test-DKillWorkerActive) {
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
        Write-DKillActiveWorkerHandoff
        return
    }
    Remove-DKillStaleWorkerArtifacts
    $powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $outFile = Join-Path $script:DKillMaintenanceRoot ('dkill-worker-' + [guid]::NewGuid().ToString('N') + '.out')
    $errFile = [IO.Path]::ChangeExtension($outFile, '.err')
    $keepArtifacts = $false
    $childArguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-Worker')
    if ($Preserve) { $childArguments += '-Preserve' }
    if ($NoRestart) { $childArguments += '-NoRestart' }
    if ($FactoryReset) { $childArguments += '-FactoryReset' }
    $childArguments += @('-OwnerSid', $script:DKillOwnerSid)
    if (-not [string]::IsNullOrWhiteSpace($ConfirmFactoryReset)) { $childArguments += @('-ConfirmFactoryReset', $ConfirmFactoryReset) }
    $childArguments += @('-MaxSeconds', [string]$MaxSeconds)
    try {
        $child = Start-Process -FilePath $powerShellExe -ArgumentList $childArguments -WorkingDirectory $script:DKillMaintenanceRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
        $recoveryDeadline = [DateTime]::UtcNow.AddSeconds($script:DKillWorkerTimeoutSeconds)
        $childExited = $false
        while (-not $childExited) {
            $remainingMilliseconds = [int][Math]::Max(0, ($recoveryDeadline - [DateTime]::UtcNow).TotalMilliseconds)
            if ($remainingMilliseconds -le 0) { break }
            $childExited = $child.WaitForExit([Math]::Min(250, $remainingMilliseconds))
        }
        if (-not $childExited) {
            $keepArtifacts = $true
            $outer.Stop()
            $elapsed = [math]::Round($outer.Elapsed.TotalSeconds, 2)
            Write-DLine ("TIMEOUT synchronous worker exceeded {0}s; terminating it" -f $script:DKillWorkerTimeoutSeconds) 'Red'
            Stop-DKillWorker -Process $child
            throw ("Docker reset did not finish within {0}s; worker terminated. Logs: {1}, {2}" -f $script:DKillWorkerTimeoutSeconds, $outFile, $errFile)
        }
        # The child has exited. Do not issue an unbounded second WaitForExit:
        # Docker's fresh frontend can inherit a redirected file handle even
        # though the reset worker itself is finished.
        $child.Refresh()
        $captured = ''
        if (Test-Path -LiteralPath $outFile) {
            $captured = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($captured)) { $Host.UI.WriteLine($captured.TrimEnd()) }
        }
        if (Test-Path -LiteralPath $errFile) {
            $capturedError = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($capturedError)) { Write-Error $capturedError.TrimEnd() }
        }
        $childExitCode = $null
        try { $childExitCode = [int]$child.ExitCode } catch { }
        $workerReportedFailure = $captured -match '(?im)^\[dkill\].*=== DKILL FAILED'
        if ($workerReportedFailure) { $childExitCode = 1 }
        $dockerExe = Find-DockerExe
        if ($NoRestart) {
            $remainingEngineDisks = @(@($script:DKillCDriveEngineDisks) + (Join-Path $script:DKillVmmDataRoot 'DockerDesktop.vhdx')) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
            $postconditionPassed = -not (Test-DaemonReady -DockerExe $dockerExe -Milliseconds 500) -and
                -not (Test-DockerFrontendReady) -and
                @($remainingEngineDisks).Count -eq 0 -and
                (Test-DKillDockerIdentityCleared)
        } else {
            $postconditionPassed = (Test-DaemonReady -DockerExe $dockerExe -Milliseconds 1000) -and (Test-DockerVmmConfigured) -and (Test-DockerFrontendReady)
            if (-not $Preserve) {
                $freshDisk = Get-Item -LiteralPath (Join-Path $script:DKillVmmDataRoot 'DockerDesktop.vhdx') -Force -ErrorAction SilentlyContinue
                $cDriveDisks = @($script:DKillCDriveEngineDisks | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
                $verifiedUsage = Get-DKillEngineUsage -DockerExe $dockerExe
                $postconditionPassed = $postconditionPassed -and $freshDisk -and
                    $freshDisk.CreationTimeUtc -ge $outerStartedUtc.AddSeconds(-2) -and
                    $cDriveDisks.Count -eq 0 -and
                    $verifiedUsage.Empty -and
                    (Test-DKillDockerIdentityCleared)
            }
        }
        if ($null -eq $childExitCode) {
            # ShellExecute elevation can omit ExitCode even after WaitForExit. The
            # fresh live postcondition is stronger than that missing metadata.
            $childExitCode = if ($postconditionPassed) { 0 } else { 1 }
        } elseif (-not $postconditionPassed) {
            $childExitCode = 1
        }
        $outer.Stop()
        $elapsed = [math]::Round($outer.Elapsed.TotalSeconds, 2)
        $withinTarget = $elapsed -lt 10
        Write-DLine ("END_TO_END elapsed={0}s child_exit={1} postcondition={2} under_10_seconds={3}" -f $elapsed, $childExitCode, $postconditionPassed, $withinTarget) $(if ($childExitCode -eq 0 -and $postconditionPassed) { 'Green' } else { 'Red' })
        if ($childExitCode -ne 0) { throw "Docker reset worker failed live postcondition verification (exit=$childExitCode)." }
        if (-not $postconditionPassed) { throw 'Docker reset failed its live ready/data-location postcondition.' }
        if (-not $withinTarget) { Write-DLine 'WARN Docker is ready, but this run could not physically complete in under ten seconds' 'Yellow' }
        return
    } finally {
        if (-not $keepArtifacts) {
            foreach ($file in @($outFile, $errFile)) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        }
        if ($mutexOwned) {
            try { $mutex.ReleaseMutex() } catch { }
            try { $mutex.Dispose() } catch { }
        }
    }
}

# A supervisor must never fall through and execute the destructive worker body
# itself, even if its caller converts a terminating child error to a record.
if (-not $Worker) { return }

if ($Preserve -and $FactoryReset) {
    Write-DLine 'Choose either -Preserve or the destructive reset, not both.' 'Red'
    exit 2
}

if ($Preserve) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-DLine '=== DKILL: PRESERVING DOCKER VMM RESTART START ===' 'Yellow'
    Set-DockerVmmSettings
    $dockerExe = Find-DockerExe
    if (-not $dockerExe) {
        Write-DLine 'docker.exe not found; Docker Desktop may not be installed' 'Red'
        exit 1
    }
    Stop-AllDocker
    if ($NoRestart) {
        Write-DLine 'Docker VMM stopped; Docker data and VMM settings preserved' 'Green'
        exit 0
    }
    if (-not (Start-DockerVmmWithTray)) { exit 1 }
    if (-not (Wait-ForDaemon -DockerExe $dockerExe -Seconds 90)) {
        Write-DLine 'Docker daemon did not become ready after the bounded VMM restart' 'Red'
        exit 1
    }
    if (-not (Test-DockerVmmConfigured)  -or -not (Test-DockerFrontendReady)) {
        Write-DLine 'Docker answered, but the Docker VMM runtime was not active' 'Red'
        exit 1
    }
    $sw.Stop()
    Write-DLine ("=== DKILL VMM RESTART COMPLETE in {0}s; daemon and tray ready; data preserved ===" -f [math]::Round($sw.Elapsed.TotalSeconds, 2)) 'Green'
    exit 0
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$resetStartedUtc = [DateTime]::UtcNow
$freeBytesBefore = [IO.DriveInfo]::new('C').AvailableFreeSpace
$script:DKillSucceeded = $true
Write-DLine '=== DKILL: COMPLETE AUTOMATIC DOCKER WIPE START ===' 'Yellow'

# Keep the retired legacy watchdog out of the VMM wipe. These calls are kept to
# 500 ms each so an unhealthy Task Scheduler service cannot break the deadline.
$schtasks = Join-Path $env:SystemRoot 'System32\schtasks.exe'
$script:WatchdogWasEnabled = $false
if (Test-Path -LiteralPath $schtasks) {
    $null = Invoke-Bounded -FilePath $schtasks -ArgumentList @('/Change', '/TN', $script:WatchdogTask, '/DISABLE') -Milliseconds 500
    $null = Invoke-Bounded -FilePath $schtasks -ArgumentList @('/End', '/TN', $script:WatchdogTask) -Milliseconds 500
    Write-DLine 'DockerDesktopWatchdog paused for the wipe' 'Cyan'
}
try { Remove-Item -LiteralPath 'C:\Temp\Docker-WSL-HealthFix.lock' -Force -ErrorAction SilentlyContinue } catch { }

# 1) Kill everything.
Write-DLine 'stopping Docker VMM processes and its optional Windows service' 'Yellow'
Stop-AllDocker

# 2) Delete every Docker-owned data location and identity record. Docker Desktop
# program files and uninstall metadata are intentionally outside these targets.
$credentialsCleared = [bool](Clear-DKillDockerCredentials)
if (-not $credentialsCleared) { $script:DKillSucceeded = $false }
$legacyVirtualizationCleared = [bool](Remove-DKillLegacyDockerVirtualizationData)
if (-not $legacyVirtualizationCleared) { $script:DKillSucceeded = $false }
Write-DLine ("identity_cleanup={0}; legacy_virtualization_cleanup={1}" -f $credentialsCleared, $legacyVirtualizationCleared) $(if ($credentialsCleared -and $legacyVirtualizationCleared) { 'Green' } else { 'Red' })

$targets = @(
    (Join-Path $env:ProgramData 'DockerDesktop'),           # vhdx, vm-data, service logs, settings
    (Join-Path $env:ProgramData 'Docker'),
    (Join-Path $env:LOCALAPPDATA 'Docker'),                 # wsl data/disks, buildx, logs, config
    (Join-Path $env:LOCALAPPDATA 'Docker Desktop'), (Join-Path $env:LOCALAPPDATA 'docker-secrets-engine'),
    (Join-Path $env:APPDATA 'Docker'),                      # settings and login identity
    (Join-Path $env:USERPROFILE '.docker'),                 # CLI auth, contexts, buildx, plugins
    (Join-Path $env:USERPROFILE '.docker-desktop'),
    $script:DKillVmmDataRoot                                # active VMM data is permanently off C:
)

# Free the active off-C disk plus every known legacy C-drive engine disk first.
$vhdPaths = @(@($script:DKillCDriveEngineDisks) + (Join-Path $script:DKillVmmDataRoot 'DockerDesktop.vhdx')) | Select-Object -Unique
$oldVhdRecords = @()
foreach ($vhdx in $vhdPaths) {
    if (-not (Test-Path -LiteralPath $vhdx -PathType Leaf)) { continue }
    $oldVhd = Get-Item -LiteralPath $vhdx -Force -ErrorAction SilentlyContinue
    if ($oldVhd) {
        $oldVhdRecords += [pscustomobject]@{ Path = $vhdx; Length = [int64]$oldVhd.Length; CreatedUtc = $oldVhd.CreationTimeUtc }
    }
    Write-DLine ("deleting Docker engine VHDX: {0}" -f $vhdx) 'Yellow'
    $vhdxGone = $false
    $vhdxDeadline = (Get-Date).AddSeconds(20)
    do {
        $null = Remove-DockerPath -Path $vhdx
        if (-not (Test-Path -LiteralPath $vhdx)) { $vhdxGone = $true; break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $vhdxDeadline)
    if ($vhdxGone) {
        Write-DLine ("VHDX deleted - released {0:N2} GB" -f ($(if ($oldVhd) { $oldVhd.Length } else { 0 }) / 1GB)) 'Green'
    } else {
        $script:DKillSucceeded = $false
        Write-DLine ("ERROR VHDX still locked: {0}" -f $vhdx) 'Red'
    }
}

$targets += $script:DKillExtraDataRoots
foreach ($t in $targets) {
    if (Test-Path -LiteralPath $t) {
        if (-not (Remove-DockerPath -Path $t)) { $script:DKillSucceeded = $false }
    }
}
$transientArtifactsCleared = [bool](Remove-DKillCDriveTransientArtifacts)
if (-not $transientArtifactsCleared) { $script:DKillSucceeded = $false }
Write-DLine ("recursive_data_cleanup={0}; transient_cleanup={1}" -f $script:DKillSucceeded, $transientArtifactsCleared) $(if ($script:DKillSucceeded) { 'Green' } else { 'Red' })

# Docker engine roots above are the verified recursive deletion targets.

Set-DockerVmmSettings -Fresh

if ($script:DKillSucceeded) { Write-DLine 'All prior Docker data, settings, sign-in state, and credentials were removed' 'Green' } else { Write-DLine 'Docker data deletion was incomplete; recovering daemon availability' 'Red' }

# 3) Bring Docker back on fresh data - ready to use, no delays.
if (-not $NoRestart) {
    Write-DLine 'starting fresh Docker VMM' 'Yellow'
    $null = Start-DockerVmmWithTray
    $dockerExe = Find-DockerExe
    if ($dockerExe) {
        # Correctness wins over the speed target: wait synchronously and fail
        # loudly if the fresh daemon cannot become usable within this bound.
        $backgroundReadySeconds = $script:DKillReadyTimeoutSeconds
        $becameReady = Wait-ForDaemon -DockerExe $dockerExe -Seconds $backgroundReadySeconds
        if (-not $becameReady) {
            $sailorAlive = @(Get-Process -Name 'com.docker.backend' -ErrorAction SilentlyContinue).Count -gt 0
            if (-not $sailorAlive) {
                Write-DLine 'hypervisor process exited; relaunching Docker VMM' 'Yellow'
                $null = Start-DockerVmmWithTray
            } else {
                Write-DLine 'daemon slow to start - running a force cycle' 'Yellow'
                Stop-AllDocker
                $null = Start-DockerVmmWithTray
            }
            $becameReady = Wait-ForDaemon -DockerExe $dockerExe -Seconds $backgroundReadySeconds
        }
        if ($becameReady) {
            $engineUsage = Get-DKillEngineUsage -DockerExe $dockerExe
            if (-not $engineUsage.Empty) {
                $script:DKillSucceeded = $false
                Write-DLine ("ERROR fresh engine is not empty or could not be audited: containers={0}; images={1}; volumes={2}; build_cache={3}; valid={4}" -f $engineUsage.Containers, $engineUsage.Images, $engineUsage.Volumes, $engineUsage.BuildCache, $engineUsage.Valid) 'Red'
            } else {
                Write-DLine ("READY - Docker daemon and system tray are running fresh. Server version: {0}; containers={1}; images={2}; volumes={3}; build_cache={4}" -f $(if ($script:DKillLastServerVersion) { $script:DKillLastServerVersion } else { 'unknown' }), $engineUsage.Containers, $engineUsage.Images, $engineUsage.Volumes, $engineUsage.BuildCache) 'Green'
            }
        } else {
            $script:DKillSucceeded = $false
            Write-DLine 'ERROR daemon not responding after the bounded fresh start' 'Red'
        }
    } else {
        $script:DKillSucceeded = $false
        Write-DLine 'ERROR docker.exe not found; Docker Desktop may not be installed' 'Red'
    }
    if (-not (Test-DockerVmmConfigured) ) {
        $script:DKillSucceeded = $false
        Write-DLine 'ERROR fresh daemon is not running on Docker VMM' 'Red'
    }
    if (-not (Test-DockerFrontendReady)) {
        $script:DKillSucceeded = $false
        Write-DLine 'ERROR Docker daemon is ready but the system-tray frontend is missing' 'Red'
    } else {
        Write-DLine 'Docker system-tray frontend verified ready' 'Green'
    }
    if (-not (Test-DKillDockerIdentityCleared)) {
        $script:DKillSucceeded = $false
        Write-DLine 'ERROR Docker sign-in or credential state remains after the fresh start' 'Red'
    } else {
        Write-DLine 'Docker sign-in files and credential store verified empty after the fresh start' 'Green'
    }
    $freshVhdPath = Join-Path $script:DKillVmmDataRoot 'DockerDesktop.vhdx'
    $freshVhd = Get-Item -LiteralPath $freshVhdPath -Force -ErrorAction SilentlyContinue
    if (-not $freshVhd -or $freshVhd.CreationTimeUtc -lt $resetStartedUtc.AddSeconds(-2)) {
        $script:DKillSucceeded = $false
        Write-DLine 'ERROR a newly created Docker VMM disk was not verified' 'Red'
    } else {
        Write-DLine ("fresh VMM disk verified: {0:N2} GB, created {1:o}" -f ($freshVhd.Length / 1GB), $freshVhd.CreationTimeUtc) 'Green'
    }
    $cDriveDiskResiduals = @($script:DKillCDriveEngineDisks | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($cDriveDiskResiduals.Count -gt 0) {
        $script:DKillSucceeded = $false
        foreach ($residual in $cDriveDiskResiduals) { Write-DLine ("ERROR C-drive Docker engine disk remains: {0}" -f $residual) 'Red' }
    } else {
        Write-DLine 'C-drive Docker engine VHDX residuals verified: 0' 'Green'
    }
} else {
    Write-DLine 'NoRestart mode: wipe complete, Docker Desktop NOT started' 'Cyan'
}

# The old WSL/Hyper-V watchdog remains retired; normal Docker commands use the
# bounded VMM-aware wrapper when recovery is actually needed.
if (Test-Path -LiteralPath $schtasks) {
    $null = Invoke-Bounded -FilePath $schtasks -ArgumentList @('/Change', '/TN', $script:WatchdogTask, '/DISABLE') -Milliseconds 500
    Write-DLine 'DockerDesktopWatchdog left disabled' 'Cyan'
}

$sw.Stop()
$freeBytesAfter = [IO.DriveInfo]::new('C').AvailableFreeSpace
$netFreedGiB = ($freeBytesAfter - $freeBytesBefore) / 1GB
Write-DLine ("C drive net free-space change: {0:N2} GB" -f $netFreedGiB) $(if ($netFreedGiB -ge 0) { 'Green' } else { 'Yellow' })
if (-not $script:DKillSucceeded) {
    Write-DLine ("=== DKILL FAILED after {0}s ===" -f [math]::Round($sw.Elapsed.TotalSeconds, 2)) 'Red'
    exit 1
}
Write-DLine ("=== DKILL COMPLETE in {0}s ===" -f [math]::Round($sw.Elapsed.TotalSeconds, 2)) 'Green'
exit 0
