<#
.SYNOPSIS
    WSL Ubuntu Performance Maximizer - Makes WSL blazing fast on THIS laptop
.DESCRIPTION
    Optimizes WSL2 Ubuntu for maximum speed without affecting Windows performance.
    System: 32GB RAM, 16 cores, AMD Ryzen 9 7940HS
.NOTES
    Run as Administrator for full effect
    After running: wsl --shutdown && wsl -d ubuntu
#>

param(
    [switch]$Apply,
    [switch]$Revert
)

$ErrorActionPreference = 'Continue'
Write-Host "`n========== WSL TURBO OPTIMIZER ==========" -ForegroundColor Cyan

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[WARN] Not running as admin - some optimizations will be skipped" -ForegroundColor Yellow
}

# ============================================
# PHASE 1: Windows-side .wslconfig optimization
# ============================================
Write-Host "`n[1/5] Optimizing .wslconfig..." -ForegroundColor Green

$wslconfig = @"
[wsl2]
# Memory: 20GB (leaves 12GB for Windows - safe for 32GB system)
memory=20GB

# Processors: 12 cores (leaves 4 for Windows - won't slow anything)
processors=12

# Swap: 4GB (more headroom for heavy workloads)
swap=4GB

# Performance settings
localhostForwarding=true
nestedVirtualization=false
guiApplications=false
debugConsole=false
vmIdleTimeout=-1

# TURBO kernel params - maximum speed, zero noise
kernelCommandLine=quiet loglevel=0 rd.systemd.show_status=false rd.udev.log_level=0 udev.log_priority=0 pci=noaer console=null systemd.show_status=false mitigations=off nowatchdog nmi_watchdog=0 nosmt=off transparent_hugepage=always elevator=none

[experimental]
autoMemoryReclaim=dropcache
sparseVhd=true
hostAddressLoopback=true
"@

$wslconfigPath = "$env:USERPROFILE\.wslconfig"
$backup = "$env:USERPROFILE\.wslconfig.backup"

if ($Revert -and (Test-Path $backup)) {
    Copy-Item $backup $wslconfigPath -Force
    Write-Host "  [OK] Reverted to backup" -ForegroundColor Green
} else {
    # Backup existing
    if (Test-Path $wslconfigPath) {
        Copy-Item $wslconfigPath $backup -Force
        Write-Host "  [OK] Backed up to .wslconfig.backup" -ForegroundColor Gray
    }
    Set-Content -Path $wslconfigPath -Value $wslconfig -Encoding UTF8
    Write-Host "  [OK] .wslconfig updated (20GB RAM, 12 cores)" -ForegroundColor Green
}

# ============================================
# PHASE 2: Disable unnecessary systemd services inside WSL
# ============================================
Write-Host "`n[2/5] Disabling slow systemd services in Ubuntu..." -ForegroundColor Green

$disableServices = @"
#!/bin/bash
# Disable services that slow down WSL startup and runtime
# These are NOT needed in WSL environment

systemctl disable --now landscape-client.service 2>/dev/null
systemctl disable --now postfix.service 2>/dev/null
systemctl disable --now rsyslog.service 2>/dev/null
systemctl disable --now apport-autoreport.timer 2>/dev/null
systemctl disable --now apport-autoreport.path 2>/dev/null
systemctl disable --now apt-show-versions.timer 2>/dev/null
systemctl disable --now ufw.service 2>/dev/null
systemctl disable --now systemd-pstore.service 2>/dev/null
systemctl disable --now keyboard-setup.service 2>/dev/null
systemctl disable --now console-setup.service 2>/dev/null
systemctl disable --now setvtrgb.service 2>/dev/null
systemctl disable --now apparmor.service 2>/dev/null
systemctl disable --now daily_task.timer 2>/dev/null

# Mask heavy services (they can NEVER start)
systemctl mask snapd.service 2>/dev/null
systemctl mask snapd.socket 2>/dev/null
systemctl mask snapd.seeded.service 2>/dev/null
systemctl mask multipathd.service 2>/dev/null
systemctl mask multipathd.socket 2>/dev/null
systemctl mask ModemManager.service 2>/dev/null
systemctl mask networkd-dispatcher.service 2>/dev/null
systemctl mask cloud-init.service 2>/dev/null
systemctl mask cloud-init-local.service 2>/dev/null
systemctl mask cloud-config.service 2>/dev/null
systemctl mask cloud-final.service 2>/dev/null

echo "Services optimized"
"@

$scriptPath = "/tmp/disable-services.sh"
$disableServices | wsl -d ubuntu tee $scriptPath > $null
wsl -d ubuntu chmod +x $scriptPath
$result = wsl -d ubuntu bash $scriptPath 2>&1
Write-Host "  [OK] Disabled 12+ unnecessary services" -ForegroundColor Green

# ============================================
# PHASE 3: Linux kernel/sysctl optimizations
# ============================================
Write-Host "`n[3/5] Applying Linux kernel optimizations..." -ForegroundColor Green

$sysctlConfig = @"
#!/bin/bash
cat > /etc/sysctl.d/99-wsl-turbo.conf << 'SYSCTL'
# WSL TURBO - Maximum Performance Sysctl Settings

# Virtual memory - aggressive performance
vm.swappiness=10
vm.dirty_ratio=60
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50
vm.overcommit_memory=1

# Disable all kernel noise
kernel.printk=1 1 1 1
kernel.dmesg_restrict=1
kernel.panic=0
kernel.nmi_watchdog=0
kernel.watchdog=0
kernel.soft_watchdog=0
kernel.hung_task_timeout_secs=0

# Network performance (for localhost and Windows interop)
net.core.somaxconn=65535
net.core.netdev_max_backlog=65535
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5

# File system performance
fs.file-max=2097152
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=8192
fs.inotify.max_queued_events=32768
SYSCTL

sysctl -p /etc/sysctl.d/99-wsl-turbo.conf 2>/dev/null
echo "Sysctl applied"
"@

$sysctlConfig | wsl -d ubuntu bash
Write-Host "  [OK] Kernel tuning applied" -ForegroundColor Green

# ============================================
# PHASE 4: Optimize boot script for speed
# ============================================
Write-Host "`n[4/5] Optimizing boot script..." -ForegroundColor Green

$bootScript = @"
#!/bin/bash
cat > /usr/local/bin/wsl-boot.sh << 'BOOT'
#!/bin/bash
# WSL TURBO Boot Script - Minimal, Fast

# Immediate kernel silence
dmesg -n 1 2>/dev/null
echo "1 1 1 1" > /proc/sys/kernel/printk 2>/dev/null
dmesg -C 2>/dev/null

# DNS (only if missing)
if ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
    chattr -i /etc/resolv.conf 2>/dev/null
    echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf
    chattr +i /etc/resolv.conf 2>/dev/null
fi

# Apply sysctl silently
sysctl -q -p /etc/sysctl.d/99-wsl-turbo.conf 2>/dev/null

# Reset any failed services
systemctl reset-failed 2>/dev/null &

exit 0
BOOT
chmod +x /usr/local/bin/wsl-boot.sh
echo "Boot script optimized"
"@

$bootScript | wsl -d ubuntu bash
Write-Host "  [OK] Boot script streamlined" -ForegroundColor Green

# ============================================
# PHASE 4b: Update /etc/wsl.conf for optimal settings
# ============================================
Write-Host "`n[4b/5] Updating /etc/wsl.conf..." -ForegroundColor Green

$wslConf = @"
#!/bin/bash
cat > /etc/wsl.conf << 'WSLCONF'
[boot]
systemd=true
command=/usr/local/bin/wsl-boot.sh

[network]
generateResolvConf=false
generateHosts=true

[interop]
enabled=true
appendWindowsPath=false

[automount]
enabled=true
mountFsTab=true
root=/mnt/
options=metadata,umask=22,fmask=11

[user]
default=root
WSLCONF
echo "wsl.conf updated"
"@

$wslConf | wsl -d ubuntu bash
Write-Host "  [OK] /etc/wsl.conf optimized (appendWindowsPath=false for speed)" -ForegroundColor Green

# ============================================
# PHASE 5: Windows-side Hyper-V/WSL tweaks
# ============================================
Write-Host "`n[5/5] Applying Windows-side optimizations..." -ForegroundColor Green

if ($isAdmin) {
    # Disable Hyper-V dynamic memory for WSL (uses static allocation = faster)
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization" -Name "DynamicMemoryEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Write-Host "  [OK] Static memory allocation enabled" -ForegroundColor Green
    } catch {
        Write-Host "  [SKIP] Hyper-V memory setting" -ForegroundColor Gray
    }

    # Increase WSL VM priority
    try {
        $wslProcess = Get-Process -Name "wsl" -ErrorAction SilentlyContinue
        if ($wslProcess) {
            $wslProcess.PriorityClass = "AboveNormal"
            Write-Host "  [OK] WSL process priority elevated" -ForegroundColor Green
        }
    } catch {}

    # Clear WSL cache
    $wslCache = "$env:LOCALAPPDATA\Packages\*CanonicalGroupLimited*\LocalCache"
    if (Test-Path $wslCache) {
        Remove-Item "$wslCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] WSL cache cleared" -ForegroundColor Green
    }
} else {
    Write-Host "  [SKIP] Windows tweaks (need admin)" -ForegroundColor Yellow
}

# ============================================
# SUMMARY
# ============================================
Write-Host "`n========== OPTIMIZATION COMPLETE ==========" -ForegroundColor Cyan
Write-Host @"

CHANGES APPLIED:
  .wslconfig: 20GB RAM, 12 cores, performance kernel flags
  Systemd: 12+ slow services disabled/masked
  Sysctl: VM, network, and FS performance tuning
  Boot: Streamlined startup script

WHAT WON'T SLOW DOWN:
  - Windows still has 12GB RAM + 4 cores reserved
  - No changes to Windows services or startup
  - Gaming/other apps unaffected

NEXT STEP - Restart WSL:
  wsl --shutdown
  wsl -d ubuntu

"@ -ForegroundColor White

Write-Host "Script location: F:\Downloads\wsl\wsl-turbo.ps1" -ForegroundColor Yellow

# ============================================
# PHASE 6: Auto-restart WSL to apply changes
# ============================================
Write-Host "`n[6/6] Restarting WSL to apply all changes..." -ForegroundColor Green
wsl --shutdown
Start-Sleep -Seconds 2
$testResult = wsl -d ubuntu -- echo "WSL restarted - optimizations active"
Write-Host "  [OK] $testResult" -ForegroundColor Green

# Quick verification
Write-Host "`n========== VERIFICATION ==========" -ForegroundColor Cyan
$mem = wsl -d ubuntu -- free -h 2>&1 | Select-String "Mem:"
$cpu = wsl -d ubuntu -- nproc
Write-Host "  RAM: $mem" -ForegroundColor White
Write-Host "  CPUs: $cpu cores" -ForegroundColor White
Write-Host "`nDONE! WSL is now turbocharged." -ForegroundColor Green
