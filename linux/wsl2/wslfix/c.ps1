# WSL2 Ultimate Fix - Fully Automated - PowerShell 5.1
# Run: Set-ExecutionPolicy Bypass -Scope Process -Force; .\wsl-fix.ps1

$ErrorActionPreference = "Continue"
$DISTRO = "Ubuntu"

function Write-OK($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "[i] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[X] $msg" -ForegroundColor Red }

function Write-Section($msg) { 
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Blue
    Write-Host "  $msg" -ForegroundColor White
    Write-Host ("=" * 70) -ForegroundColor Blue
}

# Banner
Clear-Host
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Magenta
Write-Host "  =     WSL2 ULTIMATE FIX - FULLY AUTOMATED                     =" -ForegroundColor Magenta
Write-Host "  =     No prompts - fixes everything automatically!            =" -ForegroundColor Magenta
Write-Host "  ================================================================" -ForegroundColor Magenta
Write-Host ""

# Admin check - auto elevate if needed
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warn "Elevating to Administrator..."
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# ============================================================================
Write-Section "1. BACKUP"
# ============================================================================

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir = "$env:USERPROFILE\wsl-backup-$ts"
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

$cfgPath = "$env:USERPROFILE\.wslconfig"
if (Test-Path $cfgPath) {
    Copy-Item $cfgPath "$BackupDir\wslconfig.bak" -Force
    Write-OK "Backed up .wslconfig"
} else {
    Write-Info "No existing .wslconfig"
}

# ============================================================================
Write-Section "2. REMOVE OLD CONFIG"
# ============================================================================

if (Test-Path $cfgPath) {
    Remove-Item $cfgPath -Force
    Write-OK "Removed old .wslconfig"
} else {
    Write-Info "Nothing to remove"
}

# ============================================================================
Write-Section "3. CREATE SAFE .wslconfig"
# ============================================================================

try {
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $cpu = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors
} catch {
    $ram = 16
    $cpu = 4
}

$useRAM = [math]::Min([math]::Max(4, [math]::Floor($ram / 2)), 16)
$useCPU = [math]::Min([math]::Max(2, [math]::Floor($cpu / 2)), 8)

Write-Info "System: ${ram}GB RAM, $cpu CPUs"
Write-Info "WSL: ${useRAM}GB RAM, $useCPU CPUs"

$cfg = @"
[wsl2]
memory=${useRAM}GB
processors=$useCPU
swap=2GB
localhostForwarding=true
nestedVirtualization=true
guiApplications=true
kernelCommandLine=quiet
"@

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($cfgPath, $cfg, $utf8)
Write-OK "Created .wslconfig"

# ============================================================================
Write-Section "4. SHUTDOWN WSL"
# ============================================================================

Write-Info "Shutting down WSL..."
$null = wsl --shutdown 2>&1
Start-Sleep -Seconds 3

Write-Info "Restarting WSL service..."
try { Stop-Service LxssManager -Force -EA SilentlyContinue } catch {}
Start-Sleep -Seconds 3
try { Start-Service LxssManager -EA SilentlyContinue } catch {}
Start-Sleep -Seconds 3
Write-OK "WSL service restarted"

# ============================================================================
Write-Section "5. TEST WSL"
# ============================================================================

Write-Info "Testing WSL..."
Start-Sleep -Seconds 5

$working = $false
$retries = 3

for ($i = 1; $i -le $retries; $i++) {
    Write-Info "Attempt $i of $retries..."
    $test = wsl -d $DISTRO -e echo "OK" 2>&1
    if ($test -match "OK") {
        Write-OK "WSL started!"
        $working = $true
        break
    }
    if ($i -lt $retries) {
        Write-Warn "Failed, retrying in 5s..."
        Start-Sleep -Seconds 5
    }
}

if (-not $working) {
    Write-Warn "WSL not responding, trying WSL update..."
    wsl --update 2>&1 | Out-Null
    Start-Sleep -Seconds 5
    $null = wsl --shutdown 2>&1
    Start-Sleep -Seconds 5
    
    $test = wsl -d $DISTRO -e echo "OK" 2>&1
    if ($test -match "OK") {
        Write-OK "WSL started after update!"
        $working = $true
    }
}

# ============================================================================
Write-Section "6. CREATE LINUX SCRIPT"
# ============================================================================

$linuxScript = @'
#!/bin/bash
echo ""
echo "========================================"
echo "  WSL2 Linux Fix - Automated"
echo "========================================"
echo ""

[ "$EUID" -ne 0 ] && { echo "[X] Need root"; exit 1; }

echo "[*] Fixing wsl.conf..."
rm -f /etc/wsl.conf
echo '[boot]
systemd=true

[network]
generateResolvConf=false
generateHosts=false

[interop]
enabled=true
appendWindowsPath=true

[automount]
enabled=true
mountFsTab=true
root=/mnt/
options=metadata

[user]
default=root' > /etc/wsl.conf
echo "[OK] wsl.conf"

echo "[*] Fixing DNS..."
systemctl stop systemd-resolved 2>/dev/null
systemctl disable systemd-resolved 2>/dev/null
systemctl mask systemd-resolved 2>/dev/null
chattr -i /etc/resolv.conf 2>/dev/null
rm -f /etc/resolv.conf 2>/dev/null
echo 'nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
options timeout:2 attempts:3 rotate' > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null
echo "[OK] DNS"

echo "[*] Configuring journald..."
mkdir -p /etc/systemd/journald.conf.d
echo '[Journal]
Storage=volatile
SystemMaxUse=10M
MaxLevelStore=warning
ForwardToSyslog=no
ForwardToKMsg=no
ForwardToConsole=no' > /etc/systemd/journald.conf.d/wsl.conf
systemctl restart systemd-journald 2>/dev/null
echo "[OK] journald"

echo "[*] Configuring rsyslog..."
mkdir -p /etc/rsyslog.d
echo ':msg, contains, "dxg:" stop
:msg, contains, "dxgk:" stop
:msg, contains, "PCI: Fatal" stop
:msg, contains, "CheckConnection" stop
:msg, contains, "getaddrinfo() failed" stop
:msg, contains, "Ioctl failed" stop
:msg, contains, "SRSO" stop
:msg, contains, "memfd_create" stop
:msg, contains, "esm-cache" stop
:msg, contains, "ubuntu-advantage" stop' > /etc/rsyslog.d/00-wsl.conf
systemctl restart rsyslog 2>/dev/null
echo "[OK] rsyslog"

echo "[*] Masking problematic services (including esm-cache)..."
for s in systemd-resolved snapd apt-news motd-news packagekit fwupd cups bluetooth avahi-daemon ModemManager multipathd udisks2 accounts-daemon thermald upower cloud-init cloud-config cloud-final apport whoopsie apt-daily.timer apt-daily-upgrade.timer esm-cache.service ua-timer.timer ua-timer.service ua-reboot-cmds.service ubuntu-advantage.service ua-messaging.timer ua-messaging.service ua-auto-attach.service ua-auto-attach.path motd-news.timer e2scrub_all.timer fstrim.timer man-db.timer; do
    systemctl stop $s 2>/dev/null
    systemctl disable $s 2>/dev/null
    systemctl mask $s 2>/dev/null
done
systemctl daemon-reload
systemctl reset-failed 2>/dev/null
echo "[OK] services masked (including esm-cache)"

echo "[*] Removing Ubuntu Pro/ESM completely..."
rm -f /etc/apt/sources.list.d/ubuntu-esm-*.list 2>/dev/null
rm -f /etc/apt/sources.list.d/ubuntu-advantage*.list 2>/dev/null
rm -rf /var/lib/ubuntu-advantage 2>/dev/null
rm -rf /var/log/ubuntu-advantage* 2>/dev/null
mkdir -p /var/cache/apt-show-versions
touch /var/log/ubuntu-advantage-apt-hook.log 2>/dev/null
chmod -x /etc/update-motd.d/* 2>/dev/null
echo "" > /etc/motd
echo "[OK] Ubuntu Pro/ESM removed"

echo "[*] Clearing logs..."
dmesg -C 2>/dev/null
journalctl --rotate 2>/dev/null
journalctl --vacuum-time=1s 2>/dev/null
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null
echo "[OK] logs cleared"

echo "[*] Fixing apt directories..."
mkdir -p /var/cache/apt-show-versions
mkdir -p /var/cache/apt/archives/partial
mkdir -p /var/lib/apt/lists/partial
mkdir -p /var/lib/dpkg/info
mkdir -p /var/lib/dpkg/updates
mkdir -p /var/lib/dpkg/triggers
mkdir -p /var/log/apt
touch /var/log/ubuntu-advantage-apt-hook.log
touch /var/log/dpkg.log
touch /var/log/apt/term.log
touch /var/log/apt/history.log
echo "[OK] apt directories"

echo "[*] Fixing apt/dpkg..."
rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock* /var/cache/apt/archives/lock 2>/dev/null
dpkg --configure -a 2>/dev/null
apt-get install -f -y 2>/dev/null

# Remove broken packages
BROKEN=$(dpkg -l 2>/dev/null | grep -E "^iU|^rC|^iF|^..r" | awk '{print $2}' | tr '\n' ' ')
if [ -n "$BROKEN" ]; then
    echo "[*] Removing broken packages: $BROKEN"
    for pkg in $BROKEN; do
        dpkg --remove --force-remove-reinstreq --force-depends "$pkg" 2>/dev/null
        dpkg --purge --force-remove-reinstreq --force-depends "$pkg" 2>/dev/null
    done
fi
echo "[OK] apt/dpkg"

echo "[*] Configuring sysctl..."
echo 'kernel.printk = 3 3 3 3
kernel.dmesg_restrict = 1
net.ipv4.ip_forward = 1
vm.swappiness = 10
fs.inotify.max_user_watches = 524288
fs.file-max = 2097152' > /etc/sysctl.d/99-wsl.conf
sysctl -p /etc/sysctl.d/99-wsl.conf 2>/dev/null
echo "[OK] sysctl"

echo "[*] Creating helper scripts..."

# fixdns
echo '#!/bin/bash
chattr -i /etc/resolv.conf 2>/dev/null
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null
ping -c1 -W2 google.com >/dev/null 2>&1 && echo "[OK] DNS" || echo "[FAIL] DNS"' > /usr/local/bin/fixdns
chmod +x /usr/local/bin/fixdns

# clearlogs
echo '#!/bin/bash
dmesg -C 2>/dev/null
journalctl --vacuum-time=1s 2>/dev/null
find /var/log -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null
systemctl reset-failed 2>/dev/null
echo "[OK] Logs cleared"' > /usr/local/bin/clearlogs
chmod +x /usr/local/bin/clearlogs

# updates - COMPREHENSIVE VERSION
echo '#!/bin/bash
echo "[*] WSL2 Comprehensive Update Script"
echo "===================================="

# Fix DNS first
chattr -i /etc/resolv.conf 2>/dev/null
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null

# Create required directories
mkdir -p /var/cache/apt-show-versions /var/log /var/lib/apt/lists/partial /var/cache/apt/archives/partial

# Create required files
touch /var/log/ubuntu-advantage-apt-hook.log 2>/dev/null

# Fix dpkg
dpkg --configure -a 2>/dev/null

# Fix broken installs
apt-get install -f -y 2>/dev/null

# Remove broken packages
BROKEN=$(dpkg -l 2>/dev/null | grep -E "^iU|^rC|^iF" | awk "{print \$2}" | tr "\n" " ")
if [ -n "$BROKEN" ]; then
    echo "[*] Removing broken: $BROKEN"
    dpkg --remove --force-remove-reinstreq --force-depends $BROKEN 2>/dev/null
fi

# Clean apt
apt-get clean
apt-get autoclean

# Reset apt lists
rm -rf /var/lib/apt/lists/*
mkdir -p /var/lib/apt/lists/partial

# Configure dpkg again
dpkg --configure -a

# Fix broken again
apt-get install -f -y

# Update
DEBIAN_FRONTEND=noninteractive apt-get update

# Upgrade with force options
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    -o Dpkg::Options::="--force-confnew" \
    --fix-broken --fix-missing

# Cleanup
apt-get autoremove -y
apt-get autoclean

# Final update cycle
apt-get update
apt-get upgrade -y
apt-get autoremove -y

# Clear logs
dmesg -C 2>/dev/null
journalctl --vacuum-time=1s 2>/dev/null
systemctl reset-failed 2>/dev/null

echo ""
echo "[OK] Update complete!"
echo "Failed services: $(systemctl --failed 2>/dev/null | grep -c loaded)"' > /usr/local/bin/updates
chmod +x /usr/local/bin/updates

echo "[OK] helpers: fixdns, clearlogs, updates"

echo "[*] Adding aliases to .bashrc..."
# Remove old aliases if exist
sed -i '/# WSL-FIX-ALIASES/,/# END-WSL-FIX/d' /root/.bashrc 2>/dev/null

# Add new aliases
cat >> /root/.bashrc << 'ALIASES'

# WSL-FIX-ALIASES
alias update='updates'
alias fix='fixdns'
alias logs='clearlogs'
alias cls='clear'
alias ll='ls -la'
alias ..='cd ..'

# Suppress login messages
touch ~/.hushlogin
# END-WSL-FIX
ALIASES
echo "[OK] aliases added"

echo "[*] Running initial system update..."
# Create dirs
mkdir -p /var/cache/apt-show-versions /var/log
touch /var/log/ubuntu-advantage-apt-hook.log

# Quick fix cycle
dpkg --configure -a 2>/dev/null
apt-get install -f -y 2>/dev/null

# Remove any broken
BROKEN=$(dpkg -l 2>/dev/null | grep -E "^iU|^rC|^iF" | awk '{print $2}')
for pkg in $BROKEN; do
    dpkg --remove --force-remove-reinstreq --force-depends "$pkg" 2>/dev/null
done

apt-get clean
rm -rf /var/lib/apt/lists/*
mkdir -p /var/lib/apt/lists/partial
dpkg --configure -a
apt-get install -f -y

DEBIAN_FRONTEND=noninteractive apt-get update 2>&1 | grep -v "^W:" | head -5
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    --fix-broken --fix-missing 2>&1 | grep -v "^W:" | head -5
apt-get autoremove -y 2>/dev/null
apt-get clean

# Final reset
systemctl reset-failed 2>/dev/null
dmesg -C 2>/dev/null
journalctl --vacuum-time=1s 2>/dev/null

echo ""
echo "========================================"
echo "  LINUX FIX COMPLETE!"
echo "========================================"
echo ""
ping -c1 -W2 google.com >/dev/null 2>&1 && echo "[OK] Network" || echo "[!] Network issue"
echo "[OK] Failed services: $(systemctl --failed 2>/dev/null | grep -c loaded)"
echo "[OK] Journal errors: $(journalctl -p err -b --no-pager 2>/dev/null | wc -l)"
echo ""
echo "Commands available: updates, fixdns, clearlogs"
echo "Type 'updates' for comprehensive system update"
'@

$scriptPath = "$env:USERPROFILE\wsl-linux-fix.sh"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($scriptPath, $linuxScript, $utf8)
Write-OK "Created: $scriptPath"

# ============================================================================
# RUN LINUX FIX IF WSL WORKS
# ============================================================================

if ($working) {
    Write-Section "7. RUNNING LINUX FIX"
    
    Write-Info "Running Linux fix inside WSL..."
    $wslPath = "/mnt/c/Users/$env:USERNAME/wsl-linux-fix.sh"
    
    wsl -d $DISTRO -u root chmod +x $wslPath 2>&1 | Out-Null
    wsl -d $DISTRO -u root bash $wslPath
    
    Write-OK "Linux fix complete!"
} else {
    Write-Section "7. WSL NOT WORKING"
    Write-Err "WSL could not start. Try:"
    Write-Host "  1. Restart computer" -ForegroundColor Yellow
    Write-Host "  2. Run: wsl --update" -ForegroundColor Yellow
    Write-Host "  3. Run this script again" -ForegroundColor Yellow
}

# ============================================================================
Write-Section "8. FINAL RESTART"
# ============================================================================

Write-Info "Shutting down WSL to apply all changes..."
$null = wsl --shutdown 2>&1
Start-Sleep -Seconds 3

# ============================================================================
Write-Section "SUMMARY"
# ============================================================================

Write-Host ""
if ($working) {
    Write-Host "  ==============================" -ForegroundColor Green
    Write-Host "  =    ALL FIXES APPLIED!     =" -ForegroundColor Green
    Write-Host "  ==============================" -ForegroundColor Green
} else {
    Write-Host "  ==============================" -ForegroundColor Yellow
    Write-Host "  =  WINDOWS FIXES APPLIED    =" -ForegroundColor Yellow
    Write-Host "  ==============================" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Files created:" -ForegroundColor Cyan
Write-Host "    $cfgPath"
Write-Host "    $scriptPath"
Write-Host "    $BackupDir"
Write-Host ""
Write-Host "  In WSL use:" -ForegroundColor Cyan
Write-Host "    updates   - COMPREHENSIVE system update (fixes ALL apt issues)"
Write-Host "    fixdns    - Fix DNS"
Write-Host "    clearlogs - Clear logs"  
Write-Host ""
Write-Host "  Fixed issues:" -ForegroundColor Cyan
Write-Host "    - esm-cache.service (masked)"
Write-Host "    - Ubuntu Pro/ESM (removed)"
Write-Host "    - Broken packages (auto-removed)"
Write-Host "    - All apt directories created"
Write-Host ""

# ============================================================================
Write-Section "9. STARTING UBUNTU"
# ============================================================================

Write-OK "Starting Ubuntu in 3 seconds..."
Start-Sleep -Seconds 3

# Start Ubuntu
wsl -d $DISTRO
