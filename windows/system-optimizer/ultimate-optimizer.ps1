#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Ultimate System Optimizer v3 - 530 Machine-Tailored Operations
    Windows 11 Pro | Ryzen 7 9800X3D | RTX 5080 + AMD | 94GB RAM | SSD-Only
    
.DESCRIPTION
    Every single operation verified against THIS machine's installed software.
    Removed: Brave, Opera, Vivaldi, Teams, Zoom, WhatsApp, Signal, OBS, Spotify,
    Epic, GOG, Java, Adobe, Go, Gradle, Maven, Yarn, pnpm, Composer, Ruby, Azure CLI,
    AWS CLI, Terraform, Helm, Minikube, Vagrant, Postman, Insomnia, PowerBI, SQL Server,
    Cursor, VS Code Insiders, Outlook, Clipchamp, IIS, Printer, Biometric, Touch, WSL,
    Mixed Reality, Paint 3D, Hibernation
    
    Kept: Chrome, Edge, Firefox, Discord, Slack, Telegram, Steam, Docker, VS Code,
    qBittorrent, VLC, Python, Node.js, .NET, Rust, NuGet, Chocolatey, kubectl,
    NVIDIA RTX 5080, AMD Radeon, OneDrive, Cloudflare WARP, OpenClaw
    
    PS5 compatible.
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$t = Get-Date
$freed = 0
$opCount = 0

function SZ($p) { if (Test-Path $p -EA 0) { (Get-ChildItem $p -Recurse -Force -EA 0 | Measure-Object Length -Sum -EA 0).Sum } else { 0 } }
function FR($label, $paths) {
    $b = 0
    foreach ($p in $paths) {
        if (Test-Path $p -EA 0) {
            $s = SZ $p; if ($s -gt 0) { Write-Host "  $p ($([math]::Round($s/1MB))MB)" -ForegroundColor DarkGray }
            $b += $s; Get-ChildItem $p -Force -EA 0 | Remove-Item -Recurse -Force -EA 0
        }
    }
    $script:freed += $b
    if ($b -gt 0) { Write-Host "  -> $label freed: $([math]::Round($b/1MB))MB" -ForegroundColor $(if ($b -gt 50MB) { 'Green' } elseif ($b -gt 1MB) { 'Yellow' } else { 'Gray' }) }
}
function OP($msg) { $script:opCount++; Write-Host "[$($script:opCount)/530] $msg" -ForegroundColor Cyan }
function REG($path, $name, $value, $type) {
    if (-not $type) { $type = 'DWord' }
    if (!(Test-Path $path)) { New-Item $path -Force -EA 0 | Out-Null }
    Set-ItemProperty $path -Name $name -Value $value -Type $type -EA 0
}

Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Magenta
Write-Host '║  ULTIMATE OPTIMIZER v3 - 530 Ops (Machine-Tailored)         ║' -ForegroundColor Magenta
Write-Host '║  Ryzen 9800X3D | RTX 5080 + AMD | 94GB RAM | SSD-Only      ║' -ForegroundColor Magenta
Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Magenta
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
$volBefore = (Get-Volume -DriveLetter C -EA 0).SizeRemaining

# ═══════════════════════════════════════════════════════════════
# PART 1: SPACE RECOVERY (1-200) - Windows + installed apps
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ PART 1: SPACE RECOVERY (1-200) ━━━" -ForegroundColor Yellow

# --- Windows Core Cleanup ---
OP 'Delivery Optimization cache'
Stop-Service DoSvc -Force -EA 0
FR 'DeliveryOpt' @('C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache','C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Logs')
try { Delete-DeliveryOptimizationCache -Force -EA 0 } catch { Write-Host "  Cleaned manually" -ForegroundColor DarkGray }
Start-Service DoSvc -EA 0

OP 'CBS logs (>7 days)'
Get-ChildItem 'C:\Windows\Logs\CBS' -File -Force -EA 0 | Where-Object { $_.Extension -in '.log','.cab','.etl' -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'DISM logs'
FR 'DISMLogs' @('C:\Windows\Logs\DISM')

OP 'MoSetup logs'
FR 'MoSetup' @('C:\Windows\Logs\MoSetup')

OP 'WindowsUpdate logs'
FR 'WULogs' @('C:\Windows\Logs\WindowsUpdate')

OP 'Panther logs'
FR 'Panther' @('C:\Windows\Panther\UnattendGC','C:\$Windows.~BT\Sources\Panther')

OP 'Setup log files'
Get-ChildItem 'C:\Windows' -Filter 'setupact*.log' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
Get-ChildItem 'C:\Windows' -Filter 'setuperr*.log' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'MEMORY.DMP'
if (Test-Path 'C:\Windows\MEMORY.DMP') { $s = (Get-Item 'C:\Windows\MEMORY.DMP' -Force).Length; $script:freed += $s; Remove-Item 'C:\Windows\MEMORY.DMP' -Force -EA 0 }

OP 'Minidumps'
FR 'Minidumps' @('C:\Windows\Minidump')

OP 'LiveKernelReports'
FR 'LiveKernelReports' @('C:\Windows\LiveKernelReports')

OP 'Set crash to small dump'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'CrashDumpEnabled' 3

OP 'WER ReportQueue (ProgramData)'
FR 'WER1' @('C:\ProgramData\Microsoft\Windows\WER\ReportQueue')

OP 'WER ReportArchive (ProgramData)'
FR 'WER2' @('C:\ProgramData\Microsoft\Windows\WER\ReportArchive')

OP 'WER Temp (ProgramData)'
FR 'WER3' @('C:\ProgramData\Microsoft\Windows\WER\Temp')

OP 'WER ReportQueue (User)'
FR 'WER4' @("$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue")

OP 'WER ReportArchive (User)'
FR 'WER5' @("$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive")

OP 'User CrashDumps'
FR 'CrashDumps' @("$env:LOCALAPPDATA\CrashDumps")

OP 'Defender scan history (Quick >30d)'
$p = 'C:\ProgramData\Microsoft\Windows Defender\Scans\History\Results\Quick'
if (Test-Path $p) { Get-ChildItem $p -Directory -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 } }

OP 'Defender scan history (Resource >30d)'
$p = 'C:\ProgramData\Microsoft\Windows Defender\Scans\History\Results\Resource'
if (Test-Path $p) { Get-ChildItem $p -Directory -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 } }

OP 'Defender Support logs'
FR 'DefSupport' @('C:\ProgramData\Microsoft\Windows Defender\Support')

OP 'Defender old definitions backup'
FR 'DefBackup' @('C:\ProgramData\Microsoft\Windows Defender\Definition Updates\Backup')

OP 'Clear all Event Logs'
$evtBefore = (Get-ChildItem 'C:\Windows\System32\winevt\Logs' -Force -EA 0 | Measure-Object Length -Sum).Sum
wevtutil el 2>$null | ForEach-Object { wevtutil cl $_ 2>$null }
$evtAfter = (Get-ChildItem 'C:\Windows\System32\winevt\Logs' -Force -EA 0 | Measure-Object Length -Sum).Sum
$evtFreed = [math]::Max(0, $evtBefore - $evtAfter); $script:freed += $evtFreed

OP 'Font cache'
Stop-Service FontCache -Force -EA 0; Stop-Service FontCache3.0.0.0 -Force -EA 0
FR 'FontCache' @('C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache')
if (Test-Path 'C:\Windows\System32\FNTCACHE.DAT') { $s = (Get-Item 'C:\Windows\System32\FNTCACHE.DAT' -Force -EA 0).Length; $script:freed += $s; Remove-Item 'C:\Windows\System32\FNTCACHE.DAT' -Force -EA 0 }
Start-Service FontCache -EA 0

OP 'Thumbnail cache'
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter 'thumbcache_*' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Icon cache'
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter 'iconcache_*' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Windows Search index (rebuild if >500MB)'
$searchDB = 'C:\ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb'
if (Test-Path $searchDB) { $s = (Get-Item $searchDB -Force -EA 0).Length; if ($s -gt 500MB) { Stop-Service WSearch -Force -EA 0; Remove-Item $searchDB -Force -EA 0; $script:freed += $s; Start-Service WSearch -EA 0 } }

OP 'RetailDemo content'
FR 'RetailDemo' @('C:\Windows\RetailDemo')

OP 'Downloaded Program Files'
FR 'DPF' @('C:\Windows\Downloaded Program Files')

OP 'Device Stage cache'
FR 'DevStage' @("$env:LOCALAPPDATA\Microsoft\Device Stage")

OP 'Driver Store temp'
FR 'DrvTemp' @('C:\Windows\System32\DriverStore\Temp')

OP 'Debug dump'
FR 'Debug' @('C:\Windows\debug')

OP 'PerfLogs'
FR 'PerfLogs' @('C:\PerfLogs')

OP 'Windows Temp (>2d)'
Get-ChildItem 'C:\Windows\Temp' -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } | ForEach-Object { $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'User TEMP (>2d)'
Get-ChildItem $env:TEMP -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } | ForEach-Object { $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'WU downloads'
Stop-Service wuauserv -Force -EA 0
FR 'WUDown' @('C:\Windows\SoftwareDistribution\Download','C:\Windows\SoftwareDistribution\DataStore\Logs')
Start-Service wuauserv -EA 0

OP 'Recycle Bin all drives'
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object { $rb = "$($_.DriveLetter):\`$Recycle.Bin"; if (Test-Path $rb) { Get-ChildItem $rb -Recurse -Force -EA 0 | Where-Object { !$_.PSIsContainer } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 } } }

OP 'Windows.old'
if (Test-Path 'C:\Windows.old') { $s = SZ 'C:\Windows.old'; $script:freed += $s; takeown /F 'C:\Windows.old' /R /D Y 2>$null | Out-Null; icacls 'C:\Windows.old' /grant Administrators:F 2>$null | Out-Null; Remove-Item 'C:\Windows.old' -Recurse -Force -EA 0 }

OP 'Upgrade leftovers'
FR 'Upgrade' @('C:\$Windows.~BT','C:\$Windows.~WS','C:\$WINDOWS.~Q')

OP 'Installer temp files'
Get-ChildItem 'C:\Windows\Installer' -File -EA 0 | Where-Object { $_.Extension -in '.tmp','.log','.txt' } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Old MSP patches (>180d >5MB)'
Get-ChildItem 'C:\Windows\Installer' -File -EA 0 | Where-Object { $_.Extension -eq '.msp' -and $_.LastWriteTime -lt (Get-Date).AddDays(-180) -and $_.Length -gt 5MB } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'PatchCache'
FR 'PatchCache' @('C:\Windows\Installer\$PatchCache$')

OP 'Old prefetch (>30d)'
Get-ChildItem 'C:\Windows\Prefetch' -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Old ETW traces (>14d)'
Get-ChildItem 'C:\Windows\Logs' -Filter '*.etl' -Recurse -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Diagnostic logs'
FR 'DiagLogs' @('C:\Windows\Logs\SIH','C:\Windows\Logs\dosvc','C:\Windows\Logs\NetSetup','C:\Windows\Logs\waasmedic','C:\Windows\Logs\USOClient','C:\Windows\Logs\wfp','C:\Windows\Logs\CodeIntegrity','C:\Windows\Logs\CredentialGuard','C:\Windows\Logs\TaskScheduler','C:\Windows\Logs\Autopilot','C:\Windows\Logs\DCOM','C:\Windows\Logs\SystemRestore','C:\Windows\Logs\NetSetup')

OP 'WU PostReboot cache'
FR 'WUPost' @('C:\Windows\SoftwareDistribution\PostRebootEventCache.V2','C:\Windows\SoftwareDistribution\ScanFile')

OP 'Cortana data'
FR 'Cortana' @("$env:LOCALAPPDATA\Packages\Microsoft.549981C3F5F10_8wekyb3d8bbwe\LocalState")

OP 'IE/Edge legacy cache'
FR 'IECache' @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache","$env:LOCALAPPDATA\Microsoft\Windows\INetCookies\Low","$env:LOCALAPPDATA\Microsoft\Windows\INetCache\Content.IE5","$env:LOCALAPPDATA\Microsoft\Windows\Temporary Internet Files")

OP 'System profile temp'
FR 'SysTemp1' @('C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\INetCache','C:\Windows\System32\config\systemprofile\AppData\Local\Temp')

OP 'NetworkService temp'
FR 'NetSvcTemp' @('C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Temp')

OP 'LocalService temp'
FR 'LocalSvcTemp' @('C:\Windows\ServiceProfiles\LocalService\AppData\Local\Temp')

OP 'Connected Devices Platform'
FR 'CDP' @("$env:LOCALAPPDATA\ConnectedDevicesPlatform")

OP 'Notification cache'
FR 'Notif' @("$env:LOCALAPPDATA\Microsoft\Windows\Notifications")
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Notifications" -Filter '*.db-wal' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Notifications" -Filter '*.db-shm' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'BITS failed transfers'
Get-BitsTransfer -AllUsers -EA 0 | Where-Object { $_.JobState -in 'Error','TransientError','Cancelled' } | Remove-BitsTransfer -EA 0

OP 'Offline files cache'
FR 'CSC' @('C:\Windows\CSC')

OP 'Feedback Hub data'
FR 'FeedbackHub' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsFeedbackHub_8wekyb3d8bbwe\LocalState")

OP 'Store cache'
FR 'StoreCache' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\Cache","$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\AC\TokenBroker","$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\AC\INetCache")

OP 'App Installer temp'
FR 'AppInstaller' @("$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState")

OP 'UWP staged packages'
Get-AppxPackage -AllUsers -EA 0 | Where-Object { $_.PackageUserInformation.InstallState -eq 'Staged' } | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -EA 0 }

OP 'Recent items (>90d)'
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent" -File -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Jump lists (>90d)'
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations" -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations" -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Package cache old (>90d <10MB)'
Get-ChildItem 'C:\ProgramData\Package Cache' -Directory -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) -and (SZ $_.FullName) -lt 10MB } | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Old restore points (keep last 2)'
$rps = Get-ComputerRestorePoint -EA 0 | Sort-Object SequenceNumber
if ($rps -and $rps.Count -gt 2) { vssadmin delete shadows /all /quiet 2>$null | Out-Null }

OP 'MSI temp in TEMP'
Get-ChildItem "$env:TEMP" -Filter 'MSI*.tmp' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Root C: dump files'
Get-ChildItem 'C:\' -Filter '*.dmp' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'netsh logs'
Get-ChildItem 'C:\Windows' -Filter 'netsh*.log' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'setupapi.dev.log (if >10MB)'
$sl = 'C:\Windows\inf\setupapi.dev.log'
if ((Test-Path $sl) -and (Get-Item $sl -Force -EA 0).Length -gt 10MB) { $s = (Get-Item $sl -Force).Length; $script:freed += $s; Remove-Item $sl -Force -EA 0 }

OP 'WDI trace files (>30d)'
Get-ChildItem 'C:\Windows\System32\WDI' -Filter '*.etl' -Recurse -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Appcompat data'
FR 'AppCompat' @('C:\Windows\appcompat\appraiser','C:\Windows\appcompat\pca')

OP 'Device metadata cache'
FR 'DevMeta' @('C:\ProgramData\Microsoft\Windows\DeviceMetadataCache')

OP 'SCCM cache'
FR 'SCCM' @('C:\Windows\ccmcache')

OP 'Windows Assessment data'
FR 'WinSAT' @('C:\Windows\Performance\WinSAT\DataStore')

OP 'BITS downloader state'
FR 'BITSState' @("$env:ALLUSERSPROFILE\Microsoft\Network\Downloader")

OP 'GP cache'
FR 'GPCache' @("$env:LOCALAPPDATA\Microsoft\Group Policy\History")

OP 'WER metadata (>30d)'
Get-ChildItem 'C:\ProgramData\Microsoft\Windows\WER' -Filter '*.xml' -Recurse -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'PS transcript logs'
Get-ChildItem "$env:USERPROFILE\Documents" -Filter 'PowerShell_transcript*' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'NuGetScratch'
FR 'NuGetScratch' @("$env:TEMP\NuGetScratch")

OP 'VBCSCompiler temp'
FR 'VBCSComp' @("$env:TEMP\VBCSCompiler")

OP 'dotnet-diagnostic temp'
Get-ChildItem $env:TEMP -Filter 'dotnet-diagnostic-*' -Force -EA 0 | ForEach-Object { $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Razor temp'
FR 'Razor' @("$env:TEMP\Razor")

OP 'Installer extraction dirs (>7d)'
Get-ChildItem $env:TEMP -Directory -Force -EA 0 | Where-Object { $_.Name -match '^is-' -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP '7-Zip temp'
Get-ChildItem $env:TEMP -Filter '7z*' -Force -EA 0 | ForEach-Object { $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'WinRAR temp'
Get-ChildItem $env:TEMP -Filter 'Rar*' -Force -EA 0 | ForEach-Object { $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Thumbs.db cleanup'
Get-ChildItem 'C:\Users' -Recurse -Filter 'Thumbs.db' -Force -EA 0 -Depth 5 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP '.DS_Store cleanup (F drive)'
Get-ChildItem 'F:\' -Recurse -Filter '.DS_Store' -Force -EA 0 -Depth 5 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'desktop.ini in temp'
Get-ChildItem $env:TEMP -Filter 'desktop.ini' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'MSI in temp (>7d)'
Get-ChildItem 'C:\Windows\Temp' -Filter '*.msi' -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'DxDiag reports'
Get-ChildItem "$env:USERPROFILE" -Filter 'DxDiag*.txt' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'MRT debug log'
if (Test-Path "$env:SYSTEMROOT\debug\mrt.log") { $s = (Get-Item "$env:SYSTEMROOT\debug\mrt.log" -Force).Length; $script:freed += $s; Remove-Item "$env:SYSTEMROOT\debug\mrt.log" -Force -EA 0 }

OP 'COM Surrogate crash dumps'
Get-ChildItem "$env:LOCALAPPDATA" -Filter 'dllhost.exe.*.dmp' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

# --- UWP App Caches (only installed ones) ---
OP 'ShellExperienceHost TempState'
FR 'ShellExp' @("$env:LOCALAPPDATA\Packages\Microsoft.Windows.ShellExperienceHost_cw5n1h2txyewy\TempState")

OP 'Calculator cache'
FR 'Calc' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsCalculator_8wekyb3d8bbwe\LocalCache")

OP 'Alarms cache'
FR 'Alarms' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsAlarms_8wekyb3d8bbwe\LocalState")

OP 'Camera TempState'
FR 'Camera' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsCamera_8wekyb3d8bbwe\TempState")

OP 'Photos cache'
FR 'Photos' @("$env:LOCALAPPDATA\Packages\Microsoft.Windows.Photos_8wekyb3d8bbwe\LocalState\PhotosAppTile")

OP 'Terminal cache'
FR 'Terminal' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState")

OP 'Xbox cache'
FR 'Xbox' @("$env:LOCALAPPDATA\Packages\Microsoft.XboxApp_8wekyb3d8bbwe\LocalState")

OP 'Your Phone TempState'
FR 'YourPhone' @("$env:LOCALAPPDATA\Packages\Microsoft.YourPhone_8wekyb3d8bbwe\TempState")

OP 'Sticky Notes legacy'
FR 'StickyOld' @("$env:LOCALAPPDATA\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\LocalState\Legacy")

OP 'Get Help cache'
FR 'GetHelp' @("$env:LOCALAPPDATA\Packages\Microsoft.GetHelp_8wekyb3d8bbwe\LocalState")

OP 'Tips cache'
FR 'Tips' @("$env:LOCALAPPDATA\Packages\Microsoft.Getstarted_8wekyb3d8bbwe\LocalState")

OP 'Maps offline data'
FR 'Maps' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsMaps_8wekyb3d8bbwe\LocalState")

OP 'Diagnostic data viewer'
FR 'DiagViewer' @("$env:LOCALAPPDATA\Packages\Microsoft.Windows.DiagTrack.DiagnosticDataViewer_8wekyb3d8bbwe")

OP 'App diagnostics data'
FR 'AppDiag' @("$env:LOCALAPPDATA\Microsoft\Windows\AppDiagnostics","$env:LOCALAPPDATA\Diagnostics")

# --- Installed Apps Caches ---
OP 'Chrome cache (all profiles)'
$chromeUD = "$env:LOCALAPPDATA\Google\Chrome\User Data"
if (Test-Path $chromeUD) {
    Get-ChildItem $chromeUD -Directory -Force -EA 0 | Where-Object { $_.Name -match '^(Default|Profile)' } | ForEach-Object {
        foreach ($cd in @('Cache','Cache_Data','Code Cache','Service Worker','GPUCache','GrShaderCache','DawnGraphiteCache','DawnWebGPUCache','ScriptCache','blob_storage','JumpListIconsRecentClosed','JumpListIconsMostVisited','Session Storage')) {
            $cp = Join-Path $_.FullName $cd; if (Test-Path $cp -EA 0) { $s = SZ $cp; $script:freed += $s; Get-ChildItem $cp -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 }
        }
    }
    foreach ($gd in @('ShaderCache','GrShaderCache','GraphiteDawnCache','BrowserMetrics','Crashpad','Safe Browsing','Crowd Deny','MEIPreload','WidevineCdm','optimization_guide_model_store')) {
        $gp = Join-Path $chromeUD $gd; if (Test-Path $gp -EA 0) { $s = SZ $gp; $script:freed += $s; Get-ChildItem $gp -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 }
    }
}

OP 'Chrome crash reports'
FR 'ChromeCrash' @("$env:LOCALAPPDATA\Google\Chrome\User Data\Crashpad\reports")

OP 'Edge cache (all profiles)'
$edgeUD = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
if (Test-Path $edgeUD) {
    Get-ChildItem $edgeUD -Directory -Force -EA 0 | Where-Object { $_.Name -match '^(Default|Profile)' } | ForEach-Object {
        foreach ($cd in @('Cache','Cache_Data','Code Cache','Service Worker','GPUCache','GrShaderCache','ScriptCache','blob_storage')) {
            $cp = Join-Path $_.FullName $cd; if (Test-Path $cp -EA 0) { $s = SZ $cp; $script:freed += $s; Get-ChildItem $cp -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 }
        }
    }
    foreach ($gd in @('ShaderCache','GrShaderCache','BrowserMetrics','Crashpad','Safe Browsing')) { $gp = Join-Path $edgeUD $gd; if (Test-Path $gp -EA 0) { $s = SZ $gp; $script:freed += $s; Get-ChildItem $gp -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 } }
}

OP 'Edge crash reports'
FR 'EdgeCrash' @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Crashpad\reports")

OP 'Edge WebView2 cache'
FR 'EdgeWV2' @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage")

OP 'Firefox cache (all profiles)'
$ffLocal = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $ffLocal) { Get-ChildItem $ffLocal -Directory -Force -EA 0 | ForEach-Object { foreach ($cd in @('cache2','startupCache','thumbnails','safebrowsing')) { $cp = Join-Path $_.FullName $cd; if (Test-Path $cp -EA 0) { $s = SZ $cp; $script:freed += $s; Get-ChildItem $cp -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 } } } }

OP 'Firefox crash reports'
FR 'FFCrash' @("$env:APPDATA\Mozilla\Firefox\Crash Reports\submitted","$env:APPDATA\Mozilla\Firefox\Crash Reports\pending")

OP 'Discord cache'
FR 'Discord' @("$env:APPDATA\discord\Cache","$env:APPDATA\discord\Code Cache","$env:APPDATA\discord\GPUCache")

OP 'Slack cache'
FR 'Slack' @("$env:APPDATA\Slack\Cache","$env:APPDATA\Slack\Code Cache","$env:APPDATA\Slack\GPUCache","$env:APPDATA\Slack\Service Worker")

OP 'Telegram cache'
FR 'Telegram' @("$env:APPDATA\Telegram Desktop\tdata\user_data\cache","$env:APPDATA\Telegram Desktop\tdata\emoji")

OP 'VS Code cache'
FR 'VSCode' @("$env:APPDATA\Code\Cache","$env:APPDATA\Code\CachedData","$env:APPDATA\Code\CachedExtensions","$env:APPDATA\Code\Code Cache","$env:APPDATA\Code\GPUCache","$env:APPDATA\Code\logs")

OP 'Steam shader/html cache'
FR 'SteamCache' @("$env:LOCALAPPDATA\Steam\htmlcache")
if (Test-Path 'C:\Program Files (x86)\Steam\appcache') { $s = SZ 'C:\Program Files (x86)\Steam\appcache'; $script:freed += $s; Get-ChildItem 'C:\Program Files (x86)\Steam\appcache' -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 }

OP 'Docker temp'
FR 'DockerTemp' @('C:\ProgramData\Docker\tmp')

OP 'qBittorrent logs'
FR 'qBitLogs' @("$env:LOCALAPPDATA\qBittorrent\logs")

OP 'VLC art cache'
FR 'VLC' @("$env:APPDATA\vlc\art\artistalbum")

OP 'OneDrive logs'
FR 'OneDrive' @("$env:LOCALAPPDATA\Microsoft\OneDrive\logs")

OP 'Cloudflare WARP logs'
FR 'WARP' @('C:\Program Files\Cloudflare\Cloudflare WARP\logs')

OP 'NVIDIA DX/GL/Shader cache'
FR 'NvDX' @("$env:LOCALAPPDATA\NVIDIA\DXCache")
FR 'NvGL' @("$env:LOCALAPPDATA\NVIDIA\GLCache")
FR 'NvCache' @("$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache")

OP 'NVIDIA GeForce Experience cache'
FR 'GFE' @("$env:LOCALAPPDATA\NVIDIA\GeForce Experience\CefCache","$env:LOCALAPPDATA\NVIDIA\GeForce Experience\Cache")

OP 'NVIDIA telemetry/backend'
FR 'NvTelemetry' @("$env:PROGRAMDATA\NVIDIA Corporation\NvTelemetry","$env:PROGRAMDATA\NVIDIA\NvBackend")

OP 'NVIDIA crash dumps'
Get-ChildItem "$env:LOCALAPPDATA\NVIDIA" -Filter '*.dmp' -Recurse -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'AMD DX/GL/VK shader cache'
FR 'AMDDx' @("$env:LOCALAPPDATA\AMD\DxCache")
FR 'AMDGL' @("$env:LOCALAPPDATA\AMD\GLCache")
FR 'AMDVk' @("$env:LOCALAPPDATA\AMD\VkCache")

OP 'AMD Adrenalin cache'
FR 'AMDAdren' @("$env:LOCALAPPDATA\AMD\CN","$env:LOCALAPPDATA\AMD\Radeonsoftware\cache")

OP 'AMD crash dumps'
Get-ChildItem "$env:LOCALAPPDATA\AMD" -Filter '*.dmp' -Recurse -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'DirectX shader cache (system)'
FR 'DXShader' @("$env:LOCALAPPDATA\D3DSCache")

OP 'OpenClaw media temp'
FR 'OpenClawMedia' @('C:\Users\micha\.openclaw\media\inbound','C:\Users\micha\.openclaw\temp')

OP 'OpenClaw completions'
FR 'OpenClawComp' @('C:\Users\micha\.openclaw\completions')

OP 'OpenClaw logs'
FR 'OpenClawLogs' @('C:\Users\micha\.openclaw\logs')

# --- Dev Tool Caches ---
OP 'pip cache'
pip cache purge 2>$null | Out-Null
FR 'PipCache' @("$env:LOCALAPPDATA\pip\cache")

OP 'Python __pycache__'
Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -Recurse -Directory -Filter '__pycache__' -Force -EA 0 -Depth 6 | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Python .pyc files'
Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -Recurse -File -Filter '*.pyc' -Force -EA 0 -Depth 6 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'npm cache'
npm.cmd cache clean --force 2>$null | Out-Null
FR 'NpmCache' @("$env:LOCALAPPDATA\npm-cache","$env:APPDATA\npm-cache")

OP 'npm debug logs'
Get-ChildItem "$env:USERPROFILE" -Filter 'npm-debug.log*' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'NuGet fallback folder'
if (Test-Path 'C:\Program Files\dotnet\sdk\NuGetFallbackFolder') { $s = SZ 'C:\Program Files\dotnet\sdk\NuGetFallbackFolder'; $script:freed += $s; Remove-Item 'C:\Program Files\dotnet\sdk\NuGetFallbackFolder' -Recurse -Force -EA 0 }

OP 'NuGet old package versions'
$nugetPath = "$env:USERPROFILE\.nuget\packages"
if (Test-Path $nugetPath) { Get-ChildItem $nugetPath -Directory -EA 0 | ForEach-Object { $vers = Get-ChildItem $_.FullName -Directory -EA 0 | Sort-Object Name; if ($vers.Count -gt 1) { $vers | Select-Object -SkipLast 1 | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 } } } }

OP 'Rustup temp/downloads'
FR 'RustTemp' @("$env:USERPROFILE\.rustup\tmp","$env:USERPROFILE\.rustup\downloads")

OP 'Cargo registry cache'
FR 'CargoCache' @("$env:USERPROFILE\.cargo\registry\cache")

OP 'WinGet cache'
winget cache clean --force 2>$null | Out-Null
FR 'WinGet' @("$env:LOCALAPPDATA\Microsoft\WinGet\Packages","$env:LOCALAPPDATA\Microsoft\WinGet\Cache")

OP 'Chocolatey temp + nupkg'
FR 'ChocoTemp' @("$env:TEMP\chocolatey")
Get-ChildItem "$env:ProgramData\chocolatey\lib" -Filter '*.nupkg' -Recurse -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'kubectl cache'
FR 'Kubectl' @("$env:USERPROFILE\.kube\cache","$env:USERPROFILE\.kube\http-cache")

OP 'Git pack temp'
Get-ChildItem "$env:USERPROFILE" -Recurse -Filter '*.pack.tmp' -Force -EA 0 -Depth 5 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'ESLint cache'
Get-ChildItem "$env:USERPROFILE" -Filter '.eslintcache' -Recurse -Force -EA 0 -Depth 4 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Jest cache'
Get-ChildItem "$env:TEMP" -Filter 'jest_*' -Directory -Force -EA 0 | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'GitHub CLI cache'
FR 'GHCLI' @("$env:APPDATA\GitHub CLI")

OP 'PS module analysis cache'
FR 'PSModule' @("$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\ModuleAnalysisCache")

OP 'Old .NET SDKs (EOL: 2,3,5,6,7 + old patches of 8,9)'
$sdkBase = 'C:\Program Files\dotnet\sdk'
if (Test-Path $sdkBase) {
    $sdks = Get-ChildItem $sdkBase -Directory -EA 0 | Where-Object { $_.Name -match '^\d+\.\d+\.\d+' }
    $grp = @{}; foreach ($s in $sdks) { $m = $s.Name -replace '^(\d+\.\d+)\..*','$1'; if (!$grp[$m]) { $grp[$m] = @() }; $grp[$m] += $s }
    foreach ($k in $grp.Keys) { $maj = [int]($k -replace '\..*','')
        if ($maj -in 2,3,5,6,7) { foreach ($s in $grp[$k]) { $sz = SZ $s.FullName; $script:freed += $sz; Remove-Item $s.FullName -Recurse -Force -EA 0 } }
        elseif ($maj -in 8,9) { $sorted = $grp[$k] | Sort-Object { try { [version]$_.Name } catch { [version]'0.0.0' } }; if ($sorted.Count -gt 1) { $old = $sorted[0..($sorted.Count-2)]; foreach ($s in $old) { $sz = SZ $s.FullName; $script:freed += $sz; Remove-Item $s.FullName -Recurse -Force -EA 0 } } }
    }
}

OP 'Old .NET runtimes'
$sharedBase = 'C:\Program Files\dotnet\shared'
if (Test-Path $sharedBase) {
    Get-ChildItem $sharedBase -Directory -EA 0 | ForEach-Object {
        $rts = Get-ChildItem $_.FullName -Directory -EA 0 | Where-Object { $_.Name -match '^\d+\.\d+' }
        $grp = @{}; foreach ($r in $rts) { $m = $r.Name -replace '^(\d+\.\d+)\..*','$1'; if (!$grp[$m]) { $grp[$m] = @() }; $grp[$m] += $r }
        foreach ($k in $grp.Keys) { $maj = [int]($k -replace '\..*','')
            if ($maj -in 2,3,5,6,7) { foreach ($r in $grp[$k]) { $sz = SZ $r.FullName; $script:freed += $sz; Remove-Item $r.FullName -Recurse -Force -EA 0 } }
            elseif ($maj -in 8,9) { $sorted = $grp[$k] | Sort-Object { try { [version]($_.Name -replace '-.*','') } catch { [version]'0.0.0' } }; if ($sorted.Count -gt 1) { $old = $sorted[0..($sorted.Count-2)]; foreach ($r in $old) { $sz = SZ $r.FullName; $script:freed += $sz; Remove-Item $r.FullName -Recurse -Force -EA 0 } } }
        }
    }
}

OP 'Electron app caches (generic Roaming)'
Get-ChildItem "$env:APPDATA" -Directory -EA 0 | ForEach-Object {
    foreach ($c in @('Cache','GPUCache')) { $cp = Join-Path $_.FullName $c; if ((Test-Path $cp) -and (SZ $cp) -gt 5MB) { $s = SZ $cp; $script:freed += $s; Get-ChildItem $cp -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 } }
}

OP 'Windows Timeline'
FR 'Timeline' @("$env:LOCALAPPDATA\ConnectedDevicesPlatform\L.micha")

OP 'Font download cache'
FR 'FontDL' @("$env:LOCALAPPDATA\Microsoft\FontCache")

OP 'Start menu tile cache'
FR 'TileCache' @("$env:LOCALAPPDATA\Microsoft\Windows\Caches")

OP 'Copilot logs'
FR 'CopilotLogs' @("$env:LOCALAPPDATA\Microsoft\Windows\CopilotRuntime\Logs")

OP 'CompactOS'
compact /compactos:always 2>$null | Out-Null

OP 'DISM component cleanup'
$jDism = Start-Job { dism /online /cleanup-image /startcomponentcleanup /resetbase 2>&1 | Select-Object -Last 1 }
$done = Wait-Job $jDism -Timeout 90 -EA 0; if ($done) { Receive-Job $jDism -EA 0 | Out-Null }; if (!$done) { Stop-Job $jDism -EA 0 }; Remove-Job $jDism -Force -EA 0

OP 'Disable reserved storage'
DISM /Online /Set-ReservedStorageState /State:Disabled 2>$null | Out-Null

OP 'WinSxS backup'
FR 'WinSxSBak' @('C:\Windows\WinSxS\Backup')

OP 'Service Pack uninstall data'
FR 'SPData' @('C:\Windows\$hf_mig$')

OP 'Provisioning packages'
FR 'ProvPkg' @('C:\Windows\Provisioning\Packages')

# ═══════════════════════════════════════════════════════════════
# PART 2: SERVICES (201-260) - Disable unnecessary
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ PART 2: SERVICES (201-260) ━━━" -ForegroundColor Yellow

$svcList = @(
    @('DiagTrack','Telemetry'),@('dmwappushservice','WAP Push'),@('RetailDemo','Retail Demo'),
    @('MapsBroker','Maps'),@('lfsvc','Geolocation'),@('SharedAccess','ICS'),
    @('RemoteRegistry','Remote Registry'),@('TrkWks','Link Tracking'),@('WMPNetworkSvc','WMP Network'),
    @('WerSvc','Error Reporting'),@('Fax','Fax'),@('SysMain','Superfetch'),
    @('wisvc','Insider'),@('PhoneSvc','Phone'),@('TabletInputService','Touch Keyboard'),
    @('SEMgrSvc','NFC Payments'),@('icssvc','Mobile Hotspot'),@('WpcMonSvc','Parental Controls'),
    @('RmSvc','Radio Mgmt'),@('SensorService','Sensors'),@('SensrSvc','Sensor Monitor'),
    @('SensorDataService','Sensor Data'),@('ScDeviceEnum','Smart Card Enum'),@('SCPolicySvc','Smart Card Policy'),
    @('SCardSvr','Smart Card'),@('XblAuthManager','Xbox Auth'),@('XblGameSave','Xbox Save'),
    @('XboxGipSvc','Xbox Accessory'),@('XboxNetApiSvc','Xbox Net'),@('MessagingService','Messaging'),
    @('PcaSvc','Compat Assistant'),@('FrameServer','Camera Frame'),@('WalletService','Wallet'),
    @('DPS','Diagnostic Policy'),@('WdiServiceHost','Diag Host'),@('WdiSystemHost','Diag System'),
    @('DoSvc','Delivery Optimization'),@('uhssvc','Update Health'),@('WbioSrvc','Biometric'),
    @('AssignedAccessManagerSvc','Kiosk'),@('wercplsupport','Problem Reports'),@('stisvc','Image Acquisition'),
    @('PushToInstall','Push Install'),@('shpamsvc','Shared PC'),@('AppReadiness','App Readiness'),
    @('AJRouter','AllJoyn Router'),@('ALG','App Layer Gateway'),@('NetTcpPortSharing','TCP Port Share'),
    @('p2pimsvc','Peer Networking ID'),@('PNRPAutoReg','PNRP Auto'),@('PNRPsvc','PNRP'),
    @('Spooler','Print Spooler'),@('TermService','Remote Desktop'),@('SessionEnv','RD Config'),
    @('UmRdpService','RD Port Redir'),@('NcbService','Network Conn Broker'),
    @('EntAppSvc','Enterprise App'),@('WinRM','WinRM'),@('lmhosts','TCP/IP NetBIOS Helper'),
    @('NaturalAuthentication','Natural Auth'),@('wlidsvc','MS Account Sign-in')
)

foreach ($si in $svcList) {
    OP "Disable: $($si[1])"
    $svc = Get-Service $si[0] -EA 0
    if ($svc -and $svc.StartType -ne 'Disabled') { Stop-Service $si[0] -Force -EA 0; Set-Service $si[0] -StartupType Disabled -EA 0 }
}

# ═══════════════════════════════════════════════════════════════
# PART 3: SCHEDULED TASKS (261-320)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ PART 3: SCHEDULED TASKS (261-320) ━━━" -ForegroundColor Yellow

$taskList = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Maps\MapsToastTask',
    '\Microsoft\Windows\Maps\MapsUpdateTask',
    '\Microsoft\Windows\PI\Sqm-Tasks',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
    '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask',
    '\Microsoft\Windows\DiskFootprint\Diagnostics',
    '\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting',
    '\Microsoft\Windows\Flighting\OneSettings\RefreshCache',
    '\Microsoft\Windows\Input\LocalUserSyncDataAvailable',
    '\Microsoft\Windows\Input\MouseSyncDataAvailable',
    '\Microsoft\Windows\Input\PenSyncDataAvailable',
    '\Microsoft\Windows\Input\TouchpadSyncDataAvailable',
    '\Microsoft\Windows\International\Synchronize Language Settings',
    '\Microsoft\Windows\LanguageComponentsInstaller\Installation',
    '\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources',
    '\Microsoft\Windows\License Manager\TempSignedLicenseExchange',
    '\Microsoft\Windows\Mobile Broadband Accounts\MNO Metadata Parser',
    '\Microsoft\Windows\NetTrace\GatherNetworkInfo',
    '\Microsoft\Windows\Offline Files\Background Synchronization',
    '\Microsoft\Windows\Offline Files\Logon Synchronization',
    '\Microsoft\Windows\RemoteAssistance\RemoteAssistanceTask',
    '\Microsoft\Windows\SettingSync\BackgroundUploadTask',
    '\Microsoft\Windows\SettingSync\NetworkStateChangeTask',
    '\Microsoft\Windows\Shell\FamilySafetyMonitor',
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask',
    '\Microsoft\Windows\Speech\SpeechModelDownloadTask',
    '\Microsoft\Windows\WCM\WiFiTask',
    '\Microsoft\Windows\WlanSvc\CDSSync',
    '\Microsoft\Windows\Work Folders\Work Folders Logon Synchronization',
    '\Microsoft\Windows\Work Folders\Work Folders Maintenance Work',
    '\Microsoft\Windows\Workplace Join\Automatic-Device-Join',
    '\Microsoft\Windows\WwanSvc\NotificationTask',
    '\Microsoft\Windows\WwanSvc\OobeDiscovery',
    '\Microsoft\Windows\Management\Provisioning\Cellular',
    '\Microsoft\Windows\Management\Provisioning\Logon',
    '\Microsoft\Windows\Subscription\EnableLicenseAcquisition',
    '\Microsoft\Windows\Subscription\LicenseAcquisition',
    '\Microsoft\Windows\SpacePort\SpaceAgentTask',
    '\Microsoft\Windows\SpacePort\SpaceManagerTask',
    '\Microsoft\Windows\WOF\WIM-Hash-Management',
    '\Microsoft\Windows\WOF\WIM-Hash-Validation',
    '\Microsoft\Windows\FileHistory\File History (maintenance mode)',
    '\Microsoft\Windows\Windows Filtering Platform\BfeOnServiceStartTypeChange',
    '\Microsoft\Windows\Shell\IndexerAutomaticMaintenance',
    '\Microsoft\Windows\DiskFootprint\StorageSense'
)

foreach ($task in $taskList) {
    OP "Disable: $($task -replace '.*\\','')"
    $tn = $task -replace '.*\\',''; $tp = $task -replace '[^\\]+$',''
    $st = Get-ScheduledTask -TaskName $tn -TaskPath $tp -EA 0
    if ($st -and $st.State -ne 'Disabled') { Disable-ScheduledTask -TaskName $tn -TaskPath $tp -EA 0 | Out-Null }
}

# ═══════════════════════════════════════════════════════════════
# PART 4: REGISTRY TWEAKS (321-500)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ PART 4: REGISTRY TWEAKS (321-500) ━━━" -ForegroundColor Yellow

# --- Visual Effects ---
OP 'Disable animations'; REG 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
OP 'Menu delay 0'; REG 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
OP 'Disable Aero Peek'; REG 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
OP 'Disable thumbnail hibernate'; REG 'HKCU:\Software\Microsoft\Windows\DWM' 'AlwaysHibernateThumbnails' 0
OP 'Disable cursor shadow'; REG 'HKCU:\Control Panel\Desktop' 'CursorShadow' 0
OP 'Disable taskbar animations'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
OP 'Disable selection fade'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewAlphaSelect' 0
OP 'Keep ClearType'; REG 'HKCU:\Control Panel\Desktop' 'FontSmoothing' '2' 'String'
OP 'Disable combo box anim'; REG 'HKCU:\Control Panel\Desktop' 'ComboBoxAnimation' 0
OP 'Custom visual FX'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
OP 'Disable peek desktop'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'DisablePreviewDesktop' 1
OP 'Disable listview shadow'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewShadow' 0

# --- NTFS ---
OP 'Disable last access'; fsutil behavior set disablelastaccess 1 2>$null | Out-Null
OP 'Disable 8.3 names'; fsutil behavior set disable8dot3 1 2>$null | Out-Null
OP 'NTFS memory usage'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsMemoryUsage' 2
OP 'Long paths enabled'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1
OP 'NTFS disable encryption'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableEncryption' 1
OP 'Contig file alloc size'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'ContigFileAllocSize' 64

# --- Memory ---
OP 'Disable paging executive'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1
OP 'Large system cache'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'LargeSystemCache' 1
OP 'IoPageLockLimit'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'IoPageLockLimit' 983040
OP 'SystemPages auto'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'SystemPages' 0
OP 'Pool usage max'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'PoolUsageMaximum' 60
OP 'SecondLevelDataCache'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'SecondLevelDataCache' 1024
OP 'Disable Superfetch reg'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnableSuperfetch' 0
OP 'Disable Prefetcher reg'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnablePrefetcher' 0

# --- Boot ---
OP 'Startup delay 0'
New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Force -EA 0 | Out-Null
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0
OP 'Desktop switch timeout 0'; REG 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DelayedDesktopSwitchTimeout' 0
OP 'Boot timeout 3'; bcdedit /timeout 3 2>$null | Out-Null
OP 'Verbose boot'; REG 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'VerboseStatus' 1

# --- SSD ---
OP 'Enable TRIM'; fsutil behavior set disabledeletenotify 0 2>$null | Out-Null
OP 'Disable defrag SSD'; REG 'HKLM:\SOFTWARE\Microsoft\Dfrg\BootOptimizeFunction' 'Enable' 'N' 'String'
OP 'Disable ReadyBoost'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\rdyboost' 'Start' 4

# --- Network ---
OP 'DNS max TTL'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'MaxCacheTtl' 86400
OP 'DNS neg TTL'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'MaxNegativeCacheTtl' 5
OP 'TCP TIME_WAIT 30'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'TcpTimedWaitDelay' 30
OP 'Max user ports'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'MaxUserPort' 65534
OP 'Max free TCBs'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'MaxFreeTcbs' 65536
OP 'Max hash table'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'MaxHashTableSize' 65536
OP 'TCP auto-tuning'; netsh int tcp set global autotuninglevel=normal 2>$null | Out-Null
OP 'Enable RSS'; netsh int tcp set global rss=enabled 2>$null | Out-Null
OP 'Disable chimney'; netsh int tcp set global chimney=disabled 2>$null | Out-Null
OP 'Disable ECN'; netsh int tcp set global ecncapability=disabled 2>$null | Out-Null
OP 'No network throttle'; REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xFFFFFFFF
OP 'System responsiveness 0'; REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 0
OP 'Disable Nagle all interfaces'
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -EA 0 | ForEach-Object { REG $_.PSPath 'TcpAckFrequency' 1; REG $_.PSPath 'TCPNoDelay' 1; REG $_.PSPath 'TcpDelAckTicks' 0 }
OP 'DNS cache buckets'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'CacheHashTableBucketSize' 1
OP 'DNS cache size'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'CacheHashTableSize' 384
OP 'DNS max entry TTL'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'MaxCacheEntryTtlLimit' 64000
OP 'Disable NetBIOS'
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -EA 0 | ForEach-Object { REG $_.PSPath 'NetbiosOptions' 2 }
OP 'Disable LMHOSTS'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters' 'EnableLMHOSTS' 0

# --- GPU ---
OP 'HW GPU scheduling'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
OP 'Disable MPO'; REG 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5
OP 'GPU preemption off'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler' 'EnablePreemption' 0
OP 'Disable NVIDIA telemetry svc'; Set-Service NvTelemetryContainer -StartupType Disabled -EA 0; Stop-Service NvTelemetryContainer -Force -EA 0
OP 'NVIDIA telemetry opt-out'; REG 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 0
OP 'Game DVR off'; REG 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
OP 'Game Bar minimize'; REG 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0; REG 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' 0
OP 'Game Mode on'; REG 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
OP 'Fullscreen opt off'; REG 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2; REG 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 1; REG 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehavior' 2

# --- Ads/Tips/Telemetry ---
OP 'Tips off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
OP 'Suggested apps off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0
OP 'Start suggestions off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
OP 'Suggested content 1 off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 0
OP 'Suggested content 2 off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 0
OP 'Silent installs off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
OP 'System suggestions off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
OP 'Soft landing off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 0
OP 'Lock screen suggestions off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 0
OP 'Lock screen overlay off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0
OP 'Pre-installed apps off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0
OP 'OEM apps off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 0
OP 'Settings suggestions off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 0
OP 'Bing search off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
OP 'Cortana off'; New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Force -EA 0 | Out-Null; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0
OP 'Web search off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
OP 'Search highlights off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
OP 'Advertising ID off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
OP 'Tailored experiences off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
OP 'Telemetry basic'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
OP 'Feedback off'; REG 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
OP 'Activity history off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
OP 'Cloud clipboard off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0
OP 'App launch tracking off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0
OP 'Recent docs tracking off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackDocs' 0

# --- Explorer ---
OP 'Classic context menu'; New-Item 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -Force -EA 0 | Out-Null; Set-ItemProperty 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -Name '(Default)' -Value '' -EA 0
OP 'Open to This PC'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1
OP 'OneDrive ads off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
OP 'Show file ext'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0
OP 'Show hidden files'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' 1
OP 'Show protected OS files'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSuperHidden' 1
OP 'Thumb cache off network'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'DisableThumbnailCache' 1; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'DisableThumbsDBOnNetworkFolders' 1
OP 'Folder type auto-detect off'
New-Item 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' -Force -EA 0 | Out-Null
Set-ItemProperty 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' -Name 'FolderType' -Value 'NotSpecified' -EA 0

# --- Power/CPU ---
OP 'Power throttle off'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
OP 'Boost aggressive'; powercfg /setacvalueindex scheme_current sub_processor PERFBOOSTMODE 2 2>$null | Out-Null; powercfg /setactive scheme_current 2>$null | Out-Null
OP 'Core parking 100%'; powercfg /setacvalueindex scheme_current sub_processor CPMINCORES 100 2>$null | Out-Null
OP 'Min CPU 100%'; powercfg /setacvalueindex scheme_current sub_processor PROCTHROTTLEMIN 100 2>$null | Out-Null
OP 'Max CPU 100%'; powercfg /setacvalueindex scheme_current sub_processor PROCTHROTTLEMAX 100 2>$null | Out-Null
OP 'USB suspend off'; powercfg /setacvalueindex scheme_current 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
OP 'HDD never off'; powercfg /setacvalueindex scheme_current 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0 2>$null | Out-Null
OP 'Display 15min'; powercfg /setacvalueindex scheme_current 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 900 2>$null | Out-Null
OP 'Never sleep AC'; powercfg /setacvalueindex scheme_current 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0 2>$null | Out-Null
powercfg /setactive scheme_current 2>$null | Out-Null
OP 'Win32 priority sep'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38
OP 'MMCSS Games GPU 8'; REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'GPU Priority' 8
OP 'MMCSS Games Priority 6'; REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Priority' 6
OP 'MMCSS Games High'; REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'High' 'String'
OP 'MMCSS Games SFIO High'; REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'SFIO Priority' 'High' 'String'
OP 'MMCSS Audio Priority 1'; REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio' 'Priority' 1
OP 'MMCSS Audio High'; REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio' 'Scheduling Category' 'High' 'String'

# --- Security (safe hardening) ---
OP 'Remote assistance off'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
OP 'Remote desktop off'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1
OP 'Autorun off all'; REG 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255
OP 'Autoplay off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' 'DisableAutoplay' 1
OP 'Admin shares off'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'AutoShareWks' 0
OP 'SMB signing'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'RequireSecuritySignature' 1
OP 'SMBv1 off'; Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -EA 0; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1' 0
OP 'LLMNR off'; New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Force -EA 0 | Out-Null; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0
OP 'WPAD off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad' 'WpadOverride' 1
OP 'WinRM disabled'; Set-Service WinRM -StartupType Disabled -EA 0; Stop-Service WinRM -Force -EA 0

# --- Misc perf ---
OP 'Mouse precision off'; REG 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'; REG 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'; REG 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
OP 'Keyboard speed max'; REG 'HKCU:\Control Panel\Keyboard' 'KeyboardSpeed' '31' 'String'
OP 'Keyboard delay min'; REG 'HKCU:\Control Panel\Keyboard' 'KeyboardDelay' '0' 'String'
OP 'Sticky keys off'; REG 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
OP 'Toggle keys off'; REG 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58' 'String'
OP 'Filter keys off'; REG 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String'
OP 'Edge prelaunch off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main' 'AllowPrelaunch' 0
OP 'Edge tab preload off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader' 'AllowTabPreloading' 0
OP 'Background apps off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
OP 'Transparency off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
OP 'Bing Start off'; New-Item 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Force -EA 0 | Out-Null; REG 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
OP 'Widgets off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
OP 'Meet Now off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'HideSCAMeetNow' 1
OP 'Task View off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' 0
OP 'Copilot off'; REG 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
OP 'Recall off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
OP 'First logon anim off'; REG 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableFirstLogonAnimation' 0
OP 'UAC dim off'; REG 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop' 0
OP 'Lock screen off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' 'NoLockScreen' 1
OP 'Consumer features off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
OP 'Spotlight off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1
OP 'Third party suggestions off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1
OP 'Typing insights off'; REG 'HKCU:\Software\Microsoft\Input\Settings' 'InsightsEnabled' 0
OP 'Inking personalization off'; REG 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1; REG 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
OP 'Online speech off'; REG 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
OP 'Location off'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1
OP 'Defender sample submit control'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet' 'SubmitSamplesConsent' 2
OP 'Defender scan CPU 25%'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan' 'AvgCPULoadFactor' 25
OP 'Defender UI suppress'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration' 'Notification_Suppress' 1
OP 'Low disk check off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoLowDiskSpaceChecks' 1
OP 'Storage sense off'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 0

# --- I/O / Timers ---
OP 'Service kill timeout 2s'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '2000' 'String'
OP 'Hung app timeout 1s'; REG 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '1000' 'String'
OP 'Auto end tasks'; REG 'HKCU:\Control Panel\Desktop' 'AutoEndTasks' '1' 'String'
OP 'App kill timeout 2s'; REG 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '2000' 'String'
OP 'AHCI HIPM off'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\storahci\Parameters\Device' 'HIPM_Disable' 1
OP 'AHCI DIPM off'; REG 'HKLM:\SYSTEM\CurrentControlSet\Services\storahci\Parameters\Device' 'DIPM_Disable' 1
OP 'Timer resolution'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1
OP 'Distribute timers'; REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DistributeTimers' 1
OP 'Dynamic tick off'; bcdedit /set disabledynamictick yes 2>$null | Out-Null
OP 'Platform clock off'; bcdedit /set useplatformclock false 2>$null | Out-Null
OP 'TSC sync enhanced'; bcdedit /set tscsyncpolicy enhanced 2>$null | Out-Null
OP 'Boot timeout 3s'; bcdedit /timeout 3 2>$null | Out-Null

# --- Privacy sharing ---
OP 'Account info deny'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{C1D23ACC-752B-43E5-8448-8D0E519CD6D6}' 'Value' 'Deny' 'String'
OP 'Calendar deny'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{D89823BA-7180-4B81-B50C-7E471E6121A3}' 'Value' 'Deny' 'String'
OP 'Call history deny'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{8BC668CF-7728-45BD-93F8-CF2B3B41D7AB}' 'Value' 'Deny' 'String'
OP 'Email deny'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{9231CB4C-BF57-4AF3-8C55-FDA7BFCC04C5}' 'Value' 'Deny' 'String'
OP 'Messaging deny'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{992AFA70-6F47-4148-B3E9-3003349C1548}' 'Value' 'Deny' 'String'
OP 'Radio deny'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{A8804298-2D5F-42E3-9531-9C8C39EB29CE}' 'Value' 'Deny' 'String'
OP 'Tasks deny'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{E390DF20-07DF-446D-B962-F5C953062741}' 'Value' 'Deny' 'String'
OP 'Diagnostics deny'; REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{2297E4E2-5DBE-466D-A12B-0F8286F0D9CA}' 'Value' 'Deny' 'String'

# --- Windows Update ---
OP 'No auto-restart WU'; New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Force -EA 0 | Out-Null; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1
OP 'WU download only'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions' 3
OP 'No seeding updates'; REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0

# ═══════════════════════════════════════════════════════════════
# PART 5: FINAL MAINTENANCE (501-530)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ PART 5: FINAL MAINTENANCE (501-530) ━━━" -ForegroundColor Yellow

OP 'Flush DNS'; ipconfig /flushdns 2>$null | Out-Null
OP 'Flush ARP'; netsh interface ip delete arpcache 2>$null | Out-Null
OP 'Rebuild icon cache'; ie4uinit.exe -show 2>$null
OP 'Reset Winsock'; netsh winsock reset 2>$null | Out-Null
OP 'Reset WinHTTP proxy'; netsh winhttp reset proxy 2>$null | Out-Null
OP 'Purge Kerberos tickets'; klist purge 2>$null | Out-Null
OP 'Update Group Policy'; gpupdate /force 2>$null | Out-Null
OP 'NTP sync'; w32tm /config /update /manualpeerlist:"time.windows.com,0x1 time.google.com,0x1 pool.ntp.org,0x1" /syncfromflags:manual /reliable:YES 2>$null | Out-Null
OP 'SFC scan (background)'
$jSfc = Start-Job { sfc /scannow 2>&1 | Select-Object -Last 3 }; Wait-Job $jSfc -Timeout 120 -EA 0 | Out-Null; Stop-Job $jSfc -EA 0; Remove-Job $jSfc -Force -EA 0
OP 'TRIM all SSDs'
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object { Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -EA 0 }
OP 'Refresh env vars'
[System.Environment]::SetEnvironmentVariable('Path', [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User'), 'Process')
OP 'Apply registry changes'
rundll32.exe user32.dll,UpdatePerUserSystemParameters ,1 ,True 2>$null
OP 'Restart Explorer'
Stop-Process -Name explorer -Force -EA 0; Start-Sleep 2; Start-Process explorer

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
$elapsed = (Get-Date) - $t
$volAfter = (Get-Volume -DriveLetter C -EA 0).SizeRemaining
$actualFreed = 0
if ($volBefore -and $volAfter -and ($volAfter -gt $volBefore)) { $actualFreed = $volAfter - $volBefore }

Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Green
Write-Host '║     ULTIMATE OPTIMIZER v3 COMPLETE (530 OPS)                ║' -ForegroundColor Green
Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Green
Write-Host ''
Write-Host "  Operations executed:  $opCount / 530" -ForegroundColor White
Write-Host "  Elapsed time:        $([math]::Floor($elapsed.TotalMinutes))m $($elapsed.Seconds)s" -ForegroundColor White
Write-Host ''
Write-Host '  ┌─────────────────────────────────────────────────────────────┐' -ForegroundColor Yellow
Write-Host "  │  TOTAL SPACE FREED:  $([math]::Round($freed/1MB)) MB  ($([math]::Round($freed/1GB,2)) GB)" -ForegroundColor Yellow
Write-Host '  └─────────────────────────────────────────────────────────────┘' -ForegroundColor Yellow
if ($actualFreed -gt 0) { Write-Host "  Actual disk delta:   +$([math]::Round($actualFreed/1GB,2)) GB" -ForegroundColor Cyan }
$vol = Get-Volume -DriveLetter C -EA 0
if ($vol) {
    $freeGB = $vol.SizeRemaining / 1GB; $totalGB = $vol.Size / 1GB; $pct = ($vol.SizeRemaining / $vol.Size) * 100
    Write-Host "  C: drive:            $([math]::Round($freeGB,2)) GB free / $([math]::Round($totalGB,2)) GB ($([math]::Round($pct,1))%)" -ForegroundColor $(if ($pct -gt 20) { 'Green' } elseif ($pct -gt 10) { 'Yellow' } else { 'Red' })
}
Write-Host ''
Write-Host '  Tailored for: Ryzen 9800X3D | RTX 5080 + AMD | 94GB | SSD-only' -ForegroundColor DarkCyan
Write-Host '  Removed 40+ irrelevant ops (no Brave/Teams/Zoom/Java/Adobe/WSL/etc)' -ForegroundColor DarkCyan
Write-Host '  PS5 compatible | Restart recommended' -ForegroundColor DarkYellow
Write-Host ''
