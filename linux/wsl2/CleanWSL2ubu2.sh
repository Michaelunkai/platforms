#!/bin/bash

set -euo pipefail

echo "Starting deep system cleanup for Ubuntu WSL2..."

# 1. Update & Upgrade System
echo "Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

# 2. Install deborphan for orphaned package cleanup
echo "Installing deborphan..."
sudo apt install deborphan -y

# 3. Remove unused packages and dependencies
echo "Removing unused packages and dependencies..."
sudo apt autoremove --purge -y
sudo apt autoclean -y
sudo apt clean -y

# 4. Purge residual package configurations
echo "Purging residual package configurations..."
export DEBIAN_FRONTEND=noninteractive
sudo dpkg --configure -a
sudo dpkg -l | awk '/^rc/ {print $2}' | xargs -r sudo apt purge -y

# 5. Clear logs, cache, temp
echo "Clearing logs, cache, and temporary files..."
sudo find /var/log -type f -exec truncate -s 0 {} +
sudo find /var/log -name "*.gz" -exec rm -f {} +
sudo find /var/log -regex ".*\.[0-9]+" -exec rm -f {} +
sudo rm -rf /var/cache/*
sudo rm -rf ~/.cache/* ~/.local/share/Trash/* ~/.cache/thumbnails/*
sudo rm -rf /tmp/* /var/tmp/*

# 6. Remove old kernels (safe in WSL)
echo "Removing old kernels..."
sudo apt remove --purge -y $(dpkg --list | awk '/^ii  linux-image-[0-9]/{print $2}' | grep -v $(uname -r)) || true

# 7. Remove orphaned libraries
echo "Removing orphaned libraries..."
sudo deborphan | xargs -r sudo apt-get -y remove --purge

# 8. Disable and remove non-essential services
echo "Disabling unnecessary services..."
sudo systemctl disable --now apport.service || true
sudo systemctl disable --now whoopsie || true
sudo systemctl disable --now motd-news.timer || true
sudo systemctl disable --now unattended-upgrades || true

# 9. Remove fonts and language packs
echo "Removing fonts and language packs..."
sudo apt remove --purge -y fonts-* language-pack-*

# 10. Remove documentation
echo "Removing manuals, docs, and info pages..."
sudo rm -rf /usr/share/man/* /usr/share/doc/* /usr/share/info/* /usr/share/lintian/* /usr/share/linda/*

# 11. Remove Snap and whoopsie
echo "Removing Snap and whoopsie..."
sudo systemctl stop snapd || true
sudo apt-get remove --purge -y snapd whoopsie

# 12. Clear crash reports and journal
echo "Cleaning orphaned logs and crash reports..."
sudo rm -rf /var/crash/* /var/lib/systemd/coredump/* /var/lib/apport/coredump/* ~/.xsession-errors*
sudo journalctl --vacuum-time=1d

# 13. Remove temporary SSH host keys
echo "Removing SSH host keys..."
sudo rm -rf /etc/ssh/ssh_host_*

# 14. Clean broken symlinks
echo "Removing broken symlinks..."
sudo find / -xdev -xtype l -delete

# 15. Clean thumbnail cache
echo "Removing thumbnail cache..."
sudo rm -rf ~/.thumbnails ~/.cache/thumbnails

# 16. Remove unused locales
echo "Removing unused locales..."
sudo locale-gen --purge en_US.UTF-8

# 17. Auto-delete large unused files over 50M
echo "Deleting large files (>50M)..."
sudo find / -xdev -type f -size +50M ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" -exec rm -f {} +

# 18. Clear icon cache
echo "Clearing icon cache..."
rm -rf ~/.icons ~/.local/share/icons ~/.cache/icon-cache.kcache

# 19. Remove old snapshots
echo "Cleaning old system snapshots..."
sudo rm -rf /var/lib/snapshots/* || true

# 20. Zero-fill disk
echo "Zero-filling disk space..."
sudo dd if=/dev/zero of=/EMPTY bs=1M || true
sudo rm -f /EMPTY

# 21. Optional defragment
if command -v e4defrag &> /dev/null; then
    echo "Defragmenting filesystem..."
    sudo e4defrag /
fi

# 22. Rebuild APT cache
echo "Rebuilding package lists..."
sudo rm -rf /var/lib/apt/lists/*
sudo apt update -y

# 23. Disk space check
echo "Final disk space usage:"
df -h

# 24. Remove leftover dpkg and cache
echo "Removing leftover dpkg and cache files..."
sudo rm -rf /var/lib/dpkg/info/* /var/lib/apt/lists/* /var/lib/polkit-1/*
sudo rm -rf /var/log/alternatives.log /usr/lib/x86_64-linux-gnu/dri/*
sudo rm -rf /usr/share/python-wheels/* /var/cache/apt/pkgcache.bin /var/cache/apt/srcpkgcache.bin

# 25. Remove deborphan
echo "Purging deborphan..."
sudo apt purge -y deborphan

echo "✅ Deep WSL2 cleanup completed successfully!"

