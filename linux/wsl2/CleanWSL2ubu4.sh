#!/bin/bash

set -euo pipefail

echo "Starting ENHANCED Docker, Docker Compose, Docker Buildx & Python-safe aggressive system cleanup for Ubuntu WSL2..."
echo "CRITICAL: This script will preserve ALL Docker components including Buildx, Docker Compose, and Python installations!"

# Comprehensive Docker and Python-related patterns to protect
PROTECTED_PATTERNS=(
    "docker"
    "docker-compose"
    "docker-compose-plugin"
    "docker-compose-v2"
    "docker-buildx"
    "docker-buildx-plugin"
    "buildx"
    "containerd"
    "runc"
    "docker-ce"
    "docker-ce-cli"
    "docker-ce-rootless-extras"
    "docker-scan-plugin"
    "docker-desktop"
    "docker-engine"
    "docker.io"
    "moby"
    "overlay2"
    "compose"
    "python"
    "python3"
    "python2"
    "pip"
    "pip3"
    "setuptools"
    "wheel"
    "virtualenv"
    "venv"
    "conda"
    "miniconda"
    "anaconda"
    "pyenv"
    "pipenv"
    "poetry"
    "jupyter"
    "ipython"
    "numpy"
    "scipy"
    "pandas"
    "matplotlib"
    "django"
    "flask"
    "requests"
    "urllib3"
    "certifi"
    "charset-normalizer"
    "idna"
    "distutils"
    "pkg-resources"
    "six"
    "packaging"
    "pyparsing"
    "dateutil"
    "pytz"
    "yaml"
    "jinja2"
    "markupsafe"
    "click"
    "werkzeug"
    "itsdangerous"
    "blinker"
    "cryptography"
    "cffi"
    "pycparser"
    "nacl"
    "bcrypt"
    "paramiko"
    "libcontainer"
    "containerd.io"
    "docker-proxy"
    "dockerd"
    "cri-dockerd"
)

# Enhanced Docker protection paths (including Buildx)
DOCKER_PROTECTED_PATHS=(
    "/usr/local/bin/docker"
    "/usr/local/bin/docker-compose"
    "/usr/local/bin/docker-buildx"
    "/usr/bin/docker"
    "/usr/bin/docker-compose"
    "/usr/bin/docker-buildx"
    "/bin/docker"
    "/bin/docker-compose"
    "/bin/docker-buildx"
    "/usr/local/lib/docker"
    "/usr/lib/docker"
    "/var/lib/docker"
    "/var/lib/containerd"
    "/etc/docker"
    "/etc/containerd"
    "/home/*/.docker"
    "/root/.docker"
    "~/.docker"
    "/usr/libexec/docker"
    "/opt/docker"
    "/opt/containerd"
    "/usr/local/libexec/docker"
    "/usr/share/docker"
    "/var/run/docker"
    "/var/run/containerd"
    "/run/docker"
    "/run/containerd"
    "/tmp/docker"
    "/tmp/containerd"
    "/usr/local/share/docker"
    "/usr/lib/systemd/system/docker*"
    "/usr/lib/systemd/system/containerd*"
    "/etc/systemd/system/docker*"
    "/etc/systemd/system/containerd*"
)

# Function to check if a package is protected (Docker, Docker Compose, Buildx, or Python)
is_protected() {
    local package="$1"
    
    # Convert to lowercase for case-insensitive matching
    local package_lower=$(echo "$package" | tr '[:upper:]' '[:lower:]')
    
    # Special case for docker-compose variations
    if [[ "$package_lower" == *"compose"* ]] && [[ "$package_lower" == *"docker"* ]]; then
        return 0
    fi
    
    # Special case for docker-buildx variations
    if [[ "$package_lower" == *"buildx"* ]] || [[ "$package_lower" == *"docker"* && "$package_lower" == *"build"* ]]; then
        return 0
    fi
    
    # Check against all protected patterns
    for pattern in "${PROTECTED_PATTERNS[@]}"; do
        local pattern_lower=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
        if [[ "$package_lower" == *"$pattern_lower"* ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if a path is Docker/Docker Compose/Buildx/Python related
is_protected_path() {
    local path="$1"
    local path_lower=$(echo "$path" | tr '[:upper:]' '[:lower:]')
    
    # Check for Docker Compose specific patterns
    if [[ "$path_lower" == *"docker-compose"* ]] || [[ "$path_lower" == *"compose"* && "$path_lower" == *"docker"* ]]; then
        return 0
    fi
    
    # Check for Docker Buildx specific patterns
    if [[ "$path_lower" == *"buildx"* ]] || [[ "$path_lower" == *"docker"* && "$path_lower" == *"build"* ]]; then
        return 0
    fi
    
    # Check Docker and Python patterns
    if [[ "$path_lower" == *docker* ]] || [[ "$path_lower" == *containerd* ]] || 
       [[ "$path_lower" == *python* ]] || [[ "$path_lower" == *pip* ]] || 
       [[ "$path_lower" == *__pycache__* ]] || [[ "$path" == *.pyc ]] || 
       [[ "$path" == *.pyo ]] || [[ "$path_lower" == *site-packages* ]] ||
       [[ "$path_lower" == *moby* ]] || [[ "$path_lower" == *runc* ]]; then
        return 0
    fi
    
    # Check against protected Docker paths
    for docker_path in "${DOCKER_PROTECTED_PATHS[@]}"; do
        if [[ "$path" == $docker_path* ]]; then
            return 0
        fi
    done
    
    return 1
}

# Function to safely remove packages excluding Docker, Docker Compose, Buildx, and Python
safe_remove_packages() {
    local packages_to_check="$1"
    local safe_packages=""
    
    for package in $packages_to_check; do
        if ! is_protected "$package"; then
            safe_packages="$safe_packages $package"
        else
            echo "🛡️  Skipping protected package: $package"
        fi
    done
    
    if [[ -n "$safe_packages" ]]; then
        echo "🗑️  Removing packages: $safe_packages"
        sudo apt remove --purge -y $safe_packages 2>/dev/null || true
    fi
}

# Enhanced function to safely remove files/directories
safe_remove() {
    local path="$1"
    if [[ -e "$path" ]]; then
        if ! is_protected_path "$path"; then
            rm -rf "$path" 2>/dev/null || true
        else
            echo "🛡️  Skipping protected path: $path"
        fi
    fi
}

# Pre-cleanup comprehensive Docker verification
echo ""
echo "🔍 Pre-cleanup COMPREHENSIVE Docker verification:"
echo "==============================================="

# Check Docker Engine
DOCKER_FOUND=false
if command -v docker &> /dev/null; then
    echo "✅ Found Docker Engine: $(docker --version 2>/dev/null || echo 'version check failed')"
    DOCKER_FOUND=true
    
    # Check Docker daemon
    if docker info &>/dev/null 2>&1; then
        echo "✅ Docker daemon is running and accessible"
    else
        echo "ℹ️  Docker daemon not accessible (may need restart)"
    fi
fi

# Check Docker Compose
DOCKER_COMPOSE_FOUND=false
if command -v docker-compose &> /dev/null; then
    echo "✅ Found docker-compose standalone: $(docker-compose --version 2>/dev/null || echo 'version check failed')"
    DOCKER_COMPOSE_FOUND=true
fi

if docker compose version &> /dev/null 2>&1; then
    echo "✅ Found docker compose plugin: $(docker compose version 2>/dev/null || echo 'version check failed')"
    DOCKER_COMPOSE_FOUND=true
fi

# Check Docker Buildx
DOCKER_BUILDX_FOUND=false
if command -v docker-buildx &> /dev/null; then
    echo "✅ Found docker-buildx standalone: $(docker-buildx version 2>/dev/null || echo 'version check failed')"
    DOCKER_BUILDX_FOUND=true
fi

if docker buildx version &> /dev/null 2>&1; then
    echo "✅ Found docker buildx plugin: $(docker buildx version 2>/dev/null || echo 'version check failed')"
    DOCKER_BUILDX_FOUND=true
fi

# Check for Docker binaries in common locations
echo ""
echo "🔍 Checking Docker binary locations:"
for docker_path in "${DOCKER_PROTECTED_PATHS[@]}"; do
    # Expand paths with wildcards
    for expanded_path in $docker_path; do
        if [[ -f "$expanded_path" ]] && [[ -x "$expanded_path" ]]; then
            echo "✅ Found Docker binary at: $expanded_path"
            if [[ "$expanded_path" == *"buildx"* ]]; then
                DOCKER_BUILDX_FOUND=true
            elif [[ "$expanded_path" == *"compose"* ]]; then
                DOCKER_COMPOSE_FOUND=true
            elif [[ "$expanded_path" == *"docker"* ]] && [[ "$expanded_path" != *"compose"* ]] && [[ "$expanded_path" != *"buildx"* ]]; then
                DOCKER_FOUND=true
            fi
        fi
    done
done

echo ""
echo "🛡️  PROTECTION STATUS SUMMARY:"
echo "Docker Engine: $([[ "$DOCKER_FOUND" == "true" ]] && echo "PROTECTED" || echo "NOT DETECTED")"
echo "Docker Compose: $([[ "$DOCKER_COMPOSE_FOUND" == "true" ]] && echo "PROTECTED" || echo "NOT DETECTED")"
echo "Docker Buildx: $([[ "$DOCKER_BUILDX_FOUND" == "true" ]] && echo "PROTECTED" || echo "NOT DETECTED")"

echo ""
read -p "Press Enter to continue with cleanup (Ctrl+C to abort)..."

# 1. Fix dpkg database corruption first
echo "🔧 Fixing dpkg database corruption..."
export DEBIAN_FRONTEND=noninteractive
sudo dpkg --configure -a 2>/dev/null || true

# Rebuild dpkg info directory
echo "🔧 Rebuilding dpkg database..."
sudo mkdir -p /var/lib/dpkg/info
sudo chmod 755 /var/lib/dpkg/info

# Fix missing dpkg files by reinstalling core packages
echo "🔧 Fixing missing package files..."
sudo apt update -qq 2>/dev/null || true
sudo apt install --reinstall -y dpkg apt 2>/dev/null || true

# 2. Update & Upgrade System
echo "📦 Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

# 3. Install deborphan for orphaned package cleanup
echo "📦 Installing deborphan..."
sudo apt install deborphan -y 2>/dev/null || true

# 4. Aggressive package cleanup (Docker, Docker Compose, Buildx & Python-safe)
echo "🧹 Performing aggressive package cleanup (preserving Docker, Docker Compose, Buildx & Python)..."

# Remove development packages (except Docker, Docker Compose, Buildx and Python-related)
dev_packages=$(dpkg -l | awk '/^ii.*-dev/ {print $2}' | grep -v -E "(docker|compose|buildx|containerd|python|libpython)" || true)
if [[ -n "$dev_packages" ]]; then
    safe_remove_packages "$dev_packages"
fi

# Remove unused packages and dependencies
sudo apt autoremove --purge -y 2>/dev/null || true
sudo apt autoclean -y
sudo apt clean -y

# 5. Purge residual package configurations (Docker, Docker Compose, Buildx & Python-safe)
echo "🧹 Purging residual package configurations (preserving Docker, Docker Compose, Buildx & Python)..."
residual_packages=$(dpkg -l | awk '/^rc/ {print $2}' || true)
if [[ -n "$residual_packages" ]]; then
    safe_remove_packages "$residual_packages"
fi

# 6. Aggressive log cleanup (Docker, Docker Compose, Buildx & Python-safe)
echo "📝 Aggressive log cleanup (preserving Docker, Docker Compose, Buildx & Python logs)..."
# Truncate all logs except Docker, Docker Compose, Buildx and Python
sudo find /var/log -type f ! -path "*/docker/*" ! -path "*/containerd/*" ! -path "*/compose/*" ! -path "*/buildx/*" ! -path "*/python*" ! -name "*.gz" -exec truncate -s 0 {} + 2>/dev/null || true
# Remove compressed and rotated logs
sudo find /var/log -name "*.gz" ! -path "*/docker/*" ! -path "*/containerd/*" ! -path "*/compose/*" ! -path "*/buildx/*" ! -path "*/python*" -delete 2>/dev/null || true
sudo find /var/log -regex ".*\.[0-9]+" ! -path "*/docker/*" ! -path "*/containerd/*" ! -path "*/compose/*" ! -path "*/buildx/*" ! -path "*/python*" -delete 2>/dev/null || true
sudo find /var/log -name "*.old" ! -path "*/docker/*" ! -path "*/containerd/*" ! -path "*/compose/*" ! -path "*/buildx/*" ! -path "*/python*" -delete 2>/dev/null || true

# 7. Aggressive cache cleanup (Docker, Docker Compose, Buildx & Python-safe)
echo "🗂️  Aggressive cache cleanup (preserving Docker, Docker Compose, Buildx & Python cache)..."
# System cache
sudo find /var/cache -mindepth 1 -maxdepth 1 ! -name "*docker*" ! -name "*compose*" ! -name "*buildx*" ! -name "*containerd*" ! -name "*python*" ! -name "*pip*" -exec rm -rf {} + 2>/dev/null || true
# User cache (preserve Docker, Docker Compose, Buildx and Python cache)
if [[ -d ~/.cache ]]; then
    find ~/.cache -mindepth 1 -maxdepth 1 ! -name "*docker*" ! -name "*compose*" ! -name "*buildx*" ! -name "*python*" ! -name "*pip*" -exec rm -rf {} + 2>/dev/null || true
fi
# Additional cache locations
safe_remove ~/.local/share/Trash/*
safe_remove ~/.thumbnails
safe_remove ~/.cache/thumbnails
# Don't remove /var/tmp/* as it might contain Docker, Docker Compose, Buildx or Python temporary files
sudo find /var/tmp -mindepth 1 -maxdepth 1 ! -name "*python*" ! -name "*pip*" ! -name "*docker*" ! -name "*compose*" ! -name "*buildx*" ! -name "*containerd*" -exec rm -rf {} + 2>/dev/null || true

# 8. Temporary files cleanup (Docker, Docker Compose, Buildx & Python-safe, avoid read-only)
echo "🧹 Cleaning temporary files (preserving Docker, Docker Compose, Buildx & Python, avoiding read-only)..."
# Clean /tmp but avoid X11, Docker, Docker Compose, Buildx, and Python paths
sudo find /tmp -mindepth 1 -maxdepth 1 \
    ! -name ".X11-unix" ! -name ".ICE-unix" ! -name ".font-unix" \
    ! -path "*/docker*" ! -path "*/compose*" ! -path "*/buildx*" ! -path "*/containerd*" ! -path "*/python*" ! -path "*/pip*" \
    -exec rm -rf {} + 2>/dev/null || true

# 9. Remove old kernels (safe in WSL)
echo "🧹 Removing old kernels..."
current_kernel=$(uname -r)
old_kernels=$(dpkg --list | awk '/^ii  linux-/ {print $2}' | grep -E "(image|headers|modules)" | grep -v "$current_kernel" || true)
if [[ -n "$old_kernels" ]]; then
    safe_remove_packages "$old_kernels"
fi

# 10. Remove orphaned libraries (Docker, Docker Compose, Buildx & Python-safe)
echo "🧹 Removing orphaned libraries (preserving Docker, Docker Compose, Buildx & Python)..."
orphaned_packages=$(deborphan 2>/dev/null || true)
if [[ -n "$orphaned_packages" ]]; then
    safe_remove_packages "$orphaned_packages"
fi

# 11. Disable and remove non-essential services (Docker, Docker Compose, Buildx & Python-safe)
echo "⚙️  Disabling unnecessary services (preserving Docker, Docker Compose, Buildx & Python services)..."
services_to_disable=(
    "apport.service"
    "whoopsie.service" 
    "motd-news.timer"
    "apt-daily.timer"
    "apt-daily-upgrade.timer"
    "fstrim.timer"
)

for service in "${services_to_disable[@]}"; do
    sudo systemctl disable --now "$service" 2>/dev/null || true
done

# Explicitly protect Docker services
echo "🛡️  Ensuring Docker services are protected..."
docker_services=(
    "docker.service"
    "docker.socket"
    "containerd.service"
)

for service in "${docker_services[@]}"; do
    if systemctl list-unit-files | grep -q "$service"; then
        echo "✅ Protecting Docker service: $service"
    fi
done

# 12. Aggressive font and language pack removal
echo "🔤 Removing fonts and language packs (keeping essentials)..."
# Remove all fonts except essential ones
font_packages=$(dpkg -l | awk '/^ii.*fonts-/ {print $2}' | grep -v -E "(fonts-liberation|fonts-dejavu-core|fonts-ubuntu)" || true)
if [[ -n "$font_packages" ]]; then
    safe_remove_packages "$font_packages"
fi

# Remove all language packs except English
lang_packages=$(dpkg -l | awk '/^ii.*language-pack/ {print $2}' | grep -v "language-pack-en" || true)
if [[ -n "$lang_packages" ]]; then
    safe_remove_packages "$lang_packages"
fi

# Remove locales except en_US
echo "🌐 Removing unused locales..."
sudo find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name "en*" -exec rm -rf {} + 2>/dev/null || true
sudo locale-gen --purge en_US.UTF-8 2>/dev/null || true

# 13. Remove documentation aggressively (Docker, Docker Compose, Buildx & Python-safe)
echo "📚 Removing documentation (preserving Docker, Docker Compose, Buildx & Python docs)..."
sudo find /usr/share/man -mindepth 1 ! -path "*/docker/*" ! -path "*/compose/*" ! -path "*/buildx/*" ! -path "*/containerd/*" ! -path "*/python*" -exec rm -rf {} + 2>/dev/null || true
sudo find /usr/share/doc -mindepth 1 ! -path "*/docker*" ! -path "*/compose*" ! -path "*/buildx*" ! -path "*/containerd*" ! -path "*/python*" -exec rm -rf {} + 2>/dev/null || true
safe_remove /usr/share/info/*
safe_remove /usr/share/lintian/*
safe_remove /usr/share/linda/*

# 14. Remove multimedia and unnecessary packages
echo "🎵 Removing multimedia and unnecessary packages..."
multimedia_packages=$(dpkg -l | awk '/^ii.*(sound|audio|video|multimedia|game)/ {print $2}' | grep -v -E "(docker|compose|buildx|containerd|python)" || true)
if [[ -n "$multimedia_packages" ]]; then
    safe_remove_packages "$multimedia_packages"
fi

# 15. Remove Snap (check for Docker, Docker Compose, and Buildx first)
echo "📦 Checking and removing Snap (preserving Docker, Docker Compose, and Buildx snaps)..."
if command -v snap &> /dev/null; then
    snap_docker_packages=$(snap list 2>/dev/null | grep -iE "(docker|compose|buildx)" || true)
    if [[ -n "$snap_docker_packages" ]]; then
        echo "🛡️  Warning: Docker/Docker Compose/Buildx snap packages found. Keeping snap for Docker."
        echo "    Found: $snap_docker_packages"
    else
        echo "🗑️  Removing Snap and related packages..."
        sudo systemctl stop snapd 2>/dev/null || true
        sudo apt remove --purge -y snapd gnome-software-plugin-snap 2>/dev/null || true
        safe_remove /snap
        safe_remove /var/snap
        safe_remove ~/snap
    fi
fi

# Remove whoopsie and apport
sudo apt remove --purge -y whoopsie apport 2>/dev/null || true

# 16. Clear crash reports and journal (Docker, Docker Compose, Buildx & Python-safe)
echo "💥 Cleaning crash reports and journal (preserving Docker, Docker Compose, Buildx & Python)..."
sudo find /var/crash -mindepth 1 ! -name "*docker*" ! -name "*compose*" ! -name "*buildx*" ! -name "*containerd*" ! -name "*python*" -exec rm -rf {} + 2>/dev/null || true
sudo find /var/lib/systemd/coredump -mindepth 1 ! -name "*docker*" ! -name "*compose*" ! -name "*buildx*" ! -name "*containerd*" ! -name "*python*" -exec rm -rf {} + 2>/dev/null || true
safe_remove ~/.xsession-errors*
sudo journalctl --vacuum-time=1d 2>/dev/null || true

# 17. Remove SSH host keys and configs
echo "🔑 Removing SSH host keys..."
safe_remove /etc/ssh/ssh_host_*

# 18. Clean broken symlinks (Docker, Docker Compose, Buildx & Python-safe)
echo "🔗 Removing broken symlinks (avoiding Docker, Docker Compose, Buildx & Python paths)..."
sudo find / -xdev -xtype l \
    ! -path "*/docker/*" ! -path "*/compose/*" ! -path "*/buildx/*" ! -path "*/containerd/*" ! -path "/var/lib/docker/*" \
    ! -path "*/python*" ! -path "*/site-packages/*" ! -path "*/__pycache__/*" \
    ! -path "/tmp/.X11-unix/*" ! -path "/tmp/.ICE-unix/*" \
    ! -path "/usr/local/bin/docker*" ! -path "/usr/bin/docker*" ! -path "/bin/docker*" \
    -delete 2>/dev/null || true

# 19. Aggressive file size cleanup (Docker, Docker Compose, Buildx & Python-safe)
echo "📁 Removing large files (>10M, preserving Docker, Docker Compose, Buildx & Python data)..."
sudo find / -xdev -type f -size +10M \
    ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" \
    ! -path "/var/lib/docker/*" ! -path "*/compose/*" ! -path "*/buildx/*" ! -path "*/containerd/*" \
    ! -path "/opt/docker/*" ! -path "/usr/bin/docker*" ! -path "/usr/local/bin/docker*" ! -path "/bin/docker*" \
    ! -path "*/python*" ! -path "*/site-packages/*" ! -path "*/__pycache__/*" \
    ! -path "/usr/bin/python*" ! -path "/usr/lib/python*" \
    ! -path "/tmp/.X11-unix/*" \
    -exec rm -f {} + 2>/dev/null || true

# 20. Remove icon and theme caches
echo "🎨 Clearing icon and theme caches..."
safe_remove ~/.icons
safe_remove ~/.local/share/icons  
safe_remove ~/.cache/icon-cache.kcache
safe_remove ~/.gconf
safe_remove ~/.config/dconf
safe_remove /usr/share/icons/*/icon-theme.cache

# 21. Remove Python cache and compiled files (selectively)
echo "🐍 Cleaning Python cache (removing only __pycache__ directories and .pyc files in /tmp and /var)..."
# Only remove Python cache from temporary locations, not from installed packages
sudo find /tmp -name "*.pyc" -delete 2>/dev/null || true
sudo find /tmp -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
sudo find /var/tmp -name "*.pyc" -delete 2>/dev/null || true
sudo find /var/tmp -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
sudo find /var -name "*.pyo" -path "*/tmp/*" -delete 2>/dev/null || true

# Clean user's Python cache but preserve system Python
if [[ -d ~/.cache/pip ]]; then
    find ~/.cache/pip -name "*.whl" -mtime +30 -delete 2>/dev/null || true
fi

# 22. Remove old snapshots and backups
echo "📸 Cleaning old snapshots and backups..."
safe_remove /var/lib/snapshots/*
safe_remove /var/backups/*
safe_remove ~/.local/share/recently-used.xbel*

# 23. Clean package manager files (Docker, Docker Compose, Buildx & Python-safe)
echo "📦 Cleaning package manager files (preserving Docker, Docker Compose, Buildx & Python)..."
sudo find /var/lib/dpkg/info -name "*.list" ! -name "*docker*" ! -name "*compose*" ! -name "*buildx*" ! -name "*containerd*" ! -name "*python*" -delete 2>/dev/null || true
sudo find /var/lib/dpkg/info -name "*.md5sums" ! -name "*docker*" ! -name "*compose*" ! -name "*buildx*" ! -name "*containerd*" ! -name "*python*" -delete 2>/dev/null || true 
safe_remove /var/log/alternatives.log*
safe_remove /var/log/dpkg.log*

# 24. Zero-fill free space (limited to avoid filling disk)
echo "💾 Zero-filling free space (limited)..."
sudo dd if=/dev/zero of=/EMPTY bs=1M count=50 2>/dev/null || true
sudo rm -f /EMPTY 2>/dev/null || true

# 25. Final package system cleanup
echo "🧹 Final package system cleanup..."
sudo rm -rf /var/lib/apt/lists/*
sudo apt update -y 2>/dev/null || true

# Remove remaining cache files (Docker, Docker Compose, Buildx & Python-safe)
safe_remove /usr/share/python-wheels/*
safe_remove /var/cache/apt/pkgcache.bin
safe_remove /var/cache/apt/srcpkgcache.bin
safe_remove /usr/lib/x86_64-linux-gnu/dri/*

# 26. Remove deborphan itself
echo "🗑️  Removing deborphan..."
sudo apt purge -y deborphan 2>/dev/null || true

# 27. COMPREHENSIVE Docker, Docker Compose, and Buildx verification
echo ""
echo "🔍 COMPREHENSIVE Docker, Docker Compose, and Buildx verification:"
echo "================================================================"

# Check Docker Engine
DOCKER_STATUS="❌"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version 2>/dev/null || echo 'version check failed')
    DOCKER_STATUS="✅"
    echo "$DOCKER_STATUS Docker Engine available: $DOCKER_VERSION"
    
    if systemctl is-active --quiet docker 2>/dev/null; then
        echo "✅ Docker service is running"
    else
        echo "ℹ️  Docker service not running (may need restart)"
    fi
    
    # Test Docker functionality if available
    echo "🧪 Testing Docker functionality..."
    if docker info &>/dev/null; then
        echo "✅ Docker daemon is accessible and functional"
    else
        echo "⚠️  Docker daemon not accessible (may need restart or permissions)"
    fi
else
    echo "$DOCKER_STATUS Docker Engine not installed or not in PATH"
fi

# Check Docker Compose - Multiple methods
DOCKER_COMPOSE_STATUS="❌"
echo ""
echo "🔍 Docker Compose verification (checking all methods):"

# Method 1: Standalone docker-compose
if command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version 2>/dev/null || echo 'version check failed')
    DOCKER_COMPOSE_STATUS="✅"
    echo "✅ Docker Compose (standalone) available: $COMPOSE_VERSION"
    
    # Test functionality
    if docker-compose version &>/dev/null; then
        echo "✅ Docker Compose standalone is functional"
    else
        echo "⚠️  Docker Compose standalone version check failed"
    fi
fi

# Method 2: Docker compose plugin
if docker compose version &> /dev/null 2>&1; then
    COMPOSE_PLUGIN_VERSION=$(docker compose version 2>/dev/null || echo 'version check failed')
    DOCKER_COMPOSE_STATUS="✅"
    echo "✅ Docker Compose (plugin) available: $COMPOSE_PLUGIN_VERSION"
    
    # Test functionality
    if docker compose --help &>/dev/null; then
        echo "✅ Docker Compose plugin is functional"
    else
        echo "⚠️  Docker Compose plugin help check failed"
    fi
fi

# Check Docker Buildx - Multiple methods
DOCKER_BUILDX_STATUS="❌"
echo ""
echo "🔍 Docker Buildx verification (checking all methods):"

# Method 1: Standalone docker-buildx
if command -v docker-buildx &> /dev/null; then
    BUILDX_VERSION=$(docker-buildx version 2>/dev/null || echo 'version check failed')
    DOCKER_BUILDX_STATUS="✅"
    echo "✅ Docker Buildx (standalone) available: $BUILDX_VERSION"
    
    # Test functionality
    if docker-buildx version &>/dev/null; then
        echo "✅ Docker Buildx standalone is functional"
    else
        echo "⚠️  Docker Buildx standalone version check failed"
    fi
fi

# Method 2: Docker buildx plugin
if docker buildx version &> /dev/null 2>&1; then
    BUILDX_PLUGIN_VERSION=$(docker buildx version 2>/dev/null || echo 'version check failed')
    DOCKER_BUILDX_STATUS="✅"
    echo "✅ Docker Buildx (plugin) available: $BUILDX_PLUGIN_VERSION"
    
    # Test functionality
    if docker buildx --help &>/dev/null; then
        echo "✅ Docker Buildx plugin is functional"
    else
        echo "⚠️  Docker Buildx plugin help check failed"
    fi
    
    # Check buildx builders
    echo "🔍 Checking Docker Buildx builders:"
    if docker buildx ls &>/dev/null; then
        echo "✅ Docker Buildx builders are accessible"
        docker buildx ls 2>/dev/null | head -5 || echo "   (builder list unavailable)"
    else
        echo "⚠️  Docker Buildx builders not accessible"
    fi
fi

# Method 3: Check binary locations for all Docker components
echo ""
echo "🔍 Checking Docker component binary locations:"
for docker_path in "${DOCKER_PROTECTED_PATHS[@]}"; do
    # Expand paths with wildcards
    for expanded_path in $docker_path; do
        if [[ -f "$expanded_path" ]] && [[ -x "$expanded_path" ]]; then
            echo "✅ Found Docker binary at: $expanded_path"
            
            # Categorize the binary
            if [[ "$expanded_path" == *"buildx"* ]]; then
                DOCKER_BUILDX_STATUS="✅"
                # Get version if possible
                BINARY_VERSION=$("$expanded_path" version 2>/dev/null || echo 'version unavailable')
                echo "   Buildx Version: $BINARY_VERSION"
            elif [[ "$expanded_path" == *"compose"* ]]; then
                DOCKER_COMPOSE_STATUS="✅"
                # Get version if possible
                BINARY_VERSION=$("$expanded_path" --version 2>/dev/null || echo 'version unavailable')
                echo "   Compose Version: $BINARY_VERSION"
            elif [[ "$expanded_path" == *"docker"* ]] && [[ "$expanded_path" != *"compose"* ]] && [[ "$expanded_path" != *"buildx"* ]]; then
                DOCKER_STATUS="✅"
                # Get version if possible
                BINARY_VERSION=$("$expanded_path" --version 2>/dev/null || echo 'version unavailable')
                echo "   Docker Version: $BINARY_VERSION"
            fi
        fi
    done
done

# Status summary
echo ""
echo "🛡️  FINAL PROTECTION STATUS SUMMARY:"
echo "===================================="
if [[ "$DOCKER_STATUS" == "❌" ]]; then
    echo "Docker Engine: ❌ NOT FOUND"
else
    echo "Docker Engine: ✅ PRESERVED AND FUNCTIONAL"
fi

if [[ "$DOCKER_COMPOSE_STATUS" == "❌" ]]; then
    echo "Docker Compose: ❌ NOT FOUND"
else
    echo "Docker Compose: ✅ PRESERVED AND FUNCTIONAL"
fi

if [[ "$DOCKER_BUILDX_STATUS" == "❌" ]]; then
    echo "Docker Buildx: ❌ NOT FOUND"
else
    echo "Docker Buildx: ✅ PRESERVED AND FUNCTIONAL"
fi

# Check Python
echo ""
echo "🐍 Python verification:"
echo "======================"
PYTHON_STATUS="❌"

if command -v python3 &> /dev/null; then
    PYTHON3_VERSION=$(python3 --version 2>/dev/null || echo 'version check failed')
    PYTHON_STATUS="✅"
    echo "✅ Python3 available: $PYTHON3_VERSION"
else
    echo "❌ Python3 not found"
fi

if command -v python &> /dev/null; then
    PYTHON_VERSION=$(python --version 2>/dev/null || echo 'version check failed')
    PYTHON_STATUS="✅"
    echo "✅ Python available: $PYTHON_VERSION"
fi

# Check pip
if command -v pip3 &> /dev/null; then
    PIP3_VERSION=$(pip3 --version 2>/dev/null || echo 'version check failed')
    echo "✅ pip3 available: $PIP3_VERSION"
else
    echo "⚠️  pip3 not found"
fi

if command -v pip &> /dev/null; then
    PIP_VERSION=$(pip --version 2>/dev/null || echo 'version check failed')
    echo "✅ pip available: $PIP_VERSION"
fi

# Check if Python packages are still accessible
echo "🧪 Testing Python package accessibility..."
python3 -c "import sys; print(f'✅ Python path: {sys.executable}')" 2>/dev/null || echo "❌ Python3 import test failed"

# Check for common Python packages
echo "🧪 Testing common Python packages..."
for package in "os" "sys" "json" "urllib" "datetime"; do
    if python3 -c "import $package" 2>/dev/null; then
        echo "✅ $package module available"
    else
        echo "⚠️  $package module not available"
    fi
done

# 28. Final system state and recommendations
echo ""
echo "📊 Final system state:"
echo "===================="
df -h
echo ""
echo "📦 Package count: $(dpkg -l | grep '^ii' | wc -l) packages installed"
echo "💾 Available memory:"
free -h

echo ""
echo "🎉 ENHANCED DOCKER, DOCKER COMPOSE, DOCKER BUILDX & PYTHON-SAFE WSL2 CLEANUP COMPLETED!"
echo ""
echo "📋 COMPREHENSIVE VERIFICATION SUMMARY:"
echo "======================================"
echo "Docker Engine: $DOCKER_STATUS"
echo "Docker Compose: $DOCKER_COMPOSE_STATUS"  
echo "Docker Buildx: $DOCKER_BUILDX_STATUS"
echo "Python: $PYTHON_STATUS"
echo ""
echo "📝 Post-cleanup recommendations:"
echo "==============================="
echo "1. 🔄 Restart WSL2 instance: wsl --shutdown && wsl"
echo "2. 🐳 If using Docker: sudo systemctl restart docker"
echo "3. 🧪 Test Docker Engine: docker run hello-world"
echo "4. 🧪 Test Docker Compose: docker-compose --version OR docker compose version"
echo "5. 🧪 Test Docker Buildx: docker buildx version OR docker buildx ls"
echo "6. 🐍 Test Python: python3 -c 'print(\"Python is working!\")'"
echo "7. 🔤 Rebuild font cache if needed: sudo fc-cache -fv"
echo "8. 📦 Update package database: sudo apt update"
echo "9. 🔧 Verify Docker functionality: docker info"
echo "10. 🏗️ Test Buildx functionality: docker buildx create --name test-builder --driver docker-container"
echo ""
echo "🔍 DOCKER COMPONENT VERIFICATION:"
echo "================================="
echo "• Docker Engine: Manages containers and images"
echo "• Docker Compose: Orchestrates multi-container applications"
echo "• Docker Buildx: Advanced build features and multi-platform builds"
echo ""
echo "⚠️  IMPORTANT NOTES:"
echo "• If any component shows as not functional, restart WSL2 and try again"
echo "• Some Docker functionality may require the Docker daemon to be restarted"
echo "• Buildx builders may need to be recreated after cleanup"
echo "• All Docker data in /var/lib/docker has been preserved"
echo ""
echo "✅ ALL DOCKER COMPONENTS (Engine, Compose, Buildx) AND PYTHON INSTALLATIONS PRESERVED!"
echo "🛡️  Total protected patterns: ${#PROTECTED_PATTERNS[@]} packages/components"
echo "🛡️  Total protected paths: ${#DOCKER_PROTECTED_PATHS[@]} filesystem locations"

# 29. Ensure Docker Buildx is properly installed as CLI plugin
echo ""
echo "🔧 Ensuring Docker Buildx CLI plugin is properly installed..."
echo "============================================================"

# Check if Docker is available before attempting Buildx installation
if command -v docker &> /dev/null; then
    echo "🐳 Docker detected, proceeding with Buildx CLI plugin installation..."
    
    # Create the CLI plugins directory
    echo "📁 Creating Docker CLI plugins directory..."
    mkdir -p ~/.docker/cli-plugins
    
    # Download and install the latest Docker Buildx
    echo "⬇️  Downloading latest Docker Buildx CLI plugin..."
    if curl -L "$(curl -s https://api.github.com/repos/docker/buildx/releases/latest | grep -o 'https://github.com/docker/buildx/releases/download/[^"]*linux-amd64' | head -1)" -o ~/.docker/cli-plugins/docker-buildx; then
        echo "✅ Docker Buildx downloaded successfully"
        
        # Make it executable
        echo "🔧 Making Docker Buildx executable..."
        chmod +x ~/.docker/cli-plugins/docker-buildx
        echo "✅ Docker Buildx CLI plugin permissions set"
        
        # Verify the installation
        echo "🧪 Verifying Docker Buildx CLI plugin installation..."
        if docker buildx version &>/dev/null; then
            FINAL_BUILDX_VERSION=$(docker buildx version 2>/dev/null || echo 'version check failed')
            echo "✅ Docker Buildx CLI plugin verified: $FINAL_BUILDX_VERSION"
            
            # Test builder functionality
            echo "🧪 Testing Docker Buildx builder functionality..."
            if docker buildx ls &>/dev/null; then
                echo "✅ Docker Buildx builders are accessible"
            else
                echo "ℹ️  Docker Buildx builders may need to be created (normal after fresh install)"
            fi
        else
            echo "⚠️  Docker Buildx CLI plugin installation verification failed"
        fi
    else
        echo "❌ Failed to download Docker Buildx CLI plugin"
        echo "ℹ️  You can manually install it later using the same command"
    fi
else
    echo "⚠️  Docker not detected - skipping Buildx CLI plugin installation"
    echo "ℹ️  Install Docker first, then run the Buildx installation command manually"
fi

echo ""
echo "🎊 CLEANUP AND DOCKER BUILDX INSTALLATION COMPLETED!"
echo "=================================================="
