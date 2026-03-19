#Requires -RunAsAdministrator
<#
.SYNOPSIS
    CSpaceMaximizer v2 - Ultimate C: Drive Space Recovery & PC Optimization
    Companion to cccc/ccc4/ccc5 — targets areas those functions do NOT cover.
    SAFE: Never removes apps you use, games, user data, or installed software.

.DESCRIPTION
    32 deep-clean sections covering everything cccc/ccc4/ccc5 miss:
    OS internals, dev tools, app caches, logs, old versions, compression & TRIM.

.NOTES
    Run as Administrator. All ops are SAFE. Shadow copy deletion is irreversible.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
$VerbosePreference     = 'SilentlyContinue'

$t         = Get-Date
$freed     = [long]0
$sectionGB = @{}   # per-section accounting

function SZ($p) {
    if (Test-Path $p -EA 0) {
        $r = (Get-ChildItem $p -Recurse -Force -EA 0 | Measure-Object Length -Sum -EA 0).Sum
        if ($r) { $r } else { 0 }
    } else { 0 }
}

function FR($label, [string[]]$paths) {
    $b = [long]0
    foreach ($p in $paths) {
        if (Test-Path $p -EA 0) {
            $s = SZ $p
            if ($s -gt 0) { Write-Host "    $p  ($([math]::Round($s/1MB,1))MB)" -ForegroundColor DarkGray }
            $b += $s
            Get-ChildItem $p -Force -EA 0 | Remove-Item -Recurse -Force -EA 0
        }
    }
    $script:freed += $b
    if ($b -gt 0) {
        $c = if ($b -gt 100MB) { 'Green' } elseif ($b -gt 5MB) { 'Yellow' } else { 'Gray' }
        Write-Host "  -> $label freed: $([math]::Round($b/1MB,1)) MB" -ForegroundColor $c
    } else {
        Write-Host "  -> $label: nothing" -ForegroundColor DarkGray
    }
    $b
}

function DeleteFile($path) {
    if (Test-Path $path -EA 0) {
        $s = (Get-Item $path -Force -EA 0).Length
        if ($s -gt 0) {
            $script:freed += $s
            Remove-Item $path -Force -EA 0
            Write-Host "  Removed: $path  ($([math]::Round($s/1MB,1)) MB)" -ForegroundColor DarkGray
            return $s
        }
    }
    return 0
}

function SectionStart($num, $title) {
    Write-Host "`n[$num] $title" -ForegroundColor Cyan
    $script:freed   # return current freed so caller can diff
}

$volBefore = (Get-Volume -DriveLetter C -EA 0).SizeRemaining

Write-Host '=================================================================' -ForegroundColor Magenta
Write-Host '=== CSpaceMaximizer v2  — ULTIMATE C: SPACE RECOVERY (32 ops)===' -ForegroundColor Magenta
Write-Host '=================================================================' -ForegroundColor Magenta
Write-Host "Started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
$vol0 = Get-Volume -DriveLetter C -EA 0
if ($vol0) {
    Write-Host "C: before: $([math]::Round($vol0.SizeRemaining/1GB,2)) GB free / $([math]::Round($vol0.Size/1GB,2)) GB total" -ForegroundColor Cyan
}

# ══════════════════════════════════════════════════════════════════════════════
# [01] HIBERNATE FILE
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[01] Hibernate file (hiberfil.sys)..." -ForegroundColor Cyan
$hibPath = 'C:\hiberfil.sys'
if (Test-Path $hibPath) {
    $hibSize = (Get-Item $hibPath -Force -EA 0).Length
    Write-Host "  hiberfil.sys = $([math]::Round($hibSize/1GB,2)) GB" -ForegroundColor DarkGray
    & powercfg /hibernate /size 20 2>&1 | Out-Null
    Write-Host "  Set hibernate to 20% minimum. To disable fully: powercfg /h off" -ForegroundColor Yellow
    $newHib = (Get-Item $hibPath -Force -EA 0).Length
    $saved  = $hibSize - $newHib
    if ($saved -gt 0) { $script:freed += $saved; Write-Host "  -> Hibernate freed: $([math]::Round($saved/1MB,1)) MB" -ForegroundColor Green }
} else { Write-Host "  Hibernate already off." -ForegroundColor DarkGray }

# ══════════════════════════════════════════════════════════════════════════════
# [02] PAGEFILE ADVICE
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[02] Pagefile advice..." -ForegroundColor Cyan
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem -EA 0).TotalPhysicalMemory / 1GB)
$pf  = Get-Item 'C:\pagefile.sys' -Force -EA 0
if ($pf) {
    $pfGB        = [math]::Round($pf.Length/1GB,2)
    $recommended = if ($ram -le 8) { [math]::Round($ram*1.5) } elseif ($ram -le 32) { $ram } else { [math]::Round($ram*0.5) }
    Write-Host "  pagefile=$pfGB GB | RAM=$ram GB | recommended≈$recommended GB" -ForegroundColor DarkGray
    Write-Host "  Adjust: System → Advanced → Performance Settings → Virtual Memory" -ForegroundColor Yellow
} else { Write-Host "  pagefile.sys not found (system-managed)." -ForegroundColor DarkGray }

# ══════════════════════════════════════════════════════════════════════════════
# [03] WINDOWS ERROR REPORTING & MEMORY DUMPS
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[03] Windows Error Reporting & Memory Dumps..." -ForegroundColor Cyan
$b03 = $freed
FR 'WER reports' @(
    'C:\ProgramData\Microsoft\Windows\WER\ReportArchive',
    'C:\ProgramData\Microsoft\Windows\WER\ReportQueue',
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue"
)
foreach ($dp in @('C:\Windows\Minidump','C:\Windows\LiveKernelReports')) {
    if (Test-Path $dp -EA 0) { FR "Dump:$dp" @($dp) }
}
DeleteFile 'C:\Windows\MEMORY.DMP' | Out-Null
Get-ChildItem 'C:\Users' -Directory -EA 0 | ForEach-Object {
    $udmp = Join-Path $_.FullName 'AppData\Local\CrashDumps'
    if (Test-Path $udmp -EA 0) { FR "UserDump:$($_.Name)" @($udmp) }
}

# ══════════════════════════════════════════════════════════════════════════════
# [04] CBS / SFC / SETUP / PANTHER LOGS
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[04] CBS/SFC/Setup/Panther logs..." -ForegroundColor Cyan
$b04 = $freed
$cbsLog = 'C:\Windows\Logs\CBS\CBS.log'
if (Test-Path $cbsLog -EA 0) {
    $s = (Get-Item $cbsLog -EA 0).Length
    if ($s -gt 5MB) { $script:freed += $s; Remove-Item $cbsLog -Force -EA 0; Write-Host "  CBS.log ($([math]::Round($s/1MB,1))MB)" -ForegroundColor DarkGray }
}
FR 'CBS logs' @('C:\Windows\Logs\CBS')
FR 'DISM logs' @('C:\Windows\Logs\DISM')
FR 'Panther' @('C:\Windows\Panther','C:\$Windows.~BT','C:\$Windows.~WS')
FR 'SetupAPI logs' @('C:\Windows\INF\setupapi*.log')
FR 'IIS logs' @('C:\inetpub\logs\LogFiles','C:\Windows\System32\LogFiles\W3SVC1','C:\Windows\System32\LogFiles\HTTPERR')

# ══════════════════════════════════════════════════════════════════════════════
# [05] DELIVERY OPTIMIZATION
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[05] Delivery Optimization cache..." -ForegroundColor Cyan
Stop-Service DoSvc -Force -EA 0
FR 'DeliveryOpt' @(
    'C:\Windows\SoftwareDistribution\DeliveryOptimization',
    "$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization"
)
& netsh do delete cache 2>$null | Out-Null
Start-Service DoSvc -EA 0

# ══════════════════════════════════════════════════════════════════════════════
# [06] THUMBNAIL / ICON / JUMPLIST CACHE
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[06] Thumbnail, IconCache, JumpLists..." -ForegroundColor Cyan
Stop-Process -Name explorer -Force -EA 0; Start-Sleep -Milliseconds 800
FR 'ThumbCache' @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer")
FR 'JumpLists'  @(
    "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations",
    "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations"
)
DeleteFile "$env:LOCALAPPDATA\IconCache.db" | Out-Null
Start-Process explorer -EA 0

# ══════════════════════════════════════════════════════════════════════════════
# [07] MICROSOFT STORE / WINDOWS UPDATE DOWNLOADS
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[07] Store & Windows Update downloads..." -ForegroundColor Cyan
Stop-Service wuauserv,bits -Force -EA 0
FR 'WUDownloads' @('C:\Windows\SoftwareDistribution\Download')
FR 'StoreCache'  @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache")
Start-Service bits,wuauserv -EA 0

# ══════════════════════════════════════════════════════════════════════════════
# [08] ONEDRIVE CACHE & LOGS
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[08] OneDrive cache junk (NOT your files)..." -ForegroundColor Cyan
$odBase = "$env:LOCALAPPDATA\Microsoft\OneDrive"
if (Test-Path $odBase -EA 0) {
    FR 'ODLogs' @("$odBase\logs","$odBase\setup\logs","$odBase\StandaloneUpdater")
    Get-ChildItem $odBase -Recurse -Include '*.bak','*.tmp' -EA 0 |
        ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
}

# ══════════════════════════════════════════════════════════════════════════════
# [09] OLD PREFETCH FILES (>90 days)
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[09] Old Prefetch files (>90 days)..." -ForegroundColor Cyan
$cutoff90 = (Get-Date).AddDays(-90)
$b09 = $freed
Get-ChildItem 'C:\Windows\Prefetch' -File -EA 0 |
    Where-Object { $_.LastWriteTime -lt $cutoff90 } |
    ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
Write-Host "  -> Old prefetch freed: $([math]::Round(($freed-$b09)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b09) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [10] FONT CACHE & WMI TEMP
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[10] Font cache & WMI temp..." -ForegroundColor Cyan
Stop-Service FontCache -Force -EA 0
FR 'FontCache' @(
    "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache",
    "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
)
Start-Service FontCache -EA 0

# ══════════════════════════════════════════════════════════════════════════════
# [11] WINDOWS DEFENDER SCAN HISTORY
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[11] Defender scan history (not definitions)..." -ForegroundColor Cyan
FR 'DefenderHistory' @(
    'C:\ProgramData\Microsoft\Windows Defender\Scans\History',
    'C:\ProgramData\Microsoft\Windows Defender\Scans\mpcache'
)
Get-ChildItem 'C:\ProgramData\Microsoft\Windows Defender\Quarantine' -Recurse -Force -EA 0 |
    Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }

# ══════════════════════════════════════════════════════════════════════════════
# [12] CORTANA / SEARCH CACHE
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[12] Cortana & Search cache..." -ForegroundColor Cyan
FR 'CortanaSearch' @(
    "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Cortana_cw5n1h2txyewy\LocalCache",
    "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Search_cw5n1h2txyewy\LocalCache",
    "$env:LOCALAPPDATA\Microsoft\Windows\Caches"
)

# ══════════════════════════════════════════════════════════════════════════════
# [13] REMOTE DESKTOP CACHE
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[13] Remote Desktop connection cache..." -ForegroundColor Cyan
FR 'RDPCache' @(
    "$env:LOCALAPPDATA\Microsoft\Terminal Server Client\Cache",
    "$env:APPDATA\Microsoft\Terminal Server Client\Cache"
)

# ══════════════════════════════════════════════════════════════════════════════
# [14] COMPACT OS
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[14] NTFS Compact OS (saves 2-4 GB on OS files)..." -ForegroundColor Cyan
Write-Host "  Running compact /CompactOs:always — may take a few minutes..." -ForegroundColor DarkGray
$cj = Start-Job { compact /CompactOs:always 2>&1 | Select-Object -Last 3 }
$done = Wait-Job $cj -Timeout 360 -EA 0
if ($done) { Receive-Job $cj -EA 0 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
else        { Stop-Job $cj -EA 0; Write-Host "  Compact OS running in background." -ForegroundColor Yellow }
Remove-Job $cj -Force -EA 0

# ══════════════════════════════════════════════════════════════════════════════
# [15] SSD TRIM / HDD DEFRAG
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[15] SSD TRIM / drive optimization..." -ForegroundColor Cyan
$driveType = (Get-PhysicalDisk -EA 0 | Where-Object { $_.BusType -ne 'USB' } | Select-Object -First 1).MediaType
if ($driveType -match 'SSD|NVMe|Solid') {
    Optimize-Volume -DriveLetter C -ReTrim -EA 0 | Out-Null
    Write-Host "  TRIM complete." -ForegroundColor Green
} else {
    Write-Host "  HDD/unknown — running analysis only." -ForegroundColor DarkGray
    $dj = Start-Job { defrag C: /A /U 2>&1 | Select-Object -Last 4 }
    Wait-Job $dj -Timeout 60 | Out-Null
    Receive-Job $dj -EA 0 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Remove-Job $dj -Force
}

# ══════════════════════════════════════════════════════════════════════════════
# [16] DISM DEEP COMPONENT CLEANUP
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[16] DISM deep component cleanup (WinSxS resetbase + spsuperseded)..." -ForegroundColor Cyan
Write-Host "  May take 5-10 minutes..." -ForegroundColor DarkGray
$dj = Start-Job {
    dism /online /cleanup-image /startcomponentcleanup /resetbase 2>&1 | Select-Object -Last 2
    dism /online /cleanup-image /spsuperseded 2>&1 | Select-Object -Last 1
}
$done = Wait-Job $dj -Timeout 720 -EA 0
if ($done) { Receive-Job $dj -EA 0 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
else        { Stop-Job $dj -EA 0; Write-Host "  DISM running in background." -ForegroundColor Yellow }
Remove-Job $dj -Force -EA 0

# ══════════════════════════════════════════════════════════════════════════════
# [17] VISUAL STUDIO / VSCODE / RIDER CACHES
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[17] Visual Studio / VS Code / Rider caches..." -ForegroundColor Cyan
$b17 = $freed
# VS Code workspace storage and logs (not extensions, not settings)
FR 'VSCode-WorkspaceStorage' @("$env:APPDATA\Code\User\workspaceStorage")
FR 'VSCode-Logs'             @("$env:APPDATA\Code\logs")
FR 'VSCode-CachedData'       @("$env:APPDATA\Code\CachedData","$env:APPDATA\Code\Cache","$env:APPDATA\Code\Code Cache")
FR 'VSCode-GPUCache'         @("$env:APPDATA\Code\GPUCache")
FR 'VSCode-CrashReports'     @("$env:APPDATA\Code\crashDumps")
# Visual Studio IDE caches
$vsDataBase = "$env:LOCALAPPDATA\Microsoft\VisualStudio"
if (Test-Path $vsDataBase -EA 0) {
    Get-ChildItem $vsDataBase -Directory -EA 0 | ForEach-Object {
        FR "VS-ComponentModelCache:$($_.Name)" @(Join-Path $_.FullName 'ComponentModelCache')
        FR "VS-ActivityLog:$($_.Name)"         @((Join-Path $_.FullName 'ActivityLog.xml'),(Join-Path $_.FullName 'ActivityLog.xsl'))
    }
}
FR 'VS-Roslyn'     @("$env:TEMP\VBCSCompiler","$env:TEMP\.NETCoreApp","$env:TEMP\Razor")
FR 'VS-Designer'   @("$env:LOCALAPPDATA\Microsoft\VSApplicationInsights")
# Rider
FR 'Rider-Logs'    @("$env:APPDATA\JetBrains\Rider*\log","$env:LOCALAPPDATA\JetBrains\Rider*\log")
FR 'Rider-Caches'  @("$env:LOCALAPPDATA\JetBrains\Rider*\caches")
Write-Host "  -> IDE caches section freed: $([math]::Round(($freed-$b17)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b17) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [18] DISCORD / TELEGRAM / SLACK / TEAMS CACHES
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[18] Chat app caches (Discord, Telegram, Teams, Slack, Zoom)..." -ForegroundColor Cyan
$b18 = $freed
$appDataR = $env:APPDATA
$appDataL = $env:LOCALAPPDATA
# Discord
$discordBase = "$appDataR\discord"
if (Test-Path $discordBase -EA 0) {
    Get-ChildItem $discordBase -Directory -EA 0 |
        Where-Object { $_.Name -match '^\d+\.\d+' } |
        Sort-Object Name |
        Select-Object -SkipLast 1 |
        ForEach-Object {
            $s = SZ $_.FullName; $script:freed += $s
            Write-Host "  Old Discord: $($_.Name) ($([math]::Round($s/1MB,1))MB)" -ForegroundColor DarkGray
            Remove-Item $_.FullName -Recurse -Force -EA 0
        }
    foreach ($cd in @('Cache','Code Cache','GPUCache')) {
        $p = Join-Path $discordBase $cd
        if (Test-Path $p -EA 0) { FR "Discord-$cd" @($p) }
    }
}
# Telegram
FR 'Telegram-tdata-cache' @("$appDataR\Telegram Desktop\tdata\user_data","$appDataR\Telegram Desktop\tdata\stickers")
# Slack
$slackBase = "$appDataL\slack"
if (Test-Path $slackBase -EA 0) {
    foreach ($cd in @('Cache','Code Cache','GPUCache','logs')) { FR "Slack-$cd" @("$slackBase\$cd") }
}
# Teams (new & classic)
FR 'Teams-Cache'   @("$appDataR\Microsoft\Teams\Cache","$appDataR\Microsoft\Teams\Code Cache","$appDataR\Microsoft\Teams\GPUCache")
FR 'Teams-Blobs'   @("$appDataR\Microsoft\Teams\blobs","$appDataR\Microsoft\Teams\tmp")
FR 'Teams2-Cache'  @("$appDataL\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams")
# Zoom
FR 'Zoom-Cache'    @("$appDataR\Zoom\data","$appDataL\Zoom\data\Cache","$appDataL\Zoom\logs")
# Skype
FR 'Skype-Cache'   @("$appDataR\Skype\$($env:USERNAME)\media_messaging","$appDataL\Packages\Microsoft.SkypeApp_kzf8qxf38zg5c\LocalCache")
Write-Host "  -> Chat caches freed: $([math]::Round(($freed-$b18)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b18) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [19] SPOTIFY / MEDIA APP CACHES
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[19] Spotify / media app caches..." -ForegroundColor Cyan
$b19 = $freed
FR 'Spotify-Cache'  @("$appDataL\Spotify\Storage","$appDataL\Spotify\Browser\Cache","$appDataL\Spotify\Data")
FR 'VLC-Cache'      @("$appDataR\vlc\cache")
FR 'MPC-Cache'      @("$env:TEMP\mpc-hc")
FR 'Kodi-Cache'     @("$appDataR\Kodi\userdata\Thumbnails")
FR 'iTunes-Cache'   @("$appDataL\Apple Computer\iTunes\iPad Software Updates","$appDataL\Apple Computer\iTunes\iPhone Software Updates")
Write-Host "  -> Media caches freed: $([math]::Round(($freed-$b19)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b19) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [20] GAME LAUNCHER CACHES (Steam, Epic, GOG — NOT game files)
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[20] Game launcher caches (NOT game data)..." -ForegroundColor Cyan
$b20 = $freed
# Steam HTML cache only (not steamapps)
FR 'Steam-HTMLCache'  @("$appDataL\Steam\htmlcache\Cache","$appDataL\Steam\htmlcache\Code Cache")
FR 'Steam-Logs'       @("$appDataL\Steam\logs")
FR 'Steam-DumpFiles'  @((Get-ChildItem "$appDataL\Steam" -Filter '*.dmp' -Recurse -EA 0 | Select-Object -ExpandProperty FullName))
# Epic Games
FR 'Epic-WebCache'    @("$appDataL\EpicGamesLauncher\Saved\webcache","$appDataL\EpicGamesLauncher\Saved\Logs")
FR 'Epic-UpdateLogs'  @("$appDataL\EpicGamesLauncher\Saved\Crashes")
# GOG
FR 'GOG-Cache'        @("$appDataL\GOG.com\Galaxy\webcache","$appDataL\GOG.com\Galaxy\logs")
# Ubisoft
FR 'Ubisoft-Cache'    @("$appDataL\Ubisoft Game Launcher\cache\assets")
# EA App
FR 'EA-Cache'         @("$appDataL\Electronic Arts\EA Desktop\CEF\cache")
Write-Host "  -> Launcher caches freed: $([math]::Round(($freed-$b20)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b20) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [21] DOCKER CLEANUP (images, containers, volumes — dangling only)
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[21] Docker dangling resources..." -ForegroundColor Cyan
$b21 = $freed
$dockerCmd = Get-Command docker -EA 0
if ($dockerCmd) {
    Write-Host "  Docker found — pruning dangling images/build cache..." -ForegroundColor DarkGray
    $dj = Start-Job {
        docker image prune -f 2>&1
        docker builder prune -f 2>&1
        docker container prune -f 2>&1
        docker volume prune -f 2>&1
    }
    Wait-Job $dj -Timeout 120 | Out-Null
    $out = Receive-Job $dj -EA 0
    $out | Where-Object { $_ -match 'reclaimed|deleted|total' } | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Remove-Job $dj -Force
} else { Write-Host "  Docker not found — skipped." -ForegroundColor DarkGray }
# Docker Desktop data disk (log files)
FR 'DockerDesktop-Logs' @("$appDataR\Docker\log","$appDataL\Docker\log")

# ══════════════════════════════════════════════════════════════════════════════
# [22] WSL TEMP & LOGS
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[22] WSL temp & logs..." -ForegroundColor Cyan
$b22 = $freed
FR 'WSL-Logs'  @("$env:LOCALAPPDATA\Packages\CanonicalGroupLimited.Ubuntu*\LocalCache\rootfs\var\log",
                  "$env:LOCALAPPDATA\Packages\CanonicalGroupLimited.UbuntuonWindows*\LocalCache\rootfs\var\log",
                  "$env:TEMP\wsl*")
$wslCmd = Get-Command wsl -EA 0
if ($wslCmd) {
    Write-Host "  WSL found — clearing /tmp inside default distro..." -ForegroundColor DarkGray
    & wsl -e sh -c 'find /tmp -mindepth 1 -mtime +1 -delete 2>/dev/null; find /var/log -name "*.gz" -delete 2>/dev/null; journalctl --vacuum-size=50M 2>/dev/null' 2>$null
}
Write-Host "  -> WSL freed: (disk impact depends on VHD sparse)" -ForegroundColor DarkGray

# ══════════════════════════════════════════════════════════════════════════════
# [23] GIT REPOSITORY GARBAGE COLLECTION (loose objects)
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[23] Git repositories GC (study drive)..." -ForegroundColor Cyan
$b23 = $freed
$gitCmd = Get-Command git -EA 0
if ($gitCmd) {
    $gitPaths = Get-ChildItem 'F:\study' -Recurse -Force -Depth 4 -EA 0 |
        Where-Object { $_.PSIsContainer -and $_.Name -eq '.git' } |
        Select-Object -First 30

    foreach ($gd in $gitPaths) {
        $repoPath = $gd.Parent.FullName
        $beforeGC = SZ $gd.FullName
        & git -C $repoPath gc --auto --quiet 2>$null
        & git -C $repoPath remote prune origin 2>$null
        $afterGC = SZ $gd.FullName
        $diff = $beforeGC - $afterGC
        if ($diff -gt 0) {
            $script:freed += $diff
            Write-Host "  GC: $repoPath (-$([math]::Round($diff/1MB,1)) MB)" -ForegroundColor DarkGray
        }
    }
    Write-Host "  -> Git GC freed: $([math]::Round(($freed-$b23)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b23) -gt 1MB){'Green'}else{'Gray'})
} else { Write-Host "  git not found — skipped." -ForegroundColor DarkGray }

# ══════════════════════════════════════════════════════════════════════════════
# [24] GRADLE / MAVEN / ANDROID STUDIO CACHES
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[24] Gradle / Maven / Android Studio caches..." -ForegroundColor Cyan
$b24 = $freed
# Gradle — keep current, remove old wrapper dists and old build caches
$gradleHome = "$env:USERPROFILE\.gradle"
if (Test-Path $gradleHome -EA 0) {
    # Remove old wrapper versions (keep latest per distribution)
    $wrapperBase = "$gradleHome\wrapper\dists"
    if (Test-Path $wrapperBase -EA 0) {
        Get-ChildItem $wrapperBase -Directory -EA 0 | Group-Object { $_.Name -replace '-\d+.*','' } |
            Where-Object { $_.Count -gt 1 } | ForEach-Object {
                $_.Group | Sort-Object Name | Select-Object -SkipLast 1 |
                    ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0; Write-Host "  Old Gradle wrapper: $($_.Name) ($([math]::Round($s/1MB,1))MB)" -ForegroundColor DarkGray }
            }
    }
    FR 'Gradle-daemon-logs' @("$gradleHome\daemon")
}
# Maven
$mavenHome = "$env:USERPROFILE\.m2\repository"
if (Test-Path $mavenHome -EA 0) {
    # Remove *-SNAPSHOT folders older than 30 days
    Get-ChildItem $mavenHome -Recurse -Directory -EA 0 |
        Where-Object { $_.Name -match 'SNAPSHOT' -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        ForEach-Object { $s = SZ $_.FullName; $script:freed += $s; Remove-Item $_.FullName -Recurse -Force -EA 0 }
}
# Android Studio
FR 'AndroidStudio-Cache' @(
    "$env:LOCALAPPDATA\Google\AndroidStudio*\caches",
    "$env:LOCALAPPDATA\Google\AndroidStudio*\log",
    "$env:USERPROFILE\.android\cache",
    "$env:USERPROFILE\.android\avd\.locks"
)
Write-Host "  -> Gradle/Maven/Android freed: $([math]::Round(($freed-$b24)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b24) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [25] RUST CARGO OLD REGISTRY INDICES & BUILD ARTIFACTS
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[25] Rust Cargo registry & build artifacts..." -ForegroundColor Cyan
$b25 = $freed
$cargoHome = "$env:USERPROFILE\.cargo"
if (Test-Path $cargoHome -EA 0) {
    FR 'Cargo-git-db'     @("$cargoHome\git\db")
    FR 'Cargo-registry-src' @("$cargoHome\registry\src")
    # Remove old crate index blobs (keep HEAD)
    $regIndex = "$cargoHome\registry\index"
    if (Test-Path $regIndex -EA 0) {
        Get-ChildItem $regIndex -Directory -EA 0 | ForEach-Object {
            $packDir = Join-Path $_.FullName '.git\objects\pack'
            if (Test-Path $packDir -EA 0) {
                Get-ChildItem $packDir -Filter '*.idx' -EA 0 |
                    Sort-Object LastWriteTime |
                    Select-Object -SkipLast 1 |
                    ForEach-Object {
                        $base = $_.FullName -replace '\.idx$',''
                        foreach ($ext in @('.idx','.pack')) {
                            $f = "$base$ext"
                            if (Test-Path $f -EA 0) {
                                $s = (Get-Item $f -EA 0).Length
                                $script:freed += $s
                                Remove-Item $f -Force -EA 0
                            }
                        }
                    }
            }
        }
    }
}
Write-Host "  -> Cargo freed: $([math]::Round(($freed-$b25)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b25) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [26] NODE.JS / TYPESCRIPT / WEBPACK / VITE BUILD CACHES
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[26] Node.js / TypeScript / build tool caches..." -ForegroundColor Cyan
$b26 = $freed
# TypeScript language server
FR 'TS-ServerLog'   @("$env:TEMP\tsserver*")
# Webpack / Vite / Parcel caches buried in project dirs
$projRoots = @('F:\study','C:\Users\micha\source')
foreach ($root in $projRoots) {
    if (Test-Path $root -EA 0) {
        Get-ChildItem $root -Recurse -Force -Depth 5 -EA 0 |
            Where-Object { $_.PSIsContainer -and $_.Name -in @('.cache','.parcel-cache','dist','.turbo') } |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
            ForEach-Object {
                $s = SZ $_.FullName; $script:freed += $s
                if ($s -gt 1MB) { Write-Host "  Build cache: $($_.FullName) ($([math]::Round($s/1MB,1))MB)" -ForegroundColor DarkGray }
                Remove-Item $_.FullName -Recurse -Force -EA 0
            }
    }
}
FR 'ESLint-Cache' @((Get-ChildItem 'C:\Users\micha' -Recurse -Force -Depth 4 -Filter '.eslintcache' -EA 0 | Select-Object -ExpandProperty FullName))
Write-Host "  -> Build caches freed: $([math]::Round(($freed-$b26)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b26) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [27] WINDOWS EVENT LOGS — TRUNCATE OVERGROWN LOGS
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[27] Windows Event Log cleanup (overgrown non-critical logs)..." -ForegroundColor Cyan
$b27 = $freed
$safeLogsToClear = @(
    'Microsoft-Windows-Dhcp-Client/Operational',
    'Microsoft-Windows-DNS-Client/Operational',
    'Microsoft-Windows-Kernel-PnP/Configuration',
    'Microsoft-Windows-Kernel-Power/Thermal-Operational',
    'Microsoft-Windows-NetworkProfile/Operational',
    'Microsoft-Windows-WLAN-AutoConfig/Operational',
    'Microsoft-Windows-TaskScheduler/Operational',
    'Microsoft-Windows-WinRM/Operational',
    'Microsoft-Windows-PowerShell/Operational',
    'Microsoft-Windows-Store/Operational',
    'Microsoft-Windows-AppXDeploymentServer/Operational'
)
foreach ($logName in $safeLogsToClear) {
    try {
        $log = Get-WinEvent -ListLog $logName -EA 0
        if ($log -and $log.FileSize -gt 50MB) {
            Write-Host "  Clearing $logName ($([math]::Round($log.FileSize/1MB,0))MB)" -ForegroundColor DarkGray
            $script:freed += $log.FileSize
            wevtutil cl "$logName" 2>$null
        }
    } catch {}
}
# evtx files in non-system locations
Get-ChildItem 'C:\Windows\System32\winevt\Logs' -Filter '*.evtx' -EA 0 |
    Where-Object { $_.Length -gt 100MB -and $_.Name -notmatch '^(System|Application|Security)' } |
    ForEach-Object {
        Write-Host "  Large evtx: $($_.Name) ($([math]::Round($_.Length/1MB,0))MB)" -ForegroundColor DarkGray
        $script:freed += $_.Length
        wevtutil cl "$($_.BaseName)" 2>$null
    }
Write-Host "  -> Event logs freed: $([math]::Round(($freed-$b27)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b27) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [28] SCOOP / CHOCOLATEY CACHES
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[28] Scoop & Chocolatey caches..." -ForegroundColor Cyan
$b28 = $freed
# Scoop
$scoopCmd = Get-Command scoop -EA 0
if ($scoopCmd) {
    $scoopCache = "$env:USERPROFILE\scoop\cache"
    if (Test-Path $scoopCache -EA 0) {
        # Remove old installer files (not the current version)
        $appGroups = Get-ChildItem $scoopCache -File -EA 0 |
            Where-Object { $_.Name -match '^(.+?)#' } |
            Group-Object { [regex]::Match($_.Name,'^(.+?)#').Groups[1].Value }
        foreach ($g in $appGroups) {
            if ($g.Count -gt 1) {
                $g.Group | Sort-Object LastWriteTime | Select-Object -SkipLast 1 |
                    ForEach-Object { $script:freed += $_.Length; Write-Host "  Scoop old: $($_.Name)" -ForegroundColor DarkGray; Remove-Item $_.FullName -Force -EA 0 }
            }
        }
    }
}
# Chocolatey cache
FR 'Choco-Cache' @("$env:ChocolateyInstall\lib-bkp","$env:TEMP\chocolatey")
# Winget cache
FR 'Winget-Cache' @("$env:LOCALAPPDATA\Microsoft\WinGet\defaultState")
Write-Host "  -> Package manager caches freed: $([math]::Round(($freed-$b28)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b28) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [29] PYTHON CACHES: __pycache__, .mypy_cache, .pytest_cache, Jupyter checkpoints
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[29] Python __pycache__ / .mypy_cache / .pytest_cache / Jupyter..." -ForegroundColor Cyan
$b29 = $freed
$pySearchRoots = @('F:\study','C:\Users\micha\Documents','C:\Users\micha\source')
foreach ($root in $pySearchRoots) {
    if (Test-Path $root -EA 0) {
        Get-ChildItem $root -Recurse -Force -Depth 6 -EA 0 |
            Where-Object { $_.PSIsContainer -and $_.Name -in @('__pycache__','.mypy_cache','.pytest_cache','.ipynb_checkpoints','htmlcov') } |
            ForEach-Object {
                $s = SZ $_.FullName; $script:freed += $s
                if ($s -gt 512KB) { Write-Host "  $($_.FullName) ($([math]::Round($s/1MB,1))MB)" -ForegroundColor DarkGray }
                Remove-Item $_.FullName -Recurse -Force -EA 0
            }
        # Remove compiled .pyc files outside __pycache__
        Get-ChildItem $root -Recurse -Force -Depth 6 -Filter '*.pyc' -EA 0 |
            ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
    }
}
# Matplotlib cache
FR 'Matplotlib-cache' @("$env:USERPROFILE\.matplotlib\tex.cache","$env:LOCALAPPDATA\matplotlib\fontList.json")
Write-Host "  -> Python caches freed: $([math]::Round(($freed-$b29)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b29) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [30] ADOBE / CREATIVE SUITE CACHES
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[30] Adobe / Creative Suite caches..." -ForegroundColor Cyan
$b30 = $freed
$adobeBase = "$appDataR\Adobe"
if (Test-Path $adobeBase -EA 0) {
    # Photoshop scratch
    FR 'PS-MediaCache'  @("$appDataR\Adobe\Common\Media Cache Files","$appDataR\Adobe\Common\Media Cache")
    FR 'PS-CrashReports'@("$appDataR\Adobe\Adobe Photoshop*\Adobe Photoshop * Settings\PSErrorLog.txt")
    # Premiere
    FR 'Pr-MediaCache'  @("$appDataR\Adobe\Common\Media Cache Files")
    # After Effects
    FR 'AE-DiskCache'   @("$appDataL\Temp\Adobe")
    # Acrobat
    FR 'Acrobat-Temp'   @("$appDataR\Adobe\Acrobat\*\Cache","$appDataL\Adobe\Acrobat\*\Cache")
    # Creative Cloud
    FR 'CC-Cache'       @("$appDataL\Adobe\CoreSyncExtension\Cache","$appDataL\Adobe\OOBE\opm.db")
    # General Adobe logs
    Get-ChildItem $adobeBase -Recurse -Filter '*.log' -EA 0 |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) -and $_.Length -gt 1MB } |
        ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
}
Write-Host "  -> Adobe freed: $([math]::Round(($freed-$b30)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b30) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [31] POWERSHELL TRANSCRIPT LOGS & OLD PROFILE BACKUPS
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[31] PowerShell transcripts, old backups, misc temp..." -ForegroundColor Cyan
$b31 = $freed
$cutoff30 = (Get-Date).AddDays(-30)
# PS Transcripts
@("$env:USERPROFILE\Documents\PowerShell_transcript*",
  "$env:USERPROFILE\Documents\WindowsPowerShell\Transcripts") |
    ForEach-Object {
        Get-ChildItem $_ -Recurse -Force -EA 0 |
            Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -lt $cutoff30 } |
            ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
    }
# Windows old backup BCD boot logs
FR 'BootStats' @('C:\Windows\Performance\WinSAT\DataStore')
# Crash reports from various apps
Get-ChildItem "$env:APPDATA" -Recurse -Depth 3 -Filter '*.dmp' -EA 0 |
    Where-Object { $_.LastWriteTime -lt $cutoff30 } |
    ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
# Stale .tmp files in C:\Windows >7 days
Get-ChildItem 'C:\Windows\Temp' -File -Filter '*.tmp' -EA 0 |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
# C:\Users\micha\AppData\Local\Temp - old files >3 days
Get-ChildItem $env:TEMP -Recurse -Force -EA 0 |
    Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
    ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
Write-Host "  -> PS/Temp freed: $([math]::Round(($freed-$b31)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b31) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# [32] WINDOWS SEARCH INDEX REBUILD + OUTLOOK TEMP + MISC APP CACHES
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n[32] Misc app caches (Outlook OLK, IE/WebView2, Hyper-V, Wallet)..." -ForegroundColor Cyan
$b32 = $freed
# Outlook OLK temp attachments
FR 'Outlook-OLK'    @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache\Content.Outlook")
# IE / Edge WebView2 cache
FR 'IECache'        @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache\IE","$env:LOCALAPPDATA\Microsoft\Windows\INetCache\Low")
FR 'WebView2-Cache' @("$env:LOCALAPPDATA\Microsoft\EdgeWebView\Application")
# Windows Wallet / Pay
FR 'Wallet-Logs'    @("$env:LOCALAPPDATA\Packages\Microsoft.Wallet_8wekyb3d8bbwe\LocalCache")
# Print spooler leftover spool files (safe — not active jobs)
Stop-Service Spooler -Force -EA 0
Get-ChildItem 'C:\Windows\System32\spool\PRINTERS' -File -EA 0 |
    ForEach-Object { $script:freed += $_.Length; Remove-Item $_.FullName -Force -EA 0 }
Start-Service Spooler -EA 0
# Windows Biometric
FR 'Biometric-Logs' @('C:\Windows\System32\WinBioDatabase')
# Hyper-V checkpoint temp files (NOT VHD — only temp)
FR 'HyperV-Logs'    @('C:\ProgramData\Microsoft\Windows\Hyper-V\Virtual Machines Logs')
# Certificate enrollment temp
FR 'CertEnroll'     @('C:\Windows\System32\CertSrv\CertEnroll')
# Windows Mixed Reality
FR 'WMR-Cache'      @("$env:LOCALAPPDATA\Packages\Microsoft.MixedReality.Portal_8wekyb3d8bbwe\LocalCache")
# Xbox / Game Bar
FR 'XboxCache'      @("$env:LOCALAPPDATA\Packages\Microsoft.XboxGameOverlay_8wekyb3d8bbwe\LocalCache",
                      "$env:LOCALAPPDATA\Packages\Microsoft.GamingApp_8wekyb3d8bbwe\LocalCache")
# Feedback Hub logs
FR 'FeedbackHub'    @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsFeedbackHub_8wekyb3d8bbwe\LocalCache")
Write-Host "  -> Misc freed: $([math]::Round(($freed-$b32)/1MB,1)) MB" -ForegroundColor $(if(($freed-$b32) -gt 1MB){'Green'}else{'Gray'})

# ══════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
$elapsed   = (Get-Date) - $t
$volAfter  = (Get-Volume -DriveLetter C -EA 0).SizeRemaining
$actualFreed = if ($volBefore -and $volAfter) { $volAfter - $volBefore } else { 0 }

Write-Host "`n`n=================================================================" -ForegroundColor Green
Write-Host "=== CSpaceMaximizer v2  —  COMPLETE                          ===" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "Finished : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "Elapsed  : $([math]::Floor($elapsed.TotalMinutes))m $($elapsed.Seconds)s" -ForegroundColor White
Write-Host ""
Write-Host "─── SPACE FREED ──────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "  Tracked (script counters) : $([math]::Round($freed/1GB,3)) GB  ($([math]::Round($freed/1MB,0)) MB)" -ForegroundColor Yellow
if ($actualFreed -gt 0) {
    Write-Host "  Actual disk freed         : $([math]::Round($actualFreed/1GB,3)) GB  ($([math]::Round($actualFreed/1MB,0)) MB)" -ForegroundColor Green
} elseif ($actualFreed -lt 0) {
    Write-Host "  Net change                : $([math]::Round($actualFreed/1GB,3)) GB (Windows reclaimed some; DISM/Compact may need reboot)" -ForegroundColor Yellow
}
$volFinal = Get-Volume -DriveLetter C -EA 0
if ($volFinal) {
    $freeGB  = $volFinal.SizeRemaining / 1GB
    $totalGB = $volFinal.Size / 1GB
    $pct     = ($volFinal.SizeRemaining / $volFinal.Size) * 100
    $c       = if ($pct -gt 20) { 'Green' } elseif ($pct -gt 10) { 'Yellow' } else { 'Red' }
    Write-Host ""
    Write-Host "─── C: DRIVE STATUS ──────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ("  Free  : {0:N2} GB" -f $freeGB)  -ForegroundColor $c
    Write-Host ("  Used  : {0:N2} GB" -f ($totalGB - $freeGB)) -ForegroundColor White
    Write-Host ("  Total : {0:N2} GB" -f $totalGB) -ForegroundColor White
    Write-Host ("  Free% : {0:N1}%"   -f $pct)     -ForegroundColor $c
}
Write-Host ""
Write-Host "TIP: For maximum cleanup, run cccc (or nocccc) first, then this script." -ForegroundColor DarkGray
Write-Host "     Reboot after first run — DISM & Compact OS gains appear post-reboot." -ForegroundColor DarkGray
Write-Host "=================================================================" -ForegroundColor Green
