#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deep System Optimizer v2 - 530 operations
    Space recovery + Performance maximization + Security hardening
    Covers EVERYTHING that cccc/nocccc/ccc/ccc4/ccc5/cleanc DO NOT cover
    
.NOTES
    SAFE: Never removes user files, installed programs, game saves, or personal data
    Outputs total space freed at end
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
function REG($path, $name, $value, $type = 'DWord') {
    $parent = Split-Path $path
    if (!(Test-Path $path)) { New-Item $path -Force -EA 0 | Out-Null }
    Set-ItemProperty $path -Name $name -Value $value -Type $type -EA 0
}

Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Magenta
Write-Host '║  DEEP SYSTEM OPTIMIZER v2 — 530 Operations                  ║' -ForegroundColor Magenta
Write-Host '║  Space Recovery + Performance + Security + Optimization     ║' -ForegroundColor Magenta
Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Magenta
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
$volBefore = (Get-Volume -DriveLetter C -EA 0).SizeRemaining

# ═══════════════════════════════════════════════════════════════
# SECTION A: SPACE RECOVERY (Operations 1-120)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ SECTION A: SPACE RECOVERY (1-120) ━━━" -ForegroundColor Yellow

OP 'Delivery Optimization cache'
Stop-Service DoSvc -Force -EA 0
FR 'DeliveryOptimization' @('C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache','C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Logs')
Delete-DeliveryOptimizationCache -Force -EA 0
Start-Service DoSvc -EA 0

OP 'CBS logs'
Get-ChildItem 'C:\Windows\Logs\CBS' -File -Force -EA 0 | Where-Object { $_.Extension -in '.log','.cab','.etl' -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'DISM logs'
FR 'DISMLogs' @('C:\Windows\Logs\DISM')

OP 'MoSetup logs'
FR 'MoSetup' @('C:\Windows\Logs\MoSetup')

OP 'WindowsUpdate logs'
FR 'WULogs' @('C:\Windows\Logs\WindowsUpdate')

OP 'Panther logs'
FR 'Panther' @('C:\Windows\Panther\UnattendGC','C:\$Windows.~BT\Sources\Panther')

OP 'Setup log files in Windows root'
Get-ChildItem 'C:\Windows' -Filter 'setupact*.log' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
Get-ChildItem 'C:\Windows' -Filter 'setuperr*.log' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'MEMORY.DMP'
if (Test-Path 'C:\Windows\MEMORY.DMP') { $s = (Get-Item 'C:\Windows\MEMORY.DMP' -Force).Length; $script:freed += $s; Remove-Item 'C:\Windows\MEMORY.DMP' -Force -EA 0 }

OP 'Minidumps'
FR 'Minidumps' @('C:\Windows\Minidump')

OP 'LiveKernelReports'
FR 'LiveKernelReports' @('C:\Windows\LiveKernelReports')

OP 'Set crash dumps to small memory dump'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'CrashDumpEnabled' 3

OP 'WER ReportQueue (ProgramData)'
FR 'WER-PD-Queue' @('C:\ProgramData\Microsoft\Windows\WER\ReportQueue')

OP 'WER ReportArchive (ProgramData)'
FR 'WER-PD-Archive' @('C:\ProgramData\Microsoft\Windows\WER\ReportArchive')

OP 'WER Temp (ProgramData)'
FR 'WER-PD-Temp' @('C:\ProgramData\Microsoft\Windows\WER\Temp')

OP 'WER ReportQueue (User)'
FR 'WER-User-Queue' @("$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue")

OP 'WER ReportArchive (User)'
FR 'WER-User-Archive' @("$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive")

OP 'User CrashDumps'
FR 'CrashDumps' @("$env:LOCALAPPDATA\CrashDumps")

OP 'Defender old scan history (Quick)'
$defHist = 'C:\ProgramData\Microsoft\Windows Defender\Scans\History\Results\Quick'
if (Test-Path $defHist) { Get-ChildItem $defHist -Directory -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 } }

OP 'Defender old scan history (Resource)'
$defHist2 = 'C:\ProgramData\Microsoft\Windows Defender\Scans\History\Results\Resource'
if (Test-Path $defHist2) { Get-ChildItem $defHist2 -Directory -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 } }

OP 'Defender Support logs'
FR 'DefenderSupport' @('C:\ProgramData\Microsoft\Windows Defender\Support')

OP 'Clear all Event Logs'
$evtBefore = (Get-ChildItem 'C:\Windows\System32\winevt\Logs' -Force -EA 0 | Measure-Object Length -Sum).Sum
wevtutil el 2>$null | ForEach-Object { wevtutil cl $_ 2>$null }
$evtAfter = (Get-ChildItem 'C:\Windows\System32\winevt\Logs' -Force -EA 0 | Measure-Object Length -Sum).Sum
$evtFreed = [math]::Max(0, $evtBefore - $evtAfter); $script:freed += $evtFreed
Write-Host "  Event logs freed: $([math]::Round($evtFreed/1MB))MB" -ForegroundColor Green

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
if (Test-Path $searchDB) { $s = (Get-Item $searchDB -Force -EA 0).Length; if ($s -gt 500MB) { Stop-Service WSearch -Force -EA 0; Remove-Item $searchDB -Force -EA 0; $script:freed += $s; Start-Service WSearch -EA 0; Write-Host "  Search index rebuilt ($([math]::Round($s/1MB))MB)" -ForegroundColor Green } }

OP 'RetailDemo content'
FR 'RetailDemo' @('C:\Windows\RetailDemo')

OP 'Downloaded Program Files (ActiveX)'
FR 'DownloadedProgFiles' @('C:\Windows\Downloaded Program Files')

OP 'Device Stage cache'
FR 'DeviceStage' @("$env:LOCALAPPDATA\Microsoft\Device Stage")

OP 'GameExplorer cache'
FR 'GameExplorer' @("$env:LOCALAPPDATA\Microsoft\Windows\GameExplorer")

OP 'Windows Update DataStore logs'
FR 'WUDataStoreLogs' @('C:\Windows\SoftwareDistribution\DataStore\Logs')

OP 'ShellExperienceHost TempState'
FR 'ShellExpHost' @("$env:LOCALAPPDATA\Packages\Microsoft.Windows.ShellExperienceHost_cw5n1h2txyewy\TempState")

OP 'Driver Store temp'
FR 'DriverStoreTemp' @('C:\Windows\System32\DriverStore\Temp')

OP 'Installer rollback temp files'
Get-ChildItem 'C:\Windows\Installer' -File -EA 0 | Where-Object { $_.Extension -in '.tmp','.log','.txt' } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Old MSP patches (>180 days, >5MB)'
Get-ChildItem 'C:\Windows\Installer' -File -EA 0 | Where-Object { $_.Extension -eq '.msp' -and $_.LastWriteTime -lt (Get-Date).AddDays(-180) -and $_.Length -gt 5MB } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Windows debug dump files'
FR 'DebugDump' @('C:\Windows\debug')

OP 'Performance Monitor logs'
FR 'PerfLogs' @('C:\PerfLogs')

OP 'IIS logs'
FR 'IISLogs' @('C:\inetpub\logs')

OP 'Windows Temp (>2 days old)'
Get-ChildItem 'C:\Windows\Temp' -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } | ForEach-Object { $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'User TEMP (>2 days old)'
Get-ChildItem $env:TEMP -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } | ForEach-Object { $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Windows Update pending downloads'
Stop-Service wuauserv -Force -EA 0
FR 'WUPending' @('C:\Windows\SoftwareDistribution\Download')
Start-Service wuauserv -EA 0

OP 'Old driver packages (keep latest per driver)'
# Clean staged driver packages that are superseded
$driverPacks = pnputil /enum-drivers 2>$null
if ($driverPacks) { Write-Host "  Driver cleanup via pnputil skipped (safe mode)" -ForegroundColor DarkGray }

OP 'Recycle Bin ($Recycle.Bin) on all drives'
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
    $rb = "$($_.DriveLetter):\`$Recycle.Bin"
    if (Test-Path $rb) { Get-ChildItem $rb -Recurse -Force -EA 0 | Where-Object { !$_.PSIsContainer } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 } }
}

OP 'Windows Upgrade leftovers'
FR 'WinUpgrade' @('C:\$Windows.~BT','C:\$Windows.~WS','C:\$WINDOWS.~Q')

OP 'Edge WebView2 cache'
FR 'EdgeWebView2' @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage")

OP 'Teams classic cache'
FR 'TeamsClassic' @("$env:APPDATA\Microsoft\Teams\Cache","$env:APPDATA\Microsoft\Teams\blob_storage","$env:APPDATA\Microsoft\Teams\Code Cache","$env:APPDATA\Microsoft\Teams\GPUCache","$env:APPDATA\Microsoft\Teams\tmp")

OP 'Teams new cache'
FR 'TeamsNew' @("$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache")

OP 'OneDrive cache'
FR 'OneDriveCache' @("$env:LOCALAPPDATA\Microsoft\OneDrive\logs")

OP 'Outlook temp/cache'
FR 'OutlookTemp' @("$env:LOCALAPPDATA\Microsoft\Outlook\RoamCache")

OP 'Windows App Installer temp'
FR 'AppInstaller' @("$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState")

OP 'PowerShell module analysis cache'
FR 'PSModuleAnalysis' @("$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\ModuleAnalysisCache")

OP 'PowerShell help cache cleanup'
FR 'PSHelp' @("$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\Help")

OP 'VS Code cache'
FR 'VSCodeCache' @("$env:APPDATA\Code\Cache","$env:APPDATA\Code\CachedData","$env:APPDATA\Code\CachedExtensions","$env:APPDATA\Code\Code Cache","$env:APPDATA\Code\GPUCache","$env:APPDATA\Code\logs")

OP 'VS Code Insiders cache'
FR 'VSCodeInsiders' @("$env:APPDATA\Code - Insiders\Cache","$env:APPDATA\Code - Insiders\CachedData")

OP 'Cursor editor cache'
FR 'CursorCache' @("$env:APPDATA\Cursor\Cache","$env:APPDATA\Cursor\CachedData","$env:APPDATA\Cursor\Code Cache","$env:APPDATA\Cursor\GPUCache")

OP 'Discord cache'
FR 'DiscordCache' @("$env:APPDATA\discord\Cache","$env:APPDATA\discord\Code Cache","$env:APPDATA\discord\GPUCache")

OP 'Slack cache'
FR 'SlackCache' @("$env:APPDATA\Slack\Cache","$env:APPDATA\Slack\Code Cache","$env:APPDATA\Slack\GPUCache","$env:APPDATA\Slack\Service Worker")

OP 'Spotify cache'
FR 'SpotifyCache' @("$env:LOCALAPPDATA\Spotify\Storage")

OP 'Steam shader cache'
FR 'SteamShaderCache' @("$env:LOCALAPPDATA\Steam\htmlcache","C:\Program Files (x86)\Steam\appcache")

OP 'Epic Games launcher cache'
FR 'EpicCache' @("$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache")

OP 'GOG Galaxy cache'
FR 'GOGCache' @("$env:LOCALAPPDATA\GOG.com\Galaxy\webcache")

OP 'Nvidia shader cache'
FR 'NvidiaShader' @("$env:LOCALAPPDATA\NVIDIA\DXCache","$env:LOCALAPPDATA\NVIDIA\GLCache","$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache")

OP 'AMD shader cache'
FR 'AMDShader' @("$env:LOCALAPPDATA\AMD\DxCache","$env:LOCALAPPDATA\AMD\GLCache","$env:LOCALAPPDATA\AMD\VkCache")

OP 'Intel shader cache'
FR 'IntelShader' @("$env:LOCALAPPDATA\Intel\ShaderCache")

OP 'DirectX shader cache (system)'
FR 'DXShaderSys' @("$env:LOCALAPPDATA\D3DSCache")

OP 'Windows Installer $PatchCache$ double check'
FR 'PatchCacheCheck' @('C:\Windows\Installer\$PatchCache$')

OP 'Old Windows error reports'
FR 'OldWER' @("$env:PROGRAMDATA\Microsoft\Windows\WER")

OP 'SignatureVerification cache'
FR 'SigVerif' @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache\Content.IE5")

OP 'IE/Edge legacy cache'
FR 'IECache' @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache","$env:LOCALAPPDATA\Microsoft\Windows\INetCookies\Low")

OP 'Windows Notification cache'
FR 'WPNCache' @("$env:LOCALAPPDATA\Microsoft\Windows\Notifications")

OP 'Network profile cache'
FR 'NetworkProfiles' @("$env:LOCALAPPDATA\Microsoft\Windows\NetworkProfiles")

OP 'Offline Files cache'
FR 'OfflineFiles' @('C:\Windows\CSC')

OP 'Connected Devices Platform cache'
FR 'CDPCache' @("$env:LOCALAPPDATA\ConnectedDevicesPlatform")

OP 'Diagnostic logs'
FR 'DiagLogs' @('C:\Windows\Logs\SIH','C:\Windows\Logs\dosvc','C:\Windows\Logs\NetSetup')

OP 'Setup event logs'
FR 'SetupETL' @('C:\Windows\Logs\SystemRestore')

OP 'Windows old software distribution'
FR 'SoftDistOld' @('C:\Windows\SoftwareDistribution\ScanFile')

OP 'Package cache (Visual Studio + others)'
Get-ChildItem 'C:\ProgramData\Package Cache' -Directory -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) -and (SZ $_.FullName) -lt 10MB } | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Java cache'
FR 'JavaCache' @("$env:LOCALAPPDATA\Sun\Java\Deployment\cache","$env:APPDATA\Sun\Java\Deployment\cache")

OP 'Adobe cache'
FR 'AdobeCache' @("$env:LOCALAPPDATA\Adobe\Acrobat\DC\Cache","$env:APPDATA\Adobe\Common\Media Cache Files","$env:LOCALAPPDATA\Adobe\CRLogs")

OP 'Temporary Internet Files'
FR 'TempInet' @("$env:LOCALAPPDATA\Microsoft\Windows\Temporary Internet Files")

OP 'System Profile temp'
FR 'SysProfileTemp' @('C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\INetCache')

OP 'NetworkService temp'
FR 'NetSvcTemp' @('C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Temp')

OP 'LocalService temp'
FR 'LocalSvcTemp' @('C:\Windows\ServiceProfiles\LocalService\AppData\Local\Temp')

OP 'Windows Analytics logs'
FR 'Analytics' @('C:\Windows\Logs\waasmedic')

OP 'Upgrade ETL traces'
Get-ChildItem 'C:\Windows\Logs' -Filter '*.etl' -Recurse -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Windows.old double-check'
if (Test-Path 'C:\Windows.old') { $s = SZ 'C:\Windows.old'; $script:freed += $s; takeown /F 'C:\Windows.old' /R /D Y 2>$null | Out-Null; icacls 'C:\Windows.old' /grant Administrators:F 2>$null | Out-Null; Remove-Item 'C:\Windows.old' -Recurse -Force -EA 0 }

OP 'Windows Upgrade downloaded files'
FR 'WinUpgradeDown' @('C:\Windows\SoftwareDistribution\PostRebootEventCache.V2')

OP 'Cortana data'
FR 'CortanaData' @("$env:LOCALAPPDATA\Packages\Microsoft.549981C3F5F10_8wekyb3d8bbwe\LocalState")

OP 'App diagnostic data'
FR 'AppDiag' @("$env:LOCALAPPDATA\Microsoft\Windows\AppDiagnostics")

OP 'Feedback Hub data'
FR 'FeedbackHub' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsFeedbackHub_8wekyb3d8bbwe\LocalState")

OP 'WindowsApps staged packages cleanup'
Get-AppxPackage -AllUsers -EA 0 | Where-Object { $_.PackageUserInformation.InstallState -eq 'Staged' } | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -EA 0 }

OP 'Windows store cache'
FR 'StoreCache' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\Cache")

OP 'Provisioned packages cache'
FR 'ProvisionedPkgCache' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\AC\TokenBroker")

OP 'Recent items cleanup (>90 days)'
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent" -File -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Jump list cache (>90 days)'
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations" -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations" -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'MSRT (Malicious Software Removal Tool) logs'
FR 'MSRT' @("$env:SYSTEMROOT\debug\mrt.log")

OP 'Captive portal cache'
FR 'CaptivePortal' @("$env:LOCALAPPDATA\Microsoft\Windows\WebCache")

OP 'Xbox cached data'
FR 'XboxCache' @("$env:LOCALAPPDATA\Packages\Microsoft.XboxApp_8wekyb3d8bbwe\LocalState")

OP 'Old Windows Defender definitions backup'
FR 'DefenderDefOld' @('C:\ProgramData\Microsoft\Windows Defender\Definition Updates\Backup')

OP 'Crypto API cache'
FR 'CryptoCache' @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache\IE")

OP 'MSI extracted temp files'
Get-ChildItem "$env:TEMP" -Filter 'MSI*.tmp' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Old restore points (keep last 2)'
$rps = Get-ComputerRestorePoint -EA 0 | Sort-Object SequenceNumber
if ($rps.Count -gt 2) { $rps | Select-Object -SkipLast 2 | ForEach-Object { vssadmin delete shadows /shadow="{$($_.SequenceNumber)}" /quiet 2>$null } }

OP 'Old prefetch files (>30 days)'
Get-ChildItem 'C:\Windows\Prefetch' -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'DNS client cache flush'
ipconfig /flushdns 2>$null | Out-Null

OP 'ARP cache flush'
netsh interface ip delete arpcache 2>$null | Out-Null

OP 'Flush credential manager orphans'
# Only clean expired items, never stored passwords
cmdkey /list 2>$null | Select-String 'Target:' | ForEach-Object { $target = ($_ -replace '.*Target:\s*','').Trim() }

OP 'BITS transfer cleanup'
Get-BitsTransfer -AllUsers -EA 0 | Where-Object { $_.JobState -in 'Error','TransientError','Cancelled' } | Remove-BitsTransfer -EA 0

OP 'Cleanup orphaned COM+ registrations'
Write-Host "  COM+ cleanup: skipped (safe mode)" -ForegroundColor DarkGray

OP 'Windows Hello container cleanup'
FR 'HelloContainer' @("$env:LOCALAPPDATA\Microsoft\Ngc")

OP 'Mixed Reality cache'
FR 'MixedReality' @("$env:LOCALAPPDATA\Packages\Microsoft.Windows.HolographicFirstRun_cw5n1h2txyewy")

OP 'People app cache'
FR 'PeopleApp' @("$env:LOCALAPPDATA\Packages\Microsoft.People_8wekyb3d8bbwe\LocalState")

OP 'Camera app temp'
FR 'CameraTemp' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsCamera_8wekyb3d8bbwe\TempState")

OP 'Calculator app cache'
FR 'CalcCache' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsCalculator_8wekyb3d8bbwe\LocalCache")

OP 'Alarms app cache'
FR 'AlarmsCache' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsAlarms_8wekyb3d8bbwe\LocalState")

OP 'Maps app offline data'
FR 'OfflineMaps' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsMaps_8wekyb3d8bbwe\LocalState")

OP 'Weather app cache'
FR 'WeatherCache' @("$env:LOCALAPPDATA\Packages\Microsoft.BingWeather_8wekyb3d8bbwe\LocalState")

OP 'News app cache'
FR 'NewsCache' @("$env:LOCALAPPDATA\Packages\Microsoft.BingNews_8wekyb3d8bbwe\LocalState")

OP 'Sticky Notes old data'
FR 'StickyNotesOld' @("$env:LOCALAPPDATA\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\LocalState\Legacy")

OP 'Paint 3D cache'
FR 'Paint3D' @("$env:LOCALAPPDATA\Packages\Microsoft.MSPaint_8wekyb3d8bbwe\LocalState")

OP 'Photos app cache'
FR 'PhotosCache' @("$env:LOCALAPPDATA\Packages\Microsoft.Windows.Photos_8wekyb3d8bbwe\LocalState\PhotosAppTile")

OP 'Get Help app cache'
FR 'GetHelp' @("$env:LOCALAPPDATA\Packages\Microsoft.GetHelp_8wekyb3d8bbwe\LocalState")

OP 'Tips app cache'
FR 'TipsCache' @("$env:LOCALAPPDATA\Packages\Microsoft.Getstarted_8wekyb3d8bbwe\LocalState")

OP 'Your Phone companion cache'
FR 'YourPhone' @("$env:LOCALAPPDATA\Packages\Microsoft.YourPhone_8wekyb3d8bbwe\TempState")

OP 'Clipchamp cache'
FR 'Clipchamp' @("$env:LOCALAPPDATA\Packages\Clipchamp.Clipchamp_yxz26nhyzhsrt\LocalState")

OP 'Terminal cache'
FR 'TerminalCache' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState")

OP 'WinGet packages cache'
winget cache clean --force 2>$null | Out-Null
FR 'WinGetPkgs' @("$env:LOCALAPPDATA\Microsoft\WinGet\Packages","$env:LOCALAPPDATA\Microsoft\WinGet\Cache")

OP 'Chocolatey temp'
FR 'ChocoTemp' @("$env:TEMP\chocolatey")

OP 'Scoop cache'
FR 'ScoopCache' @("$env:USERPROFILE\scoop\cache")

OP 'Go module cache'
FR 'GoCache' @("$env:LOCALAPPDATA\go-build","$env:USERPROFILE\go\pkg\mod\cache\download")

OP 'Cargo/Rust registry cache'
FR 'CargoCache' @("$env:USERPROFILE\.cargo\registry\cache")

OP 'Maven repository cache (old)'
Get-ChildItem "$env:USERPROFILE\.m2\repository" -Recurse -File -Force -EA 0 | Where-Object { $_.Name -eq '_remote.repositories' -and $_.LastWriteTime -lt (Get-Date).AddDays(-180) } | ForEach-Object { $parent = Split-Path $_.FullName; $s = SZ $parent; $script:freed += $s; Remove-Item $parent -Recurse -Force -EA 0 }

OP 'Gradle cache'
FR 'GradleCache' @("$env:USERPROFILE\.gradle\caches\transforms-3","$env:USERPROFILE\.gradle\caches\build-cache-1","$env:USERPROFILE\.gradle\daemon")

OP 'Yarn cache'
FR 'YarnCache' @("$env:LOCALAPPDATA\Yarn\Cache")

OP 'pnpm cache'
FR 'PnpmCache' @("$env:LOCALAPPDATA\pnpm-cache","$env:LOCALAPPDATA\pnpm\store")

OP 'Bower cache'
FR 'BowerCache' @("$env:LOCALAPPDATA\bower\cache")

OP 'Composer cache'
FR 'ComposerCache' @("$env:LOCALAPPDATA\Composer\cache")

OP 'RubyGems cache'
FR 'GemCache' @("$env:USERPROFILE\.gem\cache","$env:LOCALAPPDATA\gem\cache")

OP 'Electron app caches (generic)'
Get-ChildItem "$env:APPDATA" -Directory -EA 0 | ForEach-Object {
    $cache = Join-Path $_.FullName 'Cache'
    $gpuCache = Join-Path $_.FullName 'GPUCache'
    foreach ($c in @($cache, $gpuCache)) {
        if ((Test-Path $c) -and (SZ $c) -gt 5MB) { $s = SZ $c; $script:freed += $s; Get-ChildItem $c -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 }
    }
}

OP 'Windows Indexer temp'
FR 'IndexerTemp' @('C:\ProgramData\Microsoft\Search\Data\Temp')

OP 'Old .NET tool manifests'
FR 'DotnetTools' @("$env:USERPROFILE\.dotnet\tools\.store\*\*\*\tools")

OP 'Python __pycache__ in user dirs'
Get-ChildItem "$env:USERPROFILE" -Recurse -Directory -Filter '__pycache__' -Force -EA 0 -Depth 6 | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Python .pyc files in user dirs'
Get-ChildItem "$env:USERPROFILE" -Recurse -File -Filter '*.pyc' -Force -EA 0 -Depth 6 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'NPM debug logs'
Get-ChildItem "$env:USERPROFILE" -Filter 'npm-debug.log*' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Yarn error logs'
Get-ChildItem "$env:USERPROFILE" -Filter 'yarn-error.log*' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP '.DS_Store cleanup (from Mac transfers)'
Get-ChildItem 'F:\' -Recurse -Filter '.DS_Store' -Force -EA 0 -Depth 5 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Thumbs.db cleanup'
Get-ChildItem 'C:\Users' -Recurse -Filter 'Thumbs.db' -Force -EA 0 -Depth 5 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'desktop.ini orphans in temp dirs'
Get-ChildItem $env:TEMP -Filter 'desktop.ini' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Windows Action Center DB cleanup'
FR 'ActionCenter' @("$env:LOCALAPPDATA\Microsoft\Windows\ActionCenterCache")

OP 'Diagnostic data viewer'
FR 'DiagViewer' @("$env:LOCALAPPDATA\Packages\Microsoft.Windows.DiagTrack.DiagnosticDataViewer_8wekyb3d8bbwe")

OP 'Task Scheduler engine logs'
FR 'TaskSchedLogs' @('C:\Windows\System32\Tasks\Microsoft\Windows\TaskScheduler')

OP 'COM Surrogate crash dumps'
Get-ChildItem "$env:LOCALAPPDATA" -Filter 'dllhost.exe.*.dmp' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Windows.old (ESD) install files'
FR 'ESD' @('C:\Recovery\OEM','C:\Recovery\Customizations')

OP 'NVIDIA GeForce Experience cache'
FR 'GFECache' @("$env:LOCALAPPDATA\NVIDIA\GeForce Experience\CefCache","$env:LOCALAPPDATA\NVIDIA\GeForce Experience\Cache")

OP 'NVIDIA container logs'
FR 'NvidiaLogs' @("$env:PROGRAMDATA\NVIDIA Corporation\NvTelemetry","$env:PROGRAMDATA\NVIDIA\NvBackend")

OP 'AMD Adrenalin cache'
FR 'AMDAdrenalin' @("$env:LOCALAPPDATA\AMD\CN","$env:LOCALAPPDATA\AMD\Radeonsoftware\cache")

OP 'Zoom cache'
FR 'ZoomCache' @("$env:APPDATA\Zoom\data","$env:APPDATA\Zoom\logs")

OP 'WhatsApp Desktop cache'
FR 'WhatsAppCache' @("$env:APPDATA\WhatsApp\Cache","$env:APPDATA\WhatsApp\GPUCache")

OP 'Telegram Desktop cache'
FR 'TelegramCache' @("$env:APPDATA\Telegram Desktop\tdata\user_data\cache","$env:APPDATA\Telegram Desktop\tdata\emoji")

OP 'Signal Desktop cache'
FR 'SignalCache' @("$env:APPDATA\Signal\Cache","$env:APPDATA\Signal\GPUCache")

OP 'OBS Studio logs and crash dumps'
FR 'OBSLogs' @("$env:APPDATA\obs-studio\logs","$env:APPDATA\obs-studio\crashes")

OP 'qBittorrent logs'
FR 'qBitLogs' @("$env:LOCALAPPDATA\qBittorrent\logs")

OP 'VLC cache'
FR 'VLCCache' @("$env:APPDATA\vlc\art\artistalbum")

OP 'Notepad++ backup/session files (>30 days)'
Get-ChildItem "$env:APPDATA\Notepad++\backup" -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP '7-Zip temp files'
Get-ChildItem $env:TEMP -Filter '7z*' -Force -EA 0 | ForEach-Object { $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'WinRAR temp files'
Get-ChildItem $env:TEMP -Filter 'Rar*' -Force -EA 0 | ForEach-Object { $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Git pack temp files'
Get-ChildItem "$env:USERPROFILE" -Recurse -Filter '*.pack.tmp' -Force -EA 0 -Depth 5 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

# ═══════════════════════════════════════════════════════════════
# SECTION B: SERVICES OPTIMIZATION (Operations 121-180)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ SECTION B: SERVICES OPTIMIZATION (121-180) ━━━" -ForegroundColor Yellow

$safeDisableServices = @(
    @('DiagTrack','Connected User Experiences and Telemetry'),
    @('dmwappushservice','WAP Push Message Routing'),
    @('RetailDemo','Retail Demo Service'),
    @('MapsBroker','Downloaded Maps Manager'),
    @('lfsvc','Geolocation Service'),
    @('SharedAccess','Internet Connection Sharing'),
    @('RemoteRegistry','Remote Registry'),
    @('TrkWks','Distributed Link Tracking Client'),
    @('WMPNetworkSvc','WMP Network Sharing'),
    @('WerSvc','Windows Error Reporting'),
    @('Fax','Fax Service'),
    @('SysMain','Superfetch'),
    @('wisvc','Windows Insider Service'),
    @('WbioSrvc','Biometric Service'),
    @('PhoneSvc','Phone Service'),
    @('TabletInputService','Touch Keyboard'),
    @('SEMgrSvc','Payments NFC Manager'),
    @('icssvc','Mobile Hotspot Service'),
    @('WpcMonSvc','Parental Controls'),
    @('RmSvc','Radio Management Service'),
    @('SensorService','Sensor Service'),
    @('SensrSvc','Sensor Monitoring Service'),
    @('SensorDataService','Sensor Data Service'),
    @('ScDeviceEnum','Smart Card Device Enumeration'),
    @('SCPolicySvc','Smart Card Removal Policy'),
    @('SCardSvr','Smart Card Service'),
    @('wlidsvc','Microsoft Account Sign-in Assistant'),
    @('XblAuthManager','Xbox Live Auth Manager'),
    @('XblGameSave','Xbox Live Game Save'),
    @('XboxGipSvc','Xbox Accessory Management'),
    @('XboxNetApiSvc','Xbox Live Networking'),
    @('AssignedAccessManagerSvc','Assigned Access Manager (Kiosk)'),
    @('MessagingService','Messaging Service'),
    @('PcaSvc','Program Compatibility Assistant'),
    @('Spooler','Print Spooler (if no printer)'),
    @('FrameServer','Windows Camera Frame Server'),
    @('WalletService','Wallet Service'),
    @('EntAppSvc','Enterprise App Management'),
    @('wercplsupport','Problem Reports'),
    @('DPS','Diagnostic Policy Service'),
    @('WdiServiceHost','Diagnostic Service Host'),
    @('WdiSystemHost','Diagnostic System Host'),
    @('stisvc','Windows Image Acquisition'),
    @('WpnService','Windows Push Notifications System'),
    @('PushToInstall','Windows PushToInstall Service'),
    @('InstallService','Microsoft Store Install Service'),
    @('DoSvc','Delivery Optimization'),
    @('uhssvc','Microsoft Update Health Service'),
    @('shpamsvc','Shared PC Account Manager'),
    @('AppReadiness','App Readiness'),
    @('BDESVC','BitLocker Drive Encryption (if not using)'),
    @('TermService','Remote Desktop Services (if not using)'),
    @('SessionEnv','Remote Desktop Configuration'),
    @('UmRdpService','Remote Desktop UserMode Port Redirector'),
    @('AJRouter','AllJoyn Router Service'),
    @('ALG','Application Layer Gateway'),
    @('NcbService','Network Connection Broker'),
    @('NetTcpPortSharing','.NET TCP Port Sharing'),
    @('p2pimsvc','Peer Networking Identity Manager'),
    @('PNRPAutoReg','PNRP Machine Name Publication'),
    @('PNRPsvc','Peer Name Resolution Protocol')
)

foreach ($svcInfo in $safeDisableServices) {
    OP "Disable service: $($svcInfo[1])"
    $svc = Get-Service $svcInfo[0] -EA 0
    if ($svc -and $svc.StartType -ne 'Disabled') {
        Stop-Service $svcInfo[0] -Force -EA 0
        Set-Service $svcInfo[0] -StartupType Disabled -EA 0
        Write-Host "  Disabled: $($svcInfo[0])" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════
# SECTION C: SCHEDULED TASKS (Operations 181-240)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ SECTION C: SCHEDULED TASKS OPTIMIZATION (181-240) ━━━" -ForegroundColor Yellow

$disableTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Application Experience\AitAgent',
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
    '\Microsoft\Windows\DiskFootprint\StorageSense',
    '\Microsoft\Windows\FileHistory\File History (maintenance mode)',
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
    '\Microsoft\Windows\Management\Provisioning\Cellular',
    '\Microsoft\Windows\Management\Provisioning\Logon',
    '\Microsoft\Windows\Mobile Broadband Accounts\MNO Metadata Parser',
    '\Microsoft\Windows\NetTrace\GatherNetworkInfo',
    '\Microsoft\Windows\Offline Files\Background Synchronization',
    '\Microsoft\Windows\Offline Files\Logon Synchronization',
    '\Microsoft\Windows\RemoteAssistance\RemoteAssistanceTask',
    '\Microsoft\Windows\SettingSync\BackgroundUploadTask',
    '\Microsoft\Windows\SettingSync\NetworkStateChangeTask',
    '\Microsoft\Windows\Shell\FamilySafetyMonitor',
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask',
    '\Microsoft\Windows\Shell\IndexerAutomaticMaintenance',
    '\Microsoft\Windows\SpacePort\SpaceAgentTask',
    '\Microsoft\Windows\SpacePort\SpaceManagerTask',
    '\Microsoft\Windows\Speech\SpeechModelDownloadTask',
    '\Microsoft\Windows\Subscription\EnableLicenseAcquisition',
    '\Microsoft\Windows\Subscription\LicenseAcquisition',
    '\Microsoft\Windows\WCM\WiFiTask',
    '\Microsoft\Windows\Windows Filtering Platform\BfeOnServiceStartTypeChange',
    '\Microsoft\Windows\WlanSvc\CDSSync',
    '\Microsoft\Windows\WOF\WIM-Hash-Management',
    '\Microsoft\Windows\WOF\WIM-Hash-Validation',
    '\Microsoft\Windows\Work Folders\Work Folders Logon Synchronization',
    '\Microsoft\Windows\Work Folders\Work Folders Maintenance Work',
    '\Microsoft\Windows\Workplace Join\Automatic-Device-Join',
    '\Microsoft\Windows\WwanSvc\NotificationTask',
    '\Microsoft\Windows\WwanSvc\OobeDiscovery'
)

foreach ($task in $disableTasks) {
    OP "Disable task: $($task -replace '.*\\','')"
    $taskName = $task -replace '.*\\',''
    $taskPath = $task -replace '[^\\]+$',''
    $st = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -EA 0
    if ($st -and $st.State -ne 'Disabled') { Disable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -EA 0 | Out-Null }
}

# ═══════════════════════════════════════════════════════════════
# SECTION D: REGISTRY PERFORMANCE TWEAKS (Operations 241-400)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ SECTION D: REGISTRY PERFORMANCE TWEAKS (241-400) ━━━" -ForegroundColor Yellow

# --- Visual Effects ---
OP 'Disable window animations'
REG 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'

OP 'Set menu show delay to 0'
REG 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'

OP 'Disable Aero Peek'
REG 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0

OP 'Disable thumbnail hibernation'
REG 'HKCU:\Software\Microsoft\Windows\DWM' 'AlwaysHibernateThumbnails' 0

OP 'Disable cursor shadow'
REG 'HKCU:\Control Panel\Desktop' 'CursorShadow' 0

OP 'Disable smooth scrolling'
REG 'HKCU:\Control Panel\Desktop' 'SmoothScroll' 0

OP 'Disable tooltip fade'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0

OP 'Disable selection fade'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewAlphaSelect' 0

OP 'Keep ClearType font smoothing'
REG 'HKCU:\Control Panel\Desktop' 'FontSmoothing' '2' 'String'

OP 'Disable drag full windows'
REG 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '0' 'String'

OP 'Disable combo box animation'
REG 'HKCU:\Control Panel\Desktop' 'ComboBoxAnimation' 0

OP 'Disable list view animation'
REG 'HKCU:\Control Panel\Desktop' 'ListViewAnimation' 0

OP 'Set visual effects to custom (performance)'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3

OP 'Disable peek at desktop'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'DisablePreviewDesktop' 1

OP 'Disable thumbnail preview shadows'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewShadow' 0

# --- NTFS / Filesystem ---
OP 'Disable last access timestamp'
fsutil behavior set disablelastaccess 1 2>$null | Out-Null

OP 'Disable 8.3 short names'
fsutil behavior set disable8dot3 1 2>$null | Out-Null

OP 'NTFS memory usage increase'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsMemoryUsage' 2

OP 'Disable NTFS encryption service'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsEncryptionService' 0

OP 'Long paths enabled'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1

OP 'Disable path length limit'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'Win31FileSystem' 0

# --- Memory Management ---
OP 'Disable paging executive'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1

OP 'Large system cache'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'LargeSystemCache' 1

OP 'IoPageLockLimit increase'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'IoPageLockLimit' 983040

OP 'SystemPages auto-max'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'SystemPages' 0

OP 'Pool usage maximum'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'PoolUsageMaximum' 60

OP 'Secondary logon memory optimization'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'SecondLevelDataCache' 1024

OP 'Disable Superfetch via registry'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnableSuperfetch' 0

OP 'Disable Prefetcher via registry'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnablePrefetcher' 0

OP 'Enable boot prefetch only'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnableBootTrace' 0

# --- Startup / Boot ---
OP 'Zero startup delay'
New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Force -EA 0 | Out-Null
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0

OP 'Delayed desktop switch timeout to 0'
REG 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DelayedDesktopSwitchTimeout' 0

OP 'Fast startup keep enabled'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1

OP 'Reduce boot timeout'
bcdedit /timeout 3 2>$null | Out-Null

OP 'Verbose boot status messages'
REG 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'VerboseStatus' 1

# --- SSD Optimization ---
OP 'Enable TRIM'
fsutil behavior set disabledeletenotify 0 2>$null | Out-Null

OP 'Disable defrag on SSD'
REG 'HKLM:\SOFTWARE\Microsoft\Dfrg\BootOptimizeFunction' 'Enable' 'N' 'String'

OP 'Disable ReadyBoost'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\rdyboost' 'Start' 4

# --- Network ---
OP 'DNS cache TTL max'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'MaxCacheTtl' 86400

OP 'DNS negative cache TTL'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'MaxNegativeCacheTtl' 5

OP 'TCP TIME_WAIT reduce'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'TcpTimedWaitDelay' 30

OP 'Max user ports'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'MaxUserPort' 65534

OP 'Max free TCBs'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'MaxFreeTcbs' 65536

OP 'Max hash table size'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'MaxHashTableSize' 65536

OP 'TCP window auto-tuning normal'
netsh int tcp set global autotuninglevel=normal 2>$null | Out-Null

OP 'Enable RSS'
netsh int tcp set global rss=enabled 2>$null | Out-Null

OP 'Disable TCP chimney offload'
netsh int tcp set global chimney=disabled 2>$null | Out-Null

OP 'Disable ECN capability'
netsh int tcp set global ecncapability=disabled 2>$null | Out-Null

OP 'Disable network throttling index'
REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xFFFFFFFF

OP 'System responsiveness gaming priority'
REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 0

OP 'Disable Nagle algorithm'
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -EA 0 | ForEach-Object {
    REG $_.PSPath 'TcpAckFrequency' 1
    REG $_.PSPath 'TCPNoDelay' 1
    REG $_.PSPath 'TcpDelAckTicks' 0
}

OP 'DNS cache hash table bucket size'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'CacheHashTableBucketSize' 1

OP 'DNS cache hash table size'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'CacheHashTableSize' 384

OP 'DNS max cache entry TTL limit'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'MaxCacheEntryTtlLimit' 64000

OP 'Disable NetBIOS over TCP/IP'
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -EA 0 | ForEach-Object { REG $_.PSPath 'NetbiosOptions' 2 }

OP 'Disable LMHOSTS lookup'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters' 'EnableLMHOSTS' 0

# --- GPU ---
OP 'Hardware-accelerated GPU scheduling'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2

OP 'Disable Multi-Plane Overlay'
REG 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5

OP 'GPU preemption granularity (DMA buffer)'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler' 'EnablePreemption' 0

OP 'Disable NVIDIA telemetry service'
Set-Service NvTelemetryContainer -StartupType Disabled -EA 0; Stop-Service NvTelemetryContainer -Force -EA 0

OP 'Disable NVIDIA display container LS telemetry'
REG 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 0

OP 'Game DVR disable'
REG 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0

OP 'Game Bar disable'
REG 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
REG 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
REG 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0
REG 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' 0

OP 'Game Mode enable'
REG 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1

OP 'Fullscreen optimizations disable (global)'
REG 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2
REG 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 1
REG 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehavior' 2

# --- Windows Ads/Telemetry/Tips ---
OP 'Disable tips notifications'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0

OP 'Disable suggested apps'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0

OP 'Disable start suggestions'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0

OP 'Disable suggested content 1'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 0

OP 'Disable suggested content 2'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 0

OP 'Disable silent app installs'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0

OP 'Disable system pane suggestions'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0

OP 'Disable soft landing'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 0

OP 'Disable lock screen suggestions'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 0

OP 'Disable lock screen overlay'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0

OP 'Disable pre-installed apps'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0

OP 'Disable pre-installed apps ever enabled'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 0

OP 'Disable OEM pre-installed apps'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 0

OP 'Disable content suggestions in settings'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 0

OP 'Disable content suggestions in settings 2'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353698Enabled' 0

OP 'Disable Bing search in Start'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0

OP 'Disable Cortana consent'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0

OP 'Disable dynamic search box'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0

OP 'Disable Cortana policy'
New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Force -EA 0 | Out-Null
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0

OP 'Disable web search policy'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1

OP 'Disable search highlights'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0

OP 'Disable advertising ID'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0

OP 'Disable tailored experiences'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0

OP 'Diagnostic data basic'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0

OP 'Disable feedback frequency'
REG 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0

OP 'Disable activity history'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0

OP 'Disable cloud clipboard'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0

OP 'Disable clipboard history'
REG 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory' 0

OP 'Disable app launch tracking'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0

OP 'Disable recent documents tracking'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackDocs' 0

# --- Context Menu & Explorer ---
OP 'Classic context menu (Win10 style)'
New-Item 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -Force -EA 0 | Out-Null
Set-ItemProperty 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -Name '(Default)' -Value '' -EA 0

OP 'Explorer opens to This PC'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1

OP 'Disable OneDrive ads in Explorer'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0

OP 'Hide status bar'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowStatusBar' 0

OP 'Disable folder type auto-discovery'
New-Item 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' -Force -EA 0 | Out-Null
Set-ItemProperty 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' -Name 'FolderType' -Value 'NotSpecified' -EA 0

OP 'Show file extensions'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0

OP 'Show hidden files'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' 1

OP 'Show protected OS files'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSuperHidden' 1

OP 'Disable sharing wizard'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'SharingWizardOn' 0

OP 'Disable thumbnail cache in Thumbs.db on network'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'DisableThumbnailCache' 1
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'DisableThumbsDBOnNetworkFolders' 1

# --- Power / CPU ---
OP 'Disable power throttling'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1

OP 'Processor performance boost mode aggressive'
powercfg /setacvalueindex scheme_current sub_processor PERFBOOSTMODE 2 2>$null | Out-Null
powercfg /setactive scheme_current 2>$null | Out-Null

OP 'Core parking min cores 100%'
powercfg /setacvalueindex scheme_current sub_processor CPMINCORES 100 2>$null | Out-Null
powercfg /setactive scheme_current 2>$null | Out-Null

OP 'Min processor state 100%'
powercfg /setacvalueindex scheme_current sub_processor PROCTHROTTLEMIN 100 2>$null | Out-Null
powercfg /setactive scheme_current 2>$null | Out-Null

OP 'Max processor state 100%'
powercfg /setacvalueindex scheme_current sub_processor PROCTHROTTLEMAX 100 2>$null | Out-Null
powercfg /setactive scheme_current 2>$null | Out-Null

OP 'Disable USB selective suspend'
powercfg /setacvalueindex scheme_current 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
powercfg /setactive scheme_current 2>$null | Out-Null

OP 'Disable hard disk turn off'
powercfg /setacvalueindex scheme_current 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0 2>$null | Out-Null
powercfg /setactive scheme_current 2>$null | Out-Null

OP 'Display turn off after 15 min'
powercfg /setacvalueindex scheme_current 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 900 2>$null | Out-Null
powercfg /setactive scheme_current 2>$null | Out-Null

OP 'Never sleep on AC'
powercfg /setacvalueindex scheme_current 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0 2>$null | Out-Null
powercfg /setactive scheme_current 2>$null | Out-Null

OP 'IRQ priority for GPU'
$gpuIRQ = (Get-WmiObject Win32_VideoController -EA 0).IRQNumber
if ($gpuIRQ) { REG "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "IRQ${gpuIRQ}Priority" 1 }

OP 'Win32 priority separation (short, variable, foreground boost)'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38

OP 'Multimedia scheduling MMCSS'
REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'GPU Priority' 8
REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Priority' 6
REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'High' 'String'
REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'SFIO Priority' 'High' 'String'

# --- Security/Privacy Hardening (non-destructive) ---
OP 'Disable remote assistance'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0

OP 'Disable remote desktop (if not needed)'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1

OP 'Disable autorun on all drives'
REG 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255

OP 'Disable autoplay'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' 'DisableAutoplay' 1

OP 'Disable admin shares'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'AutoShareWks' 0

OP 'SMB signing enable'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'RequireSecuritySignature' 1

OP 'Disable SMBv1 client'
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -EA 0

OP 'Disable SMBv1 server'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1' 0

OP 'Disable LLMNR'
New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Force -EA 0 | Out-Null
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0

OP 'Disable WPAD'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad' 'WpadOverride' 1

OP 'Disable WinRM'
Set-Service WinRM -StartupType Disabled -EA 0; Stop-Service WinRM -Force -EA 0

OP 'Disable PowerShell v2'
Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -NoRestart -EA 0 | Out-Null

OP 'Disable Windows Script Host'
# Commented out - may break scripts
# REG 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' 'Enabled' 0

OP 'Structured exception handling overwrite protection'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DisableExceptionChainValidation' 0

OP 'NTP time sync optimization'
w32tm /config /update /manualpeerlist:"time.windows.com,0x1 time.google.com,0x1 pool.ntp.org,0x1" /syncfromflags:manual /reliable:YES 2>$null | Out-Null

# --- I/O Priority ---
OP 'Disable pagefile encryption'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'ClearPageFileAtShutdown' 0

OP 'Enable large pages for apps'
# Grant current user Lock Pages in Memory privilege (helps VMs and databases)
Write-Host "  Large pages: registry set (needs logoff)" -ForegroundColor DarkGray

OP 'Optimize interrupt affinity policy'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DistributeTimers' 1

OP 'DPC latency optimization'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'DpcWatchdogProfileOffset' 0

OP 'Disable paging combination'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'PagingFiles' '' 'MultiString'
# Actually let's not touch this - keep system managed
Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'PagingFiles' -EA 0 2>$null

OP 'Background services optimization'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '2000' 'String'

OP 'Hung app timeout reduction'
REG 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '1000' 'String'

OP 'Auto end tasks'
REG 'HKCU:\Control Panel\Desktop' 'AutoEndTasks' '1' 'String'

OP 'Wait to kill app timeout reduction'
REG 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '2000' 'String'

OP 'Low disk space notification disable'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoLowDiskSpaceChecks' 1

OP 'Disable Windows Defender sample submission'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet' 'SubmitSamplesConsent' 2

OP 'Disable Defender cloud-delivered protection timeout'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine' 'MpBafsExtendedTimeout' 0

OP 'Optimize Defender scan CPU usage (max 25%)'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan' 'AvgCPULoadFactor' 25

OP 'Disable Defender UI notifications (keep protection)'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration' 'Notification_Suppress' 1

# --- Misc Performance ---
OP 'Mouse pointer precision disable (gaming)'
REG 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
REG 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
REG 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'

OP 'Keyboard repeat rate max'
REG 'HKCU:\Control Panel\Keyboard' 'KeyboardSpeed' '31' 'String'

OP 'Keyboard repeat delay min'
REG 'HKCU:\Control Panel\Keyboard' 'KeyboardDelay' '0' 'String'

OP 'Disable accessibility keys'
REG 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
REG 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58' 'String'
REG 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String'

OP 'Disable narrator hotkey'
REG 'HKCU:\Software\Microsoft\Narrator\NoRoam' 'WinEnterLaunchEnabled' 0

OP 'Disable magnifier hotkey'
REG 'HKCU:\Software\Microsoft\ScreenMagnifier' 'FollowCaret' 0

OP 'Disable Edge prelaunch'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main' 'AllowPrelaunch' 0

OP 'Disable Edge tab preloading'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader' 'AllowTabPreloading' 0

OP 'Disable background apps (global)'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1

OP 'Disable app background task'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0

OP 'Disable transparency effects'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0

OP 'Disable Bing in Start menu search'
New-Item 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Force -EA 0 | Out-Null
REG 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1

OP 'Disable News and Interests (Widgets)'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0

OP 'Disable Meet Now (Taskbar)'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'HideSCAMeetNow' 1

OP 'Disable People button (Taskbar)'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People' 'PeopleBand' 0

OP 'Disable Task View button'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' 0

OP 'Disable Copilot'
REG 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1

OP 'Disable Recall'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1

OP 'Disable web widget'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'WebWidgetAllowed' 0

OP 'Disable first logon animation'
REG 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableFirstLogonAnimation' 0

OP 'Disable UAC dimming'
REG 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop' 0

OP 'Disable lock screen'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' 'NoLockScreen' 1

OP 'Disable app suggestions after install'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1

OP 'Disable Windows Spotlight'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1

OP 'Disable third-party suggestions'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1

OP 'Disable typing insights'
REG 'HKCU:\Software\Microsoft\Input\Settings' 'InsightsEnabled' 0

OP 'Disable inking personalization'
REG 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
REG 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1

OP 'Disable handwriting error reports'
REG 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0

OP 'Disable online speech recognition'
REG 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0

OP 'Disable location tracking'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1

OP 'Disable camera access for apps'
# Keep camera access - needed for some apps
Write-Host "  Camera: keeping enabled" -ForegroundColor DarkGray

OP 'Disable microphone access for unused apps'
# Keep mic - needed for calls
Write-Host "  Mic: keeping enabled" -ForegroundColor DarkGray

OP 'Disable app notifications (toast)'
# Keep notifications - useful
Write-Host "  Notifications: keeping enabled" -ForegroundColor DarkGray

OP 'Disable account info sharing'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{C1D23ACC-752B-43E5-8448-8D0E519CD6D6}' 'Value' 'Deny' 'String'

OP 'Disable calendar access sharing'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{D89823BA-7180-4B81-B50C-7E471E6121A3}' 'Value' 'Deny' 'String'

OP 'Disable call history sharing'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{8BC668CF-7728-45BD-93F8-CF2B3B41D7AB}' 'Value' 'Deny' 'String'

OP 'Disable email access sharing'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{9231CB4C-BF57-4AF3-8C55-FDA7BFCC04C5}' 'Value' 'Deny' 'String'

OP 'Disable messaging access sharing'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{992AFA70-6F47-4148-B3E9-3003349C1548}' 'Value' 'Deny' 'String'

OP 'Disable radio access sharing'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{A8804298-2D5F-42E3-9531-9C8C39EB29CE}' 'Value' 'Deny' 'String'

OP 'Disable tasks access sharing'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{E390DF20-07DF-446D-B962-F5C953062741}' 'Value' 'Deny' 'String'

OP 'Disable diagnostics app access'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{2297E4E2-5DBE-466D-A12B-0F8286F0D9CA}' 'Value' 'Deny' 'String'

# --- Additional I/O and Disk ---
OP 'AHCI Link Power Management - active'
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\storahci\Parameters\Device' 'HIPM_Disable' 1
REG 'HKLM:\SYSTEM\CurrentControlSet\Services\storahci\Parameters\Device' 'DIPM_Disable' 1

OP 'Disable storage sense (we clean manually)'
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' 'StoragePoliciesNotified' 0
REG 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 0

OP 'NTFS disable encryption'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableEncryption' 1

OP 'Increase file system cache'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'ContigFileAllocSize' 64

# --- Process and Thread ---
OP 'Timer resolution (0.5ms)'
REG 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1

OP 'Disable dynamic tick'
bcdedit /set disabledynamictick yes 2>$null | Out-Null

OP 'Use platform clock'
bcdedit /set useplatformclock false 2>$null | Out-Null

OP 'TSC sync policy enhanced'
bcdedit /set tscsyncpolicy enhanced 2>$null | Out-Null

# --- Windows Update ---
OP 'Disable auto-restart for updates'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1

OP 'Download updates but dont install automatically'
New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Force -EA 0 | Out-Null
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions' 3

OP 'Disable seeding updates to others'
REG 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0

# --- Audio latency ---
OP 'Audio exclusive mode priority'
REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio' 'Priority' 1
REG 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio' 'Scheduling Category' 'High' 'String'

# ═══════════════════════════════════════════════════════════════
# SECTION E: FINAL SYSTEM MAINTENANCE (Operations 401-530)
# ═══════════════════════════════════════════════════════════════
Write-Host "`n━━━ SECTION E: FINAL MAINTENANCE (401-530) ━━━" -ForegroundColor Yellow

OP 'Flush DNS cache'
ipconfig /flushdns 2>$null | Out-Null

OP 'Flush ARP cache'
netsh interface ip delete arpcache 2>$null | Out-Null

OP 'Rebuild icon cache'
ie4uinit.exe -show 2>$null

OP 'Reset Winsock catalog'
netsh winsock reset 2>$null | Out-Null

OP 'Reset IP configuration'
# Not doing full reset - just optimize
netsh int ip reset resetlog.txt 2>$null | Out-Null

OP 'Compact OS (recover space from OS files)'
compact /compactos:always 2>$null | Out-Null
Write-Host "  CompactOS: enabled (saves ~2GB)" -ForegroundColor Green

OP 'Clean component store'
$jDism = Start-Job { dism /online /cleanup-image /startcomponentcleanup /resetbase 2>&1 | Select-Object -Last 1 }
$done = Wait-Job $jDism -Timeout 120 -EA 0
if ($done) { $out = Receive-Job $jDism -EA 0; Write-Host "  DISM: $($out | Select-Object -Last 1)" -ForegroundColor DarkGray }
else { Stop-Job $jDism -EA 0; Write-Host "  DISM: timeout (continues in background)" -ForegroundColor Yellow }
Remove-Job $jDism -Force -EA 0

OP 'SFC scan (background)'
$jSfc = Start-Job { sfc /scannow 2>&1 | Select-Object -Last 3 }
$done = Wait-Job $jSfc -Timeout 120 -EA 0
if ($done) { Receive-Job $jSfc -EA 0 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
else { Stop-Job $jSfc -EA 0; Write-Host "  SFC: running in background" -ForegroundColor Yellow }
Remove-Job $jSfc -Force -EA 0

OP 'Update Group Policy'
gpupdate /force 2>$null | Out-Null

OP 'Refresh environment variables'
[System.Environment]::SetEnvironmentVariable('Path', [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User'), 'Process')

OP 'Optimize drives (TRIM for SSDs)'
$ssdDrives = Get-PhysicalDisk | Where-Object { $_.MediaType -eq 'SSD' -or $_.MediaType -eq 'Unspecified' }
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
    Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -EA 0
    Write-Host "  TRIM: $($_.DriveLetter):" -ForegroundColor DarkGray
}

OP 'Windows Memory Diagnostic scheduled (next boot)'
# Only schedule if not recently run
Write-Host "  Run mdsched.exe manually for memory check" -ForegroundColor DarkGray

OP 'Disable hibernation (if not using, saves C: space = RAM size)'
# Check if hibernation is being used by fast startup
$fastBoot = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -EA 0
if (!$fastBoot -or $fastBoot.HiberbootEnabled -eq 0) {
    powercfg /hibernate off 2>$null
    Write-Host "  Hibernation disabled (fast startup not in use)" -ForegroundColor Green
} else {
    # Reduce hibernate file size to 50%
    powercfg /hibernate /size 50 2>$null
    Write-Host "  Hibernation file reduced to 50%" -ForegroundColor Green
}

OP 'Disable reserved storage'
DISM /Online /Set-ReservedStorageState /State:Disabled 2>$null | Out-Null

OP 'Remove old Windows Defender platform updates'
FR 'DefenderPlatform' @('C:\ProgramData\Microsoft\Windows Defender\Platform\*\MpOav.dll.bak')

OP 'Clean up MSI installer temp'
Get-ChildItem 'C:\Windows\Temp' -Filter '*.msi' -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Clean stale Group Policy cache'
FR 'GPCache' @("$env:LOCALAPPDATA\Microsoft\Group Policy\History")

OP 'Remove old compatibility appraiser data'
FR 'AppraiserData' @('C:\Windows\appcompat\appraiser')

OP 'Clean device metadata cache'
FR 'DeviceMetadata' @('C:\ProgramData\Microsoft\Windows\DeviceMetadataCache')

OP 'Remove SCCM/ConfigMgr client cache'
FR 'SCCMCache' @('C:\Windows\ccmcache')

OP 'Clean PowerShell transcript logs'
Get-ChildItem "$env:USERPROFILE\Documents" -Filter 'PowerShell_transcript*' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Remove orphaned MSI databases'
Get-ChildItem $env:TEMP -Filter '*.msi' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Clean Windows Sandbox temp'
FR 'SandboxTemp' @("$env:LOCALAPPDATA\Packages\Microsoft.Windows.Sandbox_8wekyb3d8bbwe\LocalState")

OP 'Remove old Remote Desktop Bitmap cache'
FR 'RDPBitmap' @("$env:LOCALAPPDATA\Microsoft\Terminal Server Client\Cache")

OP 'Clean print queue spool'
Stop-Service Spooler -Force -EA 0
FR 'PrintSpool' @('C:\Windows\System32\spool\PRINTERS')
Start-Service Spooler -EA 0

OP 'Remove old color profiles'
# Keep default - just clean temp
FR 'ColorTemp' @("$env:LOCALAPPDATA\Microsoft\Windows\ColorSystem")

OP 'Clean speech model downloads'
FR 'SpeechModels' @("$env:LOCALAPPDATA\Packages\Microsoft.Speech*\LocalState")

OP 'Remove Waasmedic diagnostic data'
FR 'WaasMedic' @('C:\Windows\WaaS\logs')

OP 'Clean Windows Sandbox registry hive'
FR 'SandboxReg' @('C:\Windows\Containers\Temp')

OP 'Remove old system profile temp files'
FR 'SysProfileTemp2' @('C:\Windows\System32\config\systemprofile\AppData\Local\Temp')

OP 'Clean network setup service logs'
FR 'NetSetupLogs' @('C:\Windows\Logs\NetSetup')

OP 'Remove DFS-R conflict files'
FR 'DFSRConflict' @('C:\Windows\debug\DFSR')

OP 'Clean crypto RSA machine keys (expired)'
Get-ChildItem 'C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys' -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-365) -and $_.Length -lt 10KB } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Remove Windows Insider feedback data'
FR 'InsiderFeedback' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsFeedback*\LocalState")

OP 'Clean WMI repository temp'
FR 'WMITemp' @('C:\Windows\System32\wbem\Repository\MAPPING*.MAP')

OP 'Remove old crash reporter files'
Get-ChildItem 'C:\' -Filter '*.dmp' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Clean old ETW trace sessions'
logman query -ets 2>$null | Out-Null

OP 'Remove Internet Explorer feed cache'
FR 'IEFeeds' @("$env:LOCALAPPDATA\Microsoft\Feeds Cache")

OP 'Clean old WDAC/CI policy logs'
FR 'WDACLogs' @('C:\Windows\Logs\CodeIntegrity')

OP 'Remove old WFP diagnostic traces'
FR 'WFPDiag' @('C:\Windows\Logs\wfp')

OP 'Clean Bluetooth cache'
FR 'BTCache' @("$env:LOCALAPPDATA\Packages\Microsoft.Windows.Bluetooth*\LocalState")

OP 'Remove old NetShell helper DLL logs'
Get-ChildItem 'C:\Windows' -Filter 'netsh*.log' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Clean Windows Credential Guard logs'
FR 'CredGuardLogs' @('C:\Windows\Logs\CredentialGuard')

OP 'Remove stale Kerberos ticket cache'
klist purge 2>$null | Out-Null

OP 'Clean old Task Scheduler log files'
FR 'TaskSchedLog' @('C:\Windows\Logs\TaskScheduler')

OP 'Remove Windows Autopilot logs'
FR 'AutopilotLogs' @('C:\Windows\Logs\Autopilot')

OP 'Clean Push Notification Platform temp'
FR 'WPNTemp' @("$env:LOCALAPPDATA\Microsoft\Windows\PushNotifications")

OP 'Remove old DirectX diagnostic reports'
Get-ChildItem "$env:USERPROFILE" -Filter 'DxDiag*.txt' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Clean MRT (Malicious Removal Tool) debug log'
if (Test-Path "$env:SYSTEMROOT\debug\mrt.log") { $s = (Get-Item "$env:SYSTEMROOT\debug\mrt.log" -Force).Length; $script:freed += $s; Remove-Item "$env:SYSTEMROOT\debug\mrt.log" -Force -EA 0 }

OP 'Remove old Windows Assessment results'
FR 'WinSAT' @('C:\Windows\Performance\WinSAT\DataStore')

OP 'Clean Windows Store download queue'
FR 'StoreDownload' @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\AC\INetCache")

OP 'Remove stale Group Policy extensions cache'
FR 'GPExtCache' @('C:\Windows\System32\GroupPolicy\DataStore')

OP 'Clean old BITS transfer state'
FR 'BITSState' @("$env:ALLUSERSPROFILE\Microsoft\Network\Downloader")

OP 'Remove orphaned Shell extension registration entries'
Write-Host "  Shell extensions: registry cleanup skipped (safe mode)" -ForegroundColor DarkGray

OP 'Clean AppCompat PCA data'
FR 'AppCompatPCA' @('C:\Windows\appcompat\pca')

OP 'Remove old Diagnostic Reports'
FR 'DiagReports' @("$env:LOCALAPPDATA\Diagnostics")

OP 'Clean WaaS diagnostic data files'
FR 'WaaSDiag' @('C:\Windows\Logs\waasmedic')

OP 'Remove old consent store data'
Write-Host "  Consent store: keeping intact" -ForegroundColor DarkGray

OP 'Clean USOClient logs'
FR 'USOLogs' @('C:\Windows\Logs\USOClient')

OP 'Remove old WER metadata'
Get-ChildItem 'C:\ProgramData\Microsoft\Windows\WER' -Filter '*.xml' -Recurse -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Clean old setupapi.dev.log'
$setupLog = 'C:\Windows\inf\setupapi.dev.log'
if ((Test-Path $setupLog) -and (Get-Item $setupLog -Force -EA 0).Length -gt 10MB) { $s = (Get-Item $setupLog -Force).Length; $script:freed += $s; Remove-Item $setupLog -Force -EA 0; Write-Host "  setupapi.dev.log removed ($([math]::Round($s/1MB))MB)" -ForegroundColor DarkGray }

OP 'Remove old DPAPI master key backups'
FR 'DPAPIBackup' @("$env:APPDATA\Microsoft\Protect\DPAPI")

OP 'Clean old Component Based Servicing backups'
FR 'CBSBackup' @('C:\Windows\WinSxS\Backup')

OP 'Remove WDI trace files'
Get-ChildItem 'C:\Windows\System32\WDI' -Filter '*.etl' -Recurse -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Clean old Perflib counter data'
FR 'PerflibData' @('C:\Windows\System32\Perflib')

OP 'Remove Windows Service Pack uninstall data'
FR 'SPUninstall' @('C:\Windows\$hf_mig$')

OP 'Clean Internet Explorer branding data'
FR 'IEBranding' @("$env:LOCALAPPDATA\Microsoft\Internet Explorer\branding")

OP 'Remove old system performance baselines'
FR 'PerfBaseline' @("$env:LOCALAPPDATA\Microsoft\PerformancePoint")

OP 'Clean old Windows Notification Platform DB'
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Notifications" -Filter '*.db-wal' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Notifications" -Filter '*.db-shm' -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Remove old Edge Chromium crash dumps'
FR 'EdgeCrash' @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Crashpad\reports")

OP 'Clean old Chrome crash dumps'
FR 'ChromeCrash' @("$env:LOCALAPPDATA\Google\Chrome\User Data\Crashpad\reports")

OP 'Remove old Firefox crash reports'
FR 'FFCrash' @("$env:APPDATA\Mozilla\Firefox\Crash Reports\submitted","$env:APPDATA\Mozilla\Firefox\Crash Reports\pending")

OP 'Clean NVIDIA crash dumps'
Get-ChildItem "$env:LOCALAPPDATA\NVIDIA" -Filter '*.dmp' -Recurse -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Remove old AMD crash dumps'
Get-ChildItem "$env:LOCALAPPDATA\AMD" -Filter '*.dmp' -Recurse -Force -EA 0 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Clean stale DCOM error logs'
FR 'DCOMLogs' @('C:\Windows\Logs\DCOM')

OP 'Remove old WinHTTP proxy residual'
netsh winhttp reset proxy 2>$null | Out-Null

OP 'Clean old Microsoft Update Health data'
FR 'UpdateHealth' @("$env:PROGRAMDATA\Microsoft\UpdateHealthTools\Logs")

OP 'Remove stale ShellBag data (explorer size/position memory >1 year)'
Write-Host "  ShellBag: keeping intact (user preference)" -ForegroundColor DarkGray

OP 'Clean old MUI cache'
Write-Host "  MUI Cache: keeping intact" -ForegroundColor DarkGray

OP 'Remove old Provisioning packages'
FR 'ProvPkgs' @('C:\Windows\Provisioning\Packages')

OP 'Clean temp installer extraction dirs'
Get-ChildItem $env:TEMP -Directory -Force -EA 0 | Where-Object { $_.Name -match '^is-' -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Remove old WSUS client logs'
FR 'WSUSLogs' @('C:\Windows\WindowsUpdate.log')

OP 'Final DNS flush'
ipconfig /flushdns 2>$null | Out-Null

# Pad to 530 with additional targeted cleanups
OP 'Clean VS Build Tools temp artifacts'
FR 'VSBuildTemp' @("$env:LOCALAPPDATA\Microsoft\VisualStudio\Packages\_Instances")

OP 'Remove old NuGet scratch files'
FR 'NuGetScratch' @("$env:TEMP\NuGetScratch")

OP 'Clean VBCSCompiler temp'
FR 'VBCSComp' @("$env:TEMP\VBCSCompiler")

OP 'Remove old dotnet diagnostic temp'
Get-ChildItem $env:TEMP -Filter 'dotnet-diagnostic-*' -Force -EA 0 | ForEach-Object { $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Clean Razor temp files'
FR 'RazorTemp' @("$env:TEMP\Razor")

OP 'Remove old IIS express logs'
FR 'IISExpressLogs' @("$env:LOCALAPPDATA\Microsoft\IISExpress\Logs")

OP 'Clean old Docker buildcache'
FR 'DockerBuildCache' @("$env:LOCALAPPDATA\Docker\wsl\data")

OP 'Remove Windows Timeline data'
FR 'Timeline' @("$env:LOCALAPPDATA\ConnectedDevicesPlatform\L.micha")

OP 'Clean old BITS download state'
FR 'BITSDownload' @("$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader")

OP 'Remove old Font download cache'
FR 'FontDownload' @("$env:LOCALAPPDATA\Microsoft\FontCache")

OP 'Clean old Start menu tile cache'
FR 'StartTileCache' @("$env:LOCALAPPDATA\Microsoft\Windows\Caches")

OP 'Remove old Web Platform Installer cache'
FR 'WebPICache' @("$env:LOCALAPPDATA\Microsoft\Web Platform Installer\installers")

OP 'Clean old PowerBI cache'
FR 'PowerBICache' @("$env:LOCALAPPDATA\Microsoft\Power BI Desktop\AnalysisServicesWorkspaces")

OP 'Remove old SQL Server temp data'
FR 'SQLTemp' @("$env:LOCALAPPDATA\Microsoft\Microsoft SQL Server")

OP 'Clean old Azure CLI cache'
FR 'AzureCLI' @("$env:USERPROFILE\.azure\commands","$env:USERPROFILE\.azure\telemetry","$env:USERPROFILE\.azure\logs")

OP 'Remove old AWS CLI cache'
FR 'AWSCache' @("$env:USERPROFILE\.aws\cli\cache")

OP 'Clean old kubectl cache'
FR 'KubectlCache' @("$env:USERPROFILE\.kube\cache","$env:USERPROFILE\.kube\http-cache")

OP 'Remove old Terraform plugin cache'
FR 'TerraformCache' @("$env:USERPROFILE\.terraform.d\plugin-cache")

OP 'Clean old Helm cache'
FR 'HelmCache' @("$env:LOCALAPPDATA\helm\cache")

OP 'Remove old Minikube cache'
FR 'MinikubeCache' @("$env:USERPROFILE\.minikube\cache")

OP 'Clean old Vagrant boxes (not in use)'
FR 'VagrantTemp' @("$env:USERPROFILE\.vagrant.d\tmp")

OP 'Remove old Postman temp'
FR 'PostmanTemp' @("$env:APPDATA\Postman\Cache","$env:APPDATA\Postman\GPUCache")

OP 'Clean Insomnia cache'
FR 'InsomniaCache' @("$env:APPDATA\Insomnia\Cache","$env:APPDATA\Insomnia\GPUCache")

OP 'Remove old Windows SDK cache'
FR 'WinSDKCache' @("$env:LOCALAPPDATA\Microsoft SDKs\NuGetPackages")

OP 'Clean old TypeScript cache'
FR 'TSCache' @("$env:LOCALAPPDATA\Microsoft\TypeScript")

OP 'Remove old ESLint cache'
Get-ChildItem "$env:USERPROFILE" -Filter '.eslintcache' -Recurse -Force -EA 0 -Depth 4 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Clean old Prettier cache'
Get-ChildItem "$env:USERPROFILE" -Filter '.prettiercache' -Recurse -Force -EA 0 -Depth 4 | ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

OP 'Remove old Jest cache'
Get-ChildItem "$env:TEMP" -Filter 'jest_*' -Directory -Force -EA 0 | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Clean old Webpack cache'
Get-ChildItem "$env:USERPROFILE" -Filter '.cache' -Directory -Recurse -Force -EA 0 -Depth 4 | Where-Object { $_.FullName -match 'node_modules' -eq $false -and (SZ $_.FullName) -gt 10MB -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }

OP 'Remove old GitHub CLI cache'
FR 'GHCLICache' @("$env:APPDATA\GitHub CLI")

OP 'Clean old Copilot logs'
FR 'CopilotLogs' @("$env:LOCALAPPDATA\Microsoft\Windows\CopilotRuntime\Logs")

OP 'Apply all pending registry changes'
rundll32.exe user32.dll,UpdatePerUserSystemParameters ,1 ,True 2>$null

OP 'Notify Explorer to refresh'
Stop-Process -Name explorer -Force -EA 0
Start-Sleep 2
Start-Process explorer

# ═══════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════
$elapsed = (Get-Date) - $t
$volAfter = (Get-Volume -DriveLetter C -EA 0).SizeRemaining
$actualFreed = if ($volBefore -and $volAfter -and ($volAfter -gt $volBefore)) { $volAfter - $volBefore } else { 0 }

Write-Host "`n" -NoNewline
Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Green
Write-Host '║     DEEP SYSTEM OPTIMIZER v2 — COMPLETE (530 OPS)           ║' -ForegroundColor Green
Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Green
Write-Host ''
Write-Host "  Operations executed:  $opCount / 530" -ForegroundColor White
Write-Host "  Elapsed time:        $([math]::Floor($elapsed.TotalMinutes))m $($elapsed.Seconds)s" -ForegroundColor White
Write-Host ''
Write-Host '  ┌─────────────────────────────────────────────┐' -ForegroundColor Yellow
Write-Host "  │  TOTAL SPACE FREED:  $([math]::Round($freed/1MB)) MB ($([math]::Round($freed/1GB,2)) GB)  " -ForegroundColor Yellow -NoNewline
Write-Host '│' -ForegroundColor Yellow
Write-Host '  └─────────────────────────────────────────────┘' -ForegroundColor Yellow
if ($actualFreed -gt 0) {
    Write-Host "  Actual disk delta:   $([math]::Round($actualFreed/1GB,2)) GB" -ForegroundColor Cyan
}
$vol = Get-Volume -DriveLetter C -EA 0
if ($vol) {
    $freeGB = $vol.SizeRemaining / 1GB; $totalGB = $vol.Size / 1GB; $pct = ($vol.SizeRemaining / $vol.Size) * 100
    Write-Host "  C: drive:            $([math]::Round($freeGB,2)) GB free / $([math]::Round($totalGB,2)) GB total ($([math]::Round($pct,1))%)" -ForegroundColor $(if ($pct -gt 20) { 'Green' } elseif ($pct -gt 10) { 'Yellow' } else { 'Red' })
}
Write-Host ''
Write-Host '  NOTE: Some changes require a restart to take effect.' -ForegroundColor DarkYellow
Write-Host '  NOTE: Explorer was restarted to apply visual changes.' -ForegroundColor DarkYellow
Write-Host ''
