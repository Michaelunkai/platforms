#!/usr/bin/env bash
###############################################################################
# fix_docker_wsl2.sh
#  - Phase 0: nuclear purge of ALL Docker artefacts
#  - Phase 1: deep WSL2 cleanup  (user-supplied)
#  - Phase 2: clean, conflict-free install (≤3 attempts)
# 2025-06-30
###############################################################################
set -euo pipefail
IFS=$'\n\t'
green(){ printf "\033[0;32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[1;33m%s\033[0m\n" "$*"; }
red(){ printf "\033[0;31m%s\033[0m\n" "$*"; }
die(){ red "[FAIL] $*"; exit 1; }
msg(){ green "[INFO] $*"; }
wrn(){ yellow "[WARN] $*"; }
retry(){ local n=0; until "$@"; do ((n++>3))&&return 1; sleep 2; wrn "retry $n/3: $*"; done; }

[[ $EUID -eq 0 ]] || die "Run with sudo."
grep -qi microsoft /proc/version || die "Not running in WSL2."

DISTRO=$(lsb_release -sc)              # jammy / noble …
ARCH=$(dpkg --print-architecture)      # amd64 / arm64 …
TARGET_USER=${SUDO_USER:-$(logname 2>/dev/null || echo root)}

###############################################################################
### Phase-0 : wipe EVERY Docker trace
###############################################################################
msg "Phase-0: purging all Docker artefacts"
{
  systemctl stop docker.service docker.socket containerd.service 2>/dev/null || true
  pkill -f dockerd-wsl2-wrapper 2>/dev/null || true
  pkill -f dockerd 2>/dev/null || true

  retry apt-get remove --purge -y docker\* containerd.io runc || true

  rm -rf /var/lib/docker /var/lib/containerd /run/containerd \
         /var/run/docker.sock /etc/docker /etc/containerd \
         /usr/libexec/docker /usr/lib/docker /var/log/dockerd-wsl2.log

  rm -f /etc/systemd/system/docker.service.d/override.conf
  rm -f /etc/systemd/system/docker.service /lib/systemd/system/docker.service
  rm -f /etc/systemd/system/docker.socket  /lib/systemd/system/docker.socket
  rm -f /etc/systemd/system/containerd.service /lib/systemd/system/containerd.service

  rm -f /usr/local/bin/dockerd-wsl2-wrapper
  sed -i '/dockerd-wsl2-wrapper/d' /etc/wsl.conf 2>/dev/null || true

  rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
  getent group docker &>/dev/null && groupdel docker || true
  rm -rf /home/*/.docker /root/.docker
} || true
msg "Docker artefacts purged."

###############################################################################
### Phase-1 : deep system cleanup (verbatim)
###############################################################################
echo "Starting deep system cleanup for Ubuntu WSL2…"
sudo apt update -y && sudo apt upgrade -y
sudo apt install deborphan -y
sudo apt autoremove --purge -y
sudo apt autoclean -y
sudo apt clean -y
export DEBIAN_FRONTEND=noninteractive
sudo dpkg --configure -a
sudo dpkg -l | awk '/^rc/{print $2}' | xargs -r sudo apt purge -y
sudo find /var/log -type f -exec truncate -s0 {} +
sudo find /var/log -name "*.gz" -delete
sudo find /var/log -regextype posix-extended -regex '.*/[0-9]+' -delete
sudo rm -rf /var/cache/* ~/.cache/* ~/.local/share/Trash/* ~/.cache/thumbnails/*
sudo rm -rf /tmp/* /var/tmp/*
sudo apt remove --purge -y $(dpkg -l | awk '/^ii  linux-image-[0-9]/{print $2}'|grep -v $(uname -r)) || true
sudo deborphan | xargs -r sudo apt-get -y remove --purge
sudo systemctl disable --now apport.service whoopsie motd-news.timer unattended-upgrades || true
sudo apt remove --purge -y fonts-* language-pack-*
sudo rm -rf /usr/share/man /usr/share/doc /usr/share/info /usr/share/lintian /usr/share/linda
sudo systemctl stop snapd || true && sudo apt remove --purge -y snapd whoopsie
sudo rm -rf /var/crash/* /var/lib/systemd/coredump/* /var/lib/apport/coredump/* ~/.xsession-errors* || true
sudo journalctl --vacuum-time=1d || true
sudo rm -rf /etc/ssh/ssh_host_*
sudo find / -xdev -xtype l -delete
sudo rm -rf ~/.thumbnails ~/.cache/thumbnails
sudo locale-gen --purge en_US.UTF-8
sudo find / -xdev -type f -size +50M ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" -delete
rm -rf ~/.icons ~/.local/share/icons ~/.cache/icon-cache.kcache
sudo rm -rf /var/lib/snapshots/* || true
command -v e4defrag &>/dev/null && sudo e4defrag / || true
sudo rm -rf /var/lib/apt/lists/*
sudo apt update -y
df -h
sudo rm -rf /var/lib/dpkg/info/* /var/lib/apt/lists/* /var/lib/polkit-1/*
sudo rm -rf /var/log/alternatives.log /usr/lib/x86_64-linux-gnu/dri/* \
            /usr/share/python-wheels/* /var/cache/apt/pkgcache.bin /var/cache/apt/srcpkgcache.bin
sudo apt purge -y deborphan
echo "✅ Deep WSL2 cleanup completed!"

###############################################################################
### Phase-2 : install Docker, avoid hosts conflict, verify
###############################################################################
install_once() {
  local attempt=$1
  msg "▶️  Install attempt $attempt / 3"

  dpkg --configure -a >/dev/null || true
  retry apt-get -f install -y || true
  retry apt-get update -y
  retry apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg iproute2 iptables util-linux net-tools lsb-release
  update-alternatives --set iptables  /usr/sbin/iptables-legacy  || true
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true

  install -m0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${DISTRO} stable" \
      > /etc/apt/sources.list.d/docker.list
  retry apt-get update -y

  retry apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

  # choose cgroup driver
  SYSTEMD=$(ps -p1 -o comm=)
  if [[ $SYSTEMD == systemd ]]; then
      CGROUP=systemd; CTD=true
  else
      CGROUP=cgroupfs; CTD=false
  fi

  # containerd config
  mkdir -p /etc/containerd
  containerd config default | sed "s/SystemdCgroup =.*/SystemdCgroup = ${CTD}/" \
      > /etc/containerd/config.toml

  # daemon.json WITHOUT "hosts"
  mkdir -p /etc/docker
  cat >/etc/docker/daemon.json <<JSON
{
  "storage-driver": "overlay2",
  "exec-opts": ["native.cgroupdriver=${CGROUP}"],
  "dns": ["8.8.8.8","8.8.4.4"],
  "features": { "buildkit": true }
}
JSON

  # explicit ExecStart override (removes default -H fd:// flag & adds our sockets)
  install -d /etc/systemd/system/docker.service.d
  cat >/etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --host=unix:///var/run/docker.sock --host=tcp://0.0.0.0:2375 --containerd=/run/containerd/containerd.sock
EOF

  # wsl.conf
  cat >/etc/wsl.conf <<'CONF'
[network]
generateResolvConf = false

[boot]
systemd=true
CONF
  echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" >/etc/resolv.conf

  need_wrapper=false
  if [[ $SYSTEMD == systemd ]]; then
      systemctl daemon-reload
      systemctl enable containerd.service docker.service docker.socket
      systemctl restart containerd.service
      systemctl restart docker.service || need_wrapper=true
  else
      need_wrapper=true
  fi

  if $need_wrapper; then
      wrn "Using wrapper (systemd will take over after wsl --shutdown)"
      cat >/usr/local/bin/dockerd-wsl2-wrapper <<WRAP
#!/usr/bin/env bash
set -euo pipefail
LOG=/var/log/dockerd-wsl2.log
while true; do
  /usr/bin/dockerd --exec-opt native.cgroupdriver=cgroupfs \
    --host=unix:///var/run/docker.sock --host=tcp://0.0.0.0:2375 \
    --containerd=/usr/bin/containerd >>"\$LOG" 2>&1
  sleep 2
done
WRAP
      chmod +x /usr/local/bin/dockerd-wsl2-wrapper
      nohup /usr/local/bin/dockerd-wsl2-wrapper >/dev/null 2>&1 &
      grep -q dockerd-wsl2-wrapper /etc/wsl.conf || \
        sed -i '/^\[boot\]/a command="bash -c '\''nohup /usr/local/bin/dockerd-wsl2-wrapper >/dev/null 2>&1 &'\''"' /etc/wsl.conf
  fi

  # wait up to 90 s
  for i in {1..90}; do
    [[ -S /var/run/docker.sock ]] && docker info &>/dev/null && break
    sleep 1
  done
  docker info &>/dev/null
}

attempt=0
until install_once $((++attempt)); do
  [[ $attempt -ge 3 ]] && die "Docker failed after 3 attempts – check logs."
  wrn "Attempt $attempt failed – purging and retrying."
  /bin/bash "$0" purge-only || die "Purge helper failed."
done

# docker group
if [[ $TARGET_USER != root ]] && ! id "$TARGET_USER" | grep -q "(docker)"; then
  msg "Adding $TARGET_USER to docker group"
  groupadd -f docker
  usermod -aG docker "$TARGET_USER"
  wrn "Log out/in so group membership applies."
fi

# buildx
docker buildx ls | grep -q wslbuilder || docker buildx create --name wslbuilder --use

# hello-world
docker run --rm hello-world >/dev/null && msg "🎉 Docker Engine is running & no host-conflict."

[[ $(ps -p1 -o comm=) != systemd ]] && wrn "Run 'wsl.exe --shutdown' once; Docker will then run under systemd without the wrapper."
exit 0
