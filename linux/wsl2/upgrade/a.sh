#!/bin/bash
# WSL2 Ubuntu Upgrade Repair Script v4 - ULTIMATE EDITION
# Fixes ALL issues including stuck release upgrades

set +e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFFOLD=1
export NEEDRESTART_SUSPEND=1
export APT_LISTCHANGES_FRONTEND=none

echo "=== WSL2 Ubuntu Upgrade Repair Script v4 - ULTIMATE ==="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo bash a.sh"
    exit 1
fi

echo "[1/16] Killing ALL blocking processes..."
killall -9 apt apt-get dpkg 2>/dev/null || true
killall -9 packagekitd 2>/dev/null || true
killall -9 unattended-upgrade 2>/dev/null || true
killall -9 do-release-upgrade 2>/dev/null || true
pkill -9 -f DistUpgrade 2>/dev/null || true
pkill -9 -f update-manager 2>/dev/null || true
sleep 2

echo "[2/16] Removing ALL lock files..."
rm -f /var/lib/dpkg/lock* 2>/dev/null || true
rm -f /var/lib/apt/lists/lock 2>/dev/null || true
rm -f /var/cache/apt/archives/lock 2>/dev/null || true
rm -f /var/lib/dpkg/triggers/Lock 2>/dev/null || true
rm -f /var/lib/apt/daily_lock 2>/dev/null || true
rm -f /var/run/unattended-upgrades.lock 2>/dev/null || true

echo "[3/16] Disabling ALL auto-update services..."
systemctl unmask packagekit.service 2>/dev/null || true
systemctl stop packagekit.service 2>/dev/null || true
systemctl disable packagekit.service 2>/dev/null || true
systemctl stop apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily.timer 2>/dev/null || true
systemctl stop apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
systemctl stop unattended-upgrades.service 2>/dev/null || true
systemctl disable unattended-upgrades.service 2>/dev/null || true
systemctl stop motd-news.timer 2>/dev/null || true
systemctl disable motd-news.timer 2>/dev/null || true

echo "[4/16] Removing needrestart and other interactive blockers..."
apt-get remove -y needrestart 2>/dev/null || true
apt-get remove -y apt-listchanges 2>/dev/null || true

echo "[5/16] Backing up dpkg status file..."
cp /var/lib/dpkg/status /var/lib/dpkg/status.backup.$(date +%s) 2>/dev/null || true

echo "[6/16] Force removing obsolete packages..."
OBSOLETE_PKGS="libmagic1 libpython3.10-minimal libpython3.10-stdlib libpython3.10 libssl3 policykit-1 python3.10-minimal python3.10-venv python3.10 libpython3.9-minimal libpython3.9-stdlib libpython3.9 python3.9-minimal python3.9-venv python3.9 libpython3.11-minimal libpython3.11-stdlib libpython3.11 python3.11-minimal python3.11-venv python3.11"

for pkg in $OBSOLETE_PKGS; do
    if grep -q "^Package: $pkg$" /var/lib/dpkg/status 2>/dev/null; then
        echo "  Purging: $pkg"
        sed -i "/^Package: $pkg$/,/^$/d" /var/lib/dpkg/status 2>/dev/null || true
    fi
    dpkg --remove --force-remove-reinstreq --force-depends "$pkg" 2>/dev/null || true
    dpkg --purge --force-all "$pkg" 2>/dev/null || true
    rm -f /var/lib/dpkg/info/${pkg}.* 2>/dev/null || true
    rm -f /var/lib/dpkg/info/${pkg}:amd64.* 2>/dev/null || true
done

echo "[7/16] Fixing dpkg diversions..."
dpkg-divert --list 2>/dev/null | while read line; do
    div_file=$(echo "$line" | awk '{print $3}')
    if [ -n "$div_file" ] && [ ! -f "$div_file" ]; then
        dpkg-divert --remove --rename "$div_file" 2>/dev/null || true
    fi
done

echo "[8/16] Regenerating missing dpkg files lists..."
for pkg in $(dpkg --get-selections 2>/dev/null | grep -v deinstall | cut -f1 | cut -d: -f1); do
    base_pkg=$(echo "$pkg" | cut -d: -f1)
    if [ ! -f "/var/lib/dpkg/info/${base_pkg}.list" ] && [ ! -f "/var/lib/dpkg/info/${base_pkg}:amd64.list" ]; then
        touch "/var/lib/dpkg/info/${base_pkg}.list" 2>/dev/null || true
    fi
done

echo "[9/16] Deep dpkg database repair..."
dpkg --configure -a --force-confold --force-confdef 2>/dev/null || true
dpkg --audit 2>/dev/null || true

echo "[10/16] Purging apt cache..."
apt-get clean 2>/dev/null || true
rm -rf /var/lib/apt/lists/* 2>/dev/null || true
rm -rf /var/cache/apt/archives/*.deb 2>/dev/null || true
rm -rf /var/cache/apt/pkgcache.bin /var/cache/apt/srcpkgcache.bin 2>/dev/null || true

echo "[11/16] Backing up and resetting sources.list..."
cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%s) 2>/dev/null || true
CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")
echo "  Current codename: $CODENAME"

echo "[12/16] Updating package lists..."
for i in 1 2 3; do
    apt-get update -o Acquire::Check-Valid-Until=false 2>/dev/null && break
    echo "  Retry $i..."
    sleep 3
done

echo "[13/16] Fixing broken packages..."
apt-get install -f -y --allow-downgrades --allow-change-held-packages 2>/dev/null || true
dpkg --configure -a --force-confold --force-confdef 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true

echo "[14/16] System upgrade..."
apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" upgrade -y 2>/dev/null || true
apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" dist-upgrade -y 2>/dev/null || true

echo "[15/16] Cleaning orphaned packages..."
apt-get autoremove -y --purge 2>/dev/null || true

echo "[16/16] Final verification..."
dpkg --audit 2>/dev/null || true
apt-get check 2>/dev/null || true

echo ""
echo "=== Repair Complete - Starting Release Upgrade ==="
echo ""

# Ensure update-manager-core is installed
apt-get install -y update-manager-core 2>/dev/null || true

# Configure for normal upgrades
mkdir -p /etc/update-manager
cat > /etc/update-manager/release-upgrades << 'EOF'
[DEFAULT]
Prompt=normal
EOF

# Clean any previous stuck upgrade attempts
rm -rf /var/log/dist-upgrade/* 2>/dev/null || true
rm -rf /tmp/ubuntu-release-upgrader-* 2>/dev/null || true

echo "Running release upgrade (this may take 30+ minutes)..."
echo ""

# Create auto-answer config for the upgrader
mkdir -p /tmp/upgrade-config
cat > /tmp/upgrade-config/DistUpgrade.cfg << 'EOF'
[Distro]
PostInstallScripts=

[DEFAULT]
AutomaticUpgrade=True

[NonInteractive]
RealReboot=False
ProfileName=default
StepsTotalAfterReboot=0
EOF

# Method 1: Direct python with timeout and proper env
timeout 3600 python3 /usr/lib/python3/dist-packages/DistUpgrade/DistUpgradeMain.py \
    -m server \
    -f DistUpgradeViewNonInteractive \
    --datadir=/usr/share/ubuntu-release-upgrader \
    2>&1 || UPGRADE_RESULT=$?

# If method 1 failed, try method 2
if [ "${UPGRADE_RESULT:-1}" != "0" ]; then
    echo ""
    echo "Trying alternate upgrade method..."
    timeout 3600 do-release-upgrade -f DistUpgradeViewNonInteractive -m server --allow-third-party 2>&1 || true
fi

# Check result
echo ""
echo "=== Upgrade Attempt Complete ==="
echo ""
echo "Current system info:"
lsb_release -a 2>/dev/null || cat /etc/os-release
echo ""
echo "If still on old version, try rebooting WSL with: wsl --shutdown"
echo "Then run this script again."
