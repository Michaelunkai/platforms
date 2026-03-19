<#
.SYNOPSIS
    wsbug
#>
ws 'echo "=== FAILED SERVICES ==="; systemctl --failed; echo "=== JOURNAL ERRORS ==="; journalctl -p err -b; echo "=== CRITICAL ==="; journalctl -p crit -b; echo "=== KERNEL ERR/WARN ==="; dmesg --level=err,warn; echo "=== APT ERRORS ==="; grep -Ri "error" /var/log/apt 2>/dev/null; echo "=== BROKEN PACKAGES ==="; dpkg -l | grep -E "broken|^..r"; echo "=== DISK ==="; df -h; echo "=== FS ERRORS ==="; mount | grep -E "error|fail"'
