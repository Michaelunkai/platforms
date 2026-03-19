# ============================================================================
# WSL2 Ubuntu Complete Fix Script
# Achieves instant startup with Docker available for manual use
# ============================================================================
# Run as: powershell -ExecutionPolicy Bypass -File "F:\downloads\fix-wsl-ubuntu-complete.ps1"
# ============================================================================

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "WSL2 Ubuntu Complete Fix Script" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Create the bash fix script with Unix line endings
Write-Host "[1/6] Creating fix script..." -ForegroundColor Yellow

$bashScript = @'
#!/bin/bash
set -e

echo "============================================================================"
echo "WSL2 Ubuntu Complete Fix - Starting..."
echo "============================================================================"

# ============================================================================
# PART 1: Disable slow-starting services (keep them functional for manual use)
# ============================================================================
echo ""
echo "[1/5] Disabling auto-start services (keeping them available for manual use)..."

# Docker - disable auto-start but keep functional
systemctl disable docker.service docker.socket 2>/dev/null || true
systemctl stop docker.service docker.socket containerd.service 2>/dev/null || true

# Unmask so Docker CAN be started manually when needed
systemctl unmask docker.service docker.socket containerd.service 2>/dev/null || true

# Keep containerd enabled (Docker dependency) but it won't start without docker
systemctl enable containerd.service 2>/dev/null || true

# Mask services that cause delays and aren't needed
systemctl mask snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
systemctl mask networkd-wait-online.service systemd-networkd-wait-online.service 2>/dev/null || true
systemctl mask cloud-init.service cloud-init-local.service cloud-config.service cloud-final.service 2>/dev/null || true
systemctl mask multipathd.service multipathd.socket 2>/dev/null || true
systemctl mask ModemManager.service 2>/dev/null || true
systemctl mask plymouth-quit-wait.service plymouth-quit.service 2>/dev/null || true
systemctl mask apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

echo "   Services configured for fast startup"

# ============================================================================
# PART 2: Remove Docker auto-start scripts from profile.d
# ============================================================================
echo ""
echo "[2/5] Removing Docker auto-start scripts from profile.d..."

rm -f /etc/profile.d/docker-ensure.sh 2>/dev/null || true
rm -f /etc/profile.d/docker-start.sh 2>/dev/null || true
rm -f /etc/profile.d/docker*.sh 2>/dev/null || true

echo "   Removed Docker auto-start scripts"

# ============================================================================
# PART 3: Skip slow profile.d checks
# ============================================================================
echo ""
echo "[3/5] Skipping slow profile.d checks..."

# Skip locale check
mkdir -p /var/lib/cloud/instance
touch /var/lib/cloud/instance/locale-check.skip
touch ~/.cloud-locale-test.skip

echo "   Locale check skipped"

# ============================================================================
# PART 4: Fix /root/.profile to source .bashrc
# ============================================================================
echo ""
echo "[4/5] Fixing /root/.profile..."

cat > /root/.profile << 'PROFEOF'
# ~/.profile: executed by Bourne-compatible login shells.

# Source .bashrc if it exists and shell is interactive
if [ -n "$BASH" ] && [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

export XDG_RUNTIME_DIR=/run/user/0
PROFEOF

echo "   /root/.profile updated"

# ============================================================================
# PART 5: Add Docker convenience aliases and ensure PS1 is set
# ============================================================================
echo ""
echo "[5/5] Adding Docker aliases and ensuring PS1..."

# Check if Docker aliases already exist
if ! grep -q 'alias dockerstart=' /root/.bashrc 2>/dev/null; then
    echo '' >> /root/.bashrc
    echo '# Quick Docker start/stop (Docker disabled at boot for fast startup)' >> /root/.bashrc
    echo 'alias dockerstart="sudo systemctl start docker && echo Docker started"' >> /root/.bashrc
    echo 'alias dockerstop="sudo systemctl stop docker docker.socket containerd && echo Docker stopped"' >> /root/.bashrc
    echo "   Added dockerstart/dockerstop aliases"
else
    echo "   Docker aliases already exist"
fi

# Ensure RED and RESET are defined for PS1
if ! grep -q "^RED=" /root/.bashrc 2>/dev/null; then
    # Find a good place to add them (before PS1 if it exists)
    if grep -q "^PS1=" /root/.bashrc; then
        # Insert before PS1
        sed -i '/^PS1=/i RED='"'"'\\[\\033[0;31m\\]'"'"'\nRESET='"'"'\\[\\033[0m\\]'"'"'' /root/.bashrc
    else
        # Add at end with PS1
        echo '' >> /root/.bashrc
        echo '# Red prompt colors' >> /root/.bashrc
        echo "RED='\\[\\033[0;31m\\]'" >> /root/.bashrc
        echo "RESET='\\[\\033[0m\\]'" >> /root/.bashrc
        echo 'PS1="${RED}\u@\h:\w\$ ${RESET}"' >> /root/.bashrc
    fi
    echo "   Added RED/RESET color definitions"
fi

# ============================================================================
# PART 6: Configure static DNS (faster than waiting for DHCP)
# ============================================================================
echo ""
echo "[6/5] Configuring static DNS..."

# Prevent resolv.conf from being overwritten
if [ -L /etc/resolv.conf ]; then
    rm -f /etc/resolv.conf
fi

cat > /etc/resolv.conf << 'DNSEOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
DNSEOF

# Make it immutable so WSL doesn't overwrite it
chattr +i /etc/resolv.conf 2>/dev/null || true

echo "   Static DNS configured"

# ============================================================================
# PART 7: Clean up any Docker auto-start in bash.bashrc
# ============================================================================
echo ""
echo "[7/5] Cleaning Docker auto-start from bash.bashrc..."

# Remove any Docker auto-start blocks
sed -i '/# Docker auto-start/,/^fi$/d' /etc/bash.bashrc 2>/dev/null || true
sed -i '/docker ps/d' /etc/bash.bashrc 2>/dev/null || true

echo "   bash.bashrc cleaned"

# ============================================================================
# VERIFICATION
# ============================================================================
echo ""
echo "============================================================================"
echo "VERIFICATION"
echo "============================================================================"

echo ""
echo "Docker service status:"
systemctl is-enabled docker.service 2>/dev/null || echo "  docker.service: not found"
systemctl is-enabled docker.socket 2>/dev/null || echo "  docker.socket: not found"

echo ""
echo "Masked services (these won't auto-start):"
systemctl list-unit-files --state=masked 2>/dev/null | grep -E "snap|network.*wait|cloud|docker" | head -10 || true

echo ""
echo "Profile.d scripts (no docker scripts should exist):"
ls -la /etc/profile.d/*.sh 2>/dev/null | grep -v docker || echo "  (clean - no docker scripts)"

echo ""
echo "============================================================================"
echo "FIX COMPLETE!"
echo "============================================================================"
echo ""
echo "To start Docker when needed, use: dockerstart"
echo "To stop Docker when done, use:    dockerstop"
echo ""
echo "Now run: wsl --shutdown"
echo "Then:    wsl -d Ubuntu"
echo ""
'@

# Write bash script with Unix line endings (LF only)
$bashScript = $bashScript -replace "`r`n", "`n"
$bashScript = $bashScript -replace "`r", "`n"
[System.IO.File]::WriteAllText("F:\downloads\fix-wsl-complete.sh", $bashScript, [System.Text.UTF8Encoding]::new($false))

Write-Host "   Created: F:\downloads\fix-wsl-complete.sh" -ForegroundColor Green

# Step 2: Run the fix script in WSL
Write-Host ""
Write-Host "[2/6] Running fix script in WSL Ubuntu..." -ForegroundColor Yellow
wsl -d Ubuntu -u root -- bash /mnt/f/downloads/fix-wsl-complete.sh

# Step 3: Shutdown WSL
Write-Host ""
Write-Host "[3/6] Shutting down WSL for clean restart..." -ForegroundColor Yellow
wsl --shutdown
Start-Sleep -Seconds 3

# Step 4: Measure startup time
Write-Host ""
Write-Host "[4/6] Measuring cold startup time..." -ForegroundColor Yellow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
wsl -d Ubuntu -u root -- echo "WSL started"
$sw.Stop()
$startupTime = $sw.ElapsedMilliseconds
Write-Host "   Startup time: $startupTime ms" -ForegroundColor $(if ($startupTime -lt 5000) { "Green" } elseif ($startupTime -lt 10000) { "Yellow" } else { "Red" })

# Step 5: Verify Docker works manually
Write-Host ""
Write-Host "[5/6] Verifying Docker can be started manually..." -ForegroundColor Yellow
$dockerTest = wsl -d Ubuntu -u root -- bash -c "systemctl start docker 2>/dev/null && docker --version && systemctl stop docker docker.socket containerd 2>/dev/null && echo 'Docker OK'"
if ($dockerTest -match "Docker OK") {
    Write-Host "   Docker works when started manually" -ForegroundColor Green
} else {
    Write-Host "   Docker test: $dockerTest" -ForegroundColor Yellow
}

# Step 6: Final summary
Write-Host ""
Write-Host "[6/6] Verifying aliases..." -ForegroundColor Yellow
wsl -d Ubuntu -u root -- bash -c "source /root/.bashrc 2>/dev/null; type dockerstart 2>/dev/null && echo 'dockerstart alias: OK' || echo 'dockerstart alias: MISSING'"

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "COMPLETE! Summary:" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Startup time: $startupTime ms" -ForegroundColor $(if ($startupTime -lt 5000) { "Green" } elseif ($startupTime -lt 10000) { "Yellow" } else { "Red" })
Write-Host "  Docker: Disabled at boot, available via 'dockerstart' alias" -ForegroundColor Green
Write-Host "  Masked: snapd, cloud-init, networkd-wait, multipathd" -ForegroundColor Green
Write-Host "  DNS: Static (8.8.8.8, 1.1.1.1)" -ForegroundColor Green
Write-Host ""
Write-Host "Usage:" -ForegroundColor White
Write-Host "  wsl -d Ubuntu          # Fast startup" -ForegroundColor Gray
Write-Host "  dockerstart            # Start Docker when needed" -ForegroundColor Gray
Write-Host "  dockerstop             # Stop Docker when done" -ForegroundColor Gray
Write-Host ""
