[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Path,
  [switch]$PreflightOnly,
  [switch]$TarPreflightOnly,
  [switch]$BuildPreflightOnly,
  [ValidateRange(64,4096)][int64]$TargetLayerMiB = 256,
  [string]$EntryPoint = 'mmenu',
  [switch]$InternalWorker
)

# Keep the native process helper's Add-Type call on a verified local compiler
# temp path even when mmenu is launched with -NoProfile.
$codexSafeAddTypePath='F:\study\Platforms\windows\functions\Invoke-CodexSafePowerShellAddType.ps1'
if([IO.File]::Exists($codexSafeAddTypePath)){. $codexSafeAddTypePath}
$ErrorActionPreference = 'Stop'
$script:MmenuCProcessExitCode = $null
$script:MmenuCTempRoot = $null
$script:MmenuCDashboardLastRender = [datetime]::MinValue
$script:MmenuCDashboardLastLine = ''
$script:MmenuCDashboardPending = $false
$script:MmenuCDockerHubCredential = $null
$script:MmenuCDockerHubLoginAttempted = $false
function Write-MmenuC {
  param([string]$Message,[ConsoleColor]$Color=[ConsoleColor]::Cyan)
  if($env:HERMES_MMENU_GMENU -eq '1' -and $Color -notin @([ConsoleColor]::Red,[ConsoleColor]::Yellow) -and $Message -match '\[tar-layer\].*(START|DONE|complete=1)|blob already exists remotely|speed-floor|reusing cached layer digests|Docker path:|Repository mode:|direct live push is armed'){return}
  if($script:MmenuCDashboardPending){
    $script:MmenuCDashboardPending = $false
    Write-Host ''
  }
  Write-Host $Message -ForegroundColor $Color
}
trap {
  $handledError=$_
  if($_.Exception -is [System.Management.Automation.PipelineStoppedException]){
    $global:LASTEXITCODE = 130
    $script:MmenuCProcessExitCode = 130
    try{if($global:Error.Count -and [object]::ReferenceEquals($global:Error[0],$handledError)){$global:Error.RemoveAt(0)}}catch{}
    return
  }
  $msg = if ($_.Exception -and $_.Exception.Message) { $_.Exception.Message } else { [string]$_ }
  Write-MmenuC "[$EntryPoint] FAILED: $msg; returning to PowerShell shell without exception dump" Red
  $global:LASTEXITCODE = 1
  $script:MmenuCProcessExitCode = 1
  try{if($global:Error.Count -and [object]::ReferenceEquals($global:Error[0],$handledError)){$global:Error.RemoveAt(0)}}catch{}
  return
}
function Quote-MmenuCArg { param([AllowNull()][AllowEmptyString()][string]$Value) if($null -eq $Value){$Value=''}; return '"' + ($Value -replace '"','\"') + '"' }
function Quote-MmenuCPsString { param([AllowNull()][AllowEmptyString()][string]$Value) if($null -eq $Value){$Value=''}; return "'" + ($Value -replace "'","''") + "'" }
function Get-MmenuCWindowsRoot {
  foreach($candidate in @([string]$env:WINDIR,[string]$env:SystemRoot)){
    if(-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)){ return $candidate }
  }
  throw 'Windows root is unavailable through WINDIR or SystemRoot.'
}
function Format-MmenuCMiB {
  param([int64]$Bytes)
  if($Bytes -le 0){ return '0 B' }
  if($Bytes -lt 1KB){ return ('{0:N0} B' -f $Bytes) }
  if($Bytes -lt 1MB){ return ('{0:N2} KiB' -f ([double]$Bytes / 1KB)) }
  return ('{0:N2} MiB' -f ([double]$Bytes / 1MB))
}
function Test-MmenuCTempRootWritable([string]$Root) {
  $probe=$null;$stream=$null
  try {
    [void][IO.Directory]::CreateDirectory($Root)
    $probe=Join-Path $Root ('.probe-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $stream=[IO.File]::Open($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $stream.Dispose();$stream=$null
    [IO.File]::Delete($probe)
    return $true
  } catch {
    if($stream){try{$stream.Dispose()}catch{}}
    if($probe -and [IO.File]::Exists($probe)){try{[IO.File]::Delete($probe)}catch{}}
    return $false
  }
}
function Get-MmenuCTempRoot {
  param([string]$SourcePath='')
  if(-not [string]::IsNullOrWhiteSpace([string]$script:MmenuCTempRoot)){
    if(Test-Path -LiteralPath ([string]$script:MmenuCTempRoot) -PathType Container){ return [string]$script:MmenuCTempRoot }
    $script:MmenuCTempRoot=$null
  }
  $override = [string]$env:HERMES_MMENU_TEMP_ROOT
  if(-not [string]::IsNullOrWhiteSpace($override)){
    $candidates=New-Object 'Collections.Generic.List[string]'
    $candidates.Add([IO.Path]::GetFullPath($override))
  } else {
    $basis = if(-not [string]::IsNullOrWhiteSpace($SourcePath)){ $SourcePath } elseif(-not [string]::IsNullOrWhiteSpace([string]$Path)){ [string]$Path } else { (Get-Location).ProviderPath }
    try {
      if(Test-Path -LiteralPath $basis){ $basis = (Resolve-Path -LiteralPath $basis).ProviderPath }
    } catch {}
    $full = [IO.Path]::GetFullPath($basis)
    $driveRoot = [IO.Path]::GetPathRoot($full)
    $candidates=New-Object 'Collections.Generic.List[string]'
    if(-not [string]::IsNullOrWhiteSpace($driveRoot) -and -not $full.StartsWith('\\',[StringComparison]::OrdinalIgnoreCase)){
      $candidates.Add((Join-Path $driveRoot '.hermes-docker-mmenu-temp'))
    }
    $localData=[string]$env:LOCALAPPDATA
    if([string]::IsNullOrWhiteSpace($localData)){$localData=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)}
    if(-not [string]::IsNullOrWhiteSpace($localData)){$candidates.Add((Join-Path $localData '.hermes-docker-mmenu-temp'))}
    $systemTemp=[IO.Path]::GetTempPath()
    if(-not [string]::IsNullOrWhiteSpace($systemTemp)){$candidates.Add((Join-Path $systemTemp '.hermes-docker-mmenu-temp'))}
  }
  $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach($candidate in $candidates) {
    if(-not $seen.Add([string]$candidate)){continue}
    if(-not (Test-MmenuCTempRootWritable ([string]$candidate))){continue}
    try {
      $item=Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
      $item.Attributes=($item.Attributes -bor [IO.FileAttributes]::Hidden)
      $script:MmenuCTempRoot=$item.FullName
      return [string]$script:MmenuCTempRoot
    } catch {}
  }
  if(-not [string]::IsNullOrWhiteSpace($override)){throw "${EntryPoint}: configured temporary root is not writable: $override"}
  throw "${EntryPoint}: no writable temporary folder is available on the source volume or in the user temp locations. Set HERMES_MMENU_TEMP_ROOT to a writable folder with enough free space."
}
function Join-MmenuCTempPath {
  param([Parameter(Mandatory=$true)][string]$Leaf,[string]$SourcePath='')
  return (Join-Path (Get-MmenuCTempRoot -SourcePath $SourcePath) $Leaf)
}
function Get-MmenuCMinSpeedBytesPerSecond {
  $mbps = 20.0
  $raw = [string]$env:HERMES_MMENU_MIN_MBPS
  if(-not [string]::IsNullOrWhiteSpace($raw)){
    $parsed = 0.0
    if([double]::TryParse($raw,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsed)){ $mbps = $parsed }
  }
  if($mbps -le 0){ return 0L }
  return [int64]($mbps * 1MB)
}
function Get-MmenuCLowSpeedGraceSeconds {
  $seconds = 120
  if($env:HERMES_MMENU_LOW_SPEED_GRACE_SECONDS -match '^\d+$'){ $seconds = [int]$env:HERMES_MMENU_LOW_SPEED_GRACE_SECONDS }
  return [Math]::Max(15,$seconds)
}
function Get-MmenuCLowSpeedMinRemainingSeconds {
  $seconds = 600
  if($env:HERMES_MMENU_LOW_SPEED_MIN_REMAINING_SECONDS -match '^\d+$'){ $seconds = [int]$env:HERMES_MMENU_LOW_SPEED_MIN_REMAINING_SECONDS }
  return [Math]::Max(30,$seconds)
}
function Update-MmenuCLowSpeedGuard {
  param(
    [Parameter(Mandatory=$true)][hashtable]$State,
    [Parameter(Mandatory=$true)][string]$Phase,
    [Parameter(Mandatory=$true)][datetime]$Started,
    [int64]$DoneBytes=0,
    [int64]$TotalBytes=0,
    [string]$Detail=''
  )
  $floorBytes = Get-MmenuCMinSpeedBytesPerSecond
  if($floorBytes -le 0 -or $TotalBytes -le 0 -or $DoneBytes -le 0 -or $DoneBytes -ge $TotalBytes){ return $false }
  $now = Get-Date
  $grace = Get-MmenuCLowSpeedGraceSeconds
  if((($now - $Started).TotalSeconds) -lt $grace){ return $false }
  if(-not $State.ContainsKey('SpeedFloorLastBytes')){
    $State.SpeedFloorLastBytes = [int64]$DoneBytes
    $State.SpeedFloorLastTime = $now
    $State.SpeedFloorLowSince = $null
    $State.SpeedFloorLastWarnAt = [datetime]::MinValue
    return $false
  }
  $lastBytes = [int64]$State.SpeedFloorLastBytes
  $lastTime = [datetime]$State.SpeedFloorLastTime
  $deltaSeconds = [Math]::Max(0.001,($now - $lastTime).TotalSeconds)
  $deltaBytes = [Math]::Max([int64]0,[int64]$DoneBytes - $lastBytes)
  $rateBytes = [double]$deltaBytes / $deltaSeconds
  $State.SpeedFloorLastBytes = [int64]$DoneBytes
  $State.SpeedFloorLastTime = $now
  $State.SpeedFloorRateBytes = [double]$rateBytes
  if($rateBytes -ge [double]$floorBytes){
    $State.SpeedFloorLowSince = $null
    return $false
  }
  if(([double]$rateBytes / [double]$floorBytes) -ge 0.90){
    $State.SpeedFloorLowSince = $null
    return $false
  }
  if($null -eq $State.SpeedFloorLowSince){ $State.SpeedFloorLowSince = $now }
  $lowFor = [Math]::Max([double]0,($now - [datetime]$State.SpeedFloorLowSince).TotalSeconds)
  $remainingBytes = [Math]::Max([int64]0,[int64]$TotalBytes - [int64]$DoneBytes)
  $etaSeconds = if($rateBytes -gt 1){ [double]$remainingBytes / $rateBytes } else { [double]::PositiveInfinity }
  $minRemaining = Get-MmenuCLowSpeedMinRemainingSeconds
  if($deltaBytes -gt 0){
    if((($now - [datetime]$State.SpeedFloorLastWarnAt).TotalSeconds) -ge 30){
      Write-Host ''
      Write-MmenuC ("[$EntryPoint][speed-floor] {0} current={1}/s target>={2}/s but bytes are still moving; continuing instead of restarting. low_for={3:N0}s remaining={4}" -f $Phase,(Format-MmenuCMiB ([int64]$rateBytes)),(Format-MmenuCMiB $floorBytes),$lowFor,(Format-MmenuCMiB $remainingBytes)) DarkYellow
      $State.SpeedFloorLastWarnAt = $now
    }
    return $false
  }
  if($lowFor -ge $grace -and $etaSeconds -ge $minRemaining){
    Write-Host ''
    Write-MmenuC ("[$EntryPoint][speed-floor] {0} made no byte progress for {1:N0}s with {2} remaining; aborting this Docker attempt for retry. {3}" -f $Phase,$lowFor,(Format-MmenuCMiB $remainingBytes),$Detail) Yellow
    return $true
  }
  if((($now - [datetime]$State.SpeedFloorLastWarnAt).TotalSeconds) -ge 30){
    Write-Host ''
    Write-MmenuC ("[$EntryPoint][speed-floor] {0} current={1}/s target>={2}/s low_for={3:N0}s remaining={4}" -f $Phase,(Format-MmenuCMiB ([int64]$rateBytes)),(Format-MmenuCMiB $floorBytes),$lowFor,(Format-MmenuCMiB $remainingBytes)) DarkYellow
    $State.SpeedFloorLastWarnAt = $now
  }
  return $false
}
if (-not (Get-Command Write-HermesDockerCommanderDashboard -CommandType Function -ErrorAction Ignore)) {
  function Write-HermesDockerCommanderDashboard {
    param([string]$Name,[string]$Phase,[datetime]$Started,[int64]$DoneBytes,[int64]$TotalBytes,[string]$Detail='')
    $elapsed=[Math]::Max(0.001,((Get-Date)-$Started).TotalSeconds)
    $pct=if($TotalBytes -gt 0){[Math]::Min([double]100.0,[Math]::Max([double]0.0,100.0*[double]$DoneBytes/[Math]::Max([double]1.0,[double]$TotalBytes)))}else{0}
    $speed=[int64]($DoneBytes/$elapsed)
    $barWidth=24
    $fill=if($TotalBytes -gt 0){[Math]::Min([int]$barWidth,[Math]::Max([int]0,[int][Math]::Round($barWidth*$pct/100.0)))}else{0}
    $bar=('#'*$fill).PadRight($barWidth,'.')
    if($TotalBytes -gt 0){
      $metric=('{0,6:N2}% {1}/{2} {3}/s elapsed {4,5:N0}s' -f $pct,(Format-MmenuCMiB $DoneBytes),(Format-MmenuCMiB $TotalBytes),(Format-MmenuCMiB $speed),$elapsed)
    } else {
      $metric=('active elapsed={0,6:N0}s' -f $elapsed)
    }
    $line=('[{0:HH:mm:ss}] {1,-7} {2,-13} [{3}] {4} {5}' -f (Get-Date),$Name,$Phase,$bar,$metric,$Detail)
    $width=160
    if($width -lt 40){$width=160}
    if($line.Length -ge $width){$line=$line.Substring(0,$width-1)}
    Write-Host ("`r"+$line.PadRight($width-1)) -NoNewline -ForegroundColor Cyan
    $script:MmenuCDashboardPending = $true
  }
}
function Write-MmenuCDashboard {
  param([string]$Name,[string]$Phase,[datetime]$Started,[int64]$DoneBytes,[int64]$TotalBytes,[string]$Detail='')
  if($env:HERMES_MMENU_GMENU -eq '1') {
    $now=Get-Date
    if($script:GMenuDashboardPhase -eq $Phase -and $script:GMenuDashboardTime -and ($now-$script:GMenuDashboardTime).TotalMilliseconds -lt 200 -and $DoneBytes -lt $TotalBytes){return}
    $script:GMenuDashboardPhase=$Phase;$script:GMenuDashboardTime=$now
    $percent=if($TotalBytes -gt 0){[Math]::Min(100.0,[Math]::Max(0.0,100.0*$DoneBytes/$TotalBytes))}else{0}
    $rate=[Math]::Max([int64]0,$DoneBytes)/[Math]::Max(0.001,($now-$Started).TotalSeconds)/1MB
    Write-Host ('GMENU {0} {1}% {2:F1}/{3:F1} MiB {4:F1} MiB/s' -f $Phase,$percent.ToString('F3',[Globalization.CultureInfo]::InvariantCulture),($DoneBytes/1MB),($TotalBytes/1MB),$rate)
    return
  }
  $dashboardErrorCount=$global:Error.Count
  $dashboardOutput=@()
  try {
    $dashboardOutput = @(Write-HermesDockerCommanderDashboard -Name $Name -Phase $Phase -Started $Started -DoneBytes $DoneBytes -TotalBytes $TotalBytes -Detail $Detail)
  } catch {
    $dashboardOutput=@()
  } finally {
    try{while($global:Error.Count -gt $dashboardErrorCount){$global:Error.RemoveAt(0)}}catch{}
  }
  foreach($line in $dashboardOutput){
    if($null -ne $line -and -not [string]::IsNullOrWhiteSpace([string]$line)){ Write-Host ([string]$line) }
  }
}
function Convert-MmenuCSlug {
  param([AllowNull()][AllowEmptyString()][string]$Text,[int]$MaxLen=128)
  $s = ([string]$Text).Trim().ToLowerInvariant()
  $s = [Text.RegularExpressions.Regex]::Replace($s,'[^a-z0-9._-]+','-')
  $s = [Text.RegularExpressions.Regex]::Replace($s,'-+','-').Trim('-','_','.')
  if([string]::IsNullOrWhiteSpace($s)){ $s='backup' }
  if($s.Length -gt $MaxLen){ $s = $s.Substring(0,$MaxLen).Trim('-','_','.') }
  if([string]::IsNullOrWhiteSpace($s)){ $s='backup' }
  return $s
}
function ConvertTo-MmenuCExtendedPath([string]$Path) {
  if($Path.StartsWith('\\?\',[StringComparison]::OrdinalIgnoreCase)){ return $Path }
  $full=[IO.Path]::GetFullPath($Path)
  if($full.StartsWith('\\',[StringComparison]::OrdinalIgnoreCase)){ return '\\?\UNC\' + $full.Substring(2) }
  return '\\?\' + $full
}
function ConvertFrom-MmenuCExtendedPath([string]$Path) {
  if($Path.StartsWith('\\?\UNC\',[StringComparison]::OrdinalIgnoreCase)){ return '\\' + $Path.Substring(8) }
  if($Path.StartsWith('\\?\',[StringComparison]::OrdinalIgnoreCase)){ return $Path.Substring(4) }
  return $Path
}
function ConvertTo-MmenuCFolderTag {
  param([AllowNull()][AllowEmptyString()][string]$Text,[int]$MaxLen=128)
  if($MaxLen -lt 16){ throw 'Docker tag length must leave room for a stable folder suffix.' }
  $original=[string]$Text
  $slug=Convert-MmenuCSlug $original $MaxLen
  $normalized=$original.Trim().ToLowerInvariant()
  $normalized=[Text.RegularExpressions.Regex]::Replace($normalized,'[^a-z0-9._-]+','-')
  $normalized=[Text.RegularExpressions.Regex]::Replace($normalized,'-+','-').Trim('-','_','.')
  if([string]::IsNullOrWhiteSpace($normalized) -or $normalized.Length -gt $MaxLen) {
    $hashAlgorithm=[Security.Cryptography.SHA256]::Create()
    try { $suffix='-'+[BitConverter]::ToString($hashAlgorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($original))).Replace('-','').ToLowerInvariant().Substring(0,12) }
    finally { $hashAlgorithm.Dispose() }
    if([string]::IsNullOrWhiteSpace($normalized)){$slug='folder'}else{$slug=$normalized.Substring(0,$MaxLen-$suffix.Length).TrimEnd('-','_','.') }
    if([string]::IsNullOrWhiteSpace($slug)){$slug='folder'}
    $slug=$slug+$suffix
  }
  return $slug
}
function Test-MmenuCPythonCandidate {
  param([AllowNull()][AllowEmptyString()][string]$Path)
  if([string]::IsNullOrWhiteSpace($Path)){ return $false }
  if($Path -match '(?i)\\Microsoft\\WindowsApps\\(?:py|python(?:3)?)(?:\.exe)?$'){ return $false }
  try {
    if(-not [IO.File]::Exists($Path)){ return $false }
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Path
    $prefix = if(([IO.Path]::GetFileName($Path)) -ieq 'py.exe'){'-3 '}else{''}
    $startInfo.Arguments = $prefix + '-c "import sys;raise SystemExit(0 if sys.version_info[0] == 3 else 3)"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    if(-not $process){ return $false }
    try {
      if(-not $process.WaitForExit(5000)){
        try{$process.Kill()}catch{}
        return $false
      }
      return ([int]$process.ExitCode -eq 0)
    } finally {
      $process.Dispose()
    }
  } catch { return $false }
}
function Get-MmenuCCommandPath {
  param([string[]]$Names)
  $pythonLookup = @($Names | Where-Object { $_ -match '^(?i:py|python|python3)(?:\.exe)?$' }).Count -gt 0
  foreach($name in $Names){
    $commands = @(Get-Command $name -All -ErrorAction Ignore | Where-Object { $_.CommandType -eq 'Application' })
    foreach($cmd in $commands){
      foreach($c in @($cmd.Source,$cmd.Path,$cmd.Definition)){
        $cv=[string]$c
        if([string]::IsNullOrWhiteSpace($cv) -or $cv -match "[`r`n`0]"){ continue }
        try {
          if(-not (Test-Path -LiteralPath $cv -PathType Leaf)){ continue }
          if($pythonLookup -and -not (Test-MmenuCPythonCandidate $cv)){ continue }
          return ([IO.Path]::GetFullPath($cv))
        } catch { }
      }
    }
  }
  if($pythonLookup){
    $pythonCandidates = New-Object 'Collections.Generic.List[string]'
    if(-not [string]::IsNullOrWhiteSpace([string]$env:CODEX_PROFILE_PYTHON)){[void]$pythonCandidates.Add([string]$env:CODEX_PROFILE_PYTHON)}
    if(-not [string]::IsNullOrWhiteSpace([string]$env:LOCALAPPDATA)){
      foreach($version in @('Python314','Python313','Python312','Python311','Python310')){
        [void]$pythonCandidates.Add((Join-Path $env:LOCALAPPDATA ("Programs\Python\{0}\python.exe" -f $version)))
      }
    }
    foreach($programFilesRoot in @([string]$env:ProgramFiles,[string]${env:ProgramFiles(x86)})){
      if([string]::IsNullOrWhiteSpace($programFilesRoot)){continue}
      foreach($version in @('Python314','Python313','Python312','Python311','Python310')){
        [void]$pythonCandidates.Add((Join-Path $programFilesRoot ("{0}\python.exe" -f $version)))
      }
    }
    if(-not [string]::IsNullOrWhiteSpace([string]$env:LOCALAPPDATA)){
      $pythonManagerRoot=Join-Path $env:LOCALAPPDATA 'Python'
      if([IO.Directory]::Exists($pythonManagerRoot)){
        foreach($managedPythonRoot in @(Get-ChildItem -LiteralPath $pythonManagerRoot -Directory -Filter 'pythoncore-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)){
          [void]$pythonCandidates.Add((Join-Path $managedPythonRoot.FullName 'python.exe'))
        }
      }
    }
    if(-not [string]::IsNullOrWhiteSpace([string]$env:USERPROFILE)){
      [void]$pythonCandidates.Add((Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'))
    }
    if(-not [string]::IsNullOrWhiteSpace([string]$env:ProgramFiles)){
      $wingetRoot=Join-Path ([string]$env:ProgramFiles) 'WinGet\Packages'
      foreach($package in Get-ChildItem -LiteralPath $wingetRoot -Directory -Filter '*WinLibs*UCRT*' -ErrorAction SilentlyContinue){
        $pythonLibraryRoot=Join-Path $package.FullName 'mingw64\lib'
        foreach($pythonLibrary in Get-ChildItem -LiteralPath $pythonLibraryRoot -Directory -Filter 'python*' -ErrorAction SilentlyContinue){
          [void]$pythonCandidates.Add((Join-Path $pythonLibrary.FullName 'venv\scripts\nt\python.exe'))
        }
      }
    }
    foreach($candidate in @($pythonCandidates.ToArray()) + @(
      'F:\study\Dev_Toolchain\programming\python\python.exe',
      'F:\study\Dev_Toolchain\programming\python\venv\Scripts\python.exe',
      'F:\study\Dev_Toolchain\programming\python\venv11\Scripts\python.exe',
      'F:\study\Dev_Toolchain\programming\python\venvit\Scripts\python.exe',
      'F:\study\Dev_Toolchain\programming\python\venvit2\Scripts\python.exe'
    ) | Select-Object -Unique){
      if(Test-MmenuCPythonCandidate $candidate){ return ([IO.Path]::GetFullPath($candidate)) }
    }
  }
  return $null
}
function Remove-MmenuCStaleContexts {
  param([Parameter(Mandatory=$true)][string]$ContextBase,[int]$OlderThanHours=48)
  if(-not (Test-Path -LiteralPath $ContextBase -PathType Container)){ return }
  $cutoff = (Get-Date).AddHours(-[Math]::Abs($OlderThanHours))
  foreach($dir in @(Get-ChildItem -LiteralPath $ContextBase -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'ctx-*' })){
    $active = Join-Path $dir.FullName '.active'
    if((Test-Path -LiteralPath $active -PathType Leaf) -and $dir.LastWriteTime -ge $cutoff){ continue }
    if($dir.LastWriteTime -ge $cutoff){ continue }
    $hasRecoveryReceipt = (Test-Path -LiteralPath (Join-Path $dir.FullName 'source.identity.json') -PathType Leaf) -and
                          (Test-Path -LiteralPath (Join-Path $dir.FullName 'plan.json') -PathType Leaf) -and
                          (Test-Path -LiteralPath (Join-Path $dir.FullName 'layers.ready.json') -PathType Leaf)
    if($hasRecoveryReceipt){ continue }
    # ALLOW_DESTRUCTIVE: stale-only cleanup inside the source-drive mmenu temp root after active marker and age checks.
    try { Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch { }
  }
}
function Remove-MmenuCEmptyTempRoot {
  param([Parameter(Mandatory=$true)][string]$TempRoot)
  if([string]::IsNullOrWhiteSpace($TempRoot)){return}
  try {
    $full=[IO.Path]::GetFullPath($TempRoot).TrimEnd('\')
    if([IO.Path]::GetFileName($full) -ine '.hermes-docker-mmenu-temp'){return}
    $root=Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if(-not $root -or -not $root.PSIsContainer){return}
    $contextBase=Join-Path $full 'hermes-docker-mmenu-contexts'
    if(Test-Path -LiteralPath $contextBase -PathType Container){
      $contextItem=Get-Item -LiteralPath $contextBase -Force -ErrorAction SilentlyContinue
      if($contextItem -and -not @(Get-ChildItem -LiteralPath $contextBase -Force -ErrorAction SilentlyContinue).Count){
        [IO.Directory]::Delete($contextItem.FullName)
      }
    }
    if(-not @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue).Count){
      [IO.Directory]::Delete($full)
      if(-not [IO.Directory]::Exists($full)){$script:MmenuCTempRoot=$null}
    }
  } catch { }
}
function Remove-MmenuCCompletedIdentityContexts {
  param(
    [Parameter(Mandatory=$true)][string]$ContextBase,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$ImageRef
  )
  if(-not (Test-Path -LiteralPath $ContextBase -PathType Container)){return}
  $expectedSource=[IO.Path]::GetFullPath($SourcePath).TrimEnd('\')
  foreach($directory in @(Get-ChildItem -LiteralPath $ContextBase -Directory -Force -Filter 'ctx-*' -ErrorAction SilentlyContinue)){
    $identityPath=Join-Path $directory.FullName 'source.identity.json'
    if(-not (Test-Path -LiteralPath $identityPath -PathType Leaf)){continue}
    try{
      $identity=[IO.File]::ReadAllText($identityPath)|ConvertFrom-Json -ErrorAction Stop
      if([IO.Path]::GetFullPath([string]$identity.Source).TrimEnd('\') -ine $expectedSource -or
         [string]$identity.Image -ine $ImageRef){continue}
      $activePath=Join-Path $directory.FullName '.active'
      if(Test-Path -LiteralPath $activePath -PathType Leaf){
        $activeText=''
        try{$activeText=[IO.File]::ReadAllText($activePath)}catch{}
        if($activeText -match '(?:^|;)pid=(\d+)(?:;|$)' -and
           (Get-Process -Id ([int]$matches[1]) -ErrorAction SilentlyContinue)){continue}
      }
      # ALLOW_DESTRUCTIVE: a verified publication supersedes only inactive
      # recovery contexts with the same normalized source and exact image.
      Remove-Item -LiteralPath $directory.FullName -Recurse -Force -ErrorAction Stop
    }catch{
      Write-MmenuC ("[$EntryPoint][cleanup] could not remove completed matching recovery context: {0}" -f $directory.FullName) Yellow
    }
  }
}
function Test-MmenuCContextIntegrity {
  param(
    [Parameter(Mandatory=$true)]$Plan,
    [Parameter(Mandatory=$true)][string]$ContextRoot,
    [Parameter(Mandatory=$true)][string]$DockerfilePath
  )
  if(-not (Test-Path -LiteralPath $DockerfilePath -PathType Leaf)){ throw "Dockerfile was not created: $DockerfilePath" }
  $dockerfile = Get-Content -LiteralPath $DockerfilePath -Raw
  $missing = New-Object System.Collections.Generic.List[string]
  foreach($chunk in @($Plan.chunks)){
    $name = [string]$chunk.name
    $layerPath = Join-Path $ContextRoot $name
    if(-not (Test-Path -LiteralPath $layerPath -PathType Leaf)){
      [void]$missing.Add("$name missing")
      continue
    }
    $len = [int64](Get-Item -LiteralPath $layerPath).Length
    if($len -le 0){ [void]$missing.Add("$name empty") }
    $escaped = [Text.RegularExpressions.Regex]::Escape($name)
    if($dockerfile -notmatch ('ADD\s+\["' + $escaped + '"\s*,\s*"/"\]')){
      [void]$missing.Add("$name not referenced by Dockerfile ADD")
    }
  }
  if($missing.Count -gt 0){
    throw "Docker context integrity check failed before build in $ContextRoot`: $($missing -join '; ')"
  }
  return $true
}
function Get-MmenuCReusableContext {
  param(
    [Parameter(Mandatory=$true)][string]$ContextBase,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [Parameter(Mandatory=$true)][int64]$SourceBytes,
    [Parameter(Mandatory=$true)][int64]$SourceFiles,
    [Parameter(Mandatory=$true)][string]$SourceFingerprint
  )
  if(-not (Test-Path -LiteralPath $ContextBase -PathType Container)){return $null}
  $expectedSource=[IO.Path]::GetFullPath($SourcePath).TrimEnd('\')
  foreach($directory in @(Get-ChildItem -LiteralPath $ContextBase -Directory -Force -Filter 'ctx-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)){
    $activePath=Join-Path $directory.FullName '.active'
    if(Test-Path -LiteralPath $activePath -PathType Leaf){
      $activeText=''
      try{$activeText=[IO.File]::ReadAllText($activePath)}catch{}
      if($activeText -match '(?:^|;)pid=(\d+)(?:;|$)'){
        $activePid=[int]$matches[1]
        if(Get-Process -Id $activePid -ErrorAction SilentlyContinue){continue}
      }
    }
    $identityPath=Join-Path $directory.FullName 'source.identity.json'
    $planPath=Join-Path $directory.FullName 'plan.json'
    $readyPath=Join-Path $directory.FullName 'layers.ready.json'
    if(-not (Test-Path -LiteralPath $identityPath -PathType Leaf) -or
       -not (Test-Path -LiteralPath $planPath -PathType Leaf) -or
       -not (Test-Path -LiteralPath $readyPath -PathType Leaf)){continue}
    try{
      $identity=[IO.File]::ReadAllText($identityPath)|ConvertFrom-Json -ErrorAction Stop
      if([IO.Path]::GetFullPath([string]$identity.Source).TrimEnd('\') -ine $expectedSource -or
         [string]$identity.Image -ine $ImageRef -or
         [int64]$identity.SourceBytes -ne $SourceBytes -or
         [int64]$identity.SourceFiles -ne $SourceFiles -or
         [string]$identity.SourceFingerprint -cne $SourceFingerprint){continue}
      $plan=[IO.File]::ReadAllText($planPath)|ConvertFrom-Json -ErrorAction Stop
      $ready=[IO.File]::ReadAllText($readyPath)|ConvertFrom-Json -ErrorAction Stop
      if([int64]$plan.total -ne $SourceBytes -or [int64]$plan.files -ne $SourceFiles -or
         @($plan.chunks).Count -le 0 -or @($ready.layers).Count -ne @($plan.chunks).Count){continue}
      $valid=$true
      foreach($layer in @($ready.layers)){
        $name=[string]$layer.name
        if($name -notmatch '^layer\d{3}\.tar$'){$valid=$false;break}
        $layerPath=Join-Path $directory.FullName $name
        if(-not (Test-Path -LiteralPath $layerPath -PathType Leaf) -or
           [int64](Get-Item -LiteralPath $layerPath).Length -ne [int64]$layer.length){$valid=$false;break}
      }
      if($valid){return $directory.FullName}
    }catch{continue}
  }
  return $null
}
function Write-MmenuCContextIdentity {
  param(
    [Parameter(Mandatory=$true)][string]$ContextRoot,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [Parameter(Mandatory=$true)][int64]$SourceBytes,
    [Parameter(Mandatory=$true)][int64]$SourceFiles,
    [Parameter(Mandatory=$true)][string]$SourceFingerprint
  )
  $identity=[ordered]@{Version=1;Source=[IO.Path]::GetFullPath($SourcePath);Image=$ImageRef;SourceBytes=$SourceBytes;SourceFiles=$SourceFiles;SourceFingerprint=$SourceFingerprint}
  $path=Join-Path $ContextRoot 'source.identity.json'
  $temporary=$path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
  $encoding=New-Object Text.UTF8Encoding($false)
  try{
    [IO.File]::WriteAllText($temporary,($identity|ConvertTo-Json -Compress),$encoding)
    Move-Item -LiteralPath $temporary -Destination $path -Force -ErrorAction Stop
  }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Wait-MmenuCRegistryLayerSet {
  param(
    [Parameter(Mandatory=$true)]$Plan,
    [Parameter(Mandatory=$true)][string]$ContextRoot,
    [ValidateRange(1,120)][int]$TimeoutSeconds=30
  )
  $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
  $lastMissing=@()
  do {
    $paths=New-Object System.Collections.Generic.List[string]
    $missing=New-Object System.Collections.Generic.List[string]
    foreach($chunk in @($Plan.chunks)){
      $name=[string]$chunk.name
      $layerPath=[IO.Path]::Combine($ContextRoot,$name)
      try {
        $info=New-Object IO.FileInfo $layerPath
        $info.Refresh()
        if(-not $info.Exists -or $info.Length -le 0){[void]$missing.Add($name);continue}
        [void]$paths.Add($info.FullName)
      } catch {[void]$missing.Add($name)}
    }
    if($missing.Count -eq 0 -and $paths.Count -eq @($Plan.chunks).Count){return [string[]]$paths.ToArray()}
    $lastMissing=@($missing)
    Start-Sleep -Milliseconds 500
  } while((Get-Date) -lt $deadline)
  $existingCount=0
  try {if([IO.Directory]::Exists($ContextRoot)){$existingCount=@([IO.Directory]::EnumerateFiles($ContextRoot,'layer*.tar',[IO.SearchOption]::TopDirectoryOnly)).Count}}catch{}
  throw ("Registry layer set did not become durable after {0}s: context_exists={1}; expected={2}; existing={3}; missing={4}" -f $TimeoutSeconds,[IO.Directory]::Exists($ContextRoot),@($Plan.chunks).Count,$existingCount,(@($lastMissing | Select-Object -First 8) -join ','))
}
function Get-MmenuCNextDockerHubTag {
  param([Parameter(Mandatory=$true)][string]$Repository)
  $script:MmenuCLastNumericTagCount = 0
  $script:MmenuCLastHighestNumericTag = 0
  $script:MmenuCLastNextNumericTag = '1'
  if($env:HERMES_DOCKER_TAG_MOCK_JSON){
    $mock = $env:HERMES_DOCKER_TAG_MOCK_JSON | ConvertFrom-Json
    $nums=@(); foreach($t in @($mock)){ $name = if($t -is [string]){ $t } elseif($t.name){ [string]$t.name } else { [string]$t }; if($name -match '^\d+$'){ $nums += [int64]$name } }
    if($nums.Count -eq 0){ return '1' }
    $highest = [int64](($nums | Measure-Object -Maximum).Maximum)
    $countNext = [int64]$nums.Count + 1
    $next = [Math]::Max($highest + 1, $countNext)
    $script:MmenuCLastNumericTagCount = [int64]$nums.Count
    $script:MmenuCLastHighestNumericTag = $highest
    $script:MmenuCLastNextNumericTag = [string]$next
    return ([string]$next)
  }
  $repoPath = $Repository
  if($repoPath -match '^docker\.io/(.+)$'){ $repoPath = $matches[1] }
  $repoPath = $repoPath.Trim('/')
  if($repoPath -notmatch '^[^/]+/[^/]+$'){ throw "Invalid Docker Hub repository for numeric tag lookup: $Repository" }
  $encoded = ($repoPath -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
  $url = "https://hub.docker.com/v2/repositories/$encoded/tags?page_size=100"
  $nums = New-Object System.Collections.Generic.List[int64]
  try {
    while($url){
      $r = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 20
      foreach($item in @($r.results)){
        $name = [string]$item.name
        if($name -match '^\d+$'){ [void]$nums.Add([int64]$name) }
      }
      $url = $r.next
    }
    if($nums.Count -eq 0){ return '1' }
    $highest = [int64](($nums | Measure-Object -Maximum).Maximum)
    $countNext = [int64]$nums.Count + 1
    $next = [Math]::Max($highest + 1, $countNext)
    $script:MmenuCLastNumericTagCount = [int64]$nums.Count
    $script:MmenuCLastHighestNumericTag = $highest
    $script:MmenuCLastNextNumericTag = [string]$next
    return ([string]$next)
  } catch {
    $msg = $_.Exception.Message
    if($msg -match '\(404\)|404|Not Found'){ return '1' }
    throw "Could not read current Docker Hub numeric tags for $repoPath; refusing to guess/overwrite. $msg"
  }
}
function Get-MmenuCSourceStats {
  param([Parameter(Mandatory=$true)][string]$Root,[string[]]$IgnoreNames=@(),[string]$ProgressName='')
  $total=[int64]0; $files=[int64]0; $dirs=[int64]0; $bad=New-Object System.Collections.Generic.List[string]
  $scanStarted = Get-Date
  $scanLastRender = [datetime]::MinValue
  $scanDone = 0L
  $rootFull=[IO.Path]::GetFullPath((ConvertFrom-MmenuCExtendedPath $Root)).TrimEnd([char]92,[char]47)
  $rootExt=ConvertTo-MmenuCExtendedPath $rootFull
  $extendedRoot=$rootExt.TrimEnd([char]92,[char]47)
  $plainRoot=$rootFull.TrimEnd([char]92,[char]47)
  $rootBoundary=$rootFull + ([string][char]92)
  $sha = [Security.Cryptography.SHA256]::Create()
  $utf8 = [Text.Encoding]::UTF8
  function Add-MmenuCScanHashText([string]$Text){
    $bytes = $utf8.GetBytes(([string]$Text) + "`n")
    [void]$sha.TransformBlock($bytes,0,$bytes.Length,$bytes,0)
  }
  function Get-MmenuCScanRelPath([string]$PathValue){
    $rel = [string]$PathValue
    if($rel -ieq $extendedRoot -or $rel -ieq $plainRoot){ return '' }
    if($rel.StartsWith($extendedRoot+([string][char]92),[StringComparison]::OrdinalIgnoreCase)){$rel=$rel.Substring($extendedRoot.Length+1)}
    elseif($rel.StartsWith($plainRoot+([string][char]92),[StringComparison]::OrdinalIgnoreCase)){$rel=$rel.Substring($plainRoot.Length+1)}
    else {
      $rel=ConvertFrom-MmenuCExtendedPath $rel
      if($rel.StartsWith($plainRoot+([string][char]92),[StringComparison]::OrdinalIgnoreCase)){$rel=$rel.Substring($plainRoot.Length+1)}
    }
    return $rel.Replace([string][char]92,'/')
  }
  function Resolve-MmenuCScanLinkTarget([string]$PathValue){
    try {
      $plain = ConvertFrom-MmenuCExtendedPath ([string]$PathValue)
      $item = Get-Item -LiteralPath $plain -Force -ErrorAction Stop
      $tgt = $item.Target
      if($null -eq $tgt){ return $null }
      if($tgt -is [array]){ $tgt = $tgt[0] }
      $tgtStr = [string]$tgt
      if([string]::IsNullOrWhiteSpace($tgtStr)){ return $null }
      $full = $null
      if([IO.Path]::IsPathRooted($tgtStr)){
        $full = ConvertFrom-MmenuCExtendedPath ([IO.Path]::GetFullPath((ConvertFrom-MmenuCExtendedPath $tgtStr)))
      } else {
        $dir = [IO.Path]::GetDirectoryName($plain)
        $full = [IO.Path]::GetFullPath((Join-Path $dir (ConvertFrom-MmenuCExtendedPath $tgtStr)))
      }
      $fullRoot=[IO.Path]::GetPathRoot($full)
      if($full.Length -gt $fullRoot.Length){$full=$full.TrimEnd([char]92,[char]47)}else{$full=$fullRoot}
      if(-not (Test-Path -LiteralPath $full)){ return $null }
      return $full
    } catch { return $null }
  }
  function Test-MmenuCScanWithinRoot([string]$Candidate){
    if([string]::IsNullOrWhiteSpace($Candidate)){ return $false }
    return ($Candidate.StartsWith($rootBoundary, [StringComparison]::OrdinalIgnoreCase) -or $Candidate -ieq $rootFull)
  }
  try {
    $stack=New-Object System.Collections.Generic.Stack[string]
    $stack.Push($rootExt)
    while($stack.Count -gt 0){
      $d=$stack.Pop()
      try {
        foreach($sub in ([IO.Directory]::EnumerateDirectories($d) | Sort-Object)){
          $name=[IO.Path]::GetFileName($sub)
          if($IgnoreNames -contains $name){ continue }
          try {
            $subInfo = New-Object IO.DirectoryInfo($sub)
            if(($subInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
              $tgtFull = Resolve-MmenuCScanLinkTarget $sub
              $linkKey = 'dangling'
              if($tgtFull){
                if(Test-MmenuCScanWithinRoot $tgtFull){ $linkKey = Get-MmenuCScanRelPath $tgtFull }
                else { $linkKey = 'ext:' + (Get-MmenuCScanRelPath $tgtFull) }
              }
              Add-MmenuCScanHashText ("LD|{0}|{1}" -f (Get-MmenuCScanRelPath $sub),$linkKey)
              $dirs++
              continue
            }
          } catch {
            [void]$bad.Add("$(Get-MmenuCScanRelPath $sub) :: $($_.Exception.Message)")
            continue
          }
          Add-MmenuCScanHashText ("D|{0}|{1}" -f (Get-MmenuCScanRelPath $sub),[int64]$subInfo.LastWriteTimeUtc.Ticks)
          $dirs++; $stack.Push($sub)
        }
        foreach($f in ([IO.Directory]::EnumerateFiles($d) | Sort-Object)){
          $name=[IO.Path]::GetFileName($f)
          if($IgnoreNames -contains $name){ continue }
          try {
            $fi=New-Object IO.FileInfo($f)
            if(($fi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
              $tgtFull = Resolve-MmenuCScanLinkTarget $f
              $linkKey = 'dangling'
              if($tgtFull){
                if(Test-MmenuCScanWithinRoot $tgtFull){ $linkKey = Get-MmenuCScanRelPath $tgtFull }
                else { $linkKey = 'ext:' + (Get-MmenuCScanRelPath $tgtFull) }
              }
              Add-MmenuCScanHashText ("LF|{0}|{1}" -f (Get-MmenuCScanRelPath $f),$linkKey)
              $files++
              continue
            }
            $total += [int64]$fi.Length; $files++
            Add-MmenuCScanHashText ("F|{0}|{1}|{2}" -f (Get-MmenuCScanRelPath $f),[int64]$fi.Length,[int64]$fi.LastWriteTimeUtc.Ticks)
          } catch { [void]$bad.Add("$f :: $($_.Exception.Message)") }
        }
      } catch { [void]$bad.Add("$d :: $($_.Exception.Message)") }
      if(-not [string]::IsNullOrWhiteSpace($ProgressName) -and ((Get-Date)-$scanLastRender).TotalMilliseconds -ge 300){
        $scanLastRender = Get-Date
        $scanDone = [int64]$files
        Write-MmenuCDashboard -Name $ProgressName -Phase 'scan' -Started $scanStarted -DoneBytes $scanDone -TotalBytes 0 -Detail ("files={0} dirs={1} bytes={2}" -f $files,$dirs,(Format-MmenuCMiB $total))
      }
    }
  } catch { [void]$bad.Add("$rootFull :: $($_.Exception.Message)") }
  [void]$sha.TransformFinalBlock([byte[]]@(),0,0)
  $fingerprint = [BitConverter]::ToString($sha.Hash).Replace('-','').ToLowerInvariant()
  [pscustomobject]@{ TotalBytes=$total; Files=$files; Dirs=$dirs; Fingerprint=$fingerprint; Bad=$bad.ToArray() }
}
function Invoke-MmenuCNativeDocker {
  param([Parameter(Mandatory=$true)][string]$DockerExe,[Parameter(Mandatory=$true)][string[]]$DockerArgs,[int64]$ContextTotalBytes=0)
  $oldBuildKit=$env:DOCKER_BUILDKIT; $oldProgress=$env:BUILDKIT_PROGRESS; $oldCompose=$env:COMPOSE_PROGRESS; $oldTimeout=$env:COMPOSE_HTTP_TIMEOUT; $oldClientTimeout=$env:DOCKER_CLIENT_TIMEOUT
  try{
    $env:DOCKER_BUILDKIT='1'; $env:BUILDKIT_PROGRESS='plain'; $env:COMPOSE_PROGRESS='plain'; $env:COMPOSE_HTTP_TIMEOUT='300'; $env:DOCKER_CLIENT_TIMEOUT='300'
    if(Get-Command Ensure-HermesDockerCommanderReady -CommandType Function -ErrorAction SilentlyContinue){
      [void](Ensure-HermesDockerCommanderReady -DockerExe $DockerExe -Name $EntryPoint)
    }
    if(Get-Command Invoke-HermesDockerCommanderProcess -CommandType Function -ErrorAction SilentlyContinue){
      $primaryArg = if($DockerArgs -and $DockerArgs.Count -gt 0){ [string]$DockerArgs[0] } else { '' }
      $retryDockerStage = ($primaryArg -in @('build','buildx','push','pull','load','manifest'))
      $rawExit = @(Invoke-HermesDockerCommanderProcess -DockerExe $DockerExe -DockerArgs $DockerArgs -Name $EntryPoint -ContextTotalBytes $ContextTotalBytes -RetryUntilSuccess:$false)
      $script:MmenuCLastExitCode = [int]($rawExit | Select-Object -Last 1)
    } else {
      $cmdLine = (Quote-MmenuCArg $DockerExe) + ' ' + (($DockerArgs | ForEach-Object { Quote-MmenuCArg $_ }) -join ' ')
      $nativeCodeOutput = @(Invoke-MmenuCProcess -Label ([string]$DockerArgs[0]) -CommandLine $cmdLine -HeartbeatSeconds 2)
      $script:MmenuCLastExitCode = [int]$nativeCodeOutput[-1]
    }
    if($retryDockerStage -and $script:MmenuCLastExitCode -ne 0){
      $global:LASTEXITCODE = 0
      Write-MmenuC ("[$EntryPoint][docker:$primaryArg] retry-safe LASTEXITCODE=0 after recoverable Docker exit={0}" -f $script:MmenuCLastExitCode) Yellow
    } else {
      $global:LASTEXITCODE = $script:MmenuCLastExitCode
    }
  } finally {
    if($null -eq $oldBuildKit){Remove-Item Env:DOCKER_BUILDKIT -ErrorAction SilentlyContinue}else{$env:DOCKER_BUILDKIT=$oldBuildKit}
    if($null -eq $oldProgress){Remove-Item Env:BUILDKIT_PROGRESS -ErrorAction SilentlyContinue}else{$env:BUILDKIT_PROGRESS=$oldProgress}
    if($null -eq $oldCompose){Remove-Item Env:COMPOSE_PROGRESS -ErrorAction SilentlyContinue}else{$env:COMPOSE_PROGRESS=$oldCompose}
    if($null -eq $oldTimeout){Remove-Item Env:COMPOSE_HTTP_TIMEOUT -ErrorAction SilentlyContinue}else{$env:COMPOSE_HTTP_TIMEOUT=$oldTimeout}
    if($null -eq $oldClientTimeout){Remove-Item Env:DOCKER_CLIENT_TIMEOUT -ErrorAction SilentlyContinue}else{$env:DOCKER_CLIENT_TIMEOUT=$oldClientTimeout}
  }
  return [int]$script:MmenuCLastExitCode
}
function Invoke-MmenuCNativeDockerUntilSuccess {
  param(
    [Parameter(Mandatory=$true)][string]$Stage,
    [Parameter(Mandatory=$true)][string]$DockerExe,
    [Parameter(Mandatory=$true)][string[]]$DockerArgs,
    [int64]$ContextTotalBytes=0,
    [string]$ImageRef='',
    [ValidateRange(1,20)][int]$MaxAttempts=6
  )
  for($attempt=1; $attempt -le $MaxAttempts; $attempt++){
    Write-MmenuC ("[$EntryPoint][$Stage] attempt {0}/{1} started: image={2}" -f $attempt,$MaxAttempts,$ImageRef)
    $code = Invoke-MmenuCNativeDocker -DockerExe $DockerExe -DockerArgs $DockerArgs -ContextTotalBytes $ContextTotalBytes
    if($code -eq 0){
      Write-MmenuC ("[$EntryPoint][$Stage] SUCCESS exit=0 attempt={0}: {1}" -f $attempt,$ImageRef) Green
      $global:LASTEXITCODE = 0
      return 0
    }
    $global:LASTEXITCODE = 0
    Write-MmenuC ("[$EntryPoint][$Stage] retry-safe LASTEXITCODE=0 after recoverable Docker exit={0}; host terminal will stay open for retry" -f $code) Yellow
    if($attempt -ge $MaxAttempts){
      Write-MmenuC ("[$EntryPoint][$Stage] failed after {0} bounded attempts; returning exit={1}: {2}" -f $MaxAttempts,$code,$ImageRef) Red
      $global:LASTEXITCODE = $code
      return [int]$code
    }
    Write-MmenuC ("[$EntryPoint][$Stage] recoverable Docker failure exit={0} attempt={1}; retrying without rebuilding: {2}" -f $code,$attempt,$ImageRef) Yellow
    if(-not (Test-MenuCDockerEngineReady -DockerExe $DockerExe) -and -not (Wait-MenuCDockerEngineReady -DockerExe $DockerExe)){ return [int]$code }
    Start-Sleep -Seconds ([Math]::Min(30,[Math]::Max(3,3*$attempt)))
  }
}
function Get-MmenuCRetryPolicy {
  param(
    [ValidateRange(1,200)][int]$DefaultAttempts=48,
    [ValidateRange(1,10080)][int]$DefaultMinutes=1440,
    [string]$AttemptsEnvironmentName='HERMES_MMENU_PUSH_MAX_ATTEMPTS',
    [string]$MinutesEnvironmentName='HERMES_MMENU_PUSH_MAX_MINUTES'
  )
  $maxAttempts = $DefaultAttempts
  $maxMinutes = $DefaultMinutes
  $attemptsText = [Environment]::GetEnvironmentVariable($AttemptsEnvironmentName,'Process')
  $minutesText = [Environment]::GetEnvironmentVariable($MinutesEnvironmentName,'Process')
  if($attemptsText -match '^\d+$'){ $maxAttempts = [Math]::Max(1,[Math]::Min(200,[int]$attemptsText)) }
  if($minutesText -match '^\d+$'){ $maxMinutes = [Math]::Max(1,[Math]::Min(10080,[int]$minutesText)) }
  return [pscustomobject]@{
    MaxAttempts = [int]$maxAttempts
    MaxMinutes = [int]$maxMinutes
    Deadline = (Get-Date).AddMinutes($maxMinutes)
  }
}
function Stop-MmenuCProcessTree {
  param([AllowNull()][System.Diagnostics.Process]$Process)
  if($null -eq $Process){ return }
  try {
    $Process.Refresh()
    if($Process.HasExited){ return }
    $taskkill = Join-Path (Get-MmenuCWindowsRoot) 'System32\taskkill.exe'
    if(Test-Path -LiteralPath $taskkill -PathType Leaf){
      & $taskkill /PID ([string][int]$Process.Id) /T /F *> $null
    } else {
      $Process.Kill()
    }
  } catch {
    try { if(-not $Process.HasExited){ $Process.Kill() } } catch {}
  }
}
function Read-MmenuCSharedTextChunk {
  param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][ref]$Offset)
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return '' }
  $fs = $null
  try {
    $share = [IO.FileShare]([int][IO.FileShare]::ReadWrite -bor [int][IO.FileShare]::Delete)
    $fs = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
    if([int64]$Offset.Value -gt $fs.Length){ $Offset.Value = [int64]0 }
    [void]$fs.Seek([int64]$Offset.Value,[IO.SeekOrigin]::Begin)
    $remaining = [int64]($fs.Length - $fs.Position)
    if($remaining -le 0){ return '' }
    $ms = New-Object IO.MemoryStream
    $buffer = New-Object byte[] 65536
    while($remaining -gt 0){
      $want = [Math]::Min($buffer.Length,$remaining)
      $read = $fs.Read($buffer,0,[int]$want)
      if($read -le 0){ break }
      $ms.Write($buffer,0,$read)
      $remaining -= $read
    }
    $Offset.Value = [int64]$fs.Position
    return [Text.Encoding]::UTF8.GetString($ms.ToArray())
  } catch {
    return ''
  } finally {
    if($fs){ $fs.Dispose() }
  }
}
function Add-MmenuCLogChunk {
  param([string]$Text)
  if([string]::IsNullOrEmpty($Text)){ return }
  Write-Host $Text -NoNewline
}
function Get-MmenuCPushWorkerMarker {
  param([Parameter(Mandatory=$true)][string]$LogPath)
  if(-not (Test-Path -LiteralPath $LogPath -PathType Leaf)){ return $null }
  $line = Select-String -LiteralPath $LogPath -Pattern '\[(menu|mmenu)\]\[push-worker\] run_id=' | Select-Object -Last 1
  if(-not $line){ return $null }
  $text = [string]$line.Line
  $m = [regex]::Match($text,'run_id=(?<run>\S+)\s+log=(?<log>\S+)\s+exit=(?<exit>\S+)\s+ack=(?<ack>\S+)\s+(?:task=(?<task>\S+)|pid=(?<pid>\S+))')
  if(-not $m.Success){ return $null }
  $image = ''
  $bytes = [int64]0
  $extra = [regex]::Match($text,'\s+image=(?<image>\S+)\s+bytes=(?<bytes>\d+)')
  if($extra.Success){
    $image = $extra.Groups['image'].Value
    [void][int64]::TryParse($extra.Groups['bytes'].Value,[ref]$bytes)
  }
  [pscustomobject]@{
    RunId = $m.Groups['run'].Value
    LogPath = $m.Groups['log'].Value
    ExitPath = $m.Groups['exit'].Value
    AckPath = $m.Groups['ack'].Value
    TaskName = $m.Groups['task'].Value
    ProcessId = $m.Groups['pid'].Value
    ImageRef = $image
    EstimatedBytes = $bytes
  }
}
function Invoke-MmenuCOuterMonitor {
  $runId = [Guid]::NewGuid().ToString('N')
  $workerLog = Join-MmenuCTempPath ("mmenu-main-$runId.log")
  $workerExit = Join-MmenuCTempPath ("mmenu-main-$runId.exit")
  $workerCmd = Join-MmenuCTempPath ("mmenu-main-$runId.cmd")
  $ps5Exe = Join-Path (Get-MmenuCWindowsRoot) 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $taskName = 'MmenuMain-' + $runId
  $resolvedMonitorPath = (Resolve-Path -LiteralPath $Path).ProviderPath
  $args = @(
    '-NoProfile',
    '-ExecutionPolicy','Bypass',
    '-File', $PSCommandPath,
    '-Path', $resolvedMonitorPath,
    '-EntryPoint', $EntryPoint,
    '-TargetLayerMiB', ([string]$TargetLayerMiB),
    '-InternalWorker'
  )
  $q = [string][char]34
  $argText = ($args | ForEach-Object { Quote-MmenuCArg ([string]$_) }) -join ' '
  $tempRootForCmd = Get-MmenuCTempRoot
  $cmdText = @(
    '@echo off',
    'setlocal EnableExtensions',
    ('set "TEMP=' + $tempRootForCmd + '"'),
    ('set "TMP=' + $tempRootForCmd + '"'),
    ($q + $ps5Exe + $q + ' ' + $argText + ' > ' + $q + $workerLog + $q + ' 2>&1'),
    ('> ' + $q + $workerExit + $q + ' echo %ERRORLEVEL%'),
    'exit /b 0'
  ) -join "`r`n"
  [IO.File]::WriteAllText($workerCmd,$cmdText,[Text.Encoding]::ASCII)
  $folder = $null
  $workerProcess = New-Object Diagnostics.Process
  $workerPsi = New-Object Diagnostics.ProcessStartInfo
  $workerPsi.FileName = Join-Path (Get-MmenuCWindowsRoot) 'System32\cmd.exe'
  $workerPsi.Arguments = '/d /c ' + (Quote-MmenuCArg $workerCmd)
  $workerPsi.WorkingDirectory = $tempRootForCmd
  $workerPsi.EnvironmentVariables['TEMP'] = $tempRootForCmd
  $workerPsi.EnvironmentVariables['TMP'] = $tempRootForCmd
  $workerPsi.UseShellExecute = $false
  $workerPsi.CreateNoWindow = $true
  $workerProcess.StartInfo = $workerPsi
  [void]$workerProcess.Start()
  $offset = [int64]0
  $pushOffset = [int64]0
  $pushMarker = $null
  $commandPolicy = Get-MmenuCRetryPolicy -DefaultAttempts 6 -DefaultMinutes 60 -AttemptsEnvironmentName 'HERMES_MMENU_LOCAL_MAX_ATTEMPTS' -MinutesEnvironmentName 'HERMES_MMENU_COMMAND_MAX_MINUTES'
  while(-not (Test-Path -LiteralPath $workerExit -PathType Leaf)){
    Start-Sleep -Milliseconds 250
    Add-MmenuCLogChunk -Text (Read-MmenuCSharedTextChunk -Path $workerLog -Offset ([ref]$offset))
    if(-not $pushMarker){ $pushMarker = Get-MmenuCPushWorkerMarker -LogPath $workerLog }
    if($workerProcess.HasExited -and -not (Test-Path -LiteralPath $workerExit -PathType Leaf)){
      Set-Content -LiteralPath $workerExit -Value ([string][int]$workerProcess.ExitCode) -Encoding ASCII
    }
    if((Get-Date) -ge $commandPolicy.Deadline){
      Write-MmenuC "[$EntryPoint][monitor] hard command deadline reached; stopping the worker process tree." Yellow
      Stop-MmenuCProcessTree -Process $workerProcess
      Set-Content -LiteralPath $workerExit -Value '124' -Encoding ASCII
      break
    }
  }
  Add-MmenuCLogChunk -Text (Read-MmenuCSharedTextChunk -Path $workerLog -Offset ([ref]$offset))
  if(-not $pushMarker){ $pushMarker = Get-MmenuCPushWorkerMarker -LogPath $workerLog }
  $codeText = ([string](Get-Content -LiteralPath $workerExit -Raw -ErrorAction SilentlyContinue)).Trim()
  $code = 1
  if($codeText -match '^-?\d+$'){ $code = [int]$codeText }
  if($code -eq 0){
    try { if($workerProcess){ $workerProcess.Dispose() } } catch {}
    $global:LASTEXITCODE = 0
    return 0
  }
  if($code -ne 0 -and $pushMarker){
    Write-MmenuC "[$EntryPoint][push] main worker hit host exit=$code after releasing isolated push; continuing live push monitor until manifest-verified worker exit" Yellow
  }
  if($pushMarker){
    $pushStarted = Get-Date
    $pushPolicy = Get-MmenuCRetryPolicy
    $pushState = @{ Layers=@{}; LayerLastPrinted=@{}; Digest=''; DigestLine=''; LastDetail='monitoring isolated docker push worker'; Carry=''; PushRunId=$pushMarker.RunId; ImageRef=$pushMarker.ImageRef; EstimatedBytes=[int64]$pushMarker.EstimatedBytes }
    while(-not (Test-Path -LiteralPath $pushMarker.ExitPath -PathType Leaf)){
      Start-Sleep -Milliseconds 500
      Add-MmenuCPushOutput -Text (Read-MmenuCSharedTextChunk -Path $pushMarker.LogPath -Offset ([ref]$pushOffset)) -State $pushState -Started $pushStarted
      Write-MmenuCPushDashboard -Started $pushStarted -State $pushState
      $pushDoneForFloor = if($pushState.ContainsKey('BytesDone')){ [int64]$pushState.BytesDone } else { 0L }
      $pushTotalForFloor = if($pushState.ContainsKey('BytesTotal')){ [int64]$pushState.BytesTotal } elseif($pushState.ContainsKey('EstimatedBytes')){ [int64]$pushState.EstimatedBytes } else { 0L }
      if(Update-MmenuCLowSpeedGuard -State $pushState -Phase 'push' -Started $pushStarted -DoneBytes $pushDoneForFloor -TotalBytes $pushTotalForFloor -Detail ([string]$pushState.LastDetail)){
        try {
          $dockerPid = Get-MmenuCPushDockerProcessId -State $pushState
          if($dockerPid -gt 0){ Stop-Process -Id $dockerPid -Force -ErrorAction SilentlyContinue }
        } catch {}
        Set-Content -LiteralPath $pushMarker.ExitPath -Value '87' -Encoding ASCII
        break
      }
      if((Get-Date) -ge $pushPolicy.Deadline){
        Write-MmenuC "[$EntryPoint][push] hard push deadline reached; stopping the isolated push worker." Yellow
        try {
          $dockerPid = Get-MmenuCPushDockerProcessId -State $pushState
          if($dockerPid -gt 0){ Stop-Process -Id $dockerPid -Force -ErrorAction SilentlyContinue }
        } catch {}
        Set-Content -LiteralPath $pushMarker.ExitPath -Value '124' -Encoding ASCII
        break
      }
    }
    Add-MmenuCPushOutput -Text (Read-MmenuCSharedTextChunk -Path $pushMarker.LogPath -Offset ([ref]$pushOffset)) -State $pushState -Started $pushStarted
    if(-not [string]::IsNullOrWhiteSpace([string]$pushState.Carry)){ Add-MmenuCPushOutput -Text ([string]$pushState.Carry + "`n") -State $pushState -Started $pushStarted }
    Write-MmenuCPushDashboard -Started $pushStarted -State $pushState
    Write-Host ''
    $pushExitText = ([string](Get-Content -LiteralPath $pushMarker.ExitPath -Raw -ErrorAction SilentlyContinue)).Trim()
    if($pushExitText -match '^0$'){
      Set-Content -LiteralPath $pushMarker.AckPath -Value (Get-Date -Format o) -Encoding ASCII
      try {
        if($pushMarker.TaskName){
          $scheduler = New-Object -ComObject Schedule.Service
          $scheduler.Connect()
          $folder = $scheduler.GetFolder('\')
          $folder.DeleteTask([string]$pushMarker.TaskName,0)
        }
      } catch {}
      Write-MmenuC "[$EntryPoint] SUCCESS: isolated Docker push worker completed with manifest verification; returning to PowerShell shell" Green
      try { if($workerProcess){ $workerProcess.Dispose() } } catch {}
      $global:LASTEXITCODE = 0
      return 0
    }
    if($pushExitText -match '^-?\d+$'){ $code = [int]$pushExitText } else { $code = 1 }
    if($pushMarker.ImageRef -and (Test-MmenuCRemoteManifest -DockerExe (Get-MmenuCDockerExe) -ImageRef ([string]$pushMarker.ImageRef))){
      Set-Content -LiteralPath $pushMarker.AckPath -Value (Get-Date -Format o) -Encoding ASCII
      Write-MmenuC ("[$EntryPoint] SUCCESS: isolated Docker push returned exit={0}, but remote manifest is verified; returning to PowerShell shell: {1}" -f $code,$pushMarker.ImageRef) Green
      try { if($workerProcess){ $workerProcess.Dispose() } } catch {}
      $global:LASTEXITCODE = 0
      return 0
    }
  }
  Stop-MmenuCProcessTree -Process $workerProcess
  try { if($workerProcess){ $workerProcess.Dispose() } } catch {}
  $global:LASTEXITCODE = $code
  return $code
}
function ConvertFrom-MmenuCPushSizeText {
  param([string]$Text)
  $s = ([string]$Text).Trim()
  $m = [regex]::Match($s,'^(?<num>[0-9]+(?:\.[0-9]+)?)\s*(?<unit>B|KB|MB|GB|TB|KiB|MiB|GiB|TiB)$','IgnoreCase')
  if(-not $m.Success){ return [int64]0 }
  $num = [double]::Parse($m.Groups['num'].Value,[Globalization.CultureInfo]::InvariantCulture)
  $unit = $m.Groups['unit'].Value.ToUpperInvariant()
  $mult = 1.0
  switch($unit){
    'KB' { $mult = 1000.0; break }
    'MB' { $mult = 1000000.0; break }
    'GB' { $mult = 1000000000.0; break }
    'TB' { $mult = 1000000000000.0; break }
    'KIB' { $mult = 1024.0; break }
    'MIB' { $mult = 1048576.0; break }
    'GIB' { $mult = 1073741824.0; break }
    'TIB' { $mult = 1099511627776.0; break }
    default { $mult = 1.0; break }
  }
  return [int64][Math]::Max(0,[Math]::Round($num * $mult))
}
function Get-MmenuCNetworkSentBytes {
  try {
    $sum = [uint64]0
    $stats = Get-NetAdapterStatistics -ErrorAction Stop
    foreach($item in $stats){
      $sent = [uint64]0
      if($null -ne $item.SentBytes -and [uint64]::TryParse(([string]$item.SentBytes),[ref]$sent)){ $sum += $sent }
    }
    return [int64]$sum
  } catch {
    return [int64]0
  }
}
function Get-MmenuCPushDockerProcessId {
  param([hashtable]$State)
  $runId = [string]$State.PushRunId
  $imageRef = [string]$State.ImageRef
  try {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='docker.exe'" -ErrorAction Stop)
    foreach($proc in $procs){
      $cmd = [string]$proc.CommandLine
      if($cmd -notmatch '\spush\s'){ continue }
      if(-not [string]::IsNullOrWhiteSpace($imageRef) -and $cmd -like "*$imageRef*"){ return [int]$proc.ProcessId }
      if(-not [string]::IsNullOrWhiteSpace($runId)){
        $parent = $null
        try { $parent = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f [int]$proc.ParentProcessId) -ErrorAction Stop } catch {}
        if($parent -and ([string]$parent.CommandLine) -like "*$runId*"){ return [int]$proc.ProcessId }
      }
    }
  } catch {}
  return 0
}
function Update-MmenuCPushFallbackTelemetry {
  param([hashtable]$State)
  $now = Get-Date
  if(-not $State.ContainsKey('NetBaseBytes')){
    $netBase = Get-MmenuCNetworkSentBytes
    $State.NetBaseBytes = [int64]$netBase
    $State.NetLastBytes = [int64]$netBase
    $State.NetLastTime = $now
    $State.NetDeltaBytes = [int64]0
    $State.NetRateBytes = [double]0
  } else {
    $current = Get-MmenuCNetworkSentBytes
    if($current -gt 0){
      $previous = [int64]$State.NetLastBytes
      $previousTime = [datetime]$State.NetLastTime
      $seconds = [Math]::Max(0.001,($now - $previousTime).TotalSeconds)
      if($current -ge $previous){ $State.NetRateBytes = [double]($current - $previous) / $seconds }
      if($current -ge [int64]$State.NetBaseBytes){ $State.NetDeltaBytes = [int64]($current - [int64]$State.NetBaseBytes) }
      $State.NetLastBytes = [int64]$current
      $State.NetLastTime = $now
    }
  }
  if(-not $State.ContainsKey('DockerPid') -or [int]$State.DockerPid -le 0){
    $pidValue = Get-MmenuCPushDockerProcessId -State $State
    if($pidValue -gt 0){ $State.DockerPid = [int]$pidValue }
  }
  if([int64]$State.EstimatedBytes -gt 0 -and [int64]$State.NetDeltaBytes -gt 0 -and ([int64]$State.BytesDone -le 0 -or [string]$State.BytesMode -ne 'docker')){
    $State.BytesDone = [Math]::Min([int64]$State.EstimatedBytes,[int64]$State.NetDeltaBytes)
    $State.BytesTotal = [int64]$State.EstimatedBytes
    $State.BytesMode = 'network'
  }
}
function Write-MmenuCPushDashboard {
  param([datetime]$Started,[hashtable]$State,[string]$Detail='')
  Update-MmenuCPushFallbackTelemetry -State $State
  $elapsed=[Math]::Max(0.001,((Get-Date)-$Started).TotalSeconds)
  $layers = @($State.Layers.Keys)
  $total = [int]$layers.Count
  $done = 0
  foreach($layer in $layers){
    $status = [string]$State.Layers[$layer]
    if($status -match '^(Pushed|Layer already exists|Mounted from)'){ $done++ }
  }
  $barWidth = 24
  if([int64]$State.BytesTotal -gt 0 -and [int64]$State.BytesDone -gt 0){
    $bytesDone = [Math]::Min([int64]$State.BytesDone,[int64]$State.BytesTotal)
    $bytesTotal = [int64]$State.BytesTotal
    $pct = [Math]::Min(100.0,[Math]::Max(0.0,100.0 * [double]$bytesDone / [Math]::Max(1.0,[double]$bytesTotal)))
    $fill = [Math]::Min($barWidth,[Math]::Max(0,[int][Math]::Round($barWidth*$pct/100.0)))
    $rateBytes = [double]$State.NetRateBytes
    if($State.ContainsKey('DockerRateBytes') -and [double]$State.DockerRateBytes -gt 0){ $rateBytes = [double]$State.DockerRateBytes }
    $rateText = if($rateBytes -gt 0){ (Format-MmenuCMiB ([int64]$rateBytes)) + '/s' } else { 'active' }
    $mode = [string]$State.BytesMode
    if([string]::IsNullOrWhiteSpace($mode)){ $mode = 'push' }
    $metric = ('{0,6:N2}% {1}/{2} {3} {4} elapsed={5:N0}s' -f $pct,(Format-MmenuCMiB $bytesDone),(Format-MmenuCMiB $bytesTotal),$rateText,$mode,$elapsed)
  } elseif($total -gt 0){
    $pct = [Math]::Min(100.0,[Math]::Max(0.0,100.0 * [double]$done / [Math]::Max(1.0,[double]$total)))
    $fill = [Math]::Min($barWidth,[Math]::Max(0,[int][Math]::Round($barWidth*$pct/100.0)))
    $metric = ('{0,6:N2}% {1}/{2} layers elapsed={3:N0}s' -f $pct,$done,$total,$elapsed)
  } else {
    return
  }
  $bar = ('#' * $fill).PadRight($barWidth,'.')
  if([string]::IsNullOrWhiteSpace($Detail)){ $Detail = [string]$State.LastDetail }
  $line = ('[{0:HH:mm:ss}] {1,-7} {2,-13} [{3}] {4} {5}' -f (Get-Date),$EntryPoint,'push',$bar,$metric,$Detail)
  $width = try{ [Console]::WindowWidth } catch { 160 }
  if($width -lt 40){ $width = 160 }
  if($line.Length -ge $width){ $line = $line.Substring(0,$width-1) }
  Write-Host ("`r" + $line.PadRight($width-1)) -NoNewline -ForegroundColor Cyan
  $script:MmenuCDashboardPending = $true
}
function Add-MmenuCPushOutput {
  param([string]$Text,[hashtable]$State,[datetime]$Started)
  if([string]::IsNullOrEmpty($Text)){ return }
  $combined = [string]$State.Carry + $Text
  $parts = [regex]::Split($combined,"`r`n|`n|`r")
  $endsWithBreak = ($combined -match "(`r`n|`n|`r)$")
  $limit = if($endsWithBreak){ $parts.Count } else { [Math]::Max(0,$parts.Count-1) }
  for($i=0; $i -lt $limit; $i++){
    $line = ([string]$parts[$i]).Trim()
    if([string]::IsNullOrWhiteSpace($line)){ continue }
    $State.LastDetail = $line
    if($line -match 'docker push attempt\s+(\d+)\s+started'){
      $State.Attempt = [int]$matches[1]
    }
    $byteMatch = [regex]::Match($line,'(?<done>[0-9]+(?:\.[0-9]+)?\s*(?:B|KB|MB|GB|TB|KiB|MiB|GiB|TiB))\s*/\s*(?<total>[0-9]+(?:\.[0-9]+)?\s*(?:B|KB|MB|GB|TB|KiB|MiB|GiB|TiB))','IgnoreCase')
    if($byteMatch.Success){
      $doneBytes = ConvertFrom-MmenuCPushSizeText $byteMatch.Groups['done'].Value
      $totalBytes = ConvertFrom-MmenuCPushSizeText $byteMatch.Groups['total'].Value
      if($doneBytes -gt 0 -and $totalBytes -gt 0){
        $nowSample = Get-Date
        if($State.ContainsKey('DockerLastBytes') -and [int64]$State.DockerLastBytes -le $doneBytes){
          $deltaSeconds = [Math]::Max(0.001,($nowSample - [datetime]$State.DockerLastTime).TotalSeconds)
          $State.DockerRateBytes = [double]($doneBytes - [int64]$State.DockerLastBytes) / $deltaSeconds
        }
        $State.DockerLastBytes = [int64]$doneBytes
        $State.DockerLastTime = $nowSample
        $State.BytesDone = [int64]$doneBytes
        $State.BytesTotal = [int64]$totalBytes
        $State.BytesMode = 'docker'
      }
    }
    if($line -match '^([a-f0-9]{12,64}):\s+(.+)$'){
      $layer = $matches[1]
      $status = $matches[2].Trim()
      if($status -match '^(Pushed|Layer already exists|Mounted from)' -and [int64]$State.BytesTotal -gt 0){
        $State.BytesDone = [int64]$State.BytesTotal
        if([string]::IsNullOrWhiteSpace([string]$State.BytesMode)){ $State.BytesMode = 'docker' }
      }
      $old = if($State.LayerLastPrinted.ContainsKey($layer)){ [string]$State.LayerLastPrinted[$layer] } else { '' }
      $State.Layers[$layer] = $status
      if($old -ne $status){
        Write-Host ''
        Write-MmenuC ("[$EntryPoint][push-layer] {0}: {1}" -f $layer,$status) Gray
        $State.LayerLastPrinted[$layer] = $status
      }
    } elseif($line -match 'digest:\s*(sha256:[a-f0-9]+)') {
      $State.Digest = $matches[1]
      $State.DigestLine = $line
      Write-Host ''
      Write-MmenuC ("[$EntryPoint][push-digest] {0}" -f $line) Green
    } elseif($line -match '^The push refers to repository') {
      Write-Host ''
      Write-MmenuC ("[$EntryPoint][push-output] {0}" -f $line) Gray
    } elseif($line -match 'denied|unauthorized|forbidden|error|failed|timeout|TLS handshake|connection|reset|EOF') {
      Write-Host ''
      Write-MmenuC ("[$EntryPoint][push-output] {0}" -f $line) Yellow
    }
    Write-MmenuCPushDashboard -Started $Started -State $State -Detail $line
  }
  if($endsWithBreak){ $State.Carry = '' } else { $State.Carry = [string]$parts[$parts.Count-1] }
}
function Test-MmenuCRemoteManifest {
  param([Parameter(Mandatory=$true)][string]$DockerExe,[Parameter(Mandatory=$true)][string]$ImageRef)
  $old = $global:LASTEXITCODE
  $oldEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $DockerExe manifest inspect $ImageRef 2>$null | Out-Null
    $code = [int]$LASTEXITCODE
    return ($code -eq 0)
  } catch {
    return $false
  } finally {
    $ErrorActionPreference = $oldEAP
    $global:LASTEXITCODE = $old
  }
}
function Split-MmenuCImageRef {
  param([Parameter(Mandatory=$true)][string]$ImageRef)
  $ref = [string]$ImageRef
  if($ref -match '^docker\.io/(.+)$'){ $ref = $matches[1] }
  $slash = $ref.LastIndexOf('/')
  $colon = $ref.LastIndexOf(':')
  if($colon -le $slash){ throw "Image reference must include a tag: $ImageRef" }
  $repo = $ref.Substring(0,$colon).Trim('/')
  $tag = $ref.Substring($colon + 1)
  if($repo -notmatch '^[^/]+/[^/]+'){ throw "Docker Hub image reference expected: $ImageRef" }
  return [pscustomobject]@{ Repository=$repo; Tag=$tag }
}
function Get-MmenuCRemoteConfigLabels {
  param([Parameter(Mandatory=$true)][string]$ImageRef)
  try {
    $parts = Split-MmenuCImageRef -ImageRef $ImageRef
    $repo = [string]$parts.Repository
    $tag = [string]$parts.Tag
    $tokenUri = 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:' + [Uri]::EscapeDataString($repo) + ':pull'
    $token = (Invoke-RestMethod -Uri $tokenUri -Method Get -TimeoutSec 20).token
    if([string]::IsNullOrWhiteSpace([string]$token)){ return $null }
    $accept = 'application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
    $headers = @{ Authorization = "Bearer $token"; Accept = $accept }
    $manifestUri = "https://registry-1.docker.io/v2/$repo/manifests/$tag"
    $manifest = Invoke-RestMethod -Uri $manifestUri -Method Get -Headers $headers -TimeoutSec 30
    if($manifest.mediaType -match 'manifest\.list|image\.index'){
      $childDigest = $null
      foreach($m in @($manifest.manifests)){
        if($m.platform.os -eq 'linux' -and $m.platform.architecture -eq 'amd64'){ $childDigest = [string]$m.digest; break }
      }
      if([string]::IsNullOrWhiteSpace($childDigest) -and $manifest.manifests.Count -gt 0){ $childDigest = [string]$manifest.manifests[0].digest }
      if([string]::IsNullOrWhiteSpace($childDigest)){ return $null }
      $manifest = Invoke-RestMethod -Uri "https://registry-1.docker.io/v2/$repo/manifests/$childDigest" -Method Get -Headers $headers -TimeoutSec 30
    }
    $configDigest = [string]$manifest.config.digest
    if([string]::IsNullOrWhiteSpace($configDigest)){ return $null }
    $config = Invoke-RestMethod -Uri "https://registry-1.docker.io/v2/$repo/blobs/$configDigest" -Method Get -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 30
    return $config.config.Labels
  } catch {
    Write-MmenuC ("[$EntryPoint][manifest] remote label lookup unavailable for {0}: {1}" -f $ImageRef,$_.Exception.Message) DarkGray
    return $null
  }
}
function Test-MmenuCRemoteExactLabels {
  param(
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$Repository,
    [Parameter(Mandatory=$true)][string]$TagName,
    [Parameter(Mandatory=$true)][int64]$SourceBytes,
    [Parameter(Mandatory=$true)][int64]$SourceFiles,
    [string]$SourceFingerprint=''
  )
  $labels = Get-MmenuCRemoteConfigLabels -ImageRef $ImageRef
  if($null -eq $labels){ return $false }
  function Get-RemoteLabelValue([object]$Labels,[string]$Name){
    if($null -eq $Labels){ return $null }
    $prop = $Labels.PSObject.Properties[$Name]
    if($prop){ return [string]$prop.Value }
    return $null
  }
  function Normalize-RemoteLabelPath([AllowNull()][AllowEmptyString()][string]$PathValue){
    if($null -eq $PathValue){ return '' }
    $v = [string]$PathValue
    while($v -match '\\\\'){ $v = $v -replace '\\\\','\' }
    return $v.TrimEnd('\')
  }
  $baseMatch = (
    (Normalize-RemoteLabelPath (Get-RemoteLabelValue $labels 'backup.source.path')) -eq (Normalize-RemoteLabelPath ([string]$SourcePath)) -and
    (Get-RemoteLabelValue $labels 'backup.source.repo') -eq [string]$Repository -and
    (Get-RemoteLabelValue $labels 'backup.source.tag') -eq [string]$TagName -and
    (Get-RemoteLabelValue $labels 'backup.source.bytes') -eq [string]$SourceBytes -and
    (Get-RemoteLabelValue $labels 'backup.source.files') -eq [string]$SourceFiles
  )
  if(-not $baseMatch){ return $false }
  if(-not [string]::IsNullOrWhiteSpace([string]$SourceFingerprint)){
    return ((Get-RemoteLabelValue $labels 'backup.source.fingerprint') -eq [string]$SourceFingerprint)
  }
  return $true
}
function Test-MmenuCLocalExactImage {
  param(
    [Parameter(Mandatory=$true)][string]$DockerExe,
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$Repository,
    [Parameter(Mandatory=$true)][string]$TagName,
    [Parameter(Mandatory=$true)][int64]$SourceBytes,
    [Parameter(Mandatory=$true)][int64]$SourceFiles,
    [string]$SourceFingerprint=''
  )
  $old = $global:LASTEXITCODE
  try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $DockerExe
    $inspectArgs = @('image','inspect',$ImageRef,'--format','{{json .Config.Labels}}')
    $inspectParts = @()
    foreach($arg in $inspectArgs){ $inspectParts += (Quote-MmenuCArg ([string]$arg)) }
    $psi.Arguments = $inspectParts -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    [void]$proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if([int]$proc.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace([string]$stdout)){ return $false }
    $raw = $stdout
    $labels = ([string]($raw -join '')).Trim() | ConvertFrom-Json
    if($null -eq $labels){ return $false }
    $imagePath = [string]$labels.'backup.source.path'
    $imageRepo = [string]$labels.'backup.source.repo'
    $imageTag = [string]$labels.'backup.source.tag'
    $imageBytes = [int64]0
    $imageFiles = [int64]0
    $imageFingerprint = [string]$labels.'backup.source.fingerprint'
    [void][int64]::TryParse([string]$labels.'backup.source.bytes',[ref]$imageBytes)
    [void][int64]::TryParse([string]$labels.'backup.source.files',[ref]$imageFiles)
    $baseMatch = (
      [string]::Equals($imagePath,$SourcePath,[StringComparison]::OrdinalIgnoreCase) -and
      [string]::Equals($imageRepo,$Repository,[StringComparison]::OrdinalIgnoreCase) -and
      [string]::Equals($imageTag,$TagName,[StringComparison]::OrdinalIgnoreCase) -and
      $imageBytes -eq $SourceBytes -and
      $imageFiles -eq $SourceFiles
    )
    if($baseMatch -and -not [string]::IsNullOrWhiteSpace([string]$SourceFingerprint)){
      $baseMatch = [string]::Equals($imageFingerprint,[string]$SourceFingerprint,[StringComparison]::Ordinal)
    }
    if($baseMatch){
      Write-MmenuC ("[$EntryPoint][image-create] local exact-image cache hit; skipping duplicate archive/load and pushing existing image immediately: {0}" -f $ImageRef) Green
      return $true
    }
    Write-MmenuC ("[$EntryPoint][image-create] local image tag exists but source labels differ; rebuilding: {0}" -f $ImageRef) Yellow
    return $false
  } catch {
    Write-MmenuC ("[$EntryPoint][image-create] local exact-image cache check ignored after error: {0}" -f $_.Exception.Message) Yellow
    return $false
  } finally {
    $global:LASTEXITCODE = $old
  }
}
if(-not ('MmenuCWin32Process' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MmenuCWin32Process {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct STARTUPINFO {
    public UInt32 cb;
    public string lpReserved;
    public string lpDesktop;
    public string lpTitle;
    public UInt32 dwX;
    public UInt32 dwY;
    public UInt32 dwXSize;
    public UInt32 dwYSize;
    public UInt32 dwXCountChars;
    public UInt32 dwYCountChars;
    public UInt32 dwFillAttribute;
    public UInt32 dwFlags;
    public UInt16 wShowWindow;
    public UInt16 cbReserved2;
    public IntPtr lpReserved2;
    public IntPtr hStdInput;
    public IntPtr hStdOutput;
    public IntPtr hStdError;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_INFORMATION {
    public IntPtr hProcess;
    public IntPtr hThread;
    public UInt32 dwProcessId;
    public UInt32 dwThreadId;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct IO_COUNTERS {
    public UInt64 ReadOperationCount;
    public UInt64 WriteOperationCount;
    public UInt64 OtherOperationCount;
    public UInt64 ReadTransferCount;
    public UInt64 WriteTransferCount;
    public UInt64 OtherTransferCount;
  }
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CreateProcessW(
    string lpApplicationName,
    string lpCommandLine,
    IntPtr lpProcessAttributes,
    IntPtr lpThreadAttributes,
    bool bInheritHandles,
    UInt32 dwCreationFlags,
    IntPtr lpEnvironment,
    string lpCurrentDirectory,
    ref STARTUPINFO lpStartupInfo,
    out PROCESS_INFORMATION lpProcessInformation);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr hObject);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool GetProcessIoCounters(IntPtr hProcess, out IO_COUNTERS lpIoCounters);
}
'@
}
function Get-MmenuCProcessReadBytes {
  param([Parameter(Mandatory=$true)][System.Diagnostics.Process]$Process)
  try {
    if($null -eq $Process -or $Process.HasExited){ return 0 }
    $c = New-Object MmenuCWin32Process+IO_COUNTERS
    if([MmenuCWin32Process]::GetProcessIoCounters($Process.Handle,[ref]$c)){
      if([double]$c.ReadTransferCount -gt [double][int64]::MaxValue){ return [int64]::MaxValue }
      return [int64]$c.ReadTransferCount
    }
  } catch { }
  return 0
}
function Start-MmenuCDetachedProcess {
  param([Parameter(Mandatory=$true)][string]$CommandLine,[string]$WorkingDirectory='')
  if([string]::IsNullOrWhiteSpace($WorkingDirectory)){ $WorkingDirectory = Get-MmenuCTempRoot }
  $si = New-Object MmenuCWin32Process+STARTUPINFO
  $si.cb = [Runtime.InteropServices.Marshal]::SizeOf([type]'MmenuCWin32Process+STARTUPINFO')
  $pi = New-Object MmenuCWin32Process+PROCESS_INFORMATION
  $flags = [uint32]0x00000008
  $ok = [MmenuCWin32Process]::CreateProcessW($null,$CommandLine,[IntPtr]::Zero,[IntPtr]::Zero,$false,$flags,[IntPtr]::Zero,$WorkingDirectory,[ref]$si,[ref]$pi)
  if(-not $ok){
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "CreateProcess DETACHED_PROCESS failed with Win32 error $err"
  }
  if($pi.hThread -ne [IntPtr]::Zero){ [void][MmenuCWin32Process]::CloseHandle($pi.hThread) }
  if($pi.hProcess -ne [IntPtr]::Zero){ [void][MmenuCWin32Process]::CloseHandle($pi.hProcess) }
  return [uint32]$pi.dwProcessId
}
function Start-MmenuCPrestartedPushWorker {
  param([Parameter(Mandatory=$true)][string]$DockerExe,[Parameter(Mandatory=$true)][string]$ImageRef,[int64]$EstimatedBytes=0)
  $runId = [Guid]::NewGuid().ToString('N')
  $cmdPath = Join-MmenuCTempPath ("mmenu-push-$runId.cmd")
  $ps1Path = Join-MmenuCTempPath ("mmenu-push-$runId.ps1")
  $logPath = Join-MmenuCTempPath ("mmenu-push-$runId.log")
  $exitPath = Join-MmenuCTempPath ("mmenu-push-$runId.exit")
  $goPath = Join-MmenuCTempPath ("mmenu-push-$runId.go")
  $ackPath = Join-MmenuCTempPath ("mmenu-push-$runId.ack")
  $dockerDirForPath = Split-Path -Parent $DockerExe
  $workerPolicy = Get-MmenuCRetryPolicy
  $workerText = @"
`$ErrorActionPreference = 'Continue'
`$DockerExe = $(Quote-MmenuCPsString $DockerExe)
`$ImageRef = $(Quote-MmenuCPsString $ImageRef)
`$DockerDir = $(Quote-MmenuCPsString $dockerDirForPath)
`$TempRoot = $(Quote-MmenuCPsString (Get-MmenuCTempRoot))
`$GoPath = $(Quote-MmenuCPsString $goPath)
`$AckPath = $(Quote-MmenuCPsString $ackPath)
`$LogPath = $(Quote-MmenuCPsString $logPath)
`$ExitPath = $(Quote-MmenuCPsString $exitPath)
`$EntryPointName = $(Quote-MmenuCPsString $EntryPoint)
try {
  `$env:TEMP = `$TempRoot
  `$env:TMP = `$TempRoot
  if(`$DockerDir -and (Test-Path -LiteralPath `$DockerDir -PathType Container) -and (`$env:PATH -notlike "*`$DockerDir*")) { `$env:PATH = "`$DockerDir;`$env:PATH" }
  `$env:DOCKER_BUILDKIT = '1'
  `$env:BUILDKIT_PROGRESS = 'plain'
  `$env:COMPOSE_PROGRESS = 'plain'
  `$env:COMPOSE_HTTP_TIMEOUT = '300'
  `$env:DOCKER_CLIENT_TIMEOUT = '300'
  `$env:DOCKER_CLI_HINTS = 'false'
  `$env:DOCKER_SCAN_SUGGEST = 'false'
  `$GoDeadline = (Get-Date).AddMinutes(2)
  while(-not (Test-Path -LiteralPath `$GoPath -PathType Leaf)) {
    if((Get-Date) -ge `$GoDeadline) { throw 'Timed out waiting for the bounded push start signal.' }
    Start-Sleep -Milliseconds 200
  }
  Set-Content -LiteralPath `$LogPath -Value '' -Encoding UTF8
  `$MaxAttempts = $([int]$workerPolicy.MaxAttempts)
  `$OverallDeadline = (Get-Date).AddMinutes($([int]$workerPolicy.MaxMinutes))
  for(`$attempt = 1; `$attempt -le `$MaxAttempts; `$attempt++) {
    Add-Content -LiteralPath `$LogPath -Value ("[{0}][push-wrapper] docker push attempt {1}/{2} started" -f `$EntryPointName,`$attempt,`$MaxAttempts) -Encoding UTF8
    `$pushCmd = '"' + `$DockerExe + '" push "' + `$ImageRef + '" >> "' + `$LogPath + '" 2>&1'
    & `$env:ComSpec /d /c `$pushCmd
    `$pushEc = if(`$null -ne `$LASTEXITCODE){ [int]`$LASTEXITCODE } else { 999 }
    & `$DockerExe manifest inspect `$ImageRef *> `$null
    `$manifestEc = if(`$null -ne `$LASTEXITCODE){ [int]`$LASTEXITCODE } else { 999 }
    if(`$manifestEc -eq 0) {
      Add-Content -LiteralPath `$LogPath -Value ("[{0}][push-wrapper] manifest verification succeeded after docker push exit {1}" -f `$EntryPointName,`$pushEc) -Encoding UTF8
      Set-Content -LiteralPath `$ExitPath -Value '0' -Encoding ASCII
      break
    }
    if(`$attempt -ge `$MaxAttempts -or (Get-Date) -ge `$OverallDeadline) {
      `$finalExit = if(`$pushEc -ne 0){ `$pushEc } else { 1 }
      Add-Content -LiteralPath `$LogPath -Value ("[{0}][push-wrapper] bounded retries exhausted after attempt {1}; push_exit={2} manifest_exit={3}" -f `$EntryPointName,`$attempt,`$pushEc,`$manifestEc) -Encoding UTF8
      Set-Content -LiteralPath `$ExitPath -Value ([string]`$finalExit) -Encoding ASCII
      break
    }
    Add-Content -LiteralPath `$LogPath -Value ("[{0}][push-wrapper] docker push exit {1}; manifest exit {2}; retrying in 10 seconds" -f `$EntryPointName,`$pushEc,`$manifestEc) -Encoding UTF8
    for(`$remaining = 10; `$remaining -gt 0; `$remaining--) {
      Add-Content -LiteralPath `$LogPath -Value ("[{0}][push-wrapper] retry in {1} seconds after push_exit={2} manifest_exit={3}" -f `$EntryPointName,`$remaining,`$pushEc,`$manifestEc) -Encoding UTF8
      Start-Sleep -Seconds 1
    }
  }
  `$AckDeadline = (Get-Date).AddMinutes(2)
  while(-not (Test-Path -LiteralPath `$AckPath -PathType Leaf) -and (Get-Date) -lt `$AckDeadline) { Start-Sleep -Milliseconds 200 }
  exit 0
} catch {
  try { Add-Content -LiteralPath `$LogPath -Value ("[{0}][push-wrapper] fatal: {1}" -f `$EntryPointName,`$_.Exception.Message) -Encoding UTF8 } catch {}
  try { Set-Content -LiteralPath `$ExitPath -Value '1' -Encoding ASCII } catch {}
  exit 1
}
"@
  [IO.File]::WriteAllText($ps1Path,$workerText,(New-Object Text.UTF8Encoding($false)))
  $ps5Exe = Join-Path (Get-MmenuCWindowsRoot) 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $ps5Exe
  $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Quote-MmenuCArg $ps1Path)
  $tempRootForProcess = Get-MmenuCTempRoot
  $psi.WorkingDirectory = $tempRootForProcess
  $psi.EnvironmentVariables['TEMP'] = $tempRootForProcess
  $psi.EnvironmentVariables['TMP'] = $tempRootForProcess
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $proc = New-Object Diagnostics.Process
  $proc.StartInfo = $psi
  [void]$proc.Start()
  Write-MmenuC ("[$EntryPoint][push-worker] run_id={0} log={1} exit={2} ack={3} pid={4} image={5} bytes={6}" -f $runId,$logPath,$exitPath,$ackPath,$proc.Id,$ImageRef,[int64]$EstimatedBytes) DarkGray
  [pscustomobject]@{ RunId=$runId; CmdPath=$cmdPath; Ps1Path=$ps1Path; LogPath=$logPath; ExitPath=$exitPath; GoPath=$goPath; AckPath=$ackPath; TaskName=''; Process=$proc; ProcessId=[int]$proc.Id; ImageRef=$ImageRef; EstimatedBytes=[int64]$EstimatedBytes }
}
function Invoke-MmenuCPrestartedDockerPushUntilSuccess {
  param([Parameter(Mandatory=$true)]$Worker,[Parameter(Mandatory=$true)][string]$DockerExe,[Parameter(Mandatory=$true)][string]$ImageRef,[int64]$EstimatedBytes=0)
  Write-MmenuC ("[$EntryPoint][push] prestarted worker released immediately after image-create; live progress follows now; image={0}" -f $ImageRef)
  Set-Content -LiteralPath $Worker.GoPath -Value (Get-Date -Format o) -Encoding ASCII
  $started = Get-Date
  $offset = [int64]0
  $pushPolicy = Get-MmenuCRetryPolicy
  if($EstimatedBytes -le 0 -and $Worker.EstimatedBytes){ $EstimatedBytes = [int64]$Worker.EstimatedBytes }
  $state = @{ Layers=@{}; LayerLastPrinted=@{}; Digest=''; DigestLine=''; LastDetail='released prestarted docker push worker'; Carry=''; PushRunId=$Worker.RunId; ImageRef=$ImageRef; EstimatedBytes=[int64]$EstimatedBytes }
  while(-not (Test-Path -LiteralPath $Worker.ExitPath -PathType Leaf)){
    Start-Sleep -Milliseconds 500
    Add-MmenuCPushOutput -Text (Read-MmenuCSharedTextChunk -Path $Worker.LogPath -Offset ([ref]$offset)) -State $state -Started $started
    Write-MmenuCPushDashboard -Started $started -State $state
    $pushDoneForFloor = if($state.ContainsKey('BytesDone')){ [int64]$state.BytesDone } else { 0L }
    $pushTotalForFloor = if($state.ContainsKey('BytesTotal')){ [int64]$state.BytesTotal } elseif($state.ContainsKey('EstimatedBytes')){ [int64]$state.EstimatedBytes } else { 0L }
    if(Update-MmenuCLowSpeedGuard -State $state -Phase 'push' -Started $started -DoneBytes $pushDoneForFloor -TotalBytes $pushTotalForFloor -Detail ([string]$state.LastDetail)){
      try {
        $dockerPid = Get-MmenuCPushDockerProcessId -State $state
        if($dockerPid -gt 0){ Stop-Process -Id $dockerPid -Force -ErrorAction SilentlyContinue }
      } catch {}
      Stop-MmenuCProcessTree -Process $Worker.Process
      Set-Content -LiteralPath $Worker.ExitPath -Value '87' -Encoding ASCII
      break
    }
    if((Get-Date) -ge $pushPolicy.Deadline){
      Write-MmenuC "[$EntryPoint][push] hard push deadline reached; stopping the prestarted worker." Yellow
      try {
        $dockerPid = Get-MmenuCPushDockerProcessId -State $state
        if($dockerPid -gt 0){ Stop-Process -Id $dockerPid -Force -ErrorAction SilentlyContinue }
      } catch {}
      Stop-MmenuCProcessTree -Process $Worker.Process
      Set-Content -LiteralPath $Worker.ExitPath -Value '124' -Encoding ASCII
      break
    }
    $pushProcess = $null
    try {
      if($Worker.Process){
        $Worker.Process.Refresh()
        if($Worker.Process.HasExited -and -not (Test-Path -LiteralPath $Worker.ExitPath -PathType Leaf)){
          Add-Content -LiteralPath $Worker.LogPath -Value ("[$EntryPoint][push-wrapper] worker process exited before manifest success; exit={0}; falling back to direct push" -f [int]$Worker.Process.ExitCode) -Encoding UTF8
          Set-Content -LiteralPath $Worker.ExitPath -Value ([string][int]$Worker.Process.ExitCode) -Encoding ASCII
          break
        }
      } elseif($Worker.ProcessId -and -not (Get-Process -Id ([int]$Worker.ProcessId) -ErrorAction SilentlyContinue)){
        Add-Content -LiteralPath $Worker.LogPath -Value "[$EntryPoint][push-wrapper] worker process disappeared before manifest success; falling back to direct push" -Encoding UTF8
        Set-Content -LiteralPath $Worker.ExitPath -Value '1' -Encoding ASCII
        break
      }
    } catch {}
  }
  Add-MmenuCPushOutput -Text (Read-MmenuCSharedTextChunk -Path $Worker.LogPath -Offset ([ref]$offset)) -State $state -Started $started
  if(-not [string]::IsNullOrWhiteSpace([string]$state.Carry)){ Add-MmenuCPushOutput -Text ([string]$state.Carry + "`n") -State $state -Started $started }
  Write-Host ''
  $workerExitText = ([string](Get-Content -LiteralPath $Worker.ExitPath -Raw -ErrorAction SilentlyContinue)).Trim()
  $workerExit = 1
  if([int]::TryParse($workerExitText,[ref]$workerExit) -and $workerExit -eq 0){
    Set-Content -LiteralPath $Worker.AckPath -Value (Get-Date -Format o) -Encoding ASCII
    try {
      if($Worker.TaskName){
        $scheduler = New-Object -ComObject Schedule.Service
        $scheduler.Connect()
        $scheduler.GetFolder('\').DeleteTask([string]$Worker.TaskName,0)
      }
    } catch {}
    try { if($Worker.Process){ $Worker.Process.Dispose() } } catch {}
    Write-MmenuC ("[$EntryPoint][push] SUCCESS prestarted worker completed push and manifest verification: {0}" -f $ImageRef) Green
    $global:LASTEXITCODE = 0
    return 0
  }
  Write-MmenuC ("[$EntryPoint][push] prestarted worker failed before manifest verification exit={0}; switching to direct live docker push retry: {1}" -f $workerExit,$ImageRef) Yellow
  Set-Content -LiteralPath $Worker.AckPath -Value (Get-Date -Format o) -Encoding ASCII
  try {
    if($Worker.TaskName){
      $scheduler = New-Object -ComObject Schedule.Service
      $scheduler.Connect()
      $scheduler.GetFolder('\').DeleteTask([string]$Worker.TaskName,0)
    }
  } catch {}
  Stop-MmenuCProcessTree -Process $Worker.Process
  try { if($Worker.Process){ $Worker.Process.Dispose() } } catch {}
  return (Invoke-MmenuCDirectDockerPushUntilSuccess -DockerExe $DockerExe -ImageRef $ImageRef)
}
function Invoke-MmenuCDirectDockerPushUntilSuccess {
  param(
    [Parameter(Mandatory=$true)][string]$DockerExe,
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [string]$ExpectedSourcePath='',
    [string]$ExpectedRepository='',
    [string]$ExpectedTagName='',
    [int64]$ExpectedSourceBytes=0,
    [int64]$ExpectedSourceFiles=0,
    [string]$ExpectedSourceFingerprint='',
    [ValidateRange(1,20)][int]$MaxAttempts=6,
    [ValidateRange(1,240)][int]$MaxTotalMinutes=30
  )
  if($env:HERMES_MMENU_PUSH_MAX_ATTEMPTS -match '^\d+$'){ $MaxAttempts = [Math]::Max(1,[Math]::Min(20,[int]$env:HERMES_MMENU_PUSH_MAX_ATTEMPTS)) }
  if($env:HERMES_MMENU_PUSH_MAX_MINUTES -match '^\d+$'){ $MaxTotalMinutes = [Math]::Max(1,[Math]::Min(240,[int]$env:HERMES_MMENU_PUSH_MAX_MINUTES)) }
  $overallDeadline = (Get-Date).AddMinutes($MaxTotalMinutes)
  for($attempt=1; $attempt -le $MaxAttempts; $attempt++){
    Write-MmenuC ("[$EntryPoint][push] attempt {0}/{1} started: resumable push of the existing local image; image={2}" -f $attempt,$MaxAttempts,$ImageRef)
    $pushRunId = [Guid]::NewGuid().ToString('N')
    $pushCmdPath = Join-MmenuCTempPath ("mmenu-push-$pushRunId.cmd")
    $pushOutPath = Join-MmenuCTempPath ("mmenu-push-$pushRunId.log")
    $pushExitPath = Join-MmenuCTempPath ("mmenu-push-$pushRunId.exit")
    $pushAckPath = Join-MmenuCTempPath ("mmenu-push-$pushRunId.ack")
    $code = 999
    $started = Get-Date
    $state = @{
      Layers = @{}
      LayerLastPrinted = @{}
      Digest = ''
      DigestLine = ''
      LastDetail = 'starting docker push'
      Carry = ''
      PushRunId = $pushRunId
      ImageRef = $ImageRef
      EstimatedBytes = 0
    }
    try {
      $q = [string][char]34
      $dockerDirForPath = Split-Path -Parent $DockerExe
      $tempRootForCmd = Get-MmenuCTempRoot
      $cmdText = @(
        '@echo off',
        'setlocal EnableExtensions',
        ('set "TEMP=' + $tempRootForCmd + '"'),
        ('set "TMP=' + $tempRootForCmd + '"'),
        ('set "PATH=' + $dockerDirForPath + ';%PATH%"'),
        'set "DOCKER_CLIENT_TIMEOUT=300"',
        'set "COMPOSE_HTTP_TIMEOUT=300"',
        ('echo [' + $EntryPoint + '][push-wrapper] docker push attempt ' + $attempt + ' started > ' + $q + $pushOutPath + $q),
        ($q + $DockerExe + $q + ' push ' + $q + $ImageRef + $q + ' >> ' + $q + $pushOutPath + $q + ' 2>&1'),
        'set EC=%ERRORLEVEL%',
        ('> ' + $q + $pushExitPath + $q + ' echo %EC%'),
        'exit /b 0'
      ) -join "`r`n"
      [IO.File]::WriteAllText($pushCmdPath,$cmdText,[Text.Encoding]::ASCII)
      $offset = [int64]0
      Write-MmenuC "[$EntryPoint][push] docker push started through hidden direct launcher; live progress follows immediately" DarkGray
      $cmdExe = Join-Path (Get-MmenuCWindowsRoot) 'System32\cmd.exe'
      $pushPsi = New-Object Diagnostics.ProcessStartInfo
      $pushPsi.FileName = $cmdExe
      $pushPsi.Arguments = '/d /c ' + (Quote-MmenuCArg $pushCmdPath)
      $pushPsi.WorkingDirectory = $tempRootForCmd
      $pushPsi.EnvironmentVariables['TEMP'] = $tempRootForCmd
      $pushPsi.EnvironmentVariables['TMP'] = $tempRootForCmd
      $pushPsi.UseShellExecute = $false
      $pushPsi.CreateNoWindow = $true
      $pushProcess = New-Object Diagnostics.Process
      $pushProcess.StartInfo = $pushPsi
      [void]$pushProcess.Start()
      Write-MmenuC ("[$EntryPoint][push-worker] run_id={0} log={1} exit={2} ack={3} pid={4} image={5} bytes={6}" -f $pushRunId,$pushOutPath,$pushExitPath,$pushAckPath,$pushProcess.Id,$ImageRef,[int64]$ExpectedSourceBytes) DarkGray
      $global:LASTEXITCODE = 0
      $lastManifestPoll = [datetime]::MinValue
      while(-not (Test-Path -LiteralPath $pushExitPath -PathType Leaf)){
        Start-Sleep -Milliseconds 500
        Add-MmenuCPushOutput -Text (Read-MmenuCSharedTextChunk -Path $pushOutPath -Offset ([ref]$offset)) -State $state -Started $started
        Write-MmenuCPushDashboard -Started $started -State $state
        $pushDoneForFloor = if($state.ContainsKey('BytesDone')){ [int64]$state.BytesDone } else { 0L }
        $pushTotalForFloor = if($state.ContainsKey('BytesTotal')){ [int64]$state.BytesTotal } elseif($ExpectedSourceBytes -gt 0){ [int64]$ExpectedSourceBytes } else { 0L }
        if(Update-MmenuCLowSpeedGuard -State $state -Phase 'push' -Started $started -DoneBytes $pushDoneForFloor -TotalBytes $pushTotalForFloor -Detail ([string]$state.LastDetail)){
          try {
            $dockerPid = Get-MmenuCPushDockerProcessId -State $state
            if($dockerPid -gt 0){ Stop-Process -Id $dockerPid -Force -ErrorAction SilentlyContinue }
          } catch {}
          try { if($pushProcess -and -not $pushProcess.HasExited){ $pushProcess.Kill() } } catch {}
          Set-Content -LiteralPath $pushExitPath -Value '87' -Encoding ASCII
          break
        }
        if((Get-Date) -ge $overallDeadline){
          Write-MmenuC ("[$EntryPoint][push] hard deadline reached; stopping this Docker client without rebuilding the image: {0}" -f $ImageRef) Yellow
          try {
            $dockerPid = Get-MmenuCPushDockerProcessId -State $state
            if($dockerPid -gt 0){ Stop-Process -Id $dockerPid -Force -ErrorAction SilentlyContinue }
          } catch {}
          Stop-MmenuCProcessTree -Process $pushProcess
          Set-Content -LiteralPath $pushExitPath -Value '124' -Encoding ASCII
          break
        }
        $elapsedPushSeconds = ((Get-Date)-$started).TotalSeconds
        if($elapsedPushSeconds -ge 15 -and ((Get-Date)-$lastManifestPoll).TotalSeconds -ge 10){
          $lastManifestPoll = Get-Date
          $remoteOk = $false
          if(
            -not [string]::IsNullOrWhiteSpace($ExpectedSourcePath) -and
            -not [string]::IsNullOrWhiteSpace($ExpectedRepository) -and
            -not [string]::IsNullOrWhiteSpace($ExpectedTagName) -and
            $ExpectedSourceBytes -gt 0 -and
            $ExpectedSourceFiles -gt 0
          ){
            $remoteOk = Test-MmenuCRemoteExactLabels -ImageRef $ImageRef -SourcePath $ExpectedSourcePath -Repository $ExpectedRepository -TagName $ExpectedTagName -SourceBytes $ExpectedSourceBytes -SourceFiles $ExpectedSourceFiles -SourceFingerprint $ExpectedSourceFingerprint
          } else {
            $remoteOk = Test-MmenuCRemoteManifest -DockerExe $DockerExe -ImageRef $ImageRef
          }
          if($remoteOk){
            Write-MmenuC ("[$EntryPoint][push] remote image already matches while docker push is waiting; stopping wait and returning success: {0}" -f $ImageRef) Green
            try { if($pushProcess -and -not $pushProcess.HasExited){ $pushProcess.Kill() } } catch {}
            Set-Content -LiteralPath $pushExitPath -Value '0' -Encoding ASCII
            $state.LastDetail = 'remote image verified while docker push was waiting'
            $state.Digest = if($state.Digest){ $state.Digest } else { 'manifest-verified' }
            break
          }
        }
        try {
          $pushProcess.Refresh()
          if($pushProcess.HasExited -and -not (Test-Path -LiteralPath $pushExitPath -PathType Leaf)){
            Set-Content -LiteralPath $pushExitPath -Value ([string][int]$pushProcess.ExitCode) -Encoding ASCII
            break
          }
        } catch {}
      }
      Add-MmenuCPushOutput -Text (Read-MmenuCSharedTextChunk -Path $pushOutPath -Offset ([ref]$offset)) -State $state -Started $started
      if(-not [string]::IsNullOrWhiteSpace([string]$state.Carry)){
        Add-MmenuCPushOutput -Text ([string]$state.Carry + "`n") -State $state -Started $started
      }
      Write-Host ''
      if(Test-Path -LiteralPath $pushExitPath -PathType Leaf){
        $exitText = ([string](Get-Content -LiteralPath $pushExitPath -Raw -ErrorAction SilentlyContinue)).Trim()
        if($exitText -match '^-?\d+$'){ $code = [int]$exitText }
      } else {
        $code = 998
      }
    } finally {
      try {
        $dockerPid = Get-MmenuCPushDockerProcessId -State $state
        if($dockerPid -gt 0){ Stop-Process -Id $dockerPid -Force -ErrorAction SilentlyContinue }
      } catch {}
      Stop-MmenuCProcessTree -Process $pushProcess
      try { if($pushProcess){ $pushProcess.Dispose() } } catch {}
      try { Remove-Item -LiteralPath $pushCmdPath -Force -ErrorAction SilentlyContinue } catch {}
      try { Remove-Item -LiteralPath $pushOutPath -Force -ErrorAction SilentlyContinue } catch {}
      try { Remove-Item -LiteralPath $pushExitPath -Force -ErrorAction SilentlyContinue } catch {}
      try { Remove-Item -LiteralPath $pushAckPath -Force -ErrorAction SilentlyContinue } catch {}
    }
    $global:LASTEXITCODE = 0
    if($code -eq 0){
      Write-MmenuC ("[$EntryPoint][push] SUCCESS exit=0 attempt={0}: {1}" -f $attempt,$ImageRef) Green
      $global:LASTEXITCODE = 0
      return 0
    }
    $remoteOkAfterNonzeroExit = $false
    if(
      -not [string]::IsNullOrWhiteSpace($ExpectedSourcePath) -and
      -not [string]::IsNullOrWhiteSpace($ExpectedRepository) -and
      -not [string]::IsNullOrWhiteSpace($ExpectedTagName) -and
      $ExpectedSourceBytes -gt 0 -and
      $ExpectedSourceFiles -gt 0
    ){
      $remoteOkAfterNonzeroExit = Test-MmenuCRemoteExactLabels -ImageRef $ImageRef -SourcePath $ExpectedSourcePath -Repository $ExpectedRepository -TagName $ExpectedTagName -SourceBytes $ExpectedSourceBytes -SourceFiles $ExpectedSourceFiles -SourceFingerprint $ExpectedSourceFingerprint
    } else {
      $remoteOkAfterNonzeroExit = Test-MmenuCRemoteManifest -DockerExe $DockerExe -ImageRef $ImageRef
    }
    if($remoteOkAfterNonzeroExit){
      Write-MmenuC ("[$EntryPoint][push] SUCCESS remote-confirmed despite docker exit={0}; returning to shell after exact manifest check: {1}" -f $code,$ImageRef) Green
      $global:LASTEXITCODE = 0
      return 0
    }
    if(-not [string]::IsNullOrWhiteSpace([string]$state.Digest)){
      Write-MmenuC ("[$EntryPoint][push] docker push returned exit={0} after digest {1}; verifying remote manifest before retrying" -f $code,$state.Digest) Yellow
      $digestRemoteOk = $false
      if(
        -not [string]::IsNullOrWhiteSpace($ExpectedSourcePath) -and
        -not [string]::IsNullOrWhiteSpace($ExpectedRepository) -and
        -not [string]::IsNullOrWhiteSpace($ExpectedTagName) -and
        $ExpectedSourceBytes -gt 0 -and
        $ExpectedSourceFiles -gt 0
      ){
        $digestRemoteOk = Test-MmenuCRemoteExactLabels -ImageRef $ImageRef -SourcePath $ExpectedSourcePath -Repository $ExpectedRepository -TagName $ExpectedTagName -SourceBytes $ExpectedSourceBytes -SourceFiles $ExpectedSourceFiles -SourceFingerprint $ExpectedSourceFingerprint
      } else {
        $digestRemoteOk = Test-MmenuCRemoteManifest -DockerExe $DockerExe -ImageRef $ImageRef
      }
      if($digestRemoteOk){
        Write-MmenuC ("[$EntryPoint][push] SUCCESS digest-confirmed despite docker exit={0}; remote manifest exists; returning to shell after final manifest check: {1}" -f $code,$ImageRef) Green
        $global:LASTEXITCODE = 0
        return 0
      }
    }
    $global:LASTEXITCODE = 0
    if($attempt -ge $MaxAttempts -or (Get-Date) -ge $overallDeadline){
      Write-MmenuC ("[$EntryPoint][push] stopped after bounded retries; local image remains intact for a later push. attempts={0} exit={1} image={2}" -f $attempt,$code,$ImageRef) Red
      $global:LASTEXITCODE = [int]$code
      return [int]$code
    }
    Write-MmenuC ("[$EntryPoint][push] recoverable Docker Hub failure exit={0}; retrying only the existing image, never rebuilding: {1}" -f $code,$ImageRef) Yellow
    $delay = [Math]::Min(300,[Math]::Max(5,10*$attempt))
    $started = Get-Date
    for($remaining=$delay; $remaining -gt 0; $remaining--){
      Write-MmenuCDashboard -Name $EntryPoint -Phase 'push-retry' -Started $started -DoneBytes ($delay-$remaining) -TotalBytes $delay -Detail ("next push attempt in {0}s after exit={1}" -f $remaining,$code)
      Start-Sleep -Seconds 1
    }
    Write-Host ''
  }
}
function Convert-MmenuCDockerfileQuoted {
  param([AllowNull()][AllowEmptyString()][string]$Value)
  if($null -eq $Value){ $Value = '' }
  return '"' + (($Value -replace '\\','\\\\') -replace '"','\"') + '"'
}
function Convert-MmenuCBuildKitSizeToBytes {
  param([AllowNull()][AllowEmptyString()][string]$Number,[AllowNull()][AllowEmptyString()][string]$Unit)
  $n = 0.0
  if(-not [double]::TryParse(([string]$Number),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$n)){ return 0L }
  switch -Regex ([string]$Unit) {
    '^(B|bytes?)$' { return [int64]$n }
    '^(kB|KB)$' { return [int64]($n * 1000) }
    '^KiB$' { return [int64]($n * 1KB) }
    '^(mB|MB)$' { return [int64]($n * 1000 * 1000) }
    '^MiB$' { return [int64]($n * 1MB) }
    '^(gB|GB)$' { return [int64]($n * 1000 * 1000 * 1000) }
    '^GiB$' { return [int64]($n * 1GB) }
    default { return [int64]$n }
  }
}
function New-MmenuCBuildxDockerfile {
  param(
    [Parameter(Mandatory=$true)][string]$DockerfilePath,
    [string]$DockerignorePath='',
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$Repository,
    [Parameter(Mandatory=$true)][string]$TagName,
    [Parameter(Mandatory=$true)][int64]$SourceBytes,
    [Parameter(Mandatory=$true)][int64]$SourceFiles,
    [string]$SourceFingerprint=''
  )
  $dockerfile = @(
    'FROM scratch',
    'COPY . /home/',
    'WORKDIR /home',
    ('LABEL backup.source.path={0}' -f (Convert-MmenuCDockerfileQuoted $SourcePath)),
    ('LABEL backup.source.repo={0}' -f (Convert-MmenuCDockerfileQuoted $Repository)),
    ('LABEL backup.source.tag={0}' -f (Convert-MmenuCDockerfileQuoted $TagName)),
    ('LABEL backup.source.bytes={0}' -f (Convert-MmenuCDockerfileQuoted ([string]$SourceBytes))),
    ('LABEL backup.source.files={0}' -f (Convert-MmenuCDockerfileQuoted ([string]$SourceFiles))),
    ('LABEL backup.source.fingerprint={0}' -f (Convert-MmenuCDockerfileQuoted ([string]$SourceFingerprint))),
    'LABEL backup.mmenu.layering="dockerfile-buildx-copy-push-no-load-archive"',
    'LABEL backup.mmenu.builder="buildx-build-push-progress-plain"'
  ) -join "`n"
  $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
  [IO.File]::WriteAllText($DockerfilePath,$dockerfile + "`n",$utf8NoBom)
}
function Add-MmenuCBuildxOutput {
  param([AllowNull()][AllowEmptyString()][string]$Text,[hashtable]$State,[datetime]$Started,[int64]$TotalBytes)
  if([string]::IsNullOrEmpty($Text)){ return }
  $combined = [string]$State.Carry + $Text
  $parts = [regex]::Split($combined,"`r`n|`n|`r")
  $lineCount = $parts.Count
  $endsWithNewLine = ($combined -match "(`r`n|`n|`r)$")
  $limit = if($endsWithNewLine){ $lineCount } else { [Math]::Max(0,$lineCount - 1) }
  for($i=0; $i -lt $limit; $i++){
    $line = [string]$parts[$i]
    if([string]::IsNullOrWhiteSpace($line)){ continue }
    $State.LastDetail = $line
    if($line -match 'transferring context:\s*([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?i?B|bytes?)'){
      $b = Convert-MmenuCBuildKitSizeToBytes -Number $matches[1] -Unit $matches[2]
      if($b -gt [int64]$State.DoneBytes){ $State.DoneBytes = [Math]::Min([int64]$b,[int64]$TotalBytes) }
    }
    if($line -match '(?i)(pushing|pushed|exporting|writing image|naming to|DONE|CACHED|transferring context)'){ $State.PhaseDetail = $line }
    if($line -match 'digest:\s*(sha256:[0-9a-f]{64})'){ $State.Digest = $matches[1] }
    Write-Host ''
    Write-MmenuC ("[$EntryPoint][buildx] {0}" -f $line) Gray
    Write-MmenuCDashboard -Name $EntryPoint -Phase 'buildx-push' -Started $Started -DoneBytes ([int64]$State.DoneBytes) -TotalBytes $TotalBytes -Detail ([string]$State.PhaseDetail)
  }
  if($endsWithNewLine){ $State.Carry = '' } else { $State.Carry = [string]$parts[$lineCount - 1] }
}
function Test-MenuCDockerEngineReady {
  param([Parameter(Mandatory=$true)][string]$DockerExe)
  try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $DockerExe
    $psi.Arguments = 'version --format {{.Server.Version}}'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = New-Object Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    if($p.WaitForExit(3000)){
      $p.Refresh()
      return ([int]$p.ExitCode -eq 0)
    }
    Stop-MmenuCProcessTree -Process $p
    return $false
  } catch {
    Stop-MmenuCProcessTree -Process $p
    return $false
  } finally {
    try { if($p){ $p.Dispose() } } catch {}
  }
}
function Wait-MenuCDockerEngineReady {
  param([Parameter(Mandatory=$true)][string]$DockerExe,[ValidateRange(5,600)][int]$TimeoutSeconds=180)
  if($env:HERMES_MMENU_ENGINE_WAIT_SECONDS -match '^\d+$'){ $TimeoutSeconds = [Math]::Max(5,[Math]::Min(600,[int]$env:HERMES_MMENU_ENGINE_WAIT_SECONDS)) }
  $started = Get-Date
  $deadline = $started.AddSeconds($TimeoutSeconds)
  $polls = 0
  while((Get-Date) -lt $deadline){
    if(Test-MenuCDockerEngineReady -DockerExe $DockerExe){ return $true }
    $polls++
    $elapsed = [int]((Get-Date)-$started).TotalSeconds
    if($polls -eq 1 -or $polls % 5 -eq 0){
      Write-MmenuC ("[$EntryPoint][engine] Docker engine not ready yet (poll {0}, {1}s elapsed); waiting... press Ctrl+C to stop" -f $polls,$elapsed) DarkGray
    }
    Start-Sleep -Seconds 2
  }
  Write-MmenuC ("[$EntryPoint][engine] Docker engine did not become ready within {0}s; returning without an endless loading state" -f $TimeoutSeconds) Red
  return $false
}
function Invoke-MmenuCDockerfileBuildxPushUntilSuccess {
  param(
    [Parameter(Mandatory=$true)][string]$DockerExe,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$DockerfilePath,
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [int64]$EstimatedBytes=0,
    [string]$ExpectedRepository='',
    [string]$ExpectedTagName='',
    [int64]$ExpectedSourceFiles=0,
    [string]$ExpectedSourceFingerprint='',
    [ValidateRange(1,10)][int]$MaxBuildAttempts=3
  )
  if(-not (Test-Path -LiteralPath $DockerfilePath -PathType Leaf)){ throw "BuildKit Dockerfile not found: $DockerfilePath" }
  $totalBytes = [Math]::Max([int64]1,[int64]$EstimatedBytes)
  $oldBuildKit = $env:DOCKER_BUILDKIT
  $oldBuildkitProgress = $env:BUILDKIT_PROGRESS
  $oldDockerCliHints = $env:DOCKER_CLI_HINTS
  $oldDockerScanSuggest = $env:DOCKER_SCAN_SUGGEST
  $oldLocation = (Get-Location).ProviderPath
  try {
    $env:DOCKER_BUILDKIT = '1'
    $env:BUILDKIT_PROGRESS = 'plain'
    $env:DOCKER_CLI_HINTS = 'false'
    $env:DOCKER_SCAN_SUGGEST = 'false'
    Set-Location -LiteralPath $SourcePath
    Write-MmenuC "[$EntryPoint][engine] checking Docker engine readiness before build (bounded 3s probe)..." DarkGray
    if(-not (Wait-MenuCDockerEngineReady -DockerExe $DockerExe)){ throw "${EntryPoint}: Docker engine did not become ready." }
    $buildCode = 99
    for($attempt=1; $attempt -le $MaxBuildAttempts; $attempt++){
      $buildArgs = @('build','--progress=plain','--file',$DockerfilePath,'--tag',$ImageRef,'.')
      Write-MmenuC ("[$EntryPoint][build] attempt {0}/{1} started in source path; image={2}" -f $attempt,$MaxBuildAttempts,$ImageRef)
      Write-MmenuC ("[$EntryPoint][build] cwd={0}" -f (Get-Location).ProviderPath) DarkGray
      Write-MmenuC ("[$EntryPoint][build] command=docker {0}" -f (($buildArgs | ForEach-Object { Quote-MmenuCArg $_ }) -join ' ')) DarkGray
      try {
        $buildCode = Invoke-MmenuCProcess -Label 'build' -CommandLine ((Quote-MmenuCArg $DockerExe) + ' ' + (($buildArgs | ForEach-Object { Quote-MmenuCArg $_ }) -join ' ')) -WorkingDirectory $SourcePath -WatchTotalBytes $totalBytes
      } catch {
        if($_.Exception -is [System.Management.Automation.PipelineStoppedException]){ throw }
        Write-MmenuC ("[$EntryPoint][build] attempt {0} failed cleanly: {1}" -f $attempt,$_.Exception.Message) Yellow
        $buildCode = 99
      }
      if($buildCode -eq 0){ break }
      if($attempt -lt $MaxBuildAttempts){
        Write-MmenuC ("[$EntryPoint][build] docker build exited {0}; retrying the build ({1}/{2}): {3}" -f $buildCode,$attempt,$MaxBuildAttempts,$ImageRef) Yellow
        if(-not (Test-MenuCDockerEngineReady -DockerExe $DockerExe) -and -not (Wait-MenuCDockerEngineReady -DockerExe $DockerExe)){ return [int]$buildCode }
        Start-Sleep -Seconds ([Math]::Min(60,[Math]::Max(5,5*$attempt)))
      }
    }
    if($buildCode -ne 0){
      Write-MmenuC ("[$EntryPoint][build] failed after {0} bounded attempts; no push started: {1}" -f $MaxBuildAttempts,$ImageRef) Red
      return [int]$buildCode
    }
    Write-MmenuC ("[$EntryPoint][build] SUCCESS; the image is now local and will not be rebuilt if Docker Hub needs retries: {0}" -f $ImageRef) Green
    return (Invoke-MmenuCDirectDockerPushUntilSuccess -DockerExe $DockerExe -ImageRef $ImageRef -ExpectedSourcePath $SourcePath -ExpectedRepository $ExpectedRepository -ExpectedTagName $ExpectedTagName -ExpectedSourceBytes $EstimatedBytes -ExpectedSourceFiles $ExpectedSourceFiles -ExpectedSourceFingerprint $ExpectedSourceFingerprint)
  } finally {
    Set-Location -LiteralPath $oldLocation
    if($null -eq $oldBuildKit){ Remove-Item Env:DOCKER_BUILDKIT -ErrorAction SilentlyContinue } else { $env:DOCKER_BUILDKIT = $oldBuildKit }
    if($null -eq $oldBuildkitProgress){ Remove-Item Env:BUILDKIT_PROGRESS -ErrorAction SilentlyContinue } else { $env:BUILDKIT_PROGRESS = $oldBuildkitProgress }
    if($null -eq $oldDockerCliHints){ Remove-Item Env:DOCKER_CLI_HINTS -ErrorAction SilentlyContinue } else { $env:DOCKER_CLI_HINTS = $oldDockerCliHints }
    if($null -eq $oldDockerScanSuggest){ Remove-Item Env:DOCKER_SCAN_SUGGEST -ErrorAction SilentlyContinue } else { $env:DOCKER_SCAN_SUGGEST = $oldDockerScanSuggest }
  }
}
function Invoke-MmenuCDockerImportTarUntilSuccess {
  param(
    [Parameter(Mandatory=$true)][string]$DockerExe,
    [Parameter(Mandatory=$true)][string]$TarPath,
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [Parameter(Mandatory=$true)][string[]]$Changes,
    [int64]$ContextTotalBytes=0
  )
  if(-not (Test-Path -LiteralPath $TarPath -PathType Leaf)){ throw "Docker import tar not found: $TarPath" }
  $totalBytes = [int64](Get-Item -LiteralPath $TarPath).Length
  if($ContextTotalBytes -gt 0){ $totalBytes = [int64]$ContextTotalBytes }
  $dockerDir = Split-Path -Parent $DockerExe
  $retryPolicy = Get-MmenuCRetryPolicy -DefaultAttempts 3 -DefaultMinutes 30 -AttemptsEnvironmentName 'HERMES_MMENU_LOCAL_MAX_ATTEMPTS' -MinutesEnvironmentName 'HERMES_MMENU_LOCAL_MAX_MINUTES'
  for($attempt=1; $attempt -le $retryPolicy.MaxAttempts; $attempt++){
    $started = Get-Date
    Write-MmenuC ("[$EntryPoint][image-create] attempt {0}/{1} started: Docker import file={2}; image={3}" -f $attempt,$retryPolicy.MaxAttempts,(Format-MmenuCMiB ([int64](Get-Item -LiteralPath $TarPath).Length)),$ImageRef)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $DockerExe
    $args = New-Object 'System.Collections.Generic.List[string]'
    [void]$args.Add('import')
    foreach($change in $Changes){ [void]$args.Add('--change'); [void]$args.Add([string]$change) }
    [void]$args.Add($TarPath)
    [void]$args.Add($ImageRef)
    $psi.Arguments = (($args | ForEach-Object { Quote-MmenuCArg $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $tempRootForProcess = Get-MmenuCTempRoot
    $psi.WorkingDirectory = $tempRootForProcess
    $psi.EnvironmentVariables['TEMP'] = $tempRootForProcess
    $psi.EnvironmentVariables['TMP'] = $tempRootForProcess
    if($dockerDir -and (Test-Path -LiteralPath $dockerDir -PathType Container)){
      $oldPathForChild = [string]$psi.EnvironmentVariables['PATH']
      if($oldPathForChild -notlike "*$dockerDir*"){ $psi.EnvironmentVariables['PATH'] = "$dockerDir;$oldPathForChild" }
    }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $outLines = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
    $errLines = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
    $p.add_OutputDataReceived({ param($sender,$eventArgs) if($eventArgs.Data){ $outLines.Enqueue($eventArgs.Data) } })
    $p.add_ErrorDataReceived({ param($sender,$eventArgs) if($eventArgs.Data){ $errLines.Enqueue($eventArgs.Data) } })
    $sent = [int64]0
    $speedFloorState = @{ Phase='image-create' }
    $lastRender = Get-Date
    $lastDetail = 'docker import reading tar file'
    $code = -1
    try{
      [void]$p.Start()
      $p.BeginOutputReadLine()
      $p.BeginErrorReadLine()
      $baselineRead = Get-MmenuCProcessReadBytes -Process $p
      while(-not $p.WaitForExit(250)){
        $ioRead = [int64]((Get-MmenuCProcessReadBytes -Process $p) - $baselineRead)
        if($ioRead -gt $sent){ $sent = [Math]::Min([int64]$totalBytes,[int64]$ioRead) }
        $now = Get-Date
        if((New-TimeSpan -Start $lastRender -End $now).TotalMilliseconds -ge 250 -or $sent -ge $totalBytes){
          Write-MmenuCDashboard -Name $EntryPoint -Phase 'image-create' -Started $started -DoneBytes $sent -TotalBytes $totalBytes -Detail 'docker import file read'
          $lastRender = $now
        }
        if(Update-MmenuCLowSpeedGuard -State $speedFloorState -Phase 'image-create' -Started $started -DoneBytes $sent -TotalBytes $totalBytes -Detail 'docker import file read'){
          Stop-MmenuCProcessTree -Process $p
          break
        }
        if((Get-Date) -ge $retryPolicy.Deadline){
          Write-MmenuC "[$EntryPoint][image-create] hard deadline reached; stopping Docker import." Yellow
          Stop-MmenuCProcessTree -Process $p
          break
        }
        while($outLines.TryDequeue([ref]$lastDetail)){ if($lastDetail){ Write-Host ''; Write-MmenuC $lastDetail DarkGray } }
        while($errLines.TryDequeue([ref]$lastDetail)){ if($lastDetail){ Write-Host ''; Write-MmenuC $lastDetail Gray } }
      }
      $finalRead = [int64]((Get-MmenuCProcessReadBytes -Process $p) - $baselineRead)
      if($finalRead -gt $sent){ $sent = [Math]::Min([int64]$totalBytes,[int64]$finalRead) }
      $code = [int]$p.ExitCode
      if($code -eq 0 -and $sent -lt $totalBytes){ $sent = [int64]$totalBytes }
      while($outLines.TryDequeue([ref]$lastDetail)){ if($lastDetail){ Write-Host ''; Write-MmenuC $lastDetail DarkGray } }
      while($errLines.TryDequeue([ref]$lastDetail)){ if($lastDetail){ Write-Host ''; Write-MmenuC $lastDetail Gray } }
    } catch {
      $lastDetail = $_.Exception.Message
      Write-Host ''
      Write-MmenuC ("[$EntryPoint][image-create] import monitor exception: {0}" -f $lastDetail) Yellow
      Stop-MmenuCProcessTree -Process $p
      $code = -1
    } finally {
      if($p){ $p.Dispose() }
    }
    Write-MmenuCDashboard -Name $EntryPoint -Phase 'image-create' -Started $started -DoneBytes $sent -TotalBytes $totalBytes -Detail ("exit={0}" -f $code)
    if($code -eq 0){
      Write-MmenuC ("[$EntryPoint][image-create] SUCCESS exit=0 attempt={0}: {1}" -f $attempt,$ImageRef) Green
      $global:LASTEXITCODE = 0
      return 0
    }
    $global:LASTEXITCODE = 0
    if($attempt -ge $retryPolicy.MaxAttempts -or (Get-Date) -ge $retryPolicy.Deadline){
      Write-MmenuC ("[$EntryPoint][image-create] stopped after bounded retries; source and tar remain intact. attempts={0} exit={1} image={2}" -f $attempt,$code,$ImageRef) Red
      $global:LASTEXITCODE = [int]$code
      return [int]$code
    }
    Write-MmenuC ("[$EntryPoint][image-create] recoverable Docker failure exit={0} attempt={1}; retrying without recreating the source tar: {2}" -f $code,$attempt,$ImageRef) Yellow
    $delay = [Math]::Min(300,[Math]::Max(5,10*$attempt))
    $retryStarted = Get-Date
    for($remaining=$delay; $remaining -gt 0; $remaining--){
      Write-MmenuCDashboard -Name $EntryPoint -Phase 'image-create-retry' -Started $retryStarted -DoneBytes ($delay-$remaining) -TotalBytes $delay -Detail ("next attempt in {0}s after exit={1}" -f $remaining,$code)
      Start-Sleep -Seconds 1
    }
    Write-Host ''
  }
}
function Invoke-MmenuCDirectRegistryPushUntilSuccess {
  param(
    [Parameter(Mandatory=$true)][string]$DockerExe,
    [Parameter(Mandatory=$true)][string]$PythonExe,
    [string[]]$PythonArgs=@(),
    [Parameter(Mandatory=$true)][string]$TarPath,
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [Parameter(Mandatory=$true)][System.Collections.IDictionary]$Labels,
    [int64]$ContextTotalBytes=0
  )
  if(-not (Test-Path -LiteralPath $TarPath -PathType Leaf)){ throw "Direct registry tar not found: $TarPath" }
  $dockerDir = Split-Path -Parent $DockerExe
  $credentialHelper = Join-Path $dockerDir 'docker-credential-desktop.exe'
  if(-not (Test-Path -LiteralPath $credentialHelper -PathType Leaf)){ throw "Docker credential helper missing for direct registry push: $credentialHelper" }
  $runId = [Guid]::NewGuid().ToString('N')
  $scriptPath = Join-MmenuCTempPath ("mmenu-registry-push-$runId.py")
  $labelsPath = Join-MmenuCTempPath ("mmenu-registry-push-$runId.labels.json")
  $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
  [IO.File]::WriteAllText($labelsPath,($Labels | ConvertTo-Json -Compress),$utf8NoBom)
  $py = @'
import base64, hashlib, http.client, json, os, subprocess, sys, time, urllib.parse, urllib.request

tar_path, image_ref, labels_path, helper_path, entrypoint = sys.argv[1:6]
total_hint = int(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6].isdigit() else 0
with open(labels_path, 'r', encoding='utf-8') as f:
    labels = json.load(f)

def fail(msg):
    print('[%s][registry-push] ERROR %s' % (entrypoint, msg), file=sys.stderr, flush=True)
    sys.exit(1)

def split_image(ref):
    ref = ref.strip()
    if ref.startswith('docker.io/'):
        ref = ref[len('docker.io/'):]
    slash = ref.rfind('/')
    colon = ref.rfind(':')
    if colon <= slash:
        fail('image reference must include tag: ' + ref)
    repo = ref[:colon].strip('/')
    tag = ref[colon + 1:]
    if repo.count('/') < 1:
        fail('Docker Hub repository expected: ' + ref)
    return repo, tag

repo, tag = split_image(image_ref)
size = os.path.getsize(tar_path)
total = total_hint if total_hint > 0 else size

def get_token(scope):
    cp = subprocess.run([helper_path, 'get'], input=b'https://index.docker.io/v1/', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if cp.returncode != 0:
        fail('credential helper failed')
    cred = json.loads(cp.stdout.decode('utf-8'))
    pair = ('%s:%s' % (cred.get('Username',''), cred.get('Secret',''))).encode('ascii')
    basic = base64.b64encode(pair).decode('ascii')
    url = 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:%s:%s' % (urllib.parse.quote(repo, safe=''), scope)
    req = urllib.request.Request(url, headers={'Authorization':'Basic ' + basic, 'User-Agent':'mmenu-direct-registry'})
    with urllib.request.urlopen(req, timeout=60) as r:
        tok = json.loads(r.read().decode('utf-8')).get('token','')
    if not tok:
        fail('Docker Hub token was empty')
    return tok

token = get_token('push,pull')

def path_from_location(loc):
    if loc.startswith('http://') or loc.startswith('https://'):
        u = urllib.parse.urlparse(loc)
        return u.path + (('?' + u.query) if u.query else '')
    return loc

def registry_request(method, path, body=None, extra=None, ok=(200,201,202,204)):
    headers = {'Authorization':'Bearer ' + token, 'User-Agent':'mmenu-direct-registry'}
    if extra:
        headers.update(extra)
    conn = http.client.HTTPSConnection('registry-1.docker.io', timeout=180)
    conn.request(method, path, body=body, headers=headers)
    resp = conn.getresponse()
    data = resp.read()
    hdrs = dict(resp.getheaders())
    status, reason = resp.status, resp.reason
    conn.close()
    if status not in ok:
        fail('%s %s -> %s %s %r' % (method, path, status, reason, data[:300]))
    return status, hdrs, data

def start_upload():
    status, headers, data = registry_request('POST', '/v2/%s/blobs/uploads/' % repo, extra={'Content-Length':'0'})
    loc = headers.get('Location') or headers.get('location')
    if not loc:
        fail('registry did not return upload location')
    return path_from_location(loc)

def finalize_upload(location, digest, body=None):
    loc = path_from_location(location)
    u = urllib.parse.urlparse(loc if loc.startswith('/') else '/' + loc)
    query = urllib.parse.parse_qsl(u.query, keep_blank_values=True)
    query.append(('digest', digest))
    final_path = u.path + '?' + urllib.parse.urlencode(query)
    if body is None:
        registry_request('PUT', final_path, extra={'Content-Length':'0'})
    else:
        registry_request('PUT', final_path, body=body, extra={'Content-Type':'application/octet-stream','Content-Length':str(len(body))})

def upload_tar_layer():
    location = start_upload()
    sha = hashlib.sha256()
    sent = 0
    chunk_size = 8 * 1024 * 1024
    last_print = 0.0
    conn = http.client.HTTPSConnection('registry-1.docker.io', timeout=180)
    conn.putrequest('PATCH', location)
    conn.putheader('Authorization', 'Bearer ' + token)
    conn.putheader('Content-Type', 'application/octet-stream')
    conn.putheader('Content-Length', str(size))
    conn.putheader('User-Agent', 'mmenu-direct-registry')
    conn.endheaders()
    started = time.time()
    with open(tar_path, 'rb', buffering=8 * 1024 * 1024) as f:
        while True:
            data = f.read(chunk_size)
            if not data:
                break
            sha.update(data)
            conn.send(data)
            sent += len(data)
            now = time.time()
            if now - last_print >= 1.0 or sent >= size:
                print('[%s][registry-push] archived_bytes=%d total_bytes=%d percent=%.2f current_layer=registry current_file=upload' % (entrypoint, sent, total, min(100.0, 100.0 * sent / max(1, total))), flush=True)
                last_print = now
    resp = conn.getresponse()
    body = resp.read()
    headers = dict(resp.getheaders())
    status, reason = resp.status, resp.reason
    conn.close()
    if status not in (200,201,202,204):
        fail('PATCH layer upload -> %s %s %r' % (status, reason, body[:300]))
    digest = 'sha256:' + sha.hexdigest()
    finalize_upload(headers.get('Location') or headers.get('location') or location, digest)
    print('[%s][registry-push] DONE layer=registry tar_bytes=%d digest=%s' % (entrypoint, size, digest), flush=True)
    print('[%s][registry-push] archived_bytes=%d total_bytes=%d percent=100.00 complete=1' % (entrypoint, total, total), flush=True)
    return digest

def upload_blob(data):
    digest = 'sha256:' + hashlib.sha256(data).hexdigest()
    location = start_upload()
    finalize_upload(location, digest, data)
    return digest, len(data)

created = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
layer_digest = upload_tar_layer()
config = {
  'created': created,
  'architecture': 'amd64',
  'os': 'linux',
  'config': {'WorkingDir':'/home', 'Labels': labels},
  'rootfs': {'type':'layers', 'diff_ids':[layer_digest]},
  'history': [{'created':created, 'created_by':'mmenu direct registry tar push'}]
}
config_bytes = json.dumps(config, separators=(',',':')).encode('utf-8')
config_digest, config_size = upload_blob(config_bytes)
manifest = {
  'schemaVersion': 2,
  'mediaType': 'application/vnd.oci.image.manifest.v1+json',
  'config': {'mediaType':'application/vnd.oci.image.config.v1+json', 'digest':config_digest, 'size':config_size},
  'layers': [{'mediaType':'application/vnd.oci.image.layer.v1.tar', 'digest':layer_digest, 'size':size}]
}
manifest_bytes = json.dumps(manifest, separators=(',',':')).encode('utf-8')
registry_request('PUT', '/v2/%s/manifests/%s' % (repo, tag), body=manifest_bytes, extra={'Content-Type':'application/vnd.oci.image.manifest.v1+json','Content-Length':str(len(manifest_bytes))})
print('[%s][registry-push] manifest pushed image=%s layer=%s bytes=%d' % (entrypoint, image_ref, layer_digest, size), flush=True)
sys.exit(0)
'@
  [IO.File]::WriteAllText($scriptPath,$py,$utf8NoBom)
  try {
    $retryPolicy = Get-MmenuCRetryPolicy
    for($attempt=1; $attempt -le $retryPolicy.MaxAttempts; $attempt++){
      Write-MmenuC ("[$EntryPoint][registry-push] attempt {0}/{1} started: direct Docker Hub OCI push; image={2}" -f $attempt,$retryPolicy.MaxAttempts,$ImageRef)
      $parts = @((Quote-MmenuCArg $PythonExe))
      foreach($arg in @($PythonArgs)){ $parts += (Quote-MmenuCArg $arg) }
      foreach($arg in @($scriptPath,$TarPath,$ImageRef,$labelsPath,$credentialHelper,$EntryPoint,[string]$ContextTotalBytes)){ $parts += (Quote-MmenuCArg $arg) }
      $code = Invoke-MmenuCProcess -Label 'registry-push' -CommandLine ($parts -join ' ')
      if($code -eq 0){
        Write-MmenuC ("[$EntryPoint][registry-push] SUCCESS exit=0 attempt={0}: {1}" -f $attempt,$ImageRef) Green
        $global:LASTEXITCODE = 0
        return 0
      }
      $global:LASTEXITCODE = 0
      if($attempt -ge $retryPolicy.MaxAttempts -or (Get-Date) -ge $retryPolicy.Deadline){
        Write-MmenuC ("[$EntryPoint][registry-push] stopped after bounded retries; completed remote data remains reusable. attempts={0} exit={1} image={2}" -f $attempt,$code,$ImageRef) Red
        return [int]$code
      }
      Write-MmenuC ("[$EntryPoint][registry-push] recoverable registry failure exit={0} attempt={1}; retrying the existing tar: {2}" -f $code,$attempt,$ImageRef) Yellow
      $delay = [Math]::Min(300,[Math]::Max(5,10*$attempt))
      $retryStarted = Get-Date
      for($remaining=$delay; $remaining -gt 0; $remaining--){
        Write-MmenuCDashboard -Name $EntryPoint -Phase 'registry-push-retry' -Started $retryStarted -DoneBytes ($delay-$remaining) -TotalBytes $delay -Detail ("next direct registry push attempt in {0}s after exit={1}" -f $remaining,$code)
        Start-Sleep -Seconds 1
      }
      Write-Host ''
    }
  } finally {
    try { Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -LiteralPath $labelsPath -Force -ErrorAction SilentlyContinue } catch {}
  }
}
function Invoke-MmenuCCredentialHelper {
  param([Parameter(Mandatory=$true)][string]$Helper,[Parameter(Mandatory=$true)][string]$Server,[ValidateRange(1000,60000)][int]$TimeoutMilliseconds=30000)
  # Windows PowerShell 5 can prefix native pipeline input with a console BOM.
  # docker-credential-desktop treats that prefix as part of the lookup key and
  # returns exit 1 even though the credential exists. Send exact UTF-8 bytes.
  $start=New-Object Diagnostics.ProcessStartInfo
  $start.FileName=$Helper
  $start.Arguments='get'
  $start.UseShellExecute=$false
  $start.CreateNoWindow=$true
  $start.RedirectStandardInput=$true
  $start.RedirectStandardOutput=$true
  $start.RedirectStandardError=$true
  $process=New-Object Diagnostics.Process
  $process.StartInfo=$start
  try {
    if($start.PSObject.Properties['StandardInputEncoding']) {
      $start.StandardInputEncoding=New-Object Text.UTF8Encoding($false)
      [void]$process.Start()
    } else {
      $savedInputEncoding=[Console]::InputEncoding
      try {[Console]::InputEncoding=New-Object Text.UTF8Encoding($false);[void]$process.Start()}
      finally {[Console]::InputEncoding=$savedInputEncoding}
    }
    $outputTask=$process.StandardOutput.ReadToEndAsync()
    $errorTask=$process.StandardError.ReadToEndAsync()
    $inputBytes=[Text.Encoding]::UTF8.GetBytes($Server+"`n")
    try {
      $inputStream=$process.StandardInput.BaseStream
      $inputStream.Write($inputBytes,0,$inputBytes.Length)
      $inputStream.Close()
    } finally {[Array]::Clear($inputBytes,0,$inputBytes.Length)}
    if(-not $process.WaitForExit($TimeoutMilliseconds)){$process.Kill();throw 'Docker credential helper timed out.'}
    $output=$outputTask.GetAwaiter().GetResult()
    [void]$errorTask.GetAwaiter().GetResult()
    if($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
      throw ("Docker credential helper failed (exit {0})." -f $process.ExitCode)
    }
    return $output
  } finally {$process.Dispose()}
}
function Get-MmenuCDockerHubCredential {
  param([Parameter(Mandatory=$true)][string]$CredentialHelper)
  if($script:MmenuCDockerHubCredential -and
     -not [string]::IsNullOrWhiteSpace([string]$script:MmenuCDockerHubCredential.Username) -and
     -not [string]::IsNullOrWhiteSpace([string]$script:MmenuCDockerHubCredential.Secret)){
    return $script:MmenuCDockerHubCredential
  }
  $servers=@('https://index.docker.io/v1/','index.docker.io','https://registry-1.docker.io/','registry-1.docker.io')
  $lastCredentialError=$null
  for($recoveryPass=0;$recoveryPass -le 1;$recoveryPass++){
    $credentialDeadline=(Get-Date).AddSeconds($(if($recoveryPass -eq 0){3}else{30}))
    $attempt=0
    while(-not $script:MmenuCDockerHubCredential -and (Get-Date) -lt $credentialDeadline) {
      $attempt++
      foreach($server in $servers) {
        $candidateJson=$null;$candidate=$null
        try {
          $candidateJson=Invoke-MmenuCCredentialHelper -Helper $CredentialHelper -Server $server
          $candidate=$candidateJson | ConvertFrom-Json -ErrorAction Stop
          if(-not [string]::IsNullOrWhiteSpace([string]$candidate.Username) -and
             -not [string]::IsNullOrWhiteSpace([string]$candidate.Secret)) {
            $script:MmenuCDockerHubCredential=[pscustomobject]@{Username=[string]$candidate.Username;Secret=[string]$candidate.Secret}
            break
          }
          $lastCredentialError='helper returned an incomplete credential record'
        } catch {$lastCredentialError=$_.Exception.Message}
        finally {$candidateJson=$null;$candidate=$null}
      }
      if(-not $script:MmenuCDockerHubCredential -and (Get-Date) -lt $credentialDeadline){Start-Sleep -Milliseconds ([Math]::Min(1000,200*$attempt))}
    }
    if($script:MmenuCDockerHubCredential){break}
    if($recoveryPass -eq 0 -and -not $script:MmenuCDockerHubLoginAttempted){
      $script:MmenuCDockerHubLoginAttempted=$true
      $loginPath=@(
        $(if($PSScriptRoot){Join-Path $PSScriptRoot 'Invoke-DockerHubLogin.ps1'})
        'F:\study\Platforms\windows\functions\Invoke-DockerHubLogin.ps1'
      ) | Where-Object {$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)} | Select-Object -First 1
      if($loginPath){
        try {
          Write-MmenuC "[$EntryPoint][auth] Docker credential store was empty; restoring it from the current-user protected credential." Yellow
          & $loginPath | ForEach-Object {if(-not [string]::IsNullOrWhiteSpace([string]$_)){Write-MmenuC ("[$EntryPoint][auth] "+[string]$_) DarkGray}}
          if($LASTEXITCODE -and $LASTEXITCODE -ne 0){throw "protected Docker login exited with code $LASTEXITCODE"}
        } catch {$lastCredentialError=$_.Exception.Message}
      } else {
        $lastCredentialError='the protected Docker login repair script is unavailable'
      }
    }
  }
  if(-not $script:MmenuCDockerHubCredential) {
    throw ("${EntryPoint}: Docker Hub credential could not be restored after bounded retries. Last error: "+$lastCredentialError)
  }
  return $script:MmenuCDockerHubCredential
}
function Get-MmenuCDockerHubToken {
  param([Parameter(Mandatory=$true)][string]$Repository,[Parameter(Mandatory=$true)][string]$CredentialHelper,[string]$Scope='push,pull')
  $cred=Get-MmenuCDockerHubCredential -CredentialHelper $CredentialHelper
  $pair = ('{0}:{1}' -f ([string]$cred.Username),([string]$cred.Secret))
  $pairBytes=[Text.Encoding]::UTF8.GetBytes($pair)
  try {
    $basic = [Convert]::ToBase64String($pairBytes)
    $tokenUri = 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:' + [Uri]::EscapeDataString($Repository) + ':' + $Scope
    $response = Invoke-RestMethod -Uri $tokenUri -Method Get -Headers @{ Authorization = "Basic $basic"; 'User-Agent' = 'mmenu-direct-registry' } -TimeoutSec 60
    $token = $response.token
    $lifetime=if($response.expires_in){[int]$response.expires_in}else{60}
    $script:MmenuCTokenRefreshAt=(Get-Date).AddSeconds([Math]::Max(1,$lifetime-30))
    if([string]::IsNullOrWhiteSpace([string]$token)){ throw "${EntryPoint}: Docker Hub token was empty for $Repository." }
    return [string]$token
  } finally {
    [Array]::Clear($pairBytes,0,$pairBytes.Length)
    $pair=$null;$basic=$null;$cred=$null
  }
}
function Add-MmenuCRegistryDigestQuery {
  param([Parameter(Mandatory=$true)][string]$Location,[Parameter(Mandatory=$true)][string]$Digest)
  $uri = if($Location -match '^https?://'){ $Location } else { 'https://registry-1.docker.io' + $Location }
  $sep = if($uri.Contains('?')){ '&' } else { '?' }
  return $uri + $sep + 'digest=' + [Uri]::EscapeDataString($Digest)
}
function Invoke-MmenuCRegistryWebRequest {
  param(
    [Parameter(Mandatory=$true)][string]$Method,
    [Parameter(Mandatory=$true)][string]$Uri,
    [Parameter(Mandatory=$true)][string]$Token,
    [byte[]]$BodyBytes=$null,
    [string]$ContentType='application/octet-stream',
    [hashtable]$ExtraHeaders=@{}
  )
  $headers = @{ Authorization = "Bearer $Token"; 'User-Agent' = 'mmenu-direct-registry' }
  foreach($k in $ExtraHeaders.Keys){ $headers[$k] = $ExtraHeaders[$k] }
  $params = @{ Uri=$Uri; Method=$Method; Headers=$headers; UseBasicParsing=$true; TimeoutSec=180; ErrorAction='Stop' }
  if($null -ne $BodyBytes){ $params.Body = $BodyBytes; $params.ContentType = $ContentType }
  return Invoke-WebRequest @params
}
function Start-MmenuCRegistryUpload {
  param([Parameter(Mandatory=$true)][string]$Repository,[Parameter(Mandatory=$true)][string]$Token)
  $uri = "https://registry-1.docker.io/v2/$Repository/blobs/uploads/"
  $response = Invoke-MmenuCRegistryWebRequest -Method 'Post' -Uri $uri -Token $Token
  $location = $response.Headers['Location']
  if($location -is [array]){ $location = [string]$location[0] }
  if([string]::IsNullOrWhiteSpace([string]$location)){ throw "${EntryPoint}: Docker registry did not return an upload location." }
  return [string]$location
}
function Test-MmenuCRegistryBlobExists {
  param([Parameter(Mandatory=$true)][string]$Repository,[Parameter(Mandatory=$true)][string]$Digest,[Parameter(Mandatory=$true)][string]$Token)
  try {
    $uri = "https://registry-1.docker.io/v2/$Repository/blobs/$Digest"
    [void](Invoke-MmenuCRegistryWebRequest -Method 'Head' -Uri $uri -Token $Token 2>$null)
    return $true
  } catch {
    return $false
  }
}
function Get-MmenuCFileSha256WithProgress {
  param([Parameter(Mandatory=$true)][string]$FilePath,[Parameter(Mandatory=$true)][string]$Phase,[int64]$TotalBytes=0,[int64]$BaseDoneBytes=0)
  $fileSize = [int64](Get-Item -LiteralPath $FilePath).Length
  if($TotalBytes -le 0){ $TotalBytes = $fileSize }
  $sha = [Security.Cryptography.SHA256]::Create()
  $fs = $null
  $started = Get-Date
  $lastRender = [datetime]::MinValue
  $done = [int64]0
  try {
    $fs = [IO.File]::Open($FilePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $buffer = New-Object byte[] (8MB)
    while($true){
      $read = $fs.Read($buffer,0,$buffer.Length)
      if($read -le 0){ break }
      [void]$sha.TransformBlock($buffer,0,$read,$null,0)
      $done += [int64]$read
      $now = Get-Date
      if((New-TimeSpan -Start $lastRender -End $now).TotalMilliseconds -ge 250 -or $done -ge $fileSize){
        Write-MmenuCDashboard -Name $EntryPoint -Phase $Phase -Started $started -DoneBytes ([Math]::Min([int64]($BaseDoneBytes + $done),[int64]$TotalBytes)) -TotalBytes $TotalBytes -Detail 'sha256 tar digest'
        $lastRender = $now
      }
    }
    [void]$sha.TransformFinalBlock((New-Object byte[] 0),0,0)
    Write-MmenuCDashboard -Name $EntryPoint -Phase $Phase -Started $started -DoneBytes ([Math]::Min([int64]($BaseDoneBytes + $fileSize),[int64]$TotalBytes)) -TotalBytes $TotalBytes -Detail 'sha256 complete'
    return 'sha256:' + ([BitConverter]::ToString($sha.Hash).Replace('-','').ToLowerInvariant())
  } finally {
    if($fs){ $fs.Dispose() }
    if($sha){ $sha.Dispose() }
  }
}
function Get-MmenuCRegistryCurlTimeoutConfig {
  param([int64]$FileSize)
  $connectTimeout = 30
  if($env:HERMES_MMENU_CURL_CONNECT_TIMEOUT_SECONDS -match '^\d+$'){ $connectTimeout = [int]$env:HERMES_MMENU_CURL_CONNECT_TIMEOUT_SECONDS }
  $connectTimeout = [Math]::Max(5,[Math]::Min(300,$connectTimeout))
  $speedTime = Get-MmenuCLowSpeedGraceSeconds
  if($env:HERMES_MMENU_CURL_SPEED_TIME_SECONDS -match '^\d+$'){ $speedTime = [int]$env:HERMES_MMENU_CURL_SPEED_TIME_SECONDS }
  $speedTime = [Math]::Max(30,[Math]::Min(900,$speedTime))
  $speedLimit = [int64]([Math]::Max(32768,[Math]::Min(2MB,([double](Get-MmenuCMinSpeedBytesPerSecond) / 32.0))))
  if($env:HERMES_MMENU_CURL_SPEED_LIMIT_BPS -match '^\d+$'){ $speedLimit = [int64]$env:HERMES_MMENU_CURL_SPEED_LIMIT_BPS }
  $speedLimit = [Math]::Max([int64]1024,[Math]::Min([int64]128MB,[int64]$speedLimit))
  # Oversized source files must remain a single exact tar member/layer.  Curl's
  # max-time therefore has to scale with that layer, not with the nominal
  # 256-MiB target.  A fixed 30-minute (or shorter) cap deterministically kills
  # a healthy 20+ GiB upload at ordinary upstream rates.  The low-speed guard
  # still aborts a genuinely stalled transfer, so this generous size-derived
  # ceiling does not leave dead uploads running forever.
  $minimumTransferRate = [Math]::Max([double]64KB,[double]$speedLimit)
  $computedMaxTime = [int64][Math]::Ceiling((([double][Math]::Max([int64]1,$FileSize) / $minimumTransferRate) * 1.5) + 900.0)
  $maxTime = [int][Math]::Max(3600,[Math]::Min(604800,$computedMaxTime))
  # A caller may increase the safety window, but a stale small override may not
  # reintroduce the exact premature-timeout failure this function prevents.
  if($env:HERMES_MMENU_CURL_MAX_TIME_SECONDS -match '^\d+$'){
    $requestedMaxTime = [int64]$env:HERMES_MMENU_CURL_MAX_TIME_SECONDS
    $maxTime = [int][Math]::Max($maxTime,[Math]::Min(604800,$requestedMaxTime))
  }
  return [pscustomobject]@{ ConnectTimeout=$connectTimeout; SpeedTime=$speedTime; SpeedLimit=$speedLimit; MaxTime=$maxTime }
}
function Invoke-MmenuCRegistryCurlUploadFile {
  param(
    [Parameter(Mandatory=$true)][string]$CurlExe,
    [Parameter(Mandatory=$true)][string]$UploadUri,
    [Parameter(Mandatory=$true)][string]$Token,
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$true)][string]$ImageRef
  )
  $runId = [Guid]::NewGuid().ToString('N')
  $configPath = Join-MmenuCTempPath ("mmenu-curl-upload-$runId.config")
  $headerPath = Join-MmenuCTempPath ("mmenu-curl-upload-$runId.headers")
  $bodyPath = Join-MmenuCTempPath ("mmenu-curl-upload-$runId.body")
  $fileSize = [int64](Get-Item -LiteralPath $FilePath).Length
  $curlTimeout = Get-MmenuCRegistryCurlTimeoutConfig -FileSize $fileSize
  function Escape-CurlConfigValue([string]$s){ return ($s -replace '\\','\\' -replace '"','\"') }
  $config = @(
    'fail',
    'show-error',
    'silent',
    'http1.1',
    'tcp-nodelay',
    ('connect-timeout = {0}' -f [int]$curlTimeout.ConnectTimeout),
    ('max-time = {0}' -f [int]$curlTimeout.MaxTime),
    ('speed-limit = {0}' -f [int64]$curlTimeout.SpeedLimit),
    ('speed-time = {0}' -f [int]$curlTimeout.SpeedTime),
    'request = "PUT"',
    ('url = "{0}"' -f (Escape-CurlConfigValue $UploadUri)),
    ('upload-file = "{0}"' -f (Escape-CurlConfigValue $FilePath)),
    ('dump-header = "{0}"' -f (Escape-CurlConfigValue $headerPath)),
    ('output = "{0}"' -f (Escape-CurlConfigValue $bodyPath)),
    ('header = "Authorization: Bearer {0}"' -f $Token),
    'header = "Content-Type: application/octet-stream"',
    'header = "User-Agent: mmenu-direct-registry-curl"'
  ) -join "`n"
  [IO.File]::WriteAllText($configPath,$config,(New-Object System.Text.UTF8Encoding -ArgumentList $false))
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $CurlExe
  $psi.Arguments = '--config ' + (Quote-MmenuCArg $configPath)
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = New-Object Diagnostics.Process
  $p.StartInfo = $psi
  $started = Get-Date
  $curlDeadline = $started.AddSeconds([int]$curlTimeout.MaxTime + 30)
  $lastRender = [datetime]::MinValue
  try {
    [void]$p.Start()
    $baselineRead = Get-MmenuCProcessReadBytes -Process $p
    while(-not $p.WaitForExit(250)){
      if((Get-Date) -ge $curlDeadline){
        Stop-MmenuCProcessTree -Process $p
        throw "${EntryPoint}: curl registry upload exceeded its hard deadline."
      }
      $readBytes = [Math]::Min([int64]$fileSize,[int64]((Get-MmenuCProcessReadBytes -Process $p) - $baselineRead))
      $now = Get-Date
      if((New-TimeSpan -Start $lastRender -End $now).TotalMilliseconds -ge 250){
        Write-MmenuCDashboard -Name $EntryPoint -Phase 'registry-push' -Started $started -DoneBytes $readBytes -TotalBytes $fileSize -Detail 'curl registry upload'
        $lastRender = $now
      }
    }
    $p.WaitForExit()
    $code = [int]$p.ExitCode
    Write-MmenuCDashboard -Name $EntryPoint -Phase 'registry-push' -Started $started -DoneBytes $(if($code -eq 0){$fileSize}else{[Math]::Min([int64]$fileSize,[int64]((Get-MmenuCProcessReadBytes -Process $p) - $baselineRead))}) -TotalBytes $fileSize -Detail ("curl exit={0}" -f $code)
    if($code -ne 0){
      $err = ''
      try { $err = $p.StandardError.ReadToEnd() } catch {}
      throw "${EntryPoint}: curl registry upload failed exit=$code $err"
    }
    return 0
  } finally {
    Stop-MmenuCProcessTree -Process $p
    try { if($p){ $p.Dispose() } } catch {}
    try { Remove-Item -LiteralPath $configPath,$headerPath,$bodyPath -Force -ErrorAction SilentlyContinue } catch {}
  }
}
function Start-MmenuCRegistryCurlUploadProcess {
  param(
    [Parameter(Mandatory=$true)][string]$CurlExe,
    [Parameter(Mandatory=$true)][string]$UploadUri,
    [Parameter(Mandatory=$true)][string]$Token,
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$true)][string]$LayerName
  )
  $runId = [Guid]::NewGuid().ToString('N')
  $configPath = Join-MmenuCTempPath ("mmenu-curl-upload-$runId.config")
  $headerPath = Join-MmenuCTempPath ("mmenu-curl-upload-$runId.headers")
  $bodyPath = Join-MmenuCTempPath ("mmenu-curl-upload-$runId.body")
  $fileSize = [int64](Get-Item -LiteralPath $FilePath).Length
  $curlTimeout = Get-MmenuCRegistryCurlTimeoutConfig -FileSize $fileSize
  function Escape-CurlConfigValue([string]$s){ return ($s -replace '\\','\\' -replace '"','\"') }
  $config = @(
    'fail',
    'show-error',
    'silent',
    'http1.1',
    'tcp-nodelay',
    ('connect-timeout = {0}' -f [int]$curlTimeout.ConnectTimeout),
    ('max-time = {0}' -f [int]$curlTimeout.MaxTime),
    ('speed-limit = {0}' -f [int64]$curlTimeout.SpeedLimit),
    ('speed-time = {0}' -f [int]$curlTimeout.SpeedTime),
    'request = "PUT"',
    ('url = "{0}"' -f (Escape-CurlConfigValue $UploadUri)),
    ('upload-file = "{0}"' -f (Escape-CurlConfigValue $FilePath)),
    ('dump-header = "{0}"' -f (Escape-CurlConfigValue $headerPath)),
    ('output = "{0}"' -f (Escape-CurlConfigValue $bodyPath)),
    ('header = "Authorization: Bearer {0}"' -f $Token),
    'header = "Content-Type: application/octet-stream"',
    'header = "User-Agent: mmenu-direct-registry-parallel-curl"'
  ) -join "`n"
  if($env:HERMES_MMENU_GMENU -eq '1') {
    $endpoint=[uri]$UploadUri
    $addresses=@([Net.Dns]::GetHostAddresses($endpoint.DnsSafeHost) | Where-Object AddressFamily -eq ([Net.Sockets.AddressFamily]::InterNetwork) | ForEach-Object IPAddressToString)
    if($addresses.Count){$config += "`n"+('resolve = "{0}:{1}:{2}"' -f $endpoint.DnsSafeHost,$endpoint.Port,($addresses -join ','))}
  }
  [IO.File]::WriteAllText($configPath,$config,(New-Object System.Text.UTF8Encoding -ArgumentList $false))
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $CurlExe
  $psi.Arguments = '--config ' + (Quote-MmenuCArg $configPath)
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = New-Object Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $baselineRead = Get-MmenuCProcessReadBytes -Process $p
  return [pscustomobject]@{
    Process = $p
    ConfigPath = $configPath
    HeaderPath = $headerPath
    BodyPath = $bodyPath
    FilePath = $FilePath
    FileSize = $fileSize
    BaselineRead = [int64]$baselineRead
    LastReadBytes = [int64]0
    LayerName = $LayerName
    Started = (Get-Date)
    Transport = 'curl-monolithic'
  }
}
function Start-MmenuCRegistryChunkedUploadProcess {
  param(
    [Parameter(Mandatory=$true)][string]$UploadLocation,
    [Parameter(Mandatory=$true)][string]$Repository,
    [Parameter(Mandatory=$true)][string]$CredentialHelper,
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$true)][string]$LayerName,
    [Parameter(Mandatory=$true)][string]$Digest
  )
  $pythonExe=Get-MmenuCCommandPath @('py.exe','python.exe','python')
  if([string]::IsNullOrWhiteSpace($pythonExe)){throw "${EntryPoint}: Python 3 is required for resumable registry chunks."}
  $runId=[Guid]::NewGuid().ToString('N')
  $workerPath=Join-MmenuCTempPath ("mmenu-registry-chunked-$runId.py")
  $chunkMiB=128
  if($env:HERMES_MMENU_REGISTRY_CHUNK_MIB -match '^\d+$'){$chunkMiB=[Math]::Max(8,[Math]::Min(128,[int]$env:HERMES_MMENU_REGISTRY_CHUNK_MIB))}
  $workerText=@'
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

upload_url, repo, helper, file_path, digest, chunk_mib, state_path = sys.argv[1:8]
chunk_size = int(chunk_mib) * 1024 * 1024
registry = 'https://registry-1.docker.io'
user_agent = 'mmenu-resumable-registry-v1'

class PreserveMethodRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if code not in (307, 308):
            return super().redirect_request(req, fp, code, msg, headers, newurl)
        copied = dict(req.header_items())
        old_host = urllib.parse.urlsplit(req.full_url).netloc.lower()
        new_host = urllib.parse.urlsplit(newurl).netloc.lower()
        if old_host != new_host:
            copied.pop('Authorization', None)
        return urllib.request.Request(newurl, data=req.data, headers=copied, method=req.get_method())

opener = urllib.request.build_opener(PreserveMethodRedirect())

def absolute_location(base, value):
    if not value:
        raise RuntimeError('registry response omitted upload Location')
    return urllib.parse.urljoin(base, value)

def with_digest(value):
    # Upload Locations are opaque and can contain signed state.  Append only
    # the required digest, without parsing or re-encoding the existing query.
    separator = '&' if '?' in value else '?'
    return value + separator + 'digest=' + urllib.parse.quote(digest, safe=':')

def credential():
    last = 'empty credential response'
    for server in ('https://index.docker.io/v1/', 'index.docker.io', 'https://registry-1.docker.io/', 'registry-1.docker.io'):
        try:
            proc = subprocess.run([helper, 'get'], input=(server + '\n').encode('utf-8'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
            if proc.returncode != 0:
                last = 'credential helper exit %d' % proc.returncode
                continue
            raw = proc.stdout.decode('utf-8-sig', errors='strict').strip()
            record = json.loads(raw)
            username = str(record.get('Username') or '').strip()
            secret = str(record.get('Secret') or '').strip()
            if username and secret:
                return username, secret
        except Exception as exc:
            last = type(exc).__name__
    raise RuntimeError('Docker credential helper did not return a Docker Hub login: ' + last)

username, secret = credential()
token_value = None
token_refresh_at = 0.0

def refresh_token():
    global token_value, token_refresh_at
    query = urllib.parse.urlencode({'service': 'registry.docker.io', 'scope': 'repository:' + repo + ':push,pull'})
    request = urllib.request.Request('https://auth.docker.io/token?' + query, method='GET')
    request.add_header('Authorization', 'Basic ' + base64.b64encode((username + ':' + secret).encode('utf-8')).decode('ascii'))
    request.add_header('User-Agent', user_agent)
    with opener.open(request, timeout=60) as response:
        record = json.loads(response.read().decode('utf-8'))
    token_value = record.get('token') or record.get('access_token')
    if not token_value:
        raise RuntimeError('Docker Hub token service returned no token')
    lifetime = max(60, int(record.get('expires_in') or 300))
    token_refresh_at = time.time() + max(30, lifetime - 45)

def token(force=False):
    if force or not token_value or time.time() >= token_refresh_at:
        refresh_token()
    return token_value

def request(method, url, data=None, headers=None, force_token=False, timeout=300):
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('Authorization', 'Bearer ' + token(force_token))
    req.add_header('User-Agent', user_agent)
    for key, value in (headers or {}).items():
        req.add_header(key, value)
    with opener.open(req, timeout=timeout) as response:
        response.read()
        return response.status, dict(response.headers.items()), response.geturl()

def parse_offset(range_header, current_offset):
    if not range_header:
        return None
    match = re.search(r'(?:bytes=)?0-(\d+)', str(range_header))
    if not match:
        return None
    last = int(match.group(1))
    if last == 0 and current_offset == 0:
        return 0
    return last + 1

def start_upload():
    url = registry + '/v2/' + repo + '/blobs/uploads/'
    while True:
        try:
            status, headers, final_url = request('POST', url, data=b'', headers={'Content-Length': '0'}, timeout=120)
            if status != 202:
                raise RuntimeError('upload start status %d' % status)
            return absolute_location(final_url, headers.get('Location') or headers.get('location'))
        except urllib.error.HTTPError as exc:
            if exc.code == 401:
                token(True)
            elif exc.code == 429 or 500 <= exc.code < 600:
                time.sleep(10)
            else:
                raise
        except (urllib.error.URLError, TimeoutError, OSError):
            time.sleep(10)

def upload_status(url, current_offset):
    try:
        status, headers, final_url = request('GET', url, timeout=120)
        if status != 204:
            return url, None
        latest = absolute_location(final_url, headers.get('Location') or headers.get('location') or url)
        return latest, parse_offset(headers.get('Range') or headers.get('range'), current_offset)
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            token(True)
            return upload_status(url, current_offset)
        if exc.code in (404, 410):
            return start_upload(), 0
        return url, None
    except (urllib.error.URLError, TimeoutError, OSError):
        return url, None

def blob_exists():
    url = registry + '/v2/' + repo + '/blobs/' + urllib.parse.quote(digest, safe=':')
    try:
        status, _, _ = request('HEAD', url, timeout=120)
        return status == 200
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            token(True)
            return blob_exists()
        return False
    except (urllib.error.URLError, TimeoutError, OSError):
        return False

file_size = os.path.getsize(file_path)

def save_state(url, current_offset):
    record = {
        'version': 1,
        'url': url,
        'digest': digest,
        'file_size': file_size,
        'offset': int(current_offset),
        'updated': int(time.time()),
    }
    temporary = state_path + '.tmp'
    with open(temporary, 'w', encoding='utf-8') as stream:
        json.dump(record, stream, separators=(',', ':'))
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, state_path)

offset = 0
try:
    with open(state_path, 'r', encoding='utf-8-sig') as stream:
        saved = json.load(stream)
    if (str(saved.get('digest') or '').lower() == digest.lower()
            and int(saved.get('file_size') or -1) == file_size
            and str(saved.get('url') or '').startswith('http')):
        upload_url = str(saved['url'])
        upload_url, recovered = upload_status(upload_url, int(saved.get('offset') or 0))
        if recovered is not None:
            offset = recovered
except (FileNotFoundError, ValueError, TypeError, json.JSONDecodeError, OSError):
    pass
save_state(upload_url, offset)
retry_count = 0

with open(file_path, 'rb', buffering=0) as source:
    while offset < file_size:
        source.seek(offset)
        payload = source.read(min(chunk_size, file_size - offset))
        if not payload:
            raise RuntimeError('unexpected end of layer at byte %d' % offset)
        requested_start = offset
        requested_end = offset + len(payload) - 1
        while True:
            try:
                status, headers, final_url = request(
                    'PATCH', upload_url, data=payload,
                    headers={
                        'Content-Type': 'application/octet-stream',
                        'Content-Length': str(len(payload)),
                        'Content-Range': '%d-%d' % (requested_start, requested_end),
                    }, timeout=300)
                if status != 202:
                    raise RuntimeError('chunk status %d' % status)
                upload_url = absolute_location(final_url, headers.get('Location') or headers.get('location'))
                acknowledged = parse_offset(headers.get('Range') or headers.get('range'), requested_start)
                offset = requested_end + 1 if acknowledged is None else acknowledged
                if offset < requested_start or offset > requested_end + 1:
                    raise RuntimeError('registry returned an invalid upload range')
                save_state(upload_url, offset)
                retry_count = 0
                break
            except urllib.error.HTTPError as exc:
                if exc.code == 401:
                    token(True)
                    continue
                if exc.code == 416:
                    upload_url = absolute_location(upload_url, exc.headers.get('Location') or exc.headers.get('location') or upload_url)
                    recovered = parse_offset(exc.headers.get('Range') or exc.headers.get('range'), requested_start)
                    offset = requested_start if recovered is None else recovered
                    save_state(upload_url, offset)
                    break
                if exc.code in (404, 410):
                    upload_url = start_upload()
                    offset = 0
                    save_state(upload_url, offset)
                    break
                if exc.code != 429 and not (500 <= exc.code < 600):
                    raise
                retry_count += 1
                time.sleep(min(60, max(2, retry_count * 2)))
                upload_url, recovered = upload_status(upload_url, requested_start)
                if recovered is not None:
                    offset = recovered
                    save_state(upload_url, offset)
                    break
            except (urllib.error.URLError, TimeoutError, OSError):
                retry_count += 1
                time.sleep(min(60, max(2, retry_count * 2)))
                upload_url, recovered = upload_status(upload_url, requested_start)
                if recovered is not None:
                    offset = recovered
                    save_state(upload_url, offset)
                    break

while True:
    try:
        status, headers, final_url = request('PUT', with_digest(upload_url), data=b'', headers={'Content-Type': 'application/octet-stream', 'Content-Length': '0'}, timeout=300)
        if status != 201:
            raise RuntimeError('upload finalize status %d' % status)
        canonical = headers.get('Docker-Content-Digest') or headers.get('docker-content-digest')
        if canonical and canonical.lower() != digest.lower():
            raise RuntimeError('registry canonical digest mismatch')
        break
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            token(True)
            continue
        if blob_exists():
            break
        if exc.code in (404, 410):
            raise RuntimeError('registry upload session expired before finalization')
        if exc.code != 429 and not (500 <= exc.code < 600):
            raise
        time.sleep(10)
    except (urllib.error.URLError, TimeoutError, OSError):
        if blob_exists():
            break
        time.sleep(10)

if not blob_exists():
    raise RuntimeError('finalized layer was not readable by digest')
try:
    os.remove(state_path)
except FileNotFoundError:
    pass
print('MMENU_REGISTRY_CHUNKED_OK bytes=%d chunksize=%d' % (file_size, chunk_size), flush=True)
'@
  $workerEncoding=New-Object System.Text.UTF8Encoding -ArgumentList $false
  [IO.File]::WriteAllText($workerPath,$workerText,$workerEncoding)
  $pythonArgs=@()
  if((Split-Path -Leaf $pythonExe) -ieq 'py.exe'){$pythonArgs+='-3'}
  $statePath=$FilePath+'.upload-state.json'
  $arguments=@($workerPath,$UploadLocation,$Repository,$CredentialHelper,$FilePath,$Digest,[string]$chunkMiB,$statePath)
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$pythonExe
  $allArguments=@($pythonArgs)+@($arguments)
  $psi.Arguments=(($allArguments | ForEach-Object {Quote-MmenuCArg $_}) -join ' ')
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $process=New-Object Diagnostics.Process
  $process.StartInfo=$psi
  [void]$process.Start()
  $fileSize=[int64](Get-Item -LiteralPath $FilePath).Length
  $baselineRead=Get-MmenuCProcessReadBytes -Process $process
  return [pscustomobject]@{
    Process=$process
    ConfigPath=$null
    HeaderPath=$null
    BodyPath=$null
    WorkerPath=$workerPath
    StatePath=$statePath
    FilePath=$FilePath
    FileSize=$fileSize
    BaselineRead=[int64]$baselineRead
    LastReadBytes=[int64]0
    LayerName=$LayerName
    Started=(Get-Date)
    Transport='registry-chunked'
  }
}
function Remove-MmenuCRegistryCurlUploadProcessFiles {
  param([Parameter(Mandatory=$true)]$Upload)
  try { if($Upload.Process -and -not $Upload.Process.HasExited){ $Upload.Process.Kill() } } catch {}
  try { if($Upload.Process){ $Upload.Process.Dispose() } } catch {}
  try { Remove-Item -LiteralPath $Upload.ConfigPath,$Upload.HeaderPath,$Upload.BodyPath -Force -ErrorAction SilentlyContinue } catch {}
  try { if($Upload.WorkerPath){ Remove-Item -LiteralPath $Upload.WorkerPath -Force -ErrorAction SilentlyContinue } } catch {}
}
function Invoke-MmenuCRegistryPutBlobBytes {
  param([Parameter(Mandatory=$true)][string]$Repository,[Parameter(Mandatory=$true)][string]$Token,[Parameter(Mandatory=$true)][byte[]]$Bytes)
  $digest = 'sha256:' + ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($Bytes)).Replace('-','').ToLowerInvariant())
  if(-not (Test-MmenuCRegistryBlobExists -Repository $Repository -Digest $digest -Token $Token)){
    $location = Start-MmenuCRegistryUpload -Repository $Repository -Token $Token
    $uploadUri = Add-MmenuCRegistryDigestQuery -Location $location -Digest $digest
    [void](Invoke-MmenuCRegistryWebRequest -Method 'Put' -Uri $uploadUri -Token $Token -BodyBytes $Bytes -ContentType 'application/octet-stream')
  }
  return [pscustomobject]@{ Digest=$digest; Size=[int64]$Bytes.Length }
}
function Invoke-MmenuCCurlRegistryPushLayersUntilSuccess {
  param(
    [Parameter(Mandatory=$true)][string]$DockerExe,
    [Parameter(Mandatory=$true)][string[]]$LayerPaths,
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [Parameter(Mandatory=$true)][System.Collections.IDictionary]$Labels
  )
  if($LayerPaths.Count -le 0){ throw "Direct registry layer push received no layer paths." }
  foreach($lp in $LayerPaths){ if(-not (Test-Path -LiteralPath $lp -PathType Leaf)){ throw "Direct registry layer not found: $lp" } }
  $curlExe = Join-Path (Get-MmenuCWindowsRoot) 'System32\curl.exe'
  if(-not (Test-Path -LiteralPath $curlExe -PathType Leaf)){ throw "${EntryPoint}: native curl.exe not found at $curlExe" }
  $dockerDir = Split-Path -Parent $DockerExe
  $credentialHelper = Join-Path $dockerDir 'docker-credential-desktop.exe'
  if(-not (Test-Path -LiteralPath $credentialHelper -PathType Leaf)){ throw "Docker credential helper missing for direct registry push: $credentialHelper" }
  $imageParts = Split-MmenuCImageRef -ImageRef $ImageRef
  $repo = [string]$imageParts.Repository
  $tag = [string]$imageParts.Tag
  $layers = @()
  $totalLayerBytes = [int64]0
  foreach($lp in $LayerPaths){
    $name = Split-Path -Leaf $lp
    $size = [int64](Get-Item -LiteralPath $lp).Length
    $layers += [pscustomobject]@{ Name=$name; Path=$lp; Size=$size; Digest=''; Retries=0 }
    $totalLayerBytes += $size
  }
  $maxParallel = 6
  if($env:HERMES_MMENU_REGISTRY_PARALLEL_UPLOADS -match '^\d+$'){ $maxParallel = [int]$env:HERMES_MMENU_REGISTRY_PARALLEL_UPLOADS }
  $maxParallel = [Math]::Max(1,[Math]::Min(64,$maxParallel))
  $chunkedThresholdBytes=[int64]512MB
  if($env:HERMES_MMENU_REGISTRY_CHUNKED_THRESHOLD_MIB -match '^\d+$'){
    $chunkedThresholdBytes=[int64][Math]::Max(64,[Math]::Min(4096,[int]$env:HERMES_MMENU_REGISTRY_CHUNKED_THRESHOLD_MIB))*1MB
  }
  $hashesComputed = $false
  # Network/registry failures retry until the final manifest is verified.  A
  # finite cap exists only when the caller explicitly opts out via the env var.
  $maxAttempts = 0
  if($env:HERMES_MMENU_PUSH_MAX_ATTEMPTS -match '^\d+$'){ $maxAttempts = [Math]::Max(1,[Math]::Min(100000,[int]$env:HERMES_MMENU_PUSH_MAX_ATTEMPTS)) }
  $attempt=0
  while($true){
    $attempt++
    $active = @()
    try {
      $attemptDisplay=if($maxAttempts -gt 0){"$attempt/$maxAttempts"}else{"$attempt/until-success"}
      Write-MmenuC ("[$EntryPoint][registry-push] attempt {0} started: resumable Docker Hub OCI multilayer push; layers={1}; parallel={2}; image={3}" -f $attemptDisplay,$layers.Count,$maxParallel,$ImageRef)
      if(-not $hashesComputed){
        $hashStarted = Get-Date
        $hashedBytes = [int64]0
        foreach($layer in $layers){
          $layer.Digest = Get-MmenuCFileSha256WithProgress -FilePath $layer.Path -Phase 'registry-hash' -TotalBytes $totalLayerBytes -BaseDoneBytes $hashedBytes
          $hashedBytes += [int64]$layer.Size
          Write-MmenuCDashboard -Name $EntryPoint -Phase 'registry-hash' -Started $hashStarted -DoneBytes $hashedBytes -TotalBytes $totalLayerBytes -Detail ("hashed {0}/{1} {2}" -f ([Array]::IndexOf($layers,$layer)+1),$layers.Count,$layer.Name)
        }
        $hashesComputed = $true
      } else {
        Write-MmenuC ("[$EntryPoint][registry-hash] reusing cached layer digests after retry; no re-hash needed") DarkGray
      }
      $token = Get-MmenuCDockerHubToken -Repository $repo -CredentialHelper $credentialHelper -Scope 'push,pull'
      $pending = New-Object System.Collections.Queue
      $missingLayers = @()
      $remoteBytes = [int64]0
      $remoteLayers = 0
      foreach($layer in $layers){
        if(Test-MmenuCRegistryBlobExists -Repository $repo -Digest ([string]$layer.Digest) -Token $token){
          $remoteBytes += [int64]$layer.Size
          $remoteLayers++
          Write-MmenuC ("[$EntryPoint][registry-push] layer blob already exists remotely: {0} {1}" -f $layer.Name,$layer.Digest) DarkGray
        } else {
          $missingLayers += $layer
        }
      }
      foreach($layer in @($missingLayers | Sort-Object -Property Size -Descending)){
        $pending.Enqueue($layer)
      }
      if($missingLayers.Count -gt 1){
        Write-MmenuC ("[$EntryPoint][registry-push] upload order optimized: largest missing layers start first; missing_layers={0}" -f $missingLayers.Count) DarkGray
      }
      $pushStarted = Get-Date
      $guardState = @{}
      $lastRender = [datetime]::MinValue
      while($pending.Count -gt 0 -or $active.Count -gt 0){
        while($active.Count -lt $maxParallel -and $pending.Count -gt 0){
          $layer = $pending.Dequeue()
          if((Get-Date) -ge $script:MmenuCTokenRefreshAt){$token=Get-MmenuCDockerHubToken -Repository $repo -CredentialHelper $credentialHelper -Scope 'push,pull'}
          try {$location = Start-MmenuCRegistryUpload -Repository $repo -Token $token}
          catch {
            if($_.Exception.Message -notmatch '401|Unauthorized'){throw}
            $token=Get-MmenuCDockerHubToken -Repository $repo -CredentialHelper $credentialHelper -Scope 'push,pull'
            $location=Start-MmenuCRegistryUpload -Repository $repo -Token $token
          }
          if([int64]$layer.Size -ge $chunkedThresholdBytes){
            $active += (Start-MmenuCRegistryChunkedUploadProcess -UploadLocation $location -Repository $repo -CredentialHelper $credentialHelper -FilePath ([string]$layer.Path) -LayerName ([string]$layer.Name) -Digest ([string]$layer.Digest))
            Write-MmenuC ("[$EntryPoint][registry-push] resumable chunk transport started for oversized layer={0} bytes={1}" -f $layer.Name,$layer.Size) DarkGray
          } else {
            $uploadUri = Add-MmenuCRegistryDigestQuery -Location $location -Digest ([string]$layer.Digest)
            $active += (Start-MmenuCRegistryCurlUploadProcess -CurlExe $curlExe -UploadUri $uploadUri -Token $token -FilePath ([string]$layer.Path) -LayerName ([string]$layer.Name))
          }
        }
        $activeBytes = [int64]0
        foreach($upload in @($active)){
          if($upload.Process.HasExited -and [int]$upload.Process.ExitCode -eq 0){
            $readBytes = [int64]$upload.FileSize
          } else {
            $readBytes = [Math]::Min([int64]$upload.FileSize,[Math]::Max([int64]$upload.LastReadBytes,[int64]((Get-MmenuCProcessReadBytes -Process $upload.Process) - [int64]$upload.BaselineRead)))
          }
          $upload.LastReadBytes = [int64]$readBytes
          $activeBytes += $readBytes
        }
        $doneBytes = [Math]::Min([int64]$totalLayerBytes,[int64]($remoteBytes + $activeBytes))
        $now = Get-Date
        if((New-TimeSpan -Start $lastRender -End $now).TotalMilliseconds -ge 1000){
          Write-MmenuCDashboard -Name $EntryPoint -Phase 'registry-push' -Started $pushStarted -DoneBytes $doneBytes -TotalBytes $totalLayerBytes -Detail ("parallel registry uploads active={0} queued={1} done_layers={2}/{3}" -f $active.Count,$pending.Count,$remoteLayers,$layers.Count)
          $lastRender = $now
        }
        $hasResumableWorker=@($active | Where-Object { $_.Transport -eq 'registry-chunked' }).Count -gt 0
        if(-not $hasResumableWorker -and (Update-MmenuCLowSpeedGuard -State $guardState -Phase 'registry-push' -Started $pushStarted -DoneBytes $doneBytes -TotalBytes $totalLayerBytes -Detail 'parallel registry upload')){
          foreach($upload in @($active)){ Remove-MmenuCRegistryCurlUploadProcessFiles -Upload $upload }
          throw "${EntryPoint}: registry push made no byte progress long enough to require retry."
        }
        $stillActive = @()
        foreach($upload in @($active)){
          if($upload.Process.HasExited){
            $code = [int]$upload.Process.ExitCode
            if($code -ne 0){
              $err = ''
              try { $err = $upload.Process.StandardError.ReadToEnd() } catch {}
              $failedLayer=$layers | Where-Object Name -eq $upload.LayerName | Select-Object -First 1
              $failedLayer.Retries++
              Remove-MmenuCRegistryCurlUploadProcessFiles -Upload $upload
              $pending.Enqueue($failedLayer)
              if($code -eq 22){$script:MmenuCTokenRefreshAt=[datetime]::MinValue}
              Write-MmenuC ("[$EntryPoint][registry-push] retry layer={0} attempt={1}/until-success transport_exit={2}; completed blobs and other active uploads are preserved" -f $failedLayer.Name,$failedLayer.Retries,$code) Yellow
              continue
            }
            $remoteBytes += [int64]$upload.FileSize
            $remoteLayers++
            Remove-MmenuCRegistryCurlUploadProcessFiles -Upload $upload
          } else {
            $stillActive += $upload
          }
        }
        $active = $stillActive
        if($pending.Count -gt 0 -or $active.Count -gt 0){ Start-Sleep -Milliseconds 250 }
      }
      Write-MmenuCDashboard -Name $EntryPoint -Phase 'registry-push' -Started $pushStarted -DoneBytes $totalLayerBytes -TotalBytes $totalLayerBytes -Detail ("parallel registry upload complete layers={0}" -f $layers.Count)
      $token = Get-MmenuCDockerHubToken -Repository $repo -CredentialHelper $credentialHelper -Scope 'push,pull'
      $created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
      $labelObject = [ordered]@{}
      foreach($k in $Labels.Keys){ $labelObject[[string]$k] = [string]$Labels[$k] }
      $diffIds = @()
      $manifestLayers = @()
      foreach($layer in $layers){
        $diffIds += [string]$layer.Digest
        $manifestLayers += [ordered]@{ mediaType = 'application/vnd.oci.image.layer.v1.tar'; digest = [string]$layer.Digest; size = [int64]$layer.Size }
      }
      $history = @()
      foreach($layer in $layers){ $history += [ordered]@{ created = $created; created_by = ('mmenu native curl direct registry layer push ' + [string]$layer.Name) } }
      $config = [ordered]@{
        created = $created
        architecture = 'amd64'
        os = 'linux'
        config = [ordered]@{ WorkingDir = '/home'; Labels = $labelObject }
        rootfs = [ordered]@{ type = 'layers'; diff_ids = [object[]]$diffIds }
        history = [object[]]$history
      }
      $configBytes = [Text.Encoding]::UTF8.GetBytes(($config | ConvertTo-Json -Compress -Depth 20))
      $configBlob = Invoke-MmenuCRegistryPutBlobBytes -Repository $repo -Token $token -Bytes $configBytes
      $manifest = [ordered]@{
        schemaVersion = 2
        mediaType = 'application/vnd.oci.image.manifest.v1+json'
        config = [ordered]@{ mediaType = 'application/vnd.oci.image.config.v1+json'; digest = $configBlob.Digest; size = [int64]$configBlob.Size }
        layers = [object[]]$manifestLayers
      }
      $manifestBytes = [Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Compress -Depth 20))
      $manifestUri = "https://registry-1.docker.io/v2/$repo/manifests/$tag"
      [void](Invoke-MmenuCRegistryWebRequest -Method 'Put' -Uri $manifestUri -Token $token -BodyBytes $manifestBytes -ContentType 'application/vnd.oci.image.manifest.v1+json')
      Write-MmenuC ("[$EntryPoint][registry-push] SUCCESS resumable direct registry multilayer push complete: {0}" -f $ImageRef) Green
      $global:LASTEXITCODE = 0
      return 0
    } catch {
      foreach($upload in @($active)){ Remove-MmenuCRegistryCurlUploadProcessFiles -Upload $upload }
      if($_.Exception -is [System.Management.Automation.PipelineStoppedException]){ throw }
      $global:LASTEXITCODE = 0
      Write-MmenuC ("[$EntryPoint][registry-push] recoverable registry failure attempt={0}: {1}" -f $attempt,$_.Exception.Message) Yellow
      if($maxAttempts -gt 0 -and $attempt -ge $maxAttempts){
        Write-MmenuC ("[$EntryPoint][registry-push] caller-specified retry cap reached; completed remote layer blobs remain reusable. attempts={0} image={1}" -f $attempt,$ImageRef) Red
        return 1
      }
      $delay = [Math]::Min(300,[Math]::Max(5,10*$attempt))
      $retryStarted = Get-Date
      for($remaining=$delay; $remaining -gt 0; $remaining--){
        Write-MmenuCDashboard -Name $EntryPoint -Phase 'registry-push-retry' -Started $retryStarted -DoneBytes ($delay-$remaining) -TotalBytes $delay -Detail ("next native registry push attempt in {0}s" -f $remaining)
        Start-Sleep -Seconds 1
      }
      Write-Host ''
    }
  }
}
function Invoke-MmenuCCurlRegistryPushUntilSuccess {
  param(
    [Parameter(Mandatory=$true)][string]$DockerExe,
    [Parameter(Mandatory=$true)][string]$TarPath,
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [Parameter(Mandatory=$true)][System.Collections.IDictionary]$Labels
  )
  if(-not (Test-Path -LiteralPath $TarPath -PathType Leaf)){ throw "Direct registry tar not found: $TarPath" }
  $curlExe = Join-Path (Get-MmenuCWindowsRoot) 'System32\curl.exe'
  if(-not (Test-Path -LiteralPath $curlExe -PathType Leaf)){ throw "${EntryPoint}: native curl.exe not found at $curlExe" }
  $dockerDir = Split-Path -Parent $DockerExe
  $credentialHelper = Join-Path $dockerDir 'docker-credential-desktop.exe'
  if(-not (Test-Path -LiteralPath $credentialHelper -PathType Leaf)){ throw "Docker credential helper missing for direct registry push: $credentialHelper" }
  $imageParts = Split-MmenuCImageRef -ImageRef $ImageRef
  $repo = [string]$imageParts.Repository
  $tag = [string]$imageParts.Tag
  $tarBytes = [int64](Get-Item -LiteralPath $TarPath).Length
  $retryPolicy = Get-MmenuCRetryPolicy
  for($attempt=1; $attempt -le $retryPolicy.MaxAttempts; $attempt++){
    try {
      Write-MmenuC ("[$EntryPoint][registry-push] attempt {0}/{1} started: native curl direct Docker Hub OCI push; image={2}" -f $attempt,$retryPolicy.MaxAttempts,$ImageRef)
      $token = Get-MmenuCDockerHubToken -Repository $repo -CredentialHelper $credentialHelper -Scope 'push,pull'
      $layerDigest = Get-MmenuCFileSha256WithProgress -FilePath $TarPath -Phase 'registry-hash' -TotalBytes $tarBytes
      if(Test-MmenuCRegistryBlobExists -Repository $repo -Digest $layerDigest -Token $token){
        Write-MmenuC "[$EntryPoint][registry-push] layer blob already exists remotely: $layerDigest" DarkGray
      } else {
        $location = Start-MmenuCRegistryUpload -Repository $repo -Token $token
        $uploadUri = Add-MmenuCRegistryDigestQuery -Location $location -Digest $layerDigest
        [void](Invoke-MmenuCRegistryCurlUploadFile -CurlExe $curlExe -UploadUri $uploadUri -Token $token -FilePath $TarPath -ImageRef $ImageRef)
      }
      $created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
      $labelObject = [ordered]@{}
      foreach($k in $Labels.Keys){ $labelObject[[string]$k] = [string]$Labels[$k] }
      $config = [ordered]@{
        created = $created
        architecture = 'amd64'
        os = 'linux'
        config = [ordered]@{ WorkingDir = '/home'; Labels = $labelObject }
        rootfs = [ordered]@{ type = 'layers'; diff_ids = @($layerDigest) }
        history = @([ordered]@{ created = $created; created_by = 'mmenu native curl direct registry tar push' })
      }
      $configBytes = [Text.Encoding]::UTF8.GetBytes(($config | ConvertTo-Json -Compress -Depth 20))
      $configBlob = Invoke-MmenuCRegistryPutBlobBytes -Repository $repo -Token $token -Bytes $configBytes
      $manifest = [ordered]@{
        schemaVersion = 2
        mediaType = 'application/vnd.oci.image.manifest.v1+json'
        config = [ordered]@{ mediaType = 'application/vnd.oci.image.config.v1+json'; digest = $configBlob.Digest; size = [int64]$configBlob.Size }
        layers = @([ordered]@{ mediaType = 'application/vnd.oci.image.layer.v1.tar'; digest = $layerDigest; size = $tarBytes })
      }
      $manifestBytes = [Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Compress -Depth 20))
      $manifestUri = "https://registry-1.docker.io/v2/$repo/manifests/$tag"
      [void](Invoke-MmenuCRegistryWebRequest -Method 'Put' -Uri $manifestUri -Token $token -BodyBytes $manifestBytes -ContentType 'application/vnd.oci.image.manifest.v1+json')
      Write-MmenuC ("[$EntryPoint][registry-push] SUCCESS native curl direct registry push complete: {0}" -f $ImageRef) Green
      $global:LASTEXITCODE = 0
      return 0
    } catch {
      if($_.Exception -is [System.Management.Automation.PipelineStoppedException]){ throw }
      $global:LASTEXITCODE = 0
      Write-MmenuC ("[$EntryPoint][registry-push] recoverable registry failure attempt={0}: {1}" -f $attempt,$_.Exception.Message) Yellow
      if($attempt -ge $retryPolicy.MaxAttempts -or (Get-Date) -ge $retryPolicy.Deadline){
        Write-MmenuC ("[$EntryPoint][registry-push] stopped after bounded retries; completed remote blob remains reusable. attempts={0} image={1}" -f $attempt,$ImageRef) Red
        return 1
      }
      $delay = [Math]::Min(300,[Math]::Max(5,10*$attempt))
      $retryStarted = Get-Date
      for($remaining=$delay; $remaining -gt 0; $remaining--){
        Write-MmenuCDashboard -Name $EntryPoint -Phase 'registry-push-retry' -Started $retryStarted -DoneBytes ($delay-$remaining) -TotalBytes $delay -Detail ("next native registry push attempt in {0}s" -f $remaining)
        Start-Sleep -Seconds 1
      }
      Write-Host ''
    }
  }
}
function Invoke-MmenuCDockerLoadArchiveUntilSuccess {
  param(
    [Parameter(Mandatory=$true)][string]$DockerExe,
    [Parameter(Mandatory=$true)][string]$ArchivePath,
    [Parameter(Mandatory=$true)][string]$ImageRef,
    [int64]$ContextTotalBytes=0,
    [string]$ExpectedSourcePath='',
    [string]$ExpectedRepository='',
    [string]$ExpectedTagName='',
    [int64]$ExpectedSourceBytes=0,
    [int64]$ExpectedSourceFiles=0
  )
  if(-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)){ throw "Docker load archive not found: $ArchivePath" }
  $archiveBytes = [int64](Get-Item -LiteralPath $ArchivePath).Length
  $totalBytes = if($ContextTotalBytes -gt 0){ [int64]$ContextTotalBytes } else { $archiveBytes }
  $dockerDir = Split-Path -Parent $DockerExe
  $retryPolicy = Get-MmenuCRetryPolicy -DefaultAttempts 3 -DefaultMinutes 30 -AttemptsEnvironmentName 'HERMES_MMENU_LOCAL_MAX_ATTEMPTS' -MinutesEnvironmentName 'HERMES_MMENU_LOCAL_MAX_MINUTES'
  for($attempt=1; $attempt -le $retryPolicy.MaxAttempts; $attempt++){
    $started = Get-Date
    Write-MmenuC ("[$EntryPoint][load] attempt {0}/{1} started: Docker load --input archive={2}; image={3}" -f $attempt,$retryPolicy.MaxAttempts,(Format-MmenuCMiB $archiveBytes),$ImageRef)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $DockerExe
    $psi.Arguments = 'load --input ' + (Quote-MmenuCArg $ArchivePath)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $tempRootForProcess = Get-MmenuCTempRoot
    $psi.WorkingDirectory = $tempRootForProcess
    $psi.EnvironmentVariables['TEMP'] = $tempRootForProcess
    $psi.EnvironmentVariables['TMP'] = $tempRootForProcess
    if($dockerDir -and (Test-Path -LiteralPath $dockerDir -PathType Container)){
      $oldPathForChild = [string]$psi.EnvironmentVariables['PATH']
      if($oldPathForChild -notlike "*$dockerDir*"){ $psi.EnvironmentVariables['PATH'] = "$dockerDir;$oldPathForChild" }
    }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $sent = [int64]$archiveBytes
    $code = -1
    $stdout = New-Object System.Text.StringBuilder
    $stderr = New-Object System.Text.StringBuilder
    $lastProgressLineAt = [datetime]::MinValue
    $loadMaxSeconds = [Math]::Max([double]1.0,($retryPolicy.Deadline-(Get-Date)).TotalSeconds)
    $floorBytes = Get-MmenuCMinSpeedBytesPerSecond
    if($floorBytes -gt 0){ $loadMaxSeconds = [Math]::Min($loadMaxSeconds,[Math]::Max([double](Get-MmenuCLowSpeedGraceSeconds), [double]$archiveBytes / [double]$floorBytes)) }
    try{
      $p.add_OutputDataReceived({
        param($sender,$eventArgs)
        if($eventArgs.Data){
          [void]$stdout.AppendLine($eventArgs.Data)
          Write-MmenuC ("[$EntryPoint][load-output] {0}" -f $eventArgs.Data) DarkGray
        }
      })
      $p.add_ErrorDataReceived({
        param($sender,$eventArgs)
        if($eventArgs.Data){
          [void]$stderr.AppendLine($eventArgs.Data)
          Write-MmenuC ("[$EntryPoint][load-error] {0}" -f $eventArgs.Data) Yellow
        }
      })
      [void]$p.Start()
      $p.BeginOutputReadLine()
      $p.BeginErrorReadLine()
      while(-not $p.WaitForExit(1000)){
        $elapsedText = [int][Math]::Max(0,((Get-Date)-$started).TotalSeconds)
        $detail = ("Docker loading archive from disk elapsed={0}s archive={1}" -f $elapsedText,(Format-MmenuCMiB $archiveBytes))
        Write-MmenuCDashboard -Name $EntryPoint -Phase 'load' -Started $started -DoneBytes $sent -TotalBytes $totalBytes -Detail $detail
        if([double]$elapsedText -gt $loadMaxSeconds){
          Write-Host ''
          Write-MmenuC ("[$EntryPoint][speed-floor] load exceeded target floor {0}/s for archive {1}; aborting docker load attempt for retry" -f (Format-MmenuCMiB $floorBytes),(Format-MmenuCMiB $archiveBytes)) Yellow
          Stop-MmenuCProcessTree -Process $p
          break
        }
        if(((Get-Date)-$lastProgressLineAt).TotalSeconds -ge 1){
          Write-MmenuC ("[$EntryPoint][progress:load] 100.00% {0}/{1} elapsed={2}s active; Docker loading archive from disk" -f (Format-MmenuCMiB $sent),(Format-MmenuCMiB $totalBytes),$elapsedText) DarkGray
          $lastProgressLineAt = Get-Date
        }
      }
      try { $p.WaitForExit() } catch { }
      $code = [int]$p.ExitCode
    } catch {
      Write-MmenuC ("[$EntryPoint][load] error: {0}" -f $_.Exception.Message) Yellow
      Stop-MmenuCProcessTree -Process $p
      $code = -1
    } finally {
      if($p){ $p.Dispose() }
    }
    Write-MmenuCDashboard -Name $EntryPoint -Phase 'load' -Started $started -DoneBytes $sent -TotalBytes $totalBytes -Detail ("exit={0}" -f $code)
    if($code -eq 0){
      Write-MmenuC ("[$EntryPoint][load] SUCCESS exit=0 attempt={0}: {1}" -f $attempt,$ImageRef) Green
      $global:LASTEXITCODE = 0
      return 0
    }
    if(
      -not [string]::IsNullOrWhiteSpace($ExpectedSourcePath) -and
      -not [string]::IsNullOrWhiteSpace($ExpectedRepository) -and
      -not [string]::IsNullOrWhiteSpace($ExpectedTagName) -and
      $ExpectedSourceBytes -gt 0 -and
      $ExpectedSourceFiles -gt 0 -and
      (Test-MmenuCLocalExactImage -DockerExe $DockerExe -ImageRef $ImageRef -SourcePath $ExpectedSourcePath -Repository $ExpectedRepository -TagName $ExpectedTagName -SourceBytes $ExpectedSourceBytes -SourceFiles $ExpectedSourceFiles)
    ){
      Write-MmenuC ("[$EntryPoint][load] SUCCESS exact image verified after docker load exit={0}; treating stale Docker exit code as non-fatal and continuing to push: {1}" -f $code,$ImageRef) Green
      $global:LASTEXITCODE = 0
      return 0
    }
    $global:LASTEXITCODE = 0
    if($attempt -ge $retryPolicy.MaxAttempts -or (Get-Date) -ge $retryPolicy.Deadline){
      Write-MmenuC ("[$EntryPoint][load] stopped after bounded retries; archive remains intact. attempts={0} exit={1} image={2}" -f $attempt,$code,$ImageRef) Red
      $global:LASTEXITCODE = [int]$code
      return [int]$code
    }
    Write-MmenuC ("[$EntryPoint][load] recoverable Docker failure exit={0} attempt={1}; retrying the existing archive: {2}" -f $code,$attempt,$ImageRef) Yellow
    $delay = [Math]::Min(300,[Math]::Max(5,10*$attempt))
    $retryStarted = Get-Date
    for($remaining=$delay; $remaining -gt 0; $remaining--){
      Write-MmenuCDashboard -Name $EntryPoint -Phase 'load-retry' -Started $retryStarted -DoneBytes ($delay-$remaining) -TotalBytes $delay -Detail ("next attempt in {0}s after exit={1}" -f $remaining,$code)
      Start-Sleep -Seconds 1
    }
    Write-Host ''
  }
}
function Invoke-MmenuCProcess {
  param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$CommandLine,[int]$HeartbeatSeconds=1,[string]$WatchPath='',[int64]$WatchTotalBytes=0,[string]$WorkingDirectory='',[string]$ManifestImageRef='',[string]$ManifestDockerExe='',[ValidateRange(1,240)][int]$MaxMinutes=60)
  if($env:HERMES_MMENU_COMMAND_MAX_MINUTES -match '^\d+$'){ $MaxMinutes = [Math]::Max(1,[Math]::Min(240,[int]$env:HERMES_MMENU_COMMAND_MAX_MINUTES)) }
  $hardDeadline = (Get-Date).AddMinutes($MaxMinutes)
  $ps5Exe = Join-Path (Get-MmenuCWindowsRoot) 'System32\WindowsPowerShell\v1.0\powershell.exe'; $started = Get-Date
  Write-MmenuC "[$EntryPoint][docker:$Label] START $(Get-Date -Format 'HH:mm:ss')"
  $outOffset=[int64]0; $errOffset=[int64]0; $done=0L; $total=0L; $detail='starting'; $lastRender=Get-Date
  $stdoutCarry = ''
  $stderrCarry = ''
  function Update-MmenuCProcessLine([string]$Line){
    $s=[string]$Line
    if([string]::IsNullOrWhiteSpace($s)){ return }
    if($s -match 'archived_bytes=(\d+)\s+total_bytes=(\d+)\s+percent=.*current_layer=([^\s]+)(?:.*current_file=([^\s]+))?'){
      $script:MmenuCProcessDone=[int64]$matches[1]; $script:MmenuCProcessTotal=[int64]$matches[2]; $script:MmenuCProcessDetail=if($matches[4]){"$($matches[3]) $($matches[4])"}else{$matches[3]}
      Write-MmenuCDashboard -Name $EntryPoint -Phase $Label -Started $started -DoneBytes $script:MmenuCProcessDone -TotalBytes $script:MmenuCProcessTotal -Detail $script:MmenuCProcessDetail
      $script:MmenuCProcessLastRender=Get-Date
    } elseif($s -match 'total_bytes=(\d+).*chunks=(\d+).*files=(\d+).*dirs=(\d+)') {
      $script:MmenuCProcessTotal=[int64]$matches[1]
      Write-Host ''; Write-MmenuC "[$EntryPoint][$Label] plan: $(Format-MmenuCMiB $script:MmenuCProcessTotal), chunks=$($matches[2]), files=$($matches[3]), dirs=$($matches[4])"
    } elseif($s -match 'START layer=|DONE layer=|chunk-warning|complete=1') {
      Write-MmenuC $s DarkGray
    } elseif($s -match 'transferring context:') {
      $marker = 'transferring context:'
      $rest = $s.Substring($s.IndexOf($marker) + $marker.Length).Trim()
      $tok = ($rest -split ' ')[0]
      $numPart = ($tok -replace '[^.0-9]','').Trim()
      $unitPart = ($tok -replace '[0-9.]','').Trim()
      if($numPart.Length -gt 0){
        $ctxBytes = Convert-MmenuCBuildKitSizeToBytes -Number $numPart -Unit $unitPart
        if($ctxBytes -gt $script:MmenuCProcessDone){
          $script:MmenuCProcessDone = [int64]$ctxBytes
          if($script:MmenuCProcessTotal -le 0 -and $WatchTotalBytes -gt 0){ $script:MmenuCProcessTotal = [int64]$WatchTotalBytes }
          $script:MmenuCProcessDetail = ('context {0}' -f (Format-MmenuCMiB $ctxBytes))
          if($ctxBytes -ge 1MB){
            if($script:MmenuCProcessTotal -gt 0){
              $ctxPct = [Math]::Min([double]100.0,[Math]::Round(100.0 * [double]$ctxBytes / [Math]::Max([double]1.0,[double]$script:MmenuCProcessTotal),2))
              Write-MmenuC ("[$EntryPoint][$Label] context {0} / {1} ({2:N2}%)" -f (Format-MmenuCMiB $ctxBytes),(Format-MmenuCMiB $script:MmenuCProcessTotal),$ctxPct) DarkGray
            } else {
              Write-MmenuC ("[$EntryPoint][$Label] context {0}" -f (Format-MmenuCMiB $ctxBytes)) DarkGray
            }
          }
        }
      }
    } else {
      if($s -match '^The push refers to repository'){ return }
      if($s -match '^([a-f0-9]{12,64}):\s+(.+)$'){
        $layerKey = $matches[1]
        $layerRest = ([string]$matches[2]).Trim()
        $layerStatus = ([string]($layerRest -replace '\[[^\]]*\]','' -replace '[0-9]+(?:\.[0-9]+)?\s*(?:B|KB|MB|GB|TB|KiB|MiB|GiB|TiB)\s*/\s*[0-9]+(?:\.[0-9]+)?\s*(?:B|KB|MB|GB|TB|KiB|MiB|GiB|TiB)','' -replace '\s+[0-9]+(?:\.[0-9]+)?\s*(?:B|KB|MB|GB|TB|KiB|MiB|GiB|TiB)\s*$','')).Trim()
        if([string]::IsNullOrWhiteSpace($layerStatus)){ $layerStatus = $layerRest }
        if($Label -eq 'push'){
          $bytePair = [regex]::Match($layerRest,'(?<done>[0-9]+(?:\.[0-9]+)?\s*(?:B|KB|MB|GB|TB|KiB|MiB|GiB|TiB))\s*/\s*(?<total>[0-9]+(?:\.[0-9]+)?\s*(?:B|KB|MB|GB|TB|KiB|MiB|GiB|TiB))','IgnoreCase')
          if($bytePair.Success){
            $layerDoneBytes = ConvertFrom-MmenuCPushSizeText $bytePair.Groups['done'].Value
            $layerTotalBytes = ConvertFrom-MmenuCPushSizeText $bytePair.Groups['total'].Value
            if($layerDoneBytes -gt 0 -and $layerTotalBytes -gt 0){
              if(-not $script:MmenuCProcessLayerBytes.ContainsKey($layerKey)){ $script:MmenuCProcessLayerBytes[$layerKey] = @{ Done = 0L; Total = 0L } }
              $script:MmenuCProcessLayerBytes[$layerKey].Done = [int64]$layerDoneBytes
              $script:MmenuCProcessLayerBytes[$layerKey].Total = [int64]$layerTotalBytes
              $aggDone = 0L
              $aggTotal = 0L
              foreach($k in @($script:MmenuCProcessLayerBytes.Keys)){
                $aggDone += [int64]$script:MmenuCProcessLayerBytes[$k].Done
                $aggTotal += [int64]$script:MmenuCProcessLayerBytes[$k].Total
              }
              if($aggTotal -gt 0 -and $aggDone -gt [int64]$script:MmenuCProcessDone){
                $script:MmenuCProcessDone = [int64]$aggDone
                $script:MmenuCProcessTotal = [int64]$aggTotal
                $pushPct = [Math]::Min([double]100.0,[Math]::Round(100.0 * [double]$aggDone / [Math]::Max([double]1.0,[double]$aggTotal),2))
                $script:MmenuCProcessDetail = ('context {0} / {1}' -f (Format-MmenuCMiB $aggDone),(Format-MmenuCMiB $aggTotal))
                Write-MmenuC ("[$EntryPoint][$Label] context {0} / {1} ({2:N2}%)" -f (Format-MmenuCMiB $aggDone),(Format-MmenuCMiB $aggTotal),$pushPct) DarkGray
              }
            }
          }
        }
        $oldLayerStatus = if($script:MmenuCProcessLayerLast.ContainsKey($layerKey)){ [string]$script:MmenuCProcessLayerLast[$layerKey] } else { '' }
        if($oldLayerStatus -ne $layerStatus){
          $script:MmenuCProcessLayerLast[$layerKey] = $layerStatus
          if($layerStatus -match '^(Waiting|Preparing|Pushing)$'){ return }
          if($layerStatus -match 'Pushed|Layer already exists|Mounted from|Exists'){ Write-MmenuC ("[$EntryPoint][$Label] {0}: {1}" -f $layerKey,$layerStatus) Green }
          else { Write-MmenuC ("[$EntryPoint][$Label] {0}: {1}" -f $layerKey,$layerStatus) Gray }
        }
        return
      }
      if($s -match 'error|failed|denied|unauthorized|forbidden|timeout|refused|reset|EOF'){ Write-MmenuC $s Yellow }
      $t2 = $s.Trim()
      if($t2.Length -gt 0){
        $script:MmenuCProcessDetail = if($t2.Length -gt 72){ $t2.Substring(0,72) } else { $t2 }
        $script:MmenuCProcessLastRender = [datetime]::MinValue
      }
    }
  }
  function Add-MmenuCProcessText([string]$Text,[string]$CarryName){
    if([string]::IsNullOrEmpty($Text)){ return }
    $script:MmenuCProcessLastActivity = Get-Date
    $combined = [string](Get-Variable -Name $CarryName -Scope Script -ValueOnly -ErrorAction SilentlyContinue) + $Text
    $parts = [regex]::Split($combined,"`r`n|`n|`r")
    if($combined -match "(`r`n|`n|`r)$"){
      for($i=0; $i -lt $parts.Count; $i++){ if($parts[$i].Length -gt 0){ Update-MmenuCProcessLine $parts[$i] } }
      Set-Variable -Name $CarryName -Scope Script -Value ''
    } else {
      for($i=0; $i -lt ($parts.Count - 1); $i++){ if($parts[$i].Length -gt 0){ Update-MmenuCProcessLine $parts[$i] } }
      Set-Variable -Name $CarryName -Scope Script -Value ([string]$parts[$parts.Count - 1])
    }
  }
  function Complete-MmenuCProcessRead($Stream,$AsyncResult,[byte[]]$Buffer,[string]$CarryName,[ref]$Done){
    if($null -eq $AsyncResult){ $Done.Value=$true; return $null }
    if(-not $AsyncResult.IsCompleted){ return $AsyncResult }
    try{
      $count=$Stream.EndRead($AsyncResult)
      if($count -le 0){ $Done.Value=$true; return $null }
      Add-MmenuCProcessText -Text ([Text.Encoding]::UTF8.GetString($Buffer,0,$count)) -CarryName $CarryName
      return $Stream.BeginRead($Buffer,0,$Buffer.Length,$null,$null)
    } catch {
      $Done.Value=$true
      return $null
    }
  }
  $p = New-Object Diagnostics.Process
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $ps5Exe
  $innerCommand = '$ErrorActionPreference=''Continue''; & ' + $CommandLine + '; exit $LASTEXITCODE'
  $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($innerCommand))
  $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $encodedCommand
  if(-not [string]::IsNullOrWhiteSpace($WorkingDirectory)){ $psi.WorkingDirectory = $WorkingDirectory }
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p.StartInfo = $psi
  try {
    $script:MmenuCProcessDone=0L
    $script:MmenuCProcessTotal=0L
    $script:MmenuCProcessDetail='starting'
    $script:MmenuCProcessStdoutCarry=''
    $script:MmenuCProcessStderrCarry=''
    $script:MmenuCProcessLastRender=Get-Date
    $script:MmenuCProcessLastHeartbeatLine=Get-Date
    $script:MmenuCProcessLastHeartbeatDone = -1L
    $script:MmenuCProcessLastManifestCheck=Get-Date
    $script:MmenuCProcessLastActivity = Get-Date
    $script:MmenuCProcessLayerLast = @{}
    $script:MmenuCProcessLayerBytes = @{}
    $script:MmenuCNetBaseBytes = 0L
    $script:MmenuCNetLastPrintedBytes = 0L
    $script:MmenuCNetLineStepBytes = 0L
    if($WatchTotalBytes -gt 0){ $script:MmenuCProcessTotal = [int64]$WatchTotalBytes }
    if($Label -eq 'push' -and $WatchTotalBytes -gt 0){
      $netBaseNow = Get-MmenuCNetworkSentBytes
      $script:MmenuCNetBaseBytes = [int64]$netBaseNow
      $script:MmenuCNetLineStepBytes = [Math]::Max([int64]1MB,[int64]($WatchTotalBytes / 2000))
    }
    [void]$p.Start()
    $outBuffer = New-Object byte[] 65536
    $errBuffer = New-Object byte[] 65536
    $outDone = $false
    $errDone = $false
    $outAsync = $p.StandardOutput.BaseStream.BeginRead($outBuffer,0,$outBuffer.Length,$null,$null)
    $errAsync = $p.StandardError.BaseStream.BeginRead($errBuffer,0,$errBuffer.Length,$null,$null)
    $exitSeenAt = $null
    while(-not ($p.HasExited -and $outDone -and $errDone)){
      if((Get-Date) -ge $hardDeadline){
        Write-MmenuC ("[$EntryPoint][docker:$Label] hard deadline reached after {0} minutes; stopping the child process tree cleanly." -f $MaxMinutes) Yellow
        Stop-MmenuCProcessTree -Process $p
        Write-Host ''
        return 124
      }
      $outAsync = Complete-MmenuCProcessRead $p.StandardOutput.BaseStream $outAsync $outBuffer 'MmenuCProcessStdoutCarry' ([ref]$outDone)
      $errAsync = Complete-MmenuCProcessRead $p.StandardError.BaseStream $errAsync $errBuffer 'MmenuCProcessStderrCarry' ([ref]$errDone)
      if($p.HasExited){
        if($null -eq $exitSeenAt){ $exitSeenAt = Get-Date }
        if(((Get-Date)-$exitSeenAt).TotalMilliseconds -ge 2000){
          $outDone = $true
          $errDone = $true
          break
        }
      }
      if(((Get-Date)-$script:MmenuCProcessLastRender).TotalMilliseconds -ge 250){
        Write-MmenuCDashboard -Name $EntryPoint -Phase $Label -Started $started -DoneBytes $script:MmenuCProcessDone -TotalBytes $script:MmenuCProcessTotal -Detail $script:MmenuCProcessDetail
        if($Label -eq 'push' -and $script:MmenuCNetBaseBytes -gt 0 -and $WatchTotalBytes -gt 0 -and $script:MmenuCProcessLayerBytes.Count -eq 0){
          $netNowPush = Get-MmenuCNetworkSentBytes
          if($netNowPush -gt $script:MmenuCNetBaseBytes){
            $netDeltaPush = [int64]($netNowPush - $script:MmenuCNetBaseBytes)
            $netClampedPush = [Math]::Min($netDeltaPush,[int64]$WatchTotalBytes)
            if($netClampedPush -gt ([int64]$script:MmenuCNetLastPrintedBytes + [int64]$script:MmenuCNetLineStepBytes)){
              $script:MmenuCNetLastPrintedBytes = $netClampedPush
              $script:MmenuCProcessDone = $netClampedPush
              $script:MmenuCProcessTotal = [int64]$WatchTotalBytes
              $netPctPush = [Math]::Min([double]100.0,[Math]::Round(100.0 * [double]$netClampedPush / [Math]::Max([double]1.0,[double]$WatchTotalBytes),2))
              $script:MmenuCProcessDetail = ('context {0} / {1}' -f (Format-MmenuCMiB $netClampedPush),(Format-MmenuCMiB $WatchTotalBytes))
              Write-MmenuC ("[$EntryPoint][$Label] context {0} / {1} ({2:N2}%)" -f (Format-MmenuCMiB $netClampedPush),(Format-MmenuCMiB $WatchTotalBytes),$netPctPush) DarkGray
            }
          }
        }
        $script:MmenuCProcessLastRender=Get-Date
      }
      if(((Get-Date)-$script:MmenuCProcessLastHeartbeatLine).TotalMilliseconds -ge 1000){
        if(-not [string]::IsNullOrWhiteSpace($WatchPath) -and (Test-Path -LiteralPath $WatchPath -PathType Leaf)){
          try {
            $watchBytes = [int64](Get-Item -LiteralPath $WatchPath -Force).Length
            if($WatchTotalBytes -gt 0){ $script:MmenuCProcessTotal = [int64]$WatchTotalBytes }
            if($watchBytes -gt $script:MmenuCProcessDone){
              if($script:MmenuCProcessTotal -gt 0){ $script:MmenuCProcessDone = [int64][Math]::Min([double]$watchBytes,[double]$script:MmenuCProcessTotal) }
              else { $script:MmenuCProcessDone = $watchBytes }
              $script:MmenuCProcessDetail = "watchdog=$([IO.Path]::GetFileName($WatchPath)) bytes=$watchBytes; $script:MmenuCProcessDetail"
              Write-Host ''
              Write-MmenuC ("[$EntryPoint][progress:$Label] watchdog=1 path={0} bytes={1}" -f $WatchPath,$watchBytes) Cyan
            }
          } catch { }
        }
        $script:MmenuCProcessLastHeartbeatLine=Get-Date
      }
      if(
        -not [string]::IsNullOrWhiteSpace($ManifestImageRef) -and
        -not [string]::IsNullOrWhiteSpace($ManifestDockerExe) -and
        ((Get-Date)-$script:MmenuCProcessLastActivity).TotalSeconds -ge 45 -and
        ((Get-Date)-$script:MmenuCProcessLastManifestCheck).TotalSeconds -ge 30
      ){
        $script:MmenuCProcessLastManifestCheck=Get-Date
        if(Test-MmenuCRemoteManifest -DockerExe $ManifestDockerExe -ImageRef $ManifestImageRef){
          Write-MmenuC ("[$EntryPoint][$Label] remote manifest verified; Docker Hub has the image, releasing Docker client: {0}" -f $ManifestImageRef) Green
          try { if($p -and -not $p.HasExited){ $p.Kill() } } catch { }
          Write-MmenuCDashboard -Name $EntryPoint -Phase $Label -Started $started -DoneBytes ([Math]::Max([int64]$script:MmenuCProcessDone,[int64]$WatchTotalBytes)) -TotalBytes $WatchTotalBytes -Detail 'remote manifest verified'
          Write-Host ''
          return 0
        }
      }
      Start-Sleep -Milliseconds 50
    }
    if(-not [string]::IsNullOrEmpty($script:MmenuCProcessStdoutCarry)){ Update-MmenuCProcessLine $script:MmenuCProcessStdoutCarry }
    if(-not [string]::IsNullOrEmpty($script:MmenuCProcessStderrCarry)){ Update-MmenuCProcessLine $script:MmenuCProcessStderrCarry }
    $p.WaitForExit(); $p.Refresh()
    $code=[int]$p.ExitCode
    if($code -eq 0 -and $Label -eq 'push' -and $script:MmenuCProcessTotal -gt 0 -and $script:MmenuCProcessDone -lt $script:MmenuCProcessTotal){
      $script:MmenuCProcessDone = $script:MmenuCProcessTotal
      Write-MmenuC ("[$EntryPoint][$Label] context {0} / {1} (100.00%)" -f (Format-MmenuCMiB $script:MmenuCProcessTotal),(Format-MmenuCMiB $script:MmenuCProcessTotal)) DarkGray
    }
    if($code -eq 0 -and $script:MmenuCProcessTotal -gt 0){$script:MmenuCProcessDone=$script:MmenuCProcessTotal}
    Write-MmenuCDashboard -Name $EntryPoint -Phase $Label -Started $started -DoneBytes $script:MmenuCProcessDone -TotalBytes $script:MmenuCProcessTotal -Detail "exit=$code"
    Write-Host ''
    return [int]$code
  } finally {
    Stop-MmenuCProcessTree -Process $p
    try { if($p){ $p.Dispose() } } catch { }
    Remove-Variable -Name MmenuCProcessDone,MmenuCProcessTotal,MmenuCProcessDetail,MmenuCProcessStdoutCarry,MmenuCProcessStderrCarry,MmenuCProcessLastRender,MmenuCProcessLastHeartbeatLine,MmenuCProcessLastManifestCheck,MmenuCProcessLastActivity,MmenuCProcessLayerLast,MmenuCProcessLayerBytes,MmenuCNetBaseBytes,MmenuCNetLastPrintedBytes,MmenuCNetLineStepBytes -Scope Script -ErrorAction SilentlyContinue
  }
}

if($false -and -not $InternalWorker -and -not $PreflightOnly -and -not $TarPreflightOnly -and -not $BuildPreflightOnly){
  $outerCode = Invoke-MmenuCOuterMonitor
  $global:LASTEXITCODE = [int]$outerCode
  return
}

$projectItem=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
if(-not $projectItem.PSIsContainer){throw "${EntryPoint}: source path is not a folder: $Path"}
$projectPath=[IO.Path]::GetFullPath($projectItem.FullName)
$projectRoot=[IO.Path]::GetPathRoot($projectPath)
if($projectPath.TrimEnd([char]92,[char]47) -ieq $projectRoot.TrimEnd([char]92,[char]47)){
  throw "${EntryPoint}: source must be a folder below a drive or network-share root: $projectPath"
}
$folderName=[IO.Path]::GetFileName($projectPath.TrimEnd([char]92,[char]47))
if([string]::IsNullOrWhiteSpace($folderName)){ throw "${EntryPoint}: could not derive Docker tag name from path: $projectPath" }
$repoSlug = Convert-MmenuCSlug $folderName 128
if($env:HERMES_MMENU_REPOSITORY_OVERRIDE -or $env:HERMES_MMENU_TAG_OVERRIDE) {
  if($env:HERMES_MMENU_REPOSITORY_OVERRIDE -notmatch '^michadockermisha/[a-z0-9][a-z0-9._-]{0,99}$' -or
     $env:HERMES_MMENU_TAG_OVERRIDE -notmatch '^gmenu-[0-9]{14}-[a-f0-9]{8}$') { throw 'Invalid gmenu repository/tag override.' }
  $repository = [string]$env:HERMES_MMENU_REPOSITORY_OVERRIDE
  $tagName = [string]$env:HERMES_MMENU_TAG_OVERRIDE
}
elseif($EntryPoint -ieq 'mmenu') { $repository = 'michadockermisha/backup'; $tagName = ConvertTo-MmenuCFolderTag $folderName 128 }
else { $repository = "michadockermisha/$repoSlug"; $tagName = Get-MmenuCNextDockerHubTag -Repository $repository }
$imageRef = "${repository}:$tagName"
$dockerExeOverridden = $false
$dockerExeOverride = [string]$env:HERMES_MMENU_DOCKER_EXE_OVERRIDE
if(-not [string]::IsNullOrWhiteSpace($dockerExeOverride) -and (Test-Path -LiteralPath $dockerExeOverride -PathType Leaf)){
  $dockerExe = (Resolve-Path -LiteralPath $dockerExeOverride).ProviderPath
  $dockerExeOverridden = $true
} else {
  $dockerExe = Get-MmenuCCommandPath @('docker.exe','docker','docker.cmd')
  if([string]::IsNullOrWhiteSpace($dockerExe)){
    foreach($programFilesRoot in @([string]$env:ProgramFiles,[string]${env:ProgramFiles(x86)})){
      if([string]::IsNullOrWhiteSpace($programFilesRoot)){continue}
      $candidate = Join-Path $programFilesRoot 'Docker\Docker\resources\bin\docker.exe'
      if(Test-Path -LiteralPath $candidate -PathType Leaf){$dockerExe=(Resolve-Path -LiteralPath $candidate).ProviderPath;break}
    }
  }
}
if([string]::IsNullOrWhiteSpace($dockerExe)){ throw "${EntryPoint}: docker executable not found." }
$dockerBin = Split-Path -Parent $dockerExe
$dockerCredentialDesktop = Join-Path $dockerBin 'docker-credential-desktop.exe'
if((-not $dockerExeOverridden) -and -not (Test-Path -LiteralPath $dockerCredentialDesktop -PathType Leaf)){
  throw "${EntryPoint}: Docker credential helper missing: $dockerCredentialDesktop"
}
$oldPath = $env:PATH
$pathParts = @([string]$env:PATH -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if(-not ($pathParts | Where-Object { $_.TrimEnd('\') -ieq $dockerBin.TrimEnd('\') })){
  $env:PATH = $dockerBin + ';' + [string]$env:PATH
}
$pythonExe = Get-MmenuCCommandPath @('py.exe','python.exe','python')
$pyPrefix = if($pythonExe -and (Split-Path -Leaf $pythonExe) -ieq 'py.exe'){' -3'}else{''}
$targetBytes = [int64]$TargetLayerMiB * 1MB
$effectiveTargetLayerMiB = [int64]$TargetLayerMiB
$fastThresholdMiB = 256
if($env:HERMES_DOCKER_FAST_BACKUP_THRESHOLD_MIB -match '^\d+$'){ $fastThresholdMiB=[int]$env:HERMES_DOCKER_FAST_BACKUP_THRESHOLD_MIB }
$fastThresholdBytes = [int64]$fastThresholdMiB * 1MB
Write-MmenuC "[$EntryPoint] Source: $projectPath"
Write-MmenuC "[$EntryPoint] Image:  $imageRef"
if($EntryPoint -ieq 'mmenu') {
  if($env:HERMES_MMENU_REPOSITORY_OVERRIDE) { Write-MmenuC "[$EntryPoint] Repository mode: gmenu per-app encrypted backup ($imageRef)." }
  else { Write-MmenuC "[$EntryPoint] Repository mode: legacy mmenu shared repository + folder tag (michadockermisha/backup:$tagName)." }
} else {
  Write-MmenuC "[$EntryPoint] Repository mode: own Docker Hub repository (michadockermisha/$repoSlug); numeric tags pushed previously=$script:MmenuCLastNumericTagCount; highest numeric tag=$script:MmenuCLastHighestNumericTag; selected new tag=$tagName."
}
Write-MmenuC "[$EntryPoint] Docker path: $dockerExe"
$tmpSuffix = [Guid]::NewGuid().ToString('N')
$fastDockerfileName = ".hermes-docker-fast-$tmpSuffix.Dockerfile"
$fastIgnoreName = "$fastDockerfileName.dockerignore"
$stats = Get-MmenuCSourceStats -Root $projectPath -IgnoreNames @($fastDockerfileName,$fastIgnoreName) -ProgressName $EntryPoint
if($stats.Bad.Count -gt 0){ $stats.Bad | ForEach-Object { Write-MmenuC "[$EntryPoint][context-error] $_" Red }; throw "${EntryPoint}: source contains unreadable entries; refusing to publish smaller/incomplete image." }
$fingerprintShort = ''
if(-not [string]::IsNullOrWhiteSpace([string]$stats.Fingerprint)){
  $fingerprintShort = ([string]$stats.Fingerprint).Substring(0,[Math]::Min(16,([string]$stats.Fingerprint).Length))
}
Write-MmenuC ("[$EntryPoint][scan] source={0} files={1} dirs={2} unreadable=0 fingerprint={3}" -f (Format-MmenuCMiB ([int64]$stats.TotalBytes)), $stats.Files, $stats.Dirs, $fingerprintShort)
$maxAutoLayers = 96
if($env:HERMES_MMENU_MAX_LAYERS -match '^\d+$'){ $maxAutoLayers = [int]$env:HERMES_MMENU_MAX_LAYERS }
$maxAutoLayers = [Math]::Max(24,[Math]::Min(256,$maxAutoLayers))
if(([int64]$stats.TotalBytes) -gt 0 -and $targetBytes -gt 0){
  $estimatedLayers = [Math]::Ceiling(([double]([int64]$stats.TotalBytes)) / [double]$targetBytes)
  if($estimatedLayers -gt $maxAutoLayers){
    $adaptiveMiB = [int64][Math]::Ceiling((([double]([int64]$stats.TotalBytes)) / [double]$maxAutoLayers) / 1MB)
    $adaptiveMiB = [Math]::Max([int64]$TargetLayerMiB,[Math]::Min([int64]4096,$adaptiveMiB))
    if($adaptiveMiB -gt $effectiveTargetLayerMiB){
      $effectiveTargetLayerMiB = [int64]$adaptiveMiB
      $targetBytes = [int64]$effectiveTargetLayerMiB * 1MB
      Write-MmenuC ("[$EntryPoint][chunk-plan] adaptive target layer={0} MiB to keep estimated layers <= {1} for Docker usability and parallel push stability" -f $effectiveTargetLayerMiB,$maxAutoLayers) DarkGray
    }
  }
}
$buildxMaxMiB = $fastThresholdMiB
$forceImportTarEnv = $false
$forceLoadArchive = $false
$largeSourceDirectImport = ([int64]$stats.TotalBytes -gt $fastThresholdBytes)
if($env:HERMES_MMENU_GMENU -eq '1'){$largeSourceDirectImport=$true}
$autoDirectImportTar = $largeSourceDirectImport
$useDockerfileBuildx = -not $largeSourceDirectImport
if($largeSourceDirectImport -and $effectiveTargetLayerMiB -gt 256){
  $effectiveTargetLayerMiB = 256
  $targetBytes = [int64]$effectiveTargetLayerMiB * 1MB
  Write-MmenuC ("[$EntryPoint][chunk-plan] large source detected; regular files are grouped near {0} MiB; any single oversized file remains exact in one layer and receives a size-derived upload window" -f $effectiveTargetLayerMiB) DarkGray
}
if($largeSourceDirectImport -and [string]::IsNullOrWhiteSpace($pythonExe)){
  throw "${EntryPoint}: a verified Python 3 runtime is unavailable for the complete tar-layer path. The Microsoft Store execution alias is not a Python runtime."
}
if($useDockerfileBuildx){
$vmmEnforcer = @(
  $(if($PSScriptRoot){Join-Path $PSScriptRoot 'Set-DockerHyperV.ps1'}),
  'F:\study\Platforms\windows\functions\Set-DockerHyperV.ps1'
) | Where-Object {$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)} | Select-Object -First 1
if(-not $vmmEnforcer){ throw "${EntryPoint}: Docker VMM enforcer was not found in the local fallback or canonical source location." }
try {
  $vmmSelfTestOutput=@(& $vmmEnforcer -SelfTest)
  $vmmSelfTestJson=@($vmmSelfTestOutput | Where-Object { [string]$_ -match '^\s*\{.*"Mode"\s*:\s*"SelfTest"' } | Select-Object -Last 1)
  if(-not $vmmSelfTestJson.Count){ throw 'Docker VMM enforcer returned no self-test record.' }
  $vmmSelfTestRecord=$vmmSelfTestJson[0] | ConvertFrom-Json -ErrorAction Stop
  if(-not [bool]$vmmSelfTestRecord.Exists){ throw 'Docker VMM enforcer self-test reported its implementation missing.' }
} catch {
  throw ("${EntryPoint}: Docker VMM preflight failed before payload creation: " + $_.Exception.Message)
}
}
try {
  $credentialPreflightToken=Get-MmenuCDockerHubToken -Repository $repository -CredentialHelper $dockerCredentialDesktop -Scope 'push,pull'
  if([string]::IsNullOrWhiteSpace([string]$credentialPreflightToken)){throw 'Docker Hub returned an empty push token.'}
} catch {
  throw ("${EntryPoint}: Docker Hub credential preflight failed before payload creation: " + $_.Exception.Message)
} finally {$credentialPreflightToken=$null}
if($PreflightOnly){
  $strategyText = if($useDockerfileBuildx){ 'small-source Dockerfile build once, followed by bounded push-only retries' } else { 'large-source 256 MiB multilayer direct Docker Hub upload with parallel resumable layer checks and no rebuild after network failure' }
  [pscustomobject]@{ EntryPoint=$EntryPoint; Source=$projectPath; Image=$imageRef; Repository=$repository; RepoSlug=$repoSlug; Tag=$tagName; NumericTagForOwnRepo=($EntryPoint -ine 'mmenu'); ExistingNumericTags=[int64]$script:MmenuCLastNumericTagCount; HighestNumericTag=[int64]$script:MmenuCLastHighestNumericTag; Docker=$dockerExe; Python=$pythonExe; Strategy=$strategyText; DockerSettingsChanged=$false; BypassesRootDockerignore=$true; IntentionalSourceExclusions=0; AbortOnUnreadable=$true; SourceBytes=[int64]$stats.TotalBytes; SourceFiles=[int64]$stats.Files; SourceDirs=[int64]$stats.Dirs; SourceFingerprint=[string]$stats.Fingerprint; TempRoot=$null; TempRootCreated=$false; RequestedTargetLayerMiB=[int64]$TargetLayerMiB; EffectiveTargetLayerMiB=[int64]$effectiveTargetLayerMiB; MaxAutoLayers=[int]$maxAutoLayers; FastThresholdMiB=$fastThresholdMiB; BuildxMaxMiB=$buildxMaxMiB; LargeSourceDirectImport=[bool]$largeSourceDirectImport; ForceLoadArchive=[bool]$forceLoadArchive; AutoDirectImportTar=[bool]$autoDirectImportTar; MinSpeedMiBPerSecond=([Math]::Round([double](Get-MmenuCMinSpeedBytesPerSecond) / 1MB,2)); LowSpeedGraceSeconds=(Get-MmenuCLowSpeedGraceSeconds); LowSpeedMinRemainingSeconds=(Get-MmenuCLowSpeedMinRemainingSeconds) } | Format-List
  $global:LASTEXITCODE = 0
  $script:MmenuCProcessExitCode = 0
  return
}

if($TarPreflightOnly -or $BuildPreflightOnly){
  $preflightMode = if($TarPreflightOnly -and $BuildPreflightOnly){ 'tar-and-build' } elseif($TarPreflightOnly){ 'tar' } else { 'build' }
  [pscustomobject]@{ EntryPoint=$EntryPoint; Source=$projectPath; Image=$imageRef; Repository=$repository; RepoSlug=$repoSlug; Tag=$tagName; Docker=$dockerExe; Python=$pythonExe; Mode=$preflightMode; Strategy='read-only source scan; no Dockerfile, tar context, archive, or local temporary root is created'; DockerSettingsChanged=$false; BypassesRootDockerignore=$true; IntentionalSourceExclusions=0; AbortOnUnreadable=$true; SourceBytes=[int64]$stats.TotalBytes; SourceFiles=[int64]$stats.Files; SourceDirs=[int64]$stats.Dirs; SourceFingerprint=[string]$stats.Fingerprint; TempRoot=$null; TempRootCreated=$false; Dockerfile=$null; DockerignoreCreated=$false; TempContextCreated=$false; RequestedTargetLayerMiB=[int64]$TargetLayerMiB; EffectiveTargetLayerMiB=[int64]$effectiveTargetLayerMiB; MaxAutoLayers=[int]$maxAutoLayers; FastThresholdMiB=$fastThresholdMiB; BuildxMaxMiB=$buildxMaxMiB; LargeSourceDirectImport=[bool]$largeSourceDirectImport; NoLocalStaging=$true } | Format-List
  $global:LASTEXITCODE = 0
  $script:MmenuCProcessExitCode = 0
  return
}

if($useDockerfileBuildx){
& $vmmEnforcer -Label ("{0} (Docker VMM max performance)" -f $EntryPoint.ToUpperInvariant()) -Color 'DarkCyan' | Out-Host
if(-not $?){ throw "${EntryPoint}: Docker VMM enforcement failed." }
$vmmSettings = [System.IO.File]::ReadAllText((Join-Path $env:APPDATA 'Docker\settings-store.json')) | ConvertFrom-Json -ErrorAction Stop
if(-not ([bool]$vmmSettings.UseLibkrun) -or [bool]$vmmSettings.WslEngineEnabled -or [bool]$vmmSettings.UseVirtualizationFramework -or [bool]$vmmSettings.UseResourceSaver){
  throw "${EntryPoint}: Docker VMM settings verification failed."
}
if(-not (Get-Process -Name 'com.docker.sailor' -ErrorAction SilentlyContinue | Select-Object -First 1)){
  throw "${EntryPoint}: Docker VMM process is not running after enforcement."
}
Write-MmenuC "[$EntryPoint] Docker VMM verified live; WSL2 and Hyper-V backends are disabled for this command."

Write-MmenuC "[$EntryPoint][engine] checking Docker engine readiness before build (bounded 3s probe)..." DarkGray
if(-not (Wait-MenuCDockerEngineReady -DockerExe $dockerExe)){ throw "${EntryPoint}: Docker engine did not become ready." }
}else{
  Write-MmenuC "[$EntryPoint][engine] direct registry transport selected; Docker engine and VMM are not required."
}
try {
  $postVmmCredentialToken=Get-MmenuCDockerHubToken -Repository $repository -CredentialHelper $dockerCredentialDesktop -Scope 'push,pull'
  if([string]::IsNullOrWhiteSpace([string]$postVmmCredentialToken)){throw 'Docker Hub returned an empty push token after VMM stabilization.'}
} catch {
  throw ("${EntryPoint}: Docker Hub credential check failed after VMM stabilization and before layer creation: " + $_.Exception.Message)
} finally {$postVmmCredentialToken=$null}
$allowExactCachePush = ($env:HERMES_MMENU_ALLOW_EXACT_CACHE_PUSH -match '^(1|true|yes)$')
if($allowExactCachePush -and (Test-MmenuCLocalExactImage -DockerExe $dockerExe -ImageRef $imageRef -SourcePath $projectPath -Repository $repository -TagName $tagName -SourceBytes ([int64]$stats.TotalBytes) -SourceFiles ([int64]$stats.Files) -SourceFingerprint ([string]$stats.Fingerprint))){
  Write-MmenuC ("[$EntryPoint][push] started immediately after exact local image cache hit; image={0}" -f $imageRef)
  $cachePushCode = Invoke-MmenuCDirectDockerPushUntilSuccess -DockerExe $dockerExe -ImageRef $imageRef -ExpectedSourcePath $projectPath -ExpectedRepository $repository -ExpectedTagName $tagName -ExpectedSourceBytes ([int64]$stats.TotalBytes) -ExpectedSourceFiles ([int64]$stats.Files) -ExpectedSourceFingerprint ([string]$stats.Fingerprint)
  if($cachePushCode -ne 0){ throw "${EntryPoint}: Docker push failed with exit $cachePushCode after exact local cache hit." }
  Write-MmenuC ("[$EntryPoint][complete] SUCCESS cached-image push verified; returning to shell now: {0}" -f $imageRef) Green
  $global:LASTEXITCODE = 0
  $script:MmenuCProcessExitCode = 0
  return
}

$allowRemoteMetadataCache = ($env:HERMES_MMENU_ALLOW_REMOTE_METADATA_CACHE -match '^(1|true|yes)$')
if($allowRemoteMetadataCache -and (Test-MmenuCRemoteExactLabels -ImageRef $imageRef -SourcePath $projectPath -Repository $repository -TagName $tagName -SourceBytes ([int64]$stats.TotalBytes) -SourceFiles ([int64]$stats.Files) -SourceFingerprint ([string]$stats.Fingerprint))){
  Write-MmenuC ("[$EntryPoint][remote-cache] exact remote image already matches source fingerprint/path/bytes/files; skipping rebuild and push wait: {0}" -f $imageRef) Green
  Write-MmenuC ("[$EntryPoint][complete] SUCCESS remote image already current; returning to shell now: {0}" -f $imageRef) Green
  $global:LASTEXITCODE = 0
  $script:MmenuCProcessExitCode = 0
  return
} elseif(-not $allowRemoteMetadataCache) {
  Write-MmenuC "[$EntryPoint][remote-cache] disabled by default; current run will create content-addressed layer hashes and verify the final remote manifest." DarkGray
}

if($useDockerfileBuildx){
  $fastDockerfilePath = Join-MmenuCTempPath $fastDockerfileName -SourcePath $projectPath
  $fastIgnorePath = ''
  try {
    New-MmenuCBuildxDockerfile -DockerfilePath $fastDockerfilePath -DockerignorePath $fastIgnorePath -SourcePath $projectPath -Repository $repository -TagName $tagName -SourceBytes ([int64]$stats.TotalBytes) -SourceFiles ([int64]$stats.Files) -SourceFingerprint ([string]$stats.Fingerprint)
    Write-MmenuC "[$EntryPoint][dockerfile] created: $fastDockerfilePath"
    Write-MmenuC "[$EntryPoint][dockerfile] no temporary context and no Dockerfile-specific ignore were created; Docker build context is the source path itself."
    if($TarPreflightOnly){
      [pscustomobject]@{ EntryPoint=$EntryPoint; Source=$projectPath; Image=$imageRef; TarPreflightOnly=$true; Strategy='direct source Dockerfile BuildKit path has no tar/import/load archive'; Dockerfile=$fastDockerfilePath; DockerignoreCreated=$false; SourceBytes=[int64]$stats.TotalBytes; SourceFiles=[int64]$stats.Files; SourceFingerprint=[string]$stats.Fingerprint; TempContextCreated=$false } | Format-List
      $global:LASTEXITCODE = 0
      $script:MmenuCProcessExitCode = 0
      return
    }
    if($BuildPreflightOnly){
      [pscustomobject]@{ EntryPoint=$EntryPoint; Source=$projectPath; Image=$imageRef; BuildPreflightOnly=$true; Strategy='docker build from source path, then immediate docker push with live heartbeat and remote-manifest unstuck watchdog'; Dockerfile=$fastDockerfilePath; DockerignoreCreated=$false; SourceBytes=[int64]$stats.TotalBytes; SourceFiles=[int64]$stats.Files; SourceFingerprint=[string]$stats.Fingerprint; PushSkipped=$true } | Format-List
      Write-MmenuC "[$EntryPoint][build-preflight] SUCCESS: generated Dockerfile BuildKit build-and-push command surface; push skipped by BuildPreflightOnly for $imageRef" Green
      $global:LASTEXITCODE = 0
      $script:MmenuCProcessExitCode = 0
      return
    }
    Write-MmenuC "[$EntryPoint][image-create] started: Dockerfile build runs once; Docker Hub retries reuse the resulting local image and never trigger a rebuild; image=$imageRef"
    $bcode = Invoke-MmenuCDockerfileBuildxPushUntilSuccess -DockerExe $dockerExe -SourcePath $projectPath -DockerfilePath $fastDockerfilePath -ImageRef $imageRef -EstimatedBytes ([int64]$stats.TotalBytes) -ExpectedRepository $repository -ExpectedTagName $tagName -ExpectedSourceFiles ([int64]$stats.Files) -ExpectedSourceFingerprint ([string]$stats.Fingerprint)
    if($bcode -ne 0){ throw "${EntryPoint}: Dockerfile BuildKit build-and-push failed with exit $bcode." }
    Write-MmenuC "[$EntryPoint] SUCCESS: complete source scanned ($(Format-MmenuCMiB ([int64]$stats.TotalBytes)), $([int64]$stats.Files) files), Dockerfile built and pushed with live progress, returning to PowerShell shell: $imageRef" Green
    $global:LASTEXITCODE = 0
    $script:MmenuCProcessExitCode = 0
    return
  } finally {
    try { if($fastIgnorePath){ Remove-Item -LiteralPath $fastIgnorePath -Force -ErrorAction SilentlyContinue } } catch {}
    try { if($fastDockerfilePath){ Remove-Item -LiteralPath $fastDockerfilePath -Force -ErrorAction SilentlyContinue } } catch {}
  }
}

if([string]::IsNullOrWhiteSpace($pythonExe)){ throw "${EntryPoint}: verified Python 3 runtime not found for the complete tar-layer path." }
$contextBase = Join-MmenuCTempPath 'hermes-docker-mmenu-contexts' -SourcePath $projectPath
$null = New-Item -ItemType Directory -Path $contextBase -Force -ErrorAction SilentlyContinue
Remove-MmenuCStaleContexts -ContextBase $contextBase
try {
  $legacyParent = Split-Path -Parent $projectPath
  if($legacyParent -and (Test-Path -LiteralPath $legacyParent -PathType Container)){
    $legacyFilter = '.mmenu-' + 'layerctx-*'
    foreach($legacyDir in @(Get-ChildItem -LiteralPath $legacyParent -Directory -Force -Filter $legacyFilter -ErrorAction SilentlyContinue)){
      if($legacyDir.LastWriteTime -lt (Get-Date).AddHours(-48)){ try { Remove-Item -LiteralPath $legacyDir.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch { } }
    }
  }
} catch { }
$contextRoot = $null
if(-not $PreflightOnly -and -not $TarPreflightOnly -and -not $BuildPreflightOnly){
  $contextRoot = Get-MmenuCReusableContext -ContextBase $contextBase -SourcePath $projectPath -ImageRef $imageRef -SourceBytes ([int64]$stats.TotalBytes) -SourceFiles ([int64]$stats.Files) -SourceFingerprint ([string]$stats.Fingerprint)
}
$reuseLayerSet = -not [string]::IsNullOrWhiteSpace([string]$contextRoot)
if($reuseLayerSet){
  Write-MmenuC ("[$EntryPoint][recovery] reusing verified failed-run layer set without rescanning or retarring: {0}" -f $contextRoot) Yellow
}else{
  $contextRoot = Join-Path $contextBase ('ctx-' + [Guid]::NewGuid().ToString('N'))
  $null = New-Item -ItemType Directory -Path $contextRoot -Force
  Write-MmenuCContextIdentity -ContextRoot $contextRoot -SourcePath $projectPath -ImageRef $imageRef -SourceBytes ([int64]$stats.TotalBytes) -SourceFiles ([int64]$stats.Files) -SourceFingerprint ([string]$stats.Fingerprint)
}
$activeMarkerPath = Join-Path $contextRoot '.active'
Set-Content -LiteralPath $activeMarkerPath -Encoding ASCII -Value ("pid={0}; started={1:o}" -f $PID,(Get-Date))
$planJson = Join-Path $contextRoot 'plan.json'; $planScript = Join-Path $contextRoot 'make_tar_layers.py'; $dockerfilePath = Join-Path $contextRoot 'Dockerfile'
$py = @'
import os, sys, json, tarfile, time, hashlib, io, threading, concurrent.futures
try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass
def safe_progress_text(value):
    return str(value).encode('utf-8', 'replace').decode('utf-8', 'replace')
root=os.path.abspath(sys.argv[1]); ctx=os.path.abspath(sys.argv[2]); target=int(sys.argv[3]); mode=sys.argv[4]
phantom=[]; files=[]; dirs=[]
def rel(p): return os.path.relpath(p, root).replace('\\','/')
def is_reparse_dir(path):
    try:
        return bool(os.stat(path, follow_symlinks=False).st_file_attributes & 0x400)
    except AttributeError:
        return os.path.islink(path)
    except OSError:
        return False
for dp,dn,fn in os.walk(root, topdown=True, onerror=lambda e: phantom.append((getattr(e,'filename','?'),str(e)))):
    kept_dirs=[]
    for d in sorted(dn, key=str.lower):
        full_dir=os.path.join(dp, d)
        if is_reparse_dir(full_dir):
            phantom.append((rel(full_dir), 'reparse point directory would be skipped; refusing incomplete Docker backup'))
        else:
            kept_dirs.append(d)
    dn[:] = kept_dirs
    if dp != root: dirs.append(rel(dp))
    for n in sorted(fn, key=str.lower):
        p=os.path.join(dp,n)
        try:
            st=os.lstat(p)
            if getattr(st, 'st_file_attributes', 0) & 0x400:
                phantom.append((rel(p), 'reparse point file would be skipped; refusing incomplete Docker backup'))
            elif os.path.isfile(p): files.append((rel(p), p, int(st.st_size)))
        except OSError as e: phantom.append((rel(p), str(e)))
chunks=[]; cur=[]; cur_size=0
for rp,p,sz in files:
    if cur and cur_size + sz > target: chunks.append((cur,cur_size)); cur=[]; cur_size=0
    cur.append((rp,p,sz)); cur_size += sz
if cur or not chunks: chunks.append((cur,cur_size))
plan={'root':root,'total':sum(x[2] for x in files),'files':len(files),'dirs':len(dirs),'chunks':[{'name':'layer%03d.tar'%(i+1),'size':c[1],'files':len(c[0])} for i,c in enumerate(chunks)],'large_items':[{'path':rp,'size':sz} for rp,p,sz in files if sz > target], 'phantom': phantom}
with open(os.path.join(ctx,'plan.json'),'w',encoding='utf-8') as f: json.dump(plan,f,indent=2)
print('[mmenu][chunk-plan] total_bytes=%d chunks=%d files=%d dirs=%d target_bytes=%d large_items=%d unreadable_entries=%d' % (plan['total'], len(chunks), len(files), len(dirs), target, len(plan['large_items']), len(phantom)), flush=True)
if phantom:
    with open(os.path.join(ctx,'phantom.json'),'w',encoding='utf-8') as f: json.dump(phantom,f,indent=2)
    sys.exit(23)
if mode == 'plan': sys.exit(0)
last=0.0; done=0; TAR_COPY_BUFFER_BYTES=8*1024*1024; TAR_HEARTBEAT_SECONDS=2.0
done_lock=threading.Lock()
emit_lock=threading.Lock()
progress_lock=threading.Lock()
active_progress={'layer':'','file':'metadata','size':0,'done':0,'tar_path':'','stop':False,'last_emit':0.0,'last_tar_bytes':-1}
def emit_tar_progress(layer, relpath, size, file_done, heartbeat=False, tar_bytes=-1):
    global last
    file_pct=100.0*file_done/max(1,size)
    if file_pct > 100.0: file_pct=100.0
    prefix='[mmenu][tar-layer] heartbeat=1 ' if heartbeat else '[mmenu][tar-layer] '
    extra=(' tar_bytes=%d' % tar_bytes) if tar_bytes >= 0 else ''
    print(prefix + 'archived_bytes=%d total_bytes=%d percent=%.2f current_layer=%s current_file=%s file_bytes=%d file_done=%d file_percent=%.2f%s' % (done, plan['total'], min(100.0,100.0*done/max(1,plan['total'])), layer, safe_progress_text(('home/'+relpath).replace('\\','/')) if relpath != 'metadata' else 'metadata', size, file_done, file_pct, extra), flush=True)
    last=time.time()
def tar_heartbeat_worker():
    global last
    while True:
        time.sleep(TAR_HEARTBEAT_SECONDS)
        with progress_lock:
            if active_progress['stop']:
                return
            layer=active_progress['layer']; relpath=active_progress['file']; size=active_progress['size']; file_done=active_progress['done']; tar_path=active_progress['tar_path']; last_emit=active_progress['last_emit']
        try:
            tar_bytes=os.path.getsize(tar_path) if tar_path else -1
        except OSError:
            tar_bytes=-1
        now=time.time()
        if now-last_emit >= TAR_HEARTBEAT_SECONDS:
            emit_tar_progress(layer or 'unknown', relpath or 'metadata', size, file_done, True, tar_bytes)
            with progress_lock:
                active_progress['last_emit']=now; active_progress['last_tar_bytes']=tar_bytes
def start_tar_heartbeat(tar_path, layer):
    with progress_lock:
        active_progress.update({'layer':layer,'file':'metadata','size':0,'done':0,'tar_path':tar_path,'stop':False,'last_emit':time.time(),'last_tar_bytes':-1})
    t=threading.Thread(target=tar_heartbeat_worker, name='mmenu-tar-heartbeat', daemon=True)
    t.start()
    return t
def stop_tar_heartbeat(t):
    with progress_lock:
        active_progress['stop']=True
    if t is not None:
        t.join(TAR_HEARTBEAT_SECONDS+1.0)
class HermesProgressReader:
    def __init__(self, fh, size, relpath, layer):
        self.fh=fh; self.size=max(0,int(size)); self.relpath=relpath; self.layer=layer; self.read_bytes=0; self.last=time.time()
        with progress_lock:
            active_progress.update({'layer':layer,'file':relpath,'size':self.size,'done':0,'last_emit':time.time()})
    def read(self, n=-1):
        global done,last
        data=self.fh.read(n)
        if data:
            blen=len(data); self.read_bytes += blen; done += blen
            with progress_lock:
                active_progress.update({'layer':self.layer,'file':self.relpath,'size':self.size,'done':self.read_bytes})
        now=time.time()
        if now-self.last >= 0.25 or (self.size > 0 and self.read_bytes >= self.size):
            emit_tar_progress(self.layer, self.relpath, self.size, self.read_bytes)
            self.last=now
        return data
    def close(self):
        return self.fh.close()
    def __getattr__(self, name):
        return getattr(self.fh, name)
class HermesParallelProgressReader:
    def __init__(self, fh, size, relpath, layer):
        self.fh=fh; self.size=max(0,int(size)); self.relpath=relpath; self.layer=layer; self.read_bytes=0; self.last=time.time()
        with progress_lock:
            active_progress.update({'layer':layer,'file':relpath,'size':self.size,'done':0,'last_emit':time.time()})
    def read(self, n=-1):
        global done,last
        data=self.fh.read(n)
        if data:
            blen=len(data); self.read_bytes += blen
            with done_lock:
                done += blen
                done_snapshot=done
            with progress_lock:
                active_progress.update({'layer':self.layer,'file':self.relpath,'size':self.size,'done':self.read_bytes})
        else:
            with done_lock:
                done_snapshot=done
        now=time.time()
        if now-self.last >= 0.25 or (self.size > 0 and self.read_bytes >= self.size):
            with emit_lock:
                file_pct=100.0*self.read_bytes/max(1,self.size)
                if file_pct > 100.0: file_pct=100.0
                print('[mmenu][tar-layer] archived_bytes=%d total_bytes=%d percent=%.2f current_layer=%s current_file=%s file_bytes=%d file_done=%d file_percent=%.2f' % (done_snapshot, plan['total'], min(100.0,100.0*done_snapshot/max(1,plan['total'])), self.layer, safe_progress_text(('home/'+self.relpath).replace('\\','/')), self.size, self.read_bytes, file_pct), flush=True)
                last=now
            self.last=now
        return data
    def close(self):
        return self.fh.close()
    def __getattr__(self, name):
        return getattr(self.fh, name)
if mode == 'import-tar':
    lname='import.tar'; lpath=os.path.join(ctx,lname); ltmp=lpath+'.tmp'
    print('[mmenu][tar-layer] START layer=%s files=%d bytes=%d' % (lname,len(files),plan['total']), flush=True)
    try:
        os.remove(ltmp)
    except FileNotFoundError:
        pass
    print('[mmenu][tar-layer] tar_copy_buffer_bytes=%d' % TAR_COPY_BUFFER_BYTES, flush=True)
    hb=start_tar_heartbeat(ltmp,lname)
    try:
        with tarfile.open(ltmp,'w',format=tarfile.PAX_FORMAT,bufsize=TAR_COPY_BUFFER_BYTES,copybufsize=TAR_COPY_BUFFER_BYTES) as tar:
            for d in dirs:
                full=os.path.join(root,d.replace('/',os.sep))
                try:
                    info=tar.gettarinfo(full, arcname=('home/'+d).replace('\\','/')); info.uid=0; info.gid=0; info.uname='root'; info.gname='root'; tar.addfile(info)
                except OSError as e: phantom.append((d,str(e)))
            for rp,p,sz in files:
                try:
                    info=tar.gettarinfo(p, arcname=('home/'+rp).replace('\\','/'))
                    info.uid=0; info.gid=0; info.uname='root'; info.gname='root'
                    with open(p,'rb',buffering=8*1024*1024) as rf:
                        tar.addfile(info, HermesProgressReader(rf, sz, rp, lname))
                except OSError as e: phantom.append((rp,str(e)))
    finally:
        stop_tar_heartbeat(hb)
    os.replace(ltmp,lpath)
    print('[mmenu][tar-layer] DONE layer=%s tar_bytes=%d' % (lname, os.path.getsize(lpath)), flush=True)
    if phantom:
        with open(os.path.join(ctx,'phantom.json'),'w',encoding='utf-8') as f: json.dump(phantom,f,indent=2)
        sys.exit(24)
    print('[mmenu][tar-layer] archived_bytes=%d total_bytes=%d percent=100.00 complete=1' % (done, plan['total']), flush=True)
    sys.exit(0)
if mode == 'load-archive':
    image_ref=sys.argv[5]
    with open(sys.argv[6], 'r', encoding='utf-8') as lf:
        labels=json.load(lf)
    layer_names=[c['name'] for c in plan['chunks']]
    layer_sizes=[os.path.getsize(os.path.join(ctx,n)) for n in layer_names]
    total=sum(layer_sizes)
    done_hash=0
    diff_ids=[]
    for lname,lsize in zip(layer_names,layer_sizes):
        h=hashlib.sha256()
        with open(os.path.join(ctx,lname),'rb',buffering=8*1024*1024) as f:
            while True:
                b=f.read(8*1024*1024)
                if not b: break
                h.update(b); done_hash += len(b)
                print('[mmenu][load-archive] archived_bytes=%d total_bytes=%d percent=%.2f current_layer=%s current_file=sha256' % (done_hash,total,min(100.0,100.0*done_hash/max(1,total)),lname), flush=True)
        diff_ids.append('sha256:'+h.hexdigest())
    created=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    cfg={
      'created':created,'architecture':'amd64','os':'linux',
      'config':{'WorkingDir':'/home','Labels':labels},
      'container_config':{'WorkingDir':'/home','Labels':labels},
      'rootfs':{'type':'layers','diff_ids':diff_ids},
      'history':[{'created':created,'created_by':'mmenu complete backup layer'} for _ in layer_names]
    }
    cfg_bytes=json.dumps(cfg,separators=(',',':')).encode('utf-8')
    cfg_name=hashlib.sha256(cfg_bytes).hexdigest()+'.json'
    manifest_bytes=json.dumps([{'Config':cfg_name,'RepoTags':[image_ref],'Layers':layer_names}],separators=(',',':')).encode('utf-8')
    archive=os.path.join(ctx,'docker-load.tar'); tmp=archive+'.tmp'
    try:
        os.remove(tmp)
    except FileNotFoundError:
        pass
    with tarfile.open(tmp,'w',format=tarfile.PAX_FORMAT,bufsize=TAR_COPY_BUFFER_BYTES,copybufsize=TAR_COPY_BUFFER_BYTES) as tar:
        ti=tarfile.TarInfo(cfg_name); ti.size=len(cfg_bytes); ti.mtime=int(time.time()); tar.addfile(ti, io.BytesIO(cfg_bytes))
        ti=tarfile.TarInfo('manifest.json'); ti.size=len(manifest_bytes); ti.mtime=int(time.time()); tar.addfile(ti, io.BytesIO(manifest_bytes))
        copied=0
        for lname,lsize in zip(layer_names,layer_sizes):
            ti=tar.gettarinfo(os.path.join(ctx,lname), arcname=lname)
            with open(os.path.join(ctx,lname),'rb',buffering=8*1024*1024) as f:
                tar.addfile(ti, f)
            copied += lsize
            print('[mmenu][load-archive] archived_bytes=%d total_bytes=%d percent=%.2f current_layer=%s current_file=docker-load-archive' % (copied,total,min(100.0,100.0*copied/max(1,total)),lname), flush=True)
    os.replace(tmp,archive)
    print('[mmenu][load-archive] DONE archive=docker-load.tar tar_bytes=%d' % os.path.getsize(archive), flush=True)
    print('[mmenu][load-archive] archived_bytes=%d total_bytes=%d percent=100.00 complete=1' % (total,total), flush=True)
    sys.exit(0)
parallel_phantom_lock=threading.Lock()
def add_parallel_phantom(item):
    with parallel_phantom_lock:
        phantom.append(item)
def write_layer(idx, chunk, chunk_size):
    lname='layer%03d.tar'%idx; lpath=os.path.join(ctx,lname)
    print('[mmenu][tar-layer] START layer=%s files=%d bytes=%d' % (lname,len(chunk),chunk_size), flush=True)
    ltmp=lpath+'.tmp'
    try:
        os.remove(ltmp)
    except FileNotFoundError:
        pass
    with tarfile.open(ltmp,'w',format=tarfile.PAX_FORMAT,bufsize=TAR_COPY_BUFFER_BYTES,copybufsize=TAR_COPY_BUFFER_BYTES) as tar:
        if idx == 1:
            for d in dirs:
                full=os.path.join(root,d.replace('/',os.sep))
                try:
                    info=tar.gettarinfo(full, arcname=('home/'+d).replace('\\','/')); info.uid=0; info.gid=0; info.uname='root'; info.gname='root'; tar.addfile(info)
                except OSError as e: add_parallel_phantom((d,str(e)))
        for rp,p,sz in chunk:
            try:
                info=tar.gettarinfo(p, arcname=('home/'+rp).replace('\\','/'))
                info.uid=0; info.gid=0; info.uname='root'; info.gname='root'
                with open(p,'rb',buffering=8*1024*1024) as rf:
                    tar.addfile(info, HermesParallelProgressReader(rf, sz, rp, lname))
            except OSError as e: add_parallel_phantom((rp,str(e)))
    os.replace(ltmp,lpath)
    print('[mmenu][tar-layer] DONE layer=%s tar_bytes=%d' % (lname, os.path.getsize(lpath)), flush=True)
max_workers_env=os.environ.get('HERMES_MMENU_TAR_WORKERS','').strip()
try:
    max_workers=int(max_workers_env) if max_workers_env else 0
except ValueError:
    max_workers=0
if max_workers <= 0:
    max_workers=min(len(chunks), max(2, min(6, (os.cpu_count() or 4))))
print('[mmenu][tar-layer] parallel_workers=%d layers=%d' % (max_workers, len(chunks)), flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
    futures=[executor.submit(write_layer, idx, chunk, chunk_size) for idx,(chunk,chunk_size) in enumerate(chunks, start=1)]
    for future in concurrent.futures.as_completed(futures):
        future.result()
if phantom:
    with open(os.path.join(ctx,'phantom.json'),'w',encoding='utf-8') as f: json.dump(phantom,f,indent=2)
    sys.exit(24)
ready={'layers':[]}
for idx,(chunk,chunk_size) in enumerate(chunks, start=1):
    lname='layer%03d.tar'%idx; lpath=os.path.join(ctx,lname)
    if not os.path.isfile(lpath) or os.path.getsize(lpath) <= 0:
        raise RuntimeError('layer durability verification failed: '+lname)
    ready['layers'].append({'name':lname,'length':os.path.getsize(lpath)})
ready_tmp=os.path.join(ctx,'layers.ready.json.tmp'); ready_path=os.path.join(ctx,'layers.ready.json')
with open(ready_tmp,'w',encoding='utf-8') as f:
    json.dump(ready,f,separators=(',',':')); f.flush(); os.fsync(f.fileno())
os.replace(ready_tmp,ready_path)
print('[mmenu][tar-layer] archived_bytes=%d total_bytes=%d percent=100.00 complete=1' % (done, plan['total']), flush=True)
'@
$py = $py.Replace('[mmenu]',"[$EntryPoint]")
[IO.File]::WriteAllText($planScript,$py,[Text.Encoding]::UTF8)
try{
  $pyBaseArgs=@()
  if((Split-Path -Leaf $pythonExe) -ieq 'py.exe'){ $pyBaseArgs += '-3' }
  if($reuseLayerSet){
    $plan=Get-Content -LiteralPath $planJson -Raw|ConvertFrom-Json -ErrorAction Stop
    Write-MmenuC ("[$EntryPoint][docker:chunk-plan] verified cached plan reused: bytes={0} files={1} layers={2}" -f $plan.total,$plan.files,@($plan.chunks).Count) DarkGray
  }else{
    Write-MmenuC "[$EntryPoint][docker:chunk-plan] START $(Get-Date -Format 'HH:mm:ss')"
    & $pythonExe @pyBaseArgs $planScript $projectPath $contextRoot $targetBytes 'plan'
    $planCode=[int]$LASTEXITCODE
    if($planCode -ne 0){ throw "${EntryPoint}: chunk planner failed with exit $planCode." }
    $plan=Get-Content -LiteralPath $planJson -Raw|ConvertFrom-Json -ErrorAction Stop
  }
  if($plan.large_items.Count -gt 0){
    foreach($li in $plan.large_items){ Write-MmenuC ("[$EntryPoint][chunk-warning] single file bigger than target: {0} size={1}" -f $li.path,(Format-MmenuCMiB ([int64]$li.size))) Yellow }
    Write-MmenuC ("[$EntryPoint][chunk-warning] exact Docker restore requires each oversized file to remain in one layer; upload order will start largest missing layers first, but that file cannot be split into parallel Docker layers without changing the restored file layout.") Yellow
  }
  $directRegistryPush = [bool]$autoDirectImportTar
  $importTarTmpPath = Join-Path $contextRoot 'import.tar.tmp'
  if($reuseLayerSet){
    Write-MmenuC ("[$EntryPoint][docker:tar-image] verified cached layer tar set reused; retar skipped: {0}" -f $contextRoot) Green
  }else{
    Write-MmenuC "[$EntryPoint][docker:tar-image] START $(Get-Date -Format 'HH:mm:ss')"
    $tarCommandParts = @((Quote-MmenuCArg $pythonExe))
    foreach($arg in $pyBaseArgs){ $tarCommandParts += (Quote-MmenuCArg $arg) }
    $tarMode = 'layers'
    foreach($arg in @($planScript,$projectPath,$contextRoot,[string]$targetBytes,$tarMode)){ $tarCommandParts += (Quote-MmenuCArg $arg) }
    $watchPathForTar = ''
    $tarCode=Invoke-MmenuCProcess -Label 'tar-image' -CommandLine ($tarCommandParts -join ' ') -WatchPath $watchPathForTar -WatchTotalBytes ([int64]$plan.total)
    if($tarCode -ne 0){ throw "${EntryPoint}: complete image tar creation failed with exit $tarCode; push stopped." }
  }
  if($TarPreflightOnly){
    [pscustomobject]@{ EntryPoint=$EntryPoint; Source=$projectPath; Image=$imageRef; TarPreflightOnly=$true; ContextRoot=$contextRoot; SourceBytes=[int64]$plan.total; SourceFiles=[int64]$plan.files; SourceFingerprint=[string]$stats.Fingerprint; Chunks=[int]$plan.chunks.Count; ContextWillBeRemoved=$true } | Format-List
    $global:LASTEXITCODE = 0
    $script:MmenuCProcessExitCode = 0
    return
  }
  $pushArgs=@('push',$imageRef)
  $labels = [ordered]@{
    'backup.source.path' = [string]$projectPath
    'backup.source.repo' = [string]$repository
    'backup.source.tag' = [string]$tagName
    'backup.source.bytes' = [string]([int64]$plan.total)
    'backup.source.files' = [string]([int]$plan.files)
    'backup.source.fingerprint' = [string]$stats.Fingerprint
    'backup.mmenu.layering' = if($directRegistryPush){ 'direct-registry-oci-multilayer-no-docker-import' } else { 'docker-load-multilayer-no-exclusions' }
    'backup.mmenu.target_layer_mib' = [string]$effectiveTargetLayerMiB
  }
  Write-MmenuC "[$EntryPoint][image-create] started: Docker image creation uses $(if($directRegistryPush){'direct registry OCI multilayer push; no Docker Desktop import/load'}else{'chunked docker load archive for fastest feasible load/push concurrency'}); source=$(Format-MmenuCMiB ([int64]$plan.total)); files=$([int]$plan.files); chunks=$([int]$plan.chunks.Count); image=$imageRef"
  if(-not $BuildPreflightOnly){
    Write-MmenuC "[$EntryPoint][push] direct live push is armed and will start immediately after image-create success; image=$imageRef"
  }
  if($directRegistryPush){
    $readyPath=Join-Path $contextRoot 'layers.ready.json'
    if(-not [IO.File]::Exists($readyPath)){throw "${EntryPoint}: tar worker exited without its durable layer-set receipt: $readyPath"}
    $readyRecord=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($readyPath)) | ConvertFrom-Json -ErrorAction Stop
    if(@($readyRecord.layers).Count -ne @($plan.chunks).Count){throw "${EntryPoint}: durable layer-set receipt count does not match the plan."}
    $layerPaths=@(Wait-MmenuCRegistryLayerSet -Plan $plan -ContextRoot $contextRoot -TimeoutSeconds 30)
    $labels['backup.mmenu.layering'] = 'direct-registry-oci-multilayer-no-docker-import'
    Write-MmenuC "[$EntryPoint][push] started immediately after tar-image success; direct parallel Docker Hub registry upload begins now; layers=$($layerPaths.Count); image=$imageRef"
    $code=Invoke-MmenuCCurlRegistryPushLayersUntilSuccess -DockerExe $dockerExe -LayerPaths $layerPaths -ImageRef $imageRef -Labels $labels
    if($code -ne 0){ throw "${EntryPoint}: direct registry push failed with exit $code." }
    if(-not (Test-MmenuCRemoteExactLabels -ImageRef $imageRef -SourcePath $projectPath -Repository $repository -TagName $tagName -SourceBytes ([int64]$plan.total) -SourceFiles ([int64]$plan.files) -SourceFingerprint ([string]$stats.Fingerprint))){
      if(-not (Test-MmenuCRemoteManifest -DockerExe $dockerExe -ImageRef $imageRef)){ throw "${EntryPoint}: remote manifest verification failed after direct registry push: $imageRef" }
      Write-MmenuC "[$EntryPoint][manifest] remote manifest verified after direct registry push: $imageRef"
    } else {
      Write-MmenuC "[$EntryPoint][manifest] remote manifest and exact source labels verified after direct registry push: $imageRef"
    }
    Write-MmenuC "[$EntryPoint] SUCCESS: complete source scanned ($(Format-MmenuCMiB ([int64]$plan.total)), $([int]$plan.files) files), pushed directly to Docker Hub in full, remote manifest verified, returning to PowerShell shell: $imageRef" Green
    $global:LASTEXITCODE = 0
    $script:MmenuCProcessExitCode = 0
    return
  } else {
    $labelsJsonPath = Join-Path $contextRoot 'labels.json'
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [IO.File]::WriteAllText($labelsJsonPath,($labels | ConvertTo-Json -Compress),$utf8NoBom)
    Write-MmenuC "[$EntryPoint][docker:load-archive] START $(Get-Date -Format 'HH:mm:ss')"
    $loadArchiveTmpPath = Join-Path $contextRoot 'docker-load.tar.tmp'
    $loadArchiveCommandParts = @((Quote-MmenuCArg $pythonExe))
    foreach($arg in $pyBaseArgs){ $loadArchiveCommandParts += (Quote-MmenuCArg $arg) }
    foreach($arg in @($planScript,$projectPath,$contextRoot,[string]$targetBytes,'load-archive',$imageRef,$labelsJsonPath)){ $loadArchiveCommandParts += (Quote-MmenuCArg $arg) }
    $loadArchiveCode=Invoke-MmenuCProcess -Label 'load-archive' -CommandLine ($loadArchiveCommandParts -join ' ') -WatchPath $loadArchiveTmpPath -WatchTotalBytes ([int64]$plan.total)
    if($loadArchiveCode -ne 0){ throw "${EntryPoint}: Docker load archive packaging failed with exit $loadArchiveCode; push stopped." }
    $dockerLoadArchivePath = Join-Path $contextRoot 'docker-load.tar'
    if(-not (Test-Path -LiteralPath $dockerLoadArchivePath -PathType Leaf)){ throw "${EntryPoint}: Docker load archive missing after successful archive stage: $dockerLoadArchivePath" }
    $code=Invoke-MmenuCDockerLoadArchiveUntilSuccess -DockerExe $dockerExe -ArchivePath $dockerLoadArchivePath -ImageRef $imageRef -ContextTotalBytes ([int64]$plan.total) -ExpectedSourcePath $projectPath -ExpectedRepository $repository -ExpectedTagName $tagName -ExpectedSourceBytes ([int64]$plan.total) -ExpectedSourceFiles ([int64]$plan.files)
  }
  if($BuildPreflightOnly){ Write-MmenuC "[$EntryPoint][build-preflight] SUCCESS: local Docker image creation verified; push skipped by BuildPreflightOnly for $imageRef" Green; $global:LASTEXITCODE = 0; $script:MmenuCProcessExitCode = 0; return }
  Write-MmenuC "[$EntryPoint][push] started immediately after image-create success; Docker push will retry recoverable failures until success; image=$imageRef"
  $pcode=Invoke-MmenuCDirectDockerPushUntilSuccess -DockerExe $dockerExe -ImageRef $imageRef -ExpectedSourcePath $projectPath -ExpectedRepository $repository -ExpectedTagName $tagName -ExpectedSourceBytes ([int64]$plan.total) -ExpectedSourceFiles ([int64]$plan.files) -ExpectedSourceFingerprint ([string]$stats.Fingerprint)
  if($pcode -ne 0){ throw "${EntryPoint}: Docker push failed with exit $pcode after image-create." }
  if(-not (Test-MmenuCRemoteExactLabels -ImageRef $imageRef -SourcePath $projectPath -Repository $repository -TagName $tagName -SourceBytes ([int64]$plan.total) -SourceFiles ([int64]$plan.files) -SourceFingerprint ([string]$stats.Fingerprint))){
    if(-not (Test-MmenuCRemoteManifest -DockerExe $dockerExe -ImageRef $imageRef)){ throw "${EntryPoint}: remote manifest verification failed after push: $imageRef" }
    Write-MmenuC "[$EntryPoint][manifest] remote manifest verified after direct Docker push: $imageRef"
  } else {
    Write-MmenuC "[$EntryPoint][manifest] remote manifest and exact source labels verified after direct Docker push: $imageRef"
  }
  Write-MmenuC "[$EntryPoint] SUCCESS: complete source scanned ($(Format-MmenuCMiB ([int64]$plan.total)), $([int]$plan.files) files), built, pushed in full, remote manifest verified, returning to PowerShell shell: $imageRef" Green
  $global:LASTEXITCODE = 0
  $script:MmenuCProcessExitCode = 0
  return
} finally {
  if($null -eq $oldPath){ Remove-Item Env:PATH -ErrorAction SilentlyContinue } else { $env:PATH = $oldPath }
  try { if($activeMarkerPath){ Remove-Item -LiteralPath $activeMarkerPath -Force -ErrorAction SilentlyContinue } } catch { }
  if($contextRoot -and (Test-Path -LiteralPath $contextRoot -PathType Container)){
    if($script:MmenuCProcessExitCode -eq 0){
      # ALLOW_DESTRUCTIVE: exact per-run context, removed only after the public
      # command has set its verified-success exit record.
      try { Remove-Item -LiteralPath $contextRoot -Recurse -Force -ErrorAction Stop } catch { Write-MmenuC ("[$EntryPoint][cleanup] retry required for completed context: {0}" -f $contextRoot) Yellow }
      try { Remove-MmenuCCompletedIdentityContexts -ContextBase $contextBase -SourcePath $projectPath -ImageRef $imageRef } catch { Write-MmenuC ("[$EntryPoint][cleanup] matching recovery-context cleanup will retry later: {0}" -f $_.Exception.Message) Yellow }
    } else {
      Write-MmenuC ("[$EntryPoint][recovery] preserving the exact failed-run layer set for retry: {0}" -f $contextRoot) Yellow
    }
  }
  try { if($contextBase){ Remove-MmenuCStaleContexts -ContextBase $contextBase } } catch { }
  try { if($script:MmenuCTempRoot){ Remove-MmenuCEmptyTempRoot -TempRoot $script:MmenuCTempRoot } } catch { }
  if($null -ne $script:MmenuCProcessExitCode){ $global:LASTEXITCODE = [int]$script:MmenuCProcessExitCode }
}
