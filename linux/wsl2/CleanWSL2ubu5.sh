#!/bin/bash
set -euo pipefail

# Set non-interactive mode for all apt operations
export DEBIAN_FRONTEND=noninteractive

echo "🚨 ULTRA AGGRESSIVE WSL2 CLEANUP - THIS WILL REMOVE ALMOST EVERYTHING NON-ESSENTIAL! 🚨"
echo "Press Ctrl+C within 10 seconds to abort..."
sleep 10

echo "Starting nuclear-level system cleanup for Ubuntu WSL2..."

# 1. Update & Upgrade System
echo "Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

# 2. Install tools needed for cleanup
echo "Installing cleanup tools..."
sudo apt install -y deborphan || echo "deborphan installation failed, continuing..."
sudo apt install -y bleachbit || echo "bleachbit installation failed, continuing..."

# 3. Remove ALL non-essential packages aggressively
echo "Removing non-essential packages..."
sudo apt autoremove --purge -y
sudo apt autoclean -y
sudo apt clean -y

# 4. Remove development tools and compilers (if you don't need them)
echo "Removing development tools and compilers..."
sudo apt remove --purge -y build-essential gcc g++ make cmake autotools-dev automake autoconf libtool pkg-config || true
sudo apt remove --purge -y gdb valgrind strace ltrace || true
sudo apt remove --purge -y python3-dev python-dev-is-python3 || true

# 5. Remove multimedia and graphics packages
echo "Removing multimedia and graphics packages..."
sudo apt remove --purge -y '*-dev' '*-doc' '*-dbg' || true
sudo apt remove --purge -y gimp* vlc* firefox* thunderbird* libreoffice* || true

# 6. Purge ALL residual package configurations
echo "Purging ALL residual package configurations..."
sudo dpkg --configure -a
sudo dpkg -l | awk '/^rc/ {print $2}' | xargs -r sudo apt purge -y

# 7. NUCLEAR log cleanup - remove EVERYTHING
echo "NUCLEAR log cleanup..."
sudo systemctl stop rsyslog || true
sudo systemctl stop systemd-journald || true
sudo rm -rf /var/log/* /var/log/.* 2>/dev/null || true
sudo mkdir -p /var/log
sudo systemctl start systemd-journald || true
sudo systemctl start rsyslog || true
sudo journalctl --vacuum-size=1M

# 8. Remove ALL cache and temporary files
echo "Removing ALL cache and temporary files..."
sudo rm -rf /var/cache/* /tmp/* /var/tmp/* ~/.cache/* ~/.local/share/Trash/* 2>/dev/null || true
sudo rm -rf /var/spool/* /var/mail/* /var/backups/* 2>/dev/null || true
sudo rm -rf /root/.cache/* /home/*/.cache/* 2>/dev/null || true

# 9. Remove ALL documentation, manuals, and info pages
echo "Removing ALL documentation..."
sudo rm -rf /usr/share/man/* /usr/share/doc/* /usr/share/info/* 2>/dev/null || true
sudo rm -rf /usr/share/lintian/* /usr/share/linda/* /usr/share/gtk-doc/* 2>/dev/null || true
sudo rm -rf /usr/share/help/* /usr/share/gnome/help/* 2>/dev/null || true

# 10. Remove ALL fonts except basic ones
echo "Removing ALL fonts except essential..."
sudo apt remove --purge -y fonts-* || true
sudo rm -rf /usr/share/fonts/* /usr/local/share/fonts/* ~/.fonts/* 2>/dev/null || true

# 11. Remove ALL language packs and locales except English
echo "Removing ALL non-English locales..."
sudo apt remove --purge -y language-pack-* language-support-* || true
# Manual locale cleanup instead of localepurge
sudo rm -rf /usr/share/locale/* 2>/dev/null || true
sudo mkdir -p /usr/share/locale/en_US.UTF-8/LC_MESSAGES
echo "en_US.UTF-8 UTF-8" | sudo tee /etc/locale.gen > /dev/null
sudo locale-gen --purge en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8

# 12. Remove examples, samples, and templates
echo "Removing examples and samples..."
sudo rm -rf /usr/share/pixmaps/* /usr/share/applications/* 2>/dev/null || true
sudo rm -rf /etc/skel/* /usr/share/base-files/* 2>/dev/null || true
sudo rm -rf /usr/share/common-licenses/* 2>/dev/null || true

# 13. Remove old kernels and modules
echo "Removing old kernels and unused modules..."
sudo apt remove --purge -y $(dpkg --list | awk '/^ii  linux-image-[0-9]/{print $2}' | grep -v $(uname -r)) || true
sudo rm -rf /lib/modules/*/kernel/drivers/gpu/* 2>/dev/null || true
sudo rm -rf /lib/modules/*/kernel/drivers/media/* 2>/dev/null || true
sudo rm -rf /lib/modules/*/kernel/drivers/staging/* 2>/dev/null || true

# 14. Remove orphaned libraries aggressively
echo "Removing orphaned libraries..."
while sudo deborphan | grep -q .; do
    sudo deborphan | xargs -r sudo apt-get -y remove --purge
done

# 15. Remove firmware for hardware not in WSL
echo "Removing unnecessary firmware..."
sudo rm -rf /lib/firmware/* 2>/dev/null || true

# 16. Disable and remove ALL non-essential services
echo "Disabling unnecessary services..."
services_to_disable=(
    "apport.service" "whoopsie" "motd-news.timer" "unattended-upgrades"
    "bluetooth" "cups" "avahi-daemon" "ModemManager" "NetworkManager-wait-online"
    "systemd-resolved" "accounts-daemon" "udisks2" "packagekit"
)
for service in "${services_to_disable[@]}"; do
    sudo systemctl disable --now "$service" 2>/dev/null || true
    sudo apt remove --purge -y "$service" 2>/dev/null || true
done

# 17. Remove Snap completely
echo "Completely removing Snap..."
sudo systemctl stop snapd snapd.socket 2>/dev/null || true
sudo apt remove --purge -y snapd squashfs-tools 2>/dev/null || true
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd 2>/dev/null || true

# 18. Clean ALL crash reports and dumps
echo "Removing crash reports..."
sudo rm -rf /var/crash/* /var/lib/systemd/coredump/* /var/lib/apport/coredump/* 2>/dev/null || true
sudo rm -rf ~/.xsession-errors* /tmp/crash* 2>/dev/null || true

# 19. Remove SSH host keys and configs
echo "Removing SSH keys..."
sudo rm -rf /etc/ssh/ssh_host_* ~/.ssh/known_hosts 2>/dev/null || true

# 20. Remove ALL broken symlinks system-wide
echo "Removing broken symlinks..."
sudo find / -xdev -xtype l -delete 2>/dev/null || true

# 21. Remove thumbnail and icon caches
echo "Removing thumbnail and icon caches..."
sudo rm -rf ~/.thumbnails ~/.cache/thumbnails ~/.icons ~/.local/share/icons 2>/dev/null || true
sudo rm -rf /usr/share/icons/* /usr/share/pixmaps/* 2>/dev/null || true

# 22. ULTRA AGGRESSIVE: Delete large files over 10M
echo "Deleting ALL large files over 10M..."
sudo find / -xdev -type f -size +10M ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" ! -path "/mnt/*" -exec rm -f {} + 2>/dev/null || true

# 23. Remove Python wheels and caches
echo "Removing Python caches..."
sudo rm -rf /usr/share/python-wheels/* /usr/lib/python*/dist-packages/__pycache__/* 2>/dev/null || true
sudo find / -name "*.pyc" -delete 2>/dev/null || true
sudo find / -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# 24. Remove Perl and other interpreter modules
echo "Removing interpreter modules..."
sudo rm -rf /usr/share/perl5/* /usr/lib/x86_64-linux-gnu/perl5/* 2>/dev/null || true

# 25. Remove ALL database files and indexes
echo "Removing database files..."
sudo rm -rf /var/lib/mlocate/* /var/lib/apt/lists/* /var/lib/dpkg/info/* 2>/dev/null || true

# 26. Remove systemd and journal logs completely
echo "Removing systemd logs..."
sudo rm -rf /var/lib/systemd/catalog/* /var/lib/systemd/timers/* 2>/dev/null || true

# 27. Remove ALL backup and rotated files
echo "Removing backup files..."
sudo find / -name "*.bak" -o -name "*.backup" -o -name "*~" -o -name "*.old" -delete 2>/dev/null || true
sudo find / -name "*.dpkg-old" -o -name "*.dpkg-new" -o -name "*.ucf-old" -delete 2>/dev/null || true

# 28. Remove hardware detection databases
echo "Removing hardware databases..."
sudo rm -rf /usr/share/misc/* /var/lib/usbutils/* /var/lib/pci.ids* 2>/dev/null || true

# 29. Remove ALL test and example files
echo "Removing test files..."
sudo find /usr -name "*test*" -type f -delete 2>/dev/null || true
sudo find /usr -name "*example*" -type f -delete 2>/dev/null || true
sudo find /usr -name "*sample*" -type f -delete 2>/dev/null || true

# 30. Remove empty directories
echo "Removing empty directories..."
sudo find / -xdev -type d -empty -delete 2>/dev/null || true

# 31. Clear ALL package caches and rebuild minimal lists
echo "Rebuilding minimal package lists..."
sudo rm -rf /var/lib/apt/lists/* /var/cache/apt/* 2>/dev/null || true
sudo apt update -y

# 32. Remove cleanup tools we just used
echo "Removing cleanup tools..."
sudo apt remove --purge -y deborphan bleachbit 2>/dev/null || true

# 33. Final aggressive cleanup
echo "Final cleanup pass..."
sudo apt autoremove --purge -y
sudo apt autoclean -y
sudo apt clean -y

# 34. Zero out free space (optional - takes time but maximizes space)
echo "Would you like to zero out free space? This takes time but ensures maximum cleanup. (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Zeroing out free space..."
    sudo dd if=/dev/zero of=/tmp/zero.tmp bs=1M || true
    sudo rm -f /tmp/zero.tmp
fi

# 35. Final disk space check
echo "Final disk space usage:"
df -h

echo ""
echo "🚀 ULTRA AGGRESSIVE WSL2 cleanup completed!"
echo "⚠️  Warning: Many features may be broken. You may need to reinstall packages as needed."
echo "💾 You should have maximum free space now!"
echo ""
echo "To rebuild essentials if needed:"
echo "sudo apt update && sudo apt install ubuntu-minimal"
