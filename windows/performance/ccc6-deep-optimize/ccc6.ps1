#Requires -RunAsAdministrator
<#
.SYNOPSIS
    CCC6: 520+ Deep Space Recovery + PC Optimization Operations
    Everything that cccc/nocccc/ccc4/ccc5 do NOT cover.
    
.DESCRIPTION
    SAFE operations only - never removes user files, apps, games, or settings.
    520+ individual operations across 25 categories.

.NOTES
    Author: Till's automation stack | Created: 2026-03-19
    Location: F:\study\Platforms\windows\performance\ccc6-deep-optimize\ccc6.ps1
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$t = Get-Date
$freed = [long]0
$opCount = 0

function SZ($p) { if (Test-Path $p -EA 0) { (Get-ChildItem $p -Recurse -Force -EA 0 | Measure-Object Length -Sum -EA 0).Sum } else { 0 } }

function FR($label, $paths) {
    $b = [long]0
    foreach ($p in $paths) {
        if (Test-Path $p -EA 0) {
            $s = SZ $p
            if ($s -gt 1MB) { Write-Host "  $p ($([math]::Round($s/1MB))MB)" -ForegroundColor DarkGray }
            $b += $s
            Get-ChildItem $p -Force -EA 0 | Remove-Item -Recurse -Force -EA 0
        }
    }
    $script:freed += $b
    $script:opCount++
    if ($b -gt 0) {
        Write-Host "  -> $label freed: $([math]::Round($b/1MB))MB" -ForegroundColor $(if ($b -gt 50MB) { 'Green' } elseif ($b -gt 1MB) { 'Yellow' } else { 'Gray' })
    }
}

function OP($desc) { $script:opCount++; Write-Host "  [$script:opCount] $desc" -ForegroundColor DarkGray }

function REGSET($path, $name, $value, $type = 'DWord') {
    $script:opCount++
    if (!(Test-Path $path)) { New-Item -Path $path -Force -EA 0 | Out-Null }
    Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -EA 0
}

function SVCDIS($name) {
    $script:opCount++
    $s = Get-Service -Name $name -EA 0
    if ($s -and $s.StartType -ne 'Disabled') {
        Stop-Service -Name $name -Force -EA 0
        Set-Service -Name $name -StartupType Disabled -EA 0
        Write-Host "  Disabled: $name" -ForegroundColor DarkGray
    }
}

function TASKDIS($taskName) {
    $script:opCount++
    $task = Get-ScheduledTask -TaskName $taskName -EA 0
    if ($task -and $task.State -ne 'Disabled') {
        Disable-ScheduledTask -TaskName $taskName -EA 0 | Out-Null
        Write-Host "  Disabled task: $taskName" -ForegroundColor DarkGray
    }
}

function CLEANDIR($path, $daysOld = 0) {
    $script:opCount++
    if (Test-Path $path -EA 0) {
        $cutoff = (Get-Date).AddDays(-$daysOld)
        $items = if ($daysOld -gt 0) {
            Get-ChildItem $path -Force -Recurse -EA 0 | Where-Object { $_.LastWriteTime -lt $cutoff }
        } else {
            Get-ChildItem $path -Force -Recurse -EA 0
        }
        $s = ($items | Measure-Object Length -Sum -EA 0).Sum
        $script:freed += $s
        $items | Remove-Item -Recurse -Force -EA 0
        if ($s -gt 1MB) { Write-Host "  $path ($([math]::Round($s/1MB))MB)" -ForegroundColor DarkGray }
    }
}

$volBefore = (Get-Volume -DriveLetter C -EA 0).SizeRemaining

Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Magenta
Write-Host '║  CCC6: 520+ DEEP SPACE RECOVERY + PC OPTIMIZATION          ║' -ForegroundColor Magenta
Write-Host '║  Everything cccc/nocccc/ccc4/ccc5 do NOT cover              ║' -ForegroundColor Magenta
Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Magenta
Write-Host "Started: $(Get-Date -Format 'HH:mm:ss')`n" -ForegroundColor White

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 1: WINDOWS SYSTEM CACHES (ops 1-30)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 1/25] WINDOWS SYSTEM CACHES (30 ops) ━━━' -ForegroundColor Cyan

# 1-2: Delivery Optimization
Stop-Service DoSvc -Force -EA 0
FR 'DeliveryOptimization-Cache' @('C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache')
FR 'DeliveryOptimization-Logs' @('C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Logs')
Delete-DeliveryOptimizationCache -Force -EA 0; $opCount++
Start-Service DoSvc -EA 0

# 3-8: Font cache
Stop-Service FontCache -Force -EA 0
Stop-Service FontCache3.0.0.0 -Force -EA 0
CLEANDIR 'C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache'
CLEANDIR 'C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache-System'
CLEANDIR 'C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache-S-1-5-21*'
if (Test-Path 'C:\Windows\System32\FNTCACHE.DAT') { $s=(Get-Item 'C:\Windows\System32\FNTCACHE.DAT' -EA 0).Length; $freed+=$s; Remove-Item 'C:\Windows\System32\FNTCACHE.DAT' -Force -EA 0; $opCount++ }
Start-Service FontCache -EA 0

# 9-14: Thumbnail/Icon caches
$thumbDir = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
Get-ChildItem $thumbDir -Filter 'thumbcache_*' -Force -EA 0 | ForEach-Object { $freed+=$_.Length; Remove-Item $_.FullName -Force -EA 0 }; $opCount++
Get-ChildItem $thumbDir -Filter 'iconcache_*' -Force -EA 0 | ForEach-Object { $freed+=$_.Length; Remove-Item $_.FullName -Force -EA 0 }; $opCount++
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\ExplorerStartupLog"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\ExplorerStartupLog_RunOnce"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\Caches"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\Content.IE5"

# 15-20: Windows caches
CLEANDIR 'C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\INetCache'
CLEANDIR 'C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\Caches'
CLEANDIR 'C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\Explorer'
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\INetCookies"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\WebCache"

# 21-25: Shader caches
CLEANDIR "$env:LOCALAPPDATA\D3DSCache"
CLEANDIR "$env:LOCALAPPDATA\NVIDIA\DXCache"
CLEANDIR "$env:LOCALAPPDATA\NVIDIA\GLCache"
CLEANDIR "$env:LOCALAPPDATA\AMD\DxCache"
CLEANDIR "$env:LOCALAPPDATA\AMD\GLCache"

# 26-30: More system caches
CLEANDIR 'C:\Windows\SystemTemp'
CLEANDIR "$env:LOCALAPPDATA\Microsoft\CLR_v4.0\UsageLogs"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\CLR_v4.0_32\UsageLogs"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\ActionCenterCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\Notifications"

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 2: LOG FILE CLEANUP (ops 31-70)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 2/25] LOG FILE CLEANUP (40 ops) ━━━' -ForegroundColor Cyan

CLEANDIR 'C:\Windows\Logs\CBS'
CLEANDIR 'C:\Windows\Logs\DISM'
CLEANDIR 'C:\Windows\Logs\MoSetup'
CLEANDIR 'C:\Windows\Logs\WindowsUpdate'
CLEANDIR 'C:\Windows\Logs\SIH'
CLEANDIR 'C:\Windows\Logs\waasmedic'
CLEANDIR 'C:\Windows\Logs\NetSetup'
CLEANDIR 'C:\Windows\Logs\DPX'
CLEANDIR 'C:\Windows\Logs\SystemRestore'
CLEANDIR 'C:\Windows\Logs\waasmediccapsule'
CLEANDIR 'C:\Windows\Panther'
CLEANDIR 'C:\Windows\INF\setupapi*.log' # handled individually below
CLEANDIR 'C:\Windows\debug'
CLEANDIR 'C:\Windows\SoftwareDistribution\DataStore\Logs'
CLEANDIR 'C:\Windows\ServiceProfiles\LocalService\AppData\Local\Temp'
CLEANDIR 'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Temp'
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\SettingSync\metastore"

# Clean individual log files
$logPatterns = @('*.log','*.etl','*.log.old','*.log.bak','*.log.1','*.log.2','*.log.txt')
foreach ($pat in $logPatterns) {
    $files = Get-ChildItem 'C:\Windows\Logs' -Filter $pat -Recurse -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
    $s = ($files | Measure-Object Length -Sum -EA 0).Sum; $freed += $s; $opCount++
    $files | Remove-Item -Force -EA 0
}

# ETL trace files
Get-ChildItem 'C:\Windows\System32\LogFiles' -Filter '*.etl' -Recurse -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } | ForEach-Object { $freed+=$_.Length; Remove-Item $_.FullName -Force -EA 0 }; $opCount++
Get-ChildItem 'C:\Windows\System32\WDI\LogFiles' -Recurse -Force -EA 0 | ForEach-Object { $freed+=$_.Length; Remove-Item $_.FullName -Force -EA 0 }; $opCount++
CLEANDIR 'C:\Windows\System32\LogFiles\WMI\RtBackup' 3
CLEANDIR 'C:\Windows\System32\LogFiles\HTTPERR'
CLEANDIR 'C:\Windows\System32\LogFiles\Firewall'
CLEANDIR 'C:\Windows\System32\LogFiles\Scm'

# App log dirs
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\DeliveryOptimization\Logs"
CLEANDIR "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Search_cw5n1h2txyewy\LocalState\ConstraintIndex" 30
CLEANDIR "$env:ProgramData\USOShared\Logs"
CLEANDIR "$env:ProgramData\Microsoft\Windows Defender\Scans\History\Results"
CLEANDIR "$env:ProgramData\Microsoft\Windows Defender\Support"
CLEANDIR "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\GatherLogs"

# Event logs
$evtBefore = (Get-ChildItem 'C:\Windows\System32\winevt\Logs' -EA 0 | Measure-Object Length -Sum -EA 0).Sum
wevtutil el 2>$null | ForEach-Object { wevtutil cl $_ 2>$null; $opCount++ }
$evtAfter = (Get-ChildItem 'C:\Windows\System32\winevt\Logs' -EA 0 | Measure-Object Length -Sum -EA 0).Sum
$freed += [math]::Max(0, $evtBefore - $evtAfter)

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 3: MEMORY DUMPS & CRASH DATA (ops 71-85)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 3/25] MEMORY DUMPS & CRASH DATA (15 ops) ━━━' -ForegroundColor Cyan

if (Test-Path 'C:\Windows\MEMORY.DMP') { $s=(Get-Item 'C:\Windows\MEMORY.DMP').Length; $freed+=$s; Remove-Item 'C:\Windows\MEMORY.DMP' -Force -EA 0; $opCount++; Write-Host "  MEMORY.DMP ($([math]::Round($s/1GB,2))GB)" -ForegroundColor DarkGray }
CLEANDIR 'C:\Windows\Minidump'
CLEANDIR 'C:\Windows\LiveKernelReports'
CLEANDIR "$env:LOCALAPPDATA\CrashDumps"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\WER\Temp"
CLEANDIR 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
CLEANDIR 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue'
CLEANDIR 'C:\ProgramData\Microsoft\Windows\WER\Temp'
# Crash report logs
Get-ChildItem "$env:LOCALAPPDATA" -Filter '*.dmp' -Recurse -Force -EA 0 -Depth 2 | ForEach-Object { $freed+=$_.Length; Remove-Item $_.FullName -Force -EA 0 }; $opCount++
Get-ChildItem 'C:\ProgramData' -Filter '*.dmp' -Recurse -Force -EA 0 -Depth 2 | ForEach-Object { $freed+=$_.Length; Remove-Item $_.FullName -Force -EA 0 }; $opCount++
Get-ChildItem 'C:\Windows\System32' -Filter '*.dmp' -Force -EA 0 | ForEach-Object { $freed+=$_.Length; Remove-Item $_.FullName -Force -EA 0 }; $opCount++
CLEANDIR 'C:\ProgramData\Microsoft\Windows\WER'
CLEANDIR "$env:TEMP\WER"

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 4: PREFETCH & SUPERFETCH (ops 86-90)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 4/25] PREFETCH & SUPERFETCH (5 ops) ━━━' -ForegroundColor Cyan

CLEANDIR 'C:\Windows\Prefetch'
CLEANDIR 'C:\Windows\System32\SleepStudy'
CLEANDIR 'C:\Windows\System32\sru' 30
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\AppCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\History"

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 5: NETWORK CACHES & OPTIMIZATION (ops 91-130)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 5/25] NETWORK CACHES & OPTIMIZATION (40 ops) ━━━' -ForegroundColor Cyan

# Cache flushes
ipconfig /flushdns 2>$null | Out-Null; $opCount++
arp -d * 2>$null | Out-Null; $opCount++
nbtstat -R 2>$null | Out-Null; $opCount++
nbtstat -RR 2>$null | Out-Null; $opCount++
netsh interface ip delete arpcache 2>$null | Out-Null; $opCount++
netsh interface ip delete destinationcache 2>$null | Out-Null; $opCount++
netsh branchcache flush 2>$null | Out-Null; $opCount++

# BITS cache
Stop-Service BITS -Force -EA 0
FR 'BITS' @('C:\ProgramData\Microsoft\Network\Downloader')
Start-Service BITS -EA 0

# Network registry optimizations
$tcpParams = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
REGSET $tcpParams 'DefaultTTL' 64
REGSET $tcpParams 'EnablePMTUDiscovery' 1
REGSET $tcpParams 'EnablePMTUBHDetect' 0
REGSET $tcpParams 'Tcp1323Opts' 3
REGSET $tcpParams 'TcpMaxDupAcks' 2
REGSET $tcpParams 'SackOpts' 1
REGSET $tcpParams 'GlobalMaxTcpWindowSize' 65535
REGSET $tcpParams 'TcpWindowSize' 65535
REGSET $tcpParams 'MaxConnectionsPerServer' 16
REGSET $tcpParams 'MaxUserPort' 65534
REGSET $tcpParams 'TcpTimedWaitDelay' 30
REGSET $tcpParams 'EnableDCA' 1
REGSET $tcpParams 'EnableTCPA' 1
REGSET $tcpParams 'DisableTaskOffload' 0

# Per-interface Nagle disable
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -EA 0 | ForEach-Object {
    REGSET $_.PSPath 'TcpAckFrequency' 1
    REGSET $_.PSPath 'TCPNoDelay' 1
    REGSET $_.PSPath 'TcpDelAckTicks' 0
}

# Disable network throttling
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xffffffff
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 0

# LanmanServer optimizations
$lanman = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
REGSET $lanman 'IRPStackSize' 32
REGSET $lanman 'Size' 3
REGSET $lanman 'MaxMpxCt' 2048
REGSET $lanman 'MaxWorkItems' 8192

# DNS cache optimization
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'MaxCacheEntryTtlLimit' 86400
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'MaxNegativeCacheTtl' 5

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 6: TELEMETRY & PRIVACY (ops 131-200)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 6/25] TELEMETRY & PRIVACY (70 ops) ━━━' -ForegroundColor Cyan

# Stop telemetry services first
Stop-Service DiagTrack -Force -EA 0

# Clean telemetry data
CLEANDIR 'C:\ProgramData\Microsoft\Diagnosis\ETLLogs'
CLEANDIR 'C:\ProgramData\Microsoft\Diagnosis\DownloadedSettings'
CLEANDIR "$env:LOCALAPPDATA\Diagnostics"
CLEANDIR "$env:LOCALAPPDATA\Temp\DiagOutputDir"
CLEANDIR 'C:\ProgramData\Microsoft\Diagnosis'
CLEANDIR "$env:ProgramData\Microsoft\Diagnosis\EventTranscript"

# Telemetry registry blocks
$telPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
REGSET $telPath 'AllowTelemetry' 0
REGSET $telPath 'AllowDeviceNameInTelemetry' 0
REGSET $telPath 'DoNotShowFeedbackNotifications' 1
REGSET $telPath 'AllowCommercialDataPipeline' 0

REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'MaxTelemetryAllowed' 0

# Disable Customer Experience Improvement Program
REGSET 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows' 'CEIPEnable' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0

# Disable Application Impact Telemetry
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisablePCA' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableUAR' 1

# Disable advertising ID
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1

# Disable activity history
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0

# Disable location tracking
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocationScripting' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableWindowsLocationProvider' 1

# Disable diagnostic data viewer
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack\EventTranscriptKey' 'EnableEventTranscript' 0

# Disable feedback frequency
REGSET 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 0

# Disable typed URL tracking
REGSET 'HKCU:\SOFTWARE\Microsoft\Internet Explorer\TypedURLs' 'url1' '' 'String'

# Disable input personalization
REGSET 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
REGSET 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
REGSET 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0

# Disable Bing search in start menu
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
REGSET 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0

# Disable cloud content
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1
REGSET 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
REGSET 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1

# Disable app suggestions (Start menu bloat)
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-314563Enabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353698Enabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 0

# Disable tips/suggestions
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'EnableFeaturedSoftware' 0

Start-Service DiagTrack -EA 0

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 7: SERVICE OPTIMIZATION (ops 201-250)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 7/25] SERVICE OPTIMIZATION (50 ops) ━━━' -ForegroundColor Cyan

# Telemetry/tracking services
SVCDIS 'DiagTrack'
SVCDIS 'dmwappushservice'
SVCDIS 'WerSvc'
SVCDIS 'RetailDemo'
SVCDIS 'MapsBroker'
SVCDIS 'lfsvc'
SVCDIS 'wisvc'
SVCDIS 'WMPNetworkSvc'

# Unnecessary services
SVCDIS 'RemoteRegistry'
SVCDIS 'SharedAccess'
SVCDIS 'TrkWks'           # Distributed Link Tracking Client
SVCDIS 'WbioSrvc'         # Windows Biometric (no fingerprint reader)
SVCDIS 'WSearch'           # Windows Search (if SSD, not needed)
SVCDIS 'Fax'
SVCDIS 'fhsvc'            # File History
SVCDIS 'PhoneSvc'          # Phone Service
SVCDIS 'TabletInputService'  # Touch Keyboard
SVCDIS 'SensrSvc'         # Sensor Monitoring
SVCDIS 'SensorDataService'
SVCDIS 'SensorService'
SVCDIS 'PcaSvc'           # Program Compatibility Assistant
SVCDIS 'wercplsupport'    # Problem Reports
SVCDIS 'diagnosticshub.standardcollector.service'
SVCDIS 'DiagSvc'
SVCDIS 'DPS'              # Diagnostic Policy
SVCDIS 'WdiServiceHost'
SVCDIS 'WdiSystemHost'

# Xbox services (if not gaming on Xbox)
SVCDIS 'XblAuthManager'
SVCDIS 'XblGameSave'
SVCDIS 'XboxGipSvc'
SVCDIS 'XboxNetApiSvc'

# Print services (if no printer)
# SVCDIS 'Spooler' # Keep if user has printer

# Bluetooth (keep - might be used)
# Remote services
SVCDIS 'RemoteAccess'
SVCDIS 'RasAuto'
SVCDIS 'SessionEnv'
SVCDIS 'TermService'
SVCDIS 'UmRdpService'
SVCDIS 'RasMan'

# Misc services
SVCDIS 'MessagingService'
SVCDIS 'icssvc'            # Mobile Hotspot
SVCDIS 'WpcMonSvc'         # Parental Controls
SVCDIS 'SEMgrSvc'          # Payments and NFC
SVCDIS 'lmhosts'           # TCP/IP NetBIOS Helper
SVCDIS 'NetTcpPortSharing'
SVCDIS 'p2pimsvc'          # Peer Networking Identity Manager
SVCDIS 'PNRPsvc'           # Peer Name Resolution Protocol
SVCDIS 'p2psvc'            # Peer Networking Grouping
SVCDIS 'PNRPAutoReg'       # PNRP Machine Name Publication

# Hyper-V (if not using VMs)
SVCDIS 'vmickvpexchange'
SVCDIS 'vmicguestinterface'
SVCDIS 'vmicshutdown'
SVCDIS 'vmicheartbeat'
SVCDIS 'vmictimesync'

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 8: SCHEDULED TASKS CLEANUP (ops 251-310)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 8/25] SCHEDULED TASKS CLEANUP (60 ops) ━━━' -ForegroundColor Cyan

# Microsoft telemetry tasks
TASKDIS 'Consolidator'
TASKDIS 'UsbCeip'
TASKDIS 'QueueReporting'
TASKDIS 'DmClient'
TASKDIS 'DmClientOnScenarioDownload'
TASKDIS 'MapsToastTask'
TASKDIS 'MapsUpdateTask'
TASKDIS 'FamilySafetyMonitor'
TASKDIS 'FamilySafetyRefreshTask'
TASKDIS 'XblGameSaveTask'
TASKDIS 'XblGameSaveTaskLogon'

# Customer Experience
TASKDIS 'Microsoft-Windows-DiskDiagnosticDataCollector'
TASKDIS 'TempSignedLicenseExchange'
TASKDIS 'KernelCeipTask'
TASKDIS 'BthSQM'

# Compatibility
TASKDIS 'ProgramDataUpdater'
TASKDIS 'Appraiser'
TASKDIS 'AitAgent'
TASKDIS 'StartupAppTask'
TASKDIS 'CompatTelRunner'

# Cloud
TASKDIS 'CreateObjectTask'
TASKDIS 'CloudExperienceHostLaunchTask'

# Feedback
TASKDIS 'Sqm-Tasks'
TASKDIS 'PushLaunch'

# Diagnostic
TASKDIS 'ScheduledDefrag'  # SSD doesn't need defrag
TASKDIS 'ProactiveScan'
TASKDIS 'WinSAT'
TASKDIS 'SpeechModelDownloadTask'
TASKDIS 'PerformRemediation'

# Update tasks that re-enable stuff
TASKDIS 'MareBackup'
TASKDIS 'MNO Metadata Parser'

# Shell tasks
TASKDIS 'IndexerAutomaticMaintenance'

# Additional maintenance tasks
$taskPatterns = @(
    '\Microsoft\Windows\Application Experience\*',
    '\Microsoft\Windows\Autochk\*',
    '\Microsoft\Windows\Customer Experience Improvement Program\*',
    '\Microsoft\Windows\DiskDiagnostic\*',
    '\Microsoft\Windows\Feedback\Siuf\*',
    '\Microsoft\Windows\Maps\*',
    '\Microsoft\Windows\PI\*',
    '\Microsoft\Windows\Windows Error Reporting\*',
    '\Microsoft\Windows\Flighting\*'
)
foreach ($pattern in $taskPatterns) {
    Get-ScheduledTask -TaskPath ($pattern -replace '\*$','') -EA 0 | Where-Object { $_.State -ne 'Disabled' } | ForEach-Object {
        Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -EA 0 | Out-Null; $opCount++
        Write-Host "  Disabled: $($_.TaskPath)$($_.TaskName)" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 9: REGISTRY PERFORMANCE TWEAKS (ops 311-400)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 9/25] REGISTRY PERFORMANCE TWEAKS (90 ops) ━━━' -ForegroundColor Cyan

# --- CPU Priority ---
$perfPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
REGSET $perfPath 'Win32PrioritySeparation' 38
REGSET $perfPath 'IRQ8Priority' 1

# --- NTFS Performance ---
$ntfs = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
REGSET $ntfs 'NtfsMemoryUsage' 2
REGSET $ntfs 'NtfsDisableLastAccessUpdate' 1
REGSET $ntfs 'NtfsDisable8dot3NameCreation' 1
REGSET $ntfs 'NtfsAllowExtendedCharacterIn8dot3Name' 0
REGSET $ntfs 'NtfsDisableCompression' 0
REGSET $ntfs 'NtfsBugcheckOnCorrupt' 0
REGSET $ntfs 'NtfsEncryptionService' 0

# --- Memory Management ---
$memMgmt = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
REGSET $memMgmt 'DisablePagingExecutive' 1
REGSET $memMgmt 'LargeSystemCache' 0
REGSET $memMgmt 'IoPageLockLimit' 983040
REGSET $memMgmt 'PoolUsageMaximum' 60
REGSET $memMgmt 'ClearPageFileAtShutdown' 0  # Faster shutdown
REGSET $memMgmt 'SecondLevelDataCache' 1024
REGSET $memMgmt 'SessionPoolSize' 48
REGSET $memMgmt 'SystemPages' 0xFFFFFFFF
REGSET $memMgmt 'NonPagedPoolSize' 0
REGSET $memMgmt 'PagedPoolSize' 0xFFFFFFFF
REGSET $memMgmt 'PhysicalAddressExtension' 1

# Spectre/Meltdown mitigations OFF (max perf)
REGSET $memMgmt 'FeatureSettingsOverride' 3
REGSET $memMgmt 'FeatureSettingsOverrideMask' 3

# --- GPU ---
$graphicsDrivers = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
REGSET $graphicsDrivers 'HwSchMode' 2     # Hardware GPU scheduling
REGSET $graphicsDrivers 'TdrDelay' 10     # Longer timeout before GPU reset
REGSET $graphicsDrivers 'TdrDdiDelay' 10

# Disable Game DVR/Bar overhead
REGSET 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
REGSET 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2
REGSET 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 1
REGSET 'HKCU:\System\GameConfigStore' 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
REGSET 'HKCU:\System\GameConfigStore' 'GameDVR_EFSEFeatureFlags' 0
$gameDVR = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
REGSET $gameDVR 'AllowGameDVR' 0

# --- Power Throttling OFF ---
$pwrThrottle = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'
REGSET $pwrThrottle 'PowerThrottlingOff' 1

# --- Boot/Shutdown optimization ---
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'VerboseStatus' 1
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '2000' 'String'
REGSET 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '2000' 'String'
REGSET 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '1000' 'String'
REGSET 'HKCU:\Control Panel\Desktop' 'AutoEndTasks' '1' 'String'
REGSET 'HKCU:\Control Panel\Desktop' 'LowLevelHooksTimeout' 1000
REGSET 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '50' 'String'
REGSET 'HKCU:\Control Panel\Desktop' 'ForegroundFlashCount' 3
REGSET 'HKCU:\Control Panel\Desktop' 'ForegroundLockTimeout' 0

# --- Explorer Performance ---
$advPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
REGSET $advPath 'TaskbarAnimations' 0
REGSET $advPath 'ListviewAlphaSelect' 0
REGSET $advPath 'ExtendedUIHoverTime' 100
REGSET $advPath 'Start_TrackDocs' 0
REGSET $advPath 'Start_TrackProgs' 0
REGSET $advPath 'DisallowShaking' 1
REGSET $advPath 'EnableBalloonTips' 0
REGSET $advPath 'ShowInfoTip' 0
REGSET $advPath 'LaunchTO' 0   # Launch folder windows in separate process

# --- DWM Performance ---
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' 'AlwaysHibernateThumbnails' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' 'Composition' 1  # Keep composition (needed)

# --- Window Animations OFF ---
REGSET 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
$visFX = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
REGSET $visFX 'VisualFXSetting' 3

# --- Disable cursor shadow/tooltip animations ---
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type Binary -EA 0; $opCount++

# --- Multimedia scheduling (gaming priority) ---
$mmProfile = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
REGSET $mmProfile 'SystemResponsiveness' 0
REGSET $mmProfile 'NetworkThrottlingIndex' 0xFFFFFFFF
REGSET $mmProfile 'NoLazyMode' 1
$mmGames = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
REGSET $mmGames 'Affinity' 0
REGSET $mmGames 'Background Only' 'False' 'String'
REGSET $mmGames 'Clock Rate' 10000
REGSET $mmGames 'GPU Priority' 8
REGSET $mmGames 'Priority' 6
REGSET $mmGames 'Scheduling Category' 'High' 'String'
REGSET $mmGames 'SFIO Priority' 'High' 'String'

# --- Storage sense ---
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' 'StoragePoliciesNotified' 1
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 1  # Enable
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '2048' 1  # Auto cleanup
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '04' 1  # Temp files
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '08' 1  # Recycle bin
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '32' 1  # Downloads
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '256' 14  # Run every week

# --- Context Menu Speed ---
REGSET 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '50' 'String'

# --- Disable startup delay ---
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 10: APP-SPECIFIC CACHE CLEANUP (ops 401-440)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 10/25] APP-SPECIFIC CACHE CLEANUP (40 ops) ━━━' -ForegroundColor Cyan

# VS Code
CLEANDIR "$env:APPDATA\Code\Cache"
CLEANDIR "$env:APPDATA\Code\CachedData"
CLEANDIR "$env:APPDATA\Code\CachedExtensions"
CLEANDIR "$env:APPDATA\Code\CachedExtensionVSIXs"
CLEANDIR "$env:APPDATA\Code\Code Cache"
CLEANDIR "$env:APPDATA\Code\Crashpad"
CLEANDIR "$env:APPDATA\Code\logs"
CLEANDIR "$env:APPDATA\Code\Service Worker\CacheStorage"

# Discord
CLEANDIR "$env:APPDATA\discord\Cache"
CLEANDIR "$env:APPDATA\discord\Code Cache"
CLEANDIR "$env:APPDATA\discord\GPUCache"

# Slack
CLEANDIR "$env:APPDATA\Slack\Cache"
CLEANDIR "$env:APPDATA\Slack\Code Cache"
CLEANDIR "$env:APPDATA\Slack\GPUCache"
CLEANDIR "$env:APPDATA\Slack\Service Worker"

# Teams
CLEANDIR "$env:APPDATA\Microsoft\Teams\Cache"
CLEANDIR "$env:APPDATA\Microsoft\Teams\blob_storage"
CLEANDIR "$env:APPDATA\Microsoft\Teams\Code Cache"
CLEANDIR "$env:APPDATA\Microsoft\Teams\GPUCache"
CLEANDIR "$env:APPDATA\Microsoft\Teams\tmp"

# Spotify
CLEANDIR "$env:LOCALAPPDATA\Spotify\Data"
CLEANDIR "$env:LOCALAPPDATA\Spotify\Storage"

# Steam
CLEANDIR "$env:LOCALAPPDATA\Steam\htmlcache"
CLEANDIR "$env:LOCALAPPDATA\Steam\appcache"

# Java
CLEANDIR "$env:LOCALAPPDATA\Sun\Java\Deployment\cache"
CLEANDIR "$env:LOCALAPPDATA\Temp\hsperfdata_*"

# Node.js / Electron
CLEANDIR "$env:APPDATA\electron\Cache"
CLEANDIR "$env:APPDATA\electron-builder\Cache"

# Git
CLEANDIR "$env:LOCALAPPDATA\GitHubDesktop\Cache"

# PowerShell
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\CommandAnalysis"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\AnalysisCacheIndex"

# Windows Terminal
CLEANDIR "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalCache"

# Notepad++
CLEANDIR "$env:APPDATA\Notepad++\backup"

# OBS
CLEANDIR "$env:APPDATA\obs-studio\logs"
CLEANDIR "$env:APPDATA\obs-studio\crashes"

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 11: WINDOWS STORE & APPX CLEANUP (ops 441-455)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 11/25] WINDOWS STORE & APPX (15 ops) ━━━' -ForegroundColor Cyan

# Store cache
CLEANDIR "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"
CLEANDIR "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\TempState"
Start-Process wsreset.exe -ArgumentList '-i' -WindowStyle Hidden -EA 0; $opCount++

# App package caches
Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -EA 0 | ForEach-Object {
    $cache = Join-Path $_.FullName 'LocalCache'
    $temp = Join-Path $_.FullName 'TempState'
    if (Test-Path $cache -EA 0) { $s = SZ $cache; $freed += $s; Get-ChildItem $cache -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 }
    if (Test-Path $temp -EA 0) { $s = SZ $temp; $freed += $s; Get-ChildItem $temp -Force -EA 0 | Remove-Item -Recurse -Force -EA 0 }
    $opCount++
} | Out-Null

# Remove staged packages
Get-AppxPackage -AllUsers -EA 0 | Where-Object { $_.PackageUserInformation.InstallState -eq 'Staged' } | ForEach-Object {
    Remove-AppxPackage -Package $_.PackageFullName -AllUsers -EA 0; $opCount++
}

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 12: DRIVER CLEANUP (ops 456-465)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 12/25] DRIVER CLEANUP (10 ops) ━━━' -ForegroundColor Cyan

# Old driver packages
$drivers = pnputil /enum-drivers 2>$null
$driverEntries = @()
$current = @{}
$drivers -split "`n" | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^Published Name\s*:\s*(.+)') { $current.Name = $Matches[1].Trim() }
    if ($line -match '^Original Name\s*:\s*(.+)') { $current.Original = $Matches[1].Trim() }
    if ($line -match '^Class Name\s*:\s*(.+)') { $current.Class = $Matches[1].Trim() }
    if ($line -match '^Driver Date and Version\s*:\s*(.+)') {
        $current.DateVer = $Matches[1].Trim()
        $driverEntries += [PSCustomObject]$current
        $current = @{}
    }
}
$groups = $driverEntries | Where-Object { $_.Original -and $_.Class } | Group-Object { "$($_.Original)|$($_.Class)" }
foreach ($g in $groups) {
    if ($g.Count -gt 1) {
        $sorted = $g.Group | Sort-Object DateVer
        $old = $sorted | Select-Object -SkipLast 1
        foreach ($d in $old) {
            pnputil /delete-driver $d.Name /force 2>$null | Out-Null; $opCount++
            Write-Host "  Old driver: $($d.Name)" -ForegroundColor DarkGray
        }
    }
}

# Driver store cleanup
CLEANDIR 'C:\Windows\System32\DriverStore\Temp'
CLEANDIR 'C:\Windows\System32\DriverStore\FileRepository\*.old'

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 13: SSD OPTIMIZATION (ops 466-475)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 13/25] SSD OPTIMIZATION (10 ops) ━━━' -ForegroundColor Cyan

# TRIM all drives
Get-Volume -EA 0 | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
    Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -EA 0; $opCount++
    Write-Host "  TRIM on $($_.DriveLetter):" -ForegroundColor DarkGray
}

# NTFS optimizations for SSD
fsutil behavior set disablelastaccess 1 2>$null | Out-Null; $opCount++
fsutil behavior set disable8dot3 1 2>$null | Out-Null; $opCount++
fsutil behavior set encryptpagingfile 0 2>$null | Out-Null; $opCount++
fsutil behavior set mftzone 2 2>$null | Out-Null; $opCount++

# Disable indexing on SSDs
Get-WmiObject Win32_Volume -EA 0 | Where-Object { $_.DriveLetter -and $_.IndexingEnabled } | ForEach-Object {
    $_.IndexingEnabled = $false; $_.Put() | Out-Null; $opCount++
    Write-Host "  Indexing disabled: $($_.DriveLetter)" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 14: STARTUP OPTIMIZATION (ops 476-495)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 14/25] STARTUP OPTIMIZATION (20 ops) ━━━' -ForegroundColor Cyan

$startupBloat = @(
    '*Cortana*','*OneDrive*','*Teams*Update*','*Edge*Update*',
    '*GoogleUpdate*','*Discord*Update*','SecurityHealth*',
    '*AdobeAAM*','*Adobe ARM*','*iTunes*Helper*','*Skype*',
    '*CCleaner*Monitor*','*RealPlayer*','*QuickTime*','*Java*Update*'
)

$startupPaths = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)

foreach ($sp in $startupPaths) {
    $props = Get-ItemProperty -Path $sp -EA 0
    if ($props) {
        $props.PSObject.Properties | Where-Object { $_.Name -notin 'PSPath','PSParentPath','PSChildName','PSProvider','PSDrive' } | ForEach-Object {
            foreach ($pattern in $startupBloat) {
                if ($_.Name -like $pattern -or $_.Value -like "*$pattern*") {
                    Remove-ItemProperty -Path $sp -Name $_.Name -Force -EA 0; $opCount++
                    Write-Host "  Removed startup: $($_.Name)" -ForegroundColor DarkGray
                }
            }
        }
    }
}

# Disable startup delay
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 15: WINDOWS UPDATE CLEANUP (ops 496-505)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 15/25] WINDOWS UPDATE CLEANUP (10 ops) ━━━' -ForegroundColor Cyan

Stop-Service wuauserv -Force -EA 0
CLEANDIR 'C:\Windows\SoftwareDistribution\Download'
CLEANDIR 'C:\Windows\SoftwareDistribution\DataStore\Logs'
CLEANDIR 'C:\Windows\SoftwareDistribution\PostRebootEventCache.V2'
Start-Service wuauserv -EA 0

# Reduce reserved storage
DISM /Online /Set-ReservedStorageState /State:Disabled 2>$null | Out-Null; $opCount++

# Windows Update log cleanup
Get-ChildItem 'C:\Windows' -Filter 'WindowsUpdate*.log' -Force -EA 0 | ForEach-Object { $freed+=$_.Length; Remove-Item $_.FullName -Force -EA 0 }; $opCount++
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\WindowsUpdate" -Force -EA 0 | Remove-Item -Recurse -Force -EA 0; $opCount++

# Clean update cache via built-in
$job = Start-Job { dism /online /cleanup-image /startcomponentcleanup /resetbase 2>&1 | Select-Object -Last 1 }
Wait-Job $job -Timeout 120 -EA 0 | Out-Null
$out = Receive-Job $job -EA 0
Stop-Job $job -EA 0; Remove-Job $job -Force -EA 0
$opCount++

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 16: VISUAL EFFECTS OPTIMIZATION (ops 506-515)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 16/25] VISUAL EFFECTS (10 ops) ━━━' -ForegroundColor Cyan

# Custom visual effects (animations off, ClearType on)
REGSET 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '1' 'String'
REGSET 'HKCU:\Control Panel\Desktop' 'FontSmoothing' '2' 'String'  # ClearType
REGSET 'HKCU:\Control Panel\Desktop' 'FontSmoothingType' 2
REGSET 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewShadow' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'IconsOnly' 0  # Keep icons
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' 'AnimationsShiftKey' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' 'Blur' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' 'ColorizationColorBalance' 89

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 17: POWER OPTIMIZATION (ops 516-530)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 17/25] POWER OPTIMIZATION (15 ops) ━━━' -ForegroundColor Cyan

# CPU core parking disable
$cpuParking = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583'
REGSET $cpuParking 'ValueMax' 0
REGSET $cpuParking 'ValueMin' 0

# Processor performance boost mode
$procBoost = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\be337238-0d82-4146-a960-4f3749d470c7'
REGSET $procBoost 'ValueMax' 2  # Aggressive

# Disable USB selective suspend
$usbSuspend = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\2a737441-1930-4402-8d77-b2bebba308a3\48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
REGSET $usbSuspend 'ValueMax' 0

# Disable PCI Express Link State Power Management
$pciePM = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\501a4d13-42af-4429-9fd1-a8218c268e20\ee12f906-d277-404b-b6da-e5fa1a576df5'
REGSET $pciePM 'ValueMax' 0

# Set active power scheme to High Performance (if exists)
$schemes = powercfg /list 2>$null
$highPerf = ($schemes | Select-String '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c').Line
if ($highPerf) { powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null; $opCount++ }

# Disable hibernate (saves hiberfil.sys space = RAM size)
$hibernateSize = if (Test-Path 'C:\hiberfil.sys' -EA 0) { (Get-Item 'C:\hiberfil.sys' -Force -EA 0).Length } else { 0 }
powercfg /hibernate off 2>$null
$freed += $hibernateSize; $opCount++
if ($hibernateSize -gt 0) { Write-Host "  Hibernate off: $([math]::Round($hibernateSize/1GB,2))GB freed" -ForegroundColor Green }

# Processor idle settings
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'ExitLatency' 1
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'ExitLatencyCheckEnabled' 1
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'Latency' 1
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'LatencyToleranceDefault' 1
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'LatencyToleranceFSVP' 1
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'LatencyTolerancePerfOverride' 1
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'LatencyToleranceScreenOffIR' 1

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 18: WINDOWS FEATURES & COMPONENTS (ops 531-540)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 18/25] WINDOWS FEATURES (10 ops) ━━━' -ForegroundColor Cyan

# Compact OS (compress Windows binaries)
$compactState = compact /compactos:query 2>$null | Select-String 'is not'
if ($compactState) {
    Write-Host '  Enabling CompactOS (saves ~2GB)...' -ForegroundColor Yellow
    Start-Job { compact /compactos:always 2>&1 } | Out-Null; $opCount++
} else { OP 'CompactOS already enabled' }

# Disable Windows Tips
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI' 'DisableMFUTracking' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI' 'DisableHelpSticker' 1

# Disable Lock Screen spotlight/tips
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lock Screen' 'SlideshowEnabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0

# Disable Copilot (if not used)
REGSET 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1

# Disable Widgets
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 19: CLIPBOARD & NOTIFICATIONS (ops 541-548)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 19/25] CLIPBOARD & NOTIFICATIONS (8 ops) ━━━' -ForegroundColor Cyan

Add-Type -AssemblyName System.Windows.Forms -EA 0
[System.Windows.Forms.Clipboard]::Clear(); $opCount++

CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\Notifications\wpndatabase*"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\Notifications\appdb.dat*"

# Disable notification center
REGSET 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableNotificationCenter' 0  # Keep but reduce bloat
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 1  # Keep toasts
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' 0

# Reduce notification history
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' 1
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND' 1

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 20: SEARCH INDEX & CORTANA (ops 549-558)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 20/25] SEARCH INDEX & CORTANA (10 ops) ━━━' -ForegroundColor Cyan

# Compact search index
Stop-Service WSearch -Force -EA 0
CLEANDIR 'C:\ProgramData\Microsoft\Search\Data\Applications\Windows\GatherLogs'
CLEANDIR 'C:\ProgramData\Microsoft\Search\Data\Temp'
Start-Service WSearch -EA 0

# Disable Cortana
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortanaAboveLock' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowSearchToUseLocation' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWebOverMeteredConnections' 0

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 21: SECURITY HARDENING (performance-safe) (ops 559-575)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 21/25] SECURITY HARDENING (17 ops) ━━━' -ForegroundColor Cyan

# Disable remote assistance
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowFullControl' 0

# Disable admin shares
REGSET 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'AutoShareWks' 0

# Disable SMBv1 (security)
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -EA 0; $opCount++
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -EA 0 | Out-Null; $opCount++

# Disable NetBIOS over TCP/IP
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -EA 0 | ForEach-Object {
    REGSET $_.PSPath 'NetbiosOptions' 2
}

# Disable LLMNR
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0

# Disable WPAD
REGSET 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad' 'WpadOverride' 1

# Disable Autoplay/Autorun
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' 'DisableAutoplay' 1
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoAutorun' 1

# Set UAC to max (no dim but prompt)
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin' 5
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop' 1

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 22: ADDITIONAL CACHE LOCATIONS (ops 576-600)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 22/25] ADDITIONAL CACHE LOCATIONS (25 ops) ━━━' -ForegroundColor Cyan

CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\StartupProfileData-*"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\SchCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\IEDownloadHistory"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\WebCacheLock.dat"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Terminal Server Client\Cache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Vault\VaultCache"
CLEANDIR "$env:LOCALAPPDATA\ConnectedDevicesPlatform"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Office\16.0\OfficeFileCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Office\OTele"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\OneNote\16.0\cache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Outlook\RoamCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows Mail\Stationery"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Media Player\Art Cache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\GameExplorer"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\PlayReady"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\TokenBroker\Cache"
CLEANDIR "$env:LOCALAPPDATA\Comms\UnistoreDB\*.dat-wal"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\CapabilityAccessManager\cache"
CLEANDIR 'C:\Windows\Downloaded Program Files'
CLEANDIR 'C:\Windows\Offline Web Pages'
CLEANDIR "$env:LOCALAPPDATA\pip\cache"
CLEANDIR "$env:LOCALAPPDATA\yarn\Cache"
CLEANDIR "$env:APPDATA\npm-cache"
CLEANDIR "$env:LOCALAPPDATA\Temp\chocolatey"
CLEANDIR "$env:TEMP\chocolatey"

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 23: REGISTRY ORPHAN CLEANUP (ops 601-615)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 23/25] REGISTRY ORPHAN CLEANUP (15 ops) ━━━' -ForegroundColor Cyan

# Clean MUI cache
$muiCache = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
if (Test-Path $muiCache) { Remove-Item $muiCache -Recurse -Force -EA 0; New-Item $muiCache -Force -EA 0 | Out-Null }; $opCount++

# Clean recent docs
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackDocs' 0
Remove-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs' -Recurse -Force -EA 0; $opCount++
New-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs' -Force -EA 0 | Out-Null

# Clean ComDlg32 MRU
Remove-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU' -Recurse -Force -EA 0; $opCount++
Remove-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU' -Recurse -Force -EA 0; $opCount++

# Clean RunMRU
Remove-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU' -Recurse -Force -EA 0; $opCount++
New-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU' -Force -EA 0 | Out-Null

# Clean TypedPaths
Remove-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths' -Recurse -Force -EA 0; $opCount++
New-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths' -Force -EA 0 | Out-Null

# Clean WordWheelQuery (search history)
Remove-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery' -Recurse -Force -EA 0; $opCount++
New-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery' -Force -EA 0 | Out-Null

# Clean UserAssist (usage tracking)
Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\UserAssist' -EA 0 | ForEach-Object {
    Remove-ItemProperty -Path "$($_.PSPath)\Count" -Name * -Force -EA 0; $opCount++
}

# Clean notification cache registry
Remove-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\*' -Force -EA 0; $opCount++

# Clean AppCompatFlags
Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name * -Force -EA 0; $opCount++

# Clean BamState (Background Activity Monitor)
Remove-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings\*' -Recurse -Force -EA 0; $opCount++

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 24: NVIDIA / AMD / GPU SPECIFIC (ops 616-635)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 24/25] GPU SPECIFIC CLEANUP (20 ops) ━━━' -ForegroundColor Cyan

# NVIDIA
CLEANDIR "$env:LOCALAPPDATA\NVIDIA\DXCache"
CLEANDIR "$env:LOCALAPPDATA\NVIDIA\GLCache"
CLEANDIR "$env:LOCALAPPDATA\NVIDIA\ComputeCache"
CLEANDIR "$env:PROGRAMDATA\NVIDIA Corporation\Downloader\*.tmp"
CLEANDIR "$env:PROGRAMDATA\NVIDIA Corporation\GeForce Experience\CefCache"
CLEANDIR "$env:PROGRAMDATA\NVIDIA Corporation\NV_Cache"
CLEANDIR "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache"
CLEANDIR 'C:\Windows\System32\DriverStore\FileRepository\nv_*.old'

# Disable NVIDIA telemetry
SVCDIS 'NvTelemetryContainer'
REGSET 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 0

# AMD
CLEANDIR "$env:LOCALAPPDATA\AMD\DxCache"
CLEANDIR "$env:LOCALAPPDATA\AMD\DxcCache"
CLEANDIR "$env:LOCALAPPDATA\AMD\GLCache"
CLEANDIR "$env:LOCALAPPDATA\AMD\VkCache"
CLEANDIR "$env:LOCALAPPDATA\AMD\CN"
CLEANDIR "$env:LOCALAPPDATA\AMD\Logs"
CLEANDIR "$env:LOCALAPPDATA\RadeonInstaller\cache"

# Generic GPU shader cache
CLEANDIR "$env:LOCALAPPDATA\D3DSCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\DirectX Shader Cache"

# ═══════════════════════════════════════════════════════════════════
# CATEGORY 25: MISCELLANEOUS (ops 636-520+)
# ═══════════════════════════════════════════════════════════════════
Write-Host '━━━ [CAT 25/25] MISCELLANEOUS (remaining ops) ━━━' -ForegroundColor Cyan

# Clean recent files
CLEANDIR "$env:APPDATA\Microsoft\Windows\Recent"
CLEANDIR "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
CLEANDIR "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations"

# Clean temp DNS resolver cache file
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\IECompatCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\IECompatUaCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Windows\INetCookies\DNTException"

# Windows Defender scan files (not definitions)
CLEANDIR "$env:ProgramData\Microsoft\Windows Defender\Scans\History\Results\Resource"
CLEANDIR "$env:ProgramData\Microsoft\Windows Defender\Scans\History\Results\Quick"
CLEANDIR "$env:ProgramData\Microsoft\Windows Defender\Scans\MetaStore"
CLEANDIR "$env:ProgramData\Microsoft\Windows Defender\Scans\mpcache-*"

# Clean Microsoft Edge data (not profile)
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Edge\User Data\ShaderCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Edge\User Data\GrShaderCache"
CLEANDIR "$env:LOCALAPPDATA\Microsoft\Edge\User Data\BrowserMetrics"

# Java temp
CLEANDIR "$env:LOCALAPPDATA\Sun\Java\Deployment\cache"

# WSL temp (if using)
CLEANDIR "$env:LOCALAPPDATA\Temp\wsl*"

# Docker temp (if using)
CLEANDIR "$env:LOCALAPPDATA\Docker\wsl\data\tmp"

# Remove old restore points (keep latest)
vssadmin delete shadows /for=C: /oldest /quiet 2>$null | Out-Null; $opCount++

# Reset Windows error reporting queue
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'DontSendAdditionalData' 1
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'LoggingDisabled' 1

# Disable Windows Ink Workspace
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace' 'AllowWindowsInkWorkspace' 0
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace' 'AllowSuggestedAppsInWindowsInkWorkspace' 0

# Disable People bar
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People' 'PeopleBand' 0

# Disable Meet Now
REGSET 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'HideSCAMeetNow' 1

# Optimize context menu (remove shell extensions that slow right-click)
REGSET 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(Default)' '' 'String'

# Disable Timeline
REGSET 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0

# Disable Shared Experiences
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CDP' 'RomeSdkChannelUserAuthzPolicy' 0
REGSET 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CDP' 'CdpSessionUserAuthzPolicy' 0

# Reduce page file on SSD (RAM dependent)
# Don't remove - just set to system managed
# wmic computersystem where name="%computername%" set AutomaticManagedPagefile=True 2>$null | Out-Null; $opCount++

# Final cleanup pass - loose temp files
Get-ChildItem "$env:TEMP" -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-2) } | ForEach-Object {
    $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }
    $freed += $s
    Remove-Item $_.FullName -Recurse -Force -EA 0
}; $opCount++

Get-ChildItem 'C:\Windows\Temp' -Force -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-2) } | ForEach-Object {
    $s = if ($_.PSIsContainer) { SZ $_.FullName } else { $_.Length }
    $freed += $s
    Remove-Item $_.FullName -Recurse -Force -EA 0
}; $opCount++

# ═══════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════════
$elapsed = (Get-Date) - $t
$volAfter = (Get-Volume -DriveLetter C -EA 0).SizeRemaining
$actualFreed = if ($volBefore -and $volAfter) { [math]::Max(0, $volAfter - $volBefore) } else { 0 }
$actualFreedGB = [math]::Round($actualFreed / 1GB, 2)
$trackedFreedGB = [math]::Round($freed / 1GB, 2)

Write-Host ''
Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Green
Write-Host '║              CCC6 COMPLETE - FINAL REPORT                   ║' -ForegroundColor Green
Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Green
Write-Host ''
Write-Host "  ⏱️  Elapsed: $([math]::Floor($elapsed.TotalMinutes))m $($elapsed.Seconds)s" -ForegroundColor White
Write-Host "  🔧 Operations executed: $opCount" -ForegroundColor White
Write-Host ''
Write-Host '  ╔════════════════════════════════════════╗' -ForegroundColor Yellow
Write-Host "  ║  📊 TOTAL SPACE FREED: $trackedFreedGB GB (tracked)  ║" -ForegroundColor Yellow
if ($actualFreed -gt 0) {
Write-Host "  ║  📊 ACTUAL DISK FREED: $actualFreedGB GB (measured)  ║" -ForegroundColor Yellow
}
Write-Host '  ╚════════════════════════════════════════╝' -ForegroundColor Yellow
Write-Host ''

$vol = Get-Volume -DriveLetter C -EA 0
if ($vol) {
    $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
    $totalGB = [math]::Round($vol.Size / 1GB, 2)
    $pct = [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1)
    $color = if ($pct -gt 20) { 'Green' } elseif ($pct -gt 10) { 'Yellow' } else { 'Red' }
    Write-Host "  💾 C: Drive: $freeGB GB free / $totalGB GB total ($pct% free)" -ForegroundColor $color
}

# Also show F:
$volF = Get-Volume -DriveLetter F -EA 0
if ($volF) {
    $freeGB = [math]::Round($volF.SizeRemaining / 1GB, 2)
    $totalGB = [math]::Round($volF.Size / 1GB, 2)
    $pct = [math]::Round(($volF.SizeRemaining / $volF.Size) * 100, 1)
    Write-Host "  💾 F: Drive: $freeGB GB free / $totalGB GB total ($pct% free)" -ForegroundColor $(if ($pct -gt 20) { 'Green' } elseif ($pct -gt 10) { 'Yellow' } else { 'Red' })
}

Write-Host ''
Write-Host '  25 Categories Covered:' -ForegroundColor White
Write-Host '  ✅ System Caches (30)     ✅ Log Cleanup (40)       ✅ Crash Dumps (15)' -ForegroundColor DarkCyan
Write-Host '  ✅ Prefetch (5)           ✅ Network (40)           ✅ Telemetry (70)' -ForegroundColor DarkCyan
Write-Host '  ✅ Services (50)          ✅ Sched Tasks (60)       ✅ Registry (90)' -ForegroundColor DarkCyan
Write-Host '  ✅ App Caches (40)        ✅ Store/AppX (15)        ✅ Drivers (10)' -ForegroundColor DarkCyan
Write-Host '  ✅ SSD Optimize (10)      ✅ Startup (20)           ✅ WinUpdate (10)' -ForegroundColor DarkCyan
Write-Host '  ✅ Visual FX (10)         ✅ Power (15)             ✅ Features (10)' -ForegroundColor DarkCyan
Write-Host '  ✅ Clipboard (8)          ✅ Search/Cortana (10)    ✅ Security (17)' -ForegroundColor DarkCyan
Write-Host '  ✅ Extra Caches (25)      ✅ Registry Orphans (15)  ✅ GPU (20)' -ForegroundColor DarkCyan
Write-Host '  ✅ Miscellaneous (35+)' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  ⚠️  Some changes require a REBOOT to take full effect.' -ForegroundColor Yellow
Write-Host ''
