<#
.SYNOPSIS
    wslfull
#>
wsl -u root bash -c "echo 'ubuntu ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ubuntu && chmod 440 /etc/sudoers.d/ubuntu && for g in root sudo adm disk sys kmem dialout cdrom floppy tape audio dip www-data video plugdev staff games users netdev lxd docker; do usermod -aG \$g ubuntu 2>/dev/null; done && chown -R ubuntu:ubuntu /home/ubuntu && echo 'root:ubuntu' | chpasswd && echo 'ubuntu:ubuntu' | chpasswd && chmod 755 /root && chown ubuntu:ubuntu /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock 2>/dev/null && chmod 777 /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock 2>/dev/null"
