#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "=== COMPREHENSIVE ERROR CHECK ==="
ERROR_COUNT=0

# Known WSL2 boot messages to ignore (unfixable, harmless kernel virtualization messages)
IGNORE_PATTERN="dxg:|dxgk:|Ioctl fail|query_adapter|is_feature_enabled|PCI:.*config space|No config space|AER:|ACPI:|hv_balloon|hv_utils|Hyper-V|hyperv|plan9|9p|vsock|virtio|CheckConnection|getaddrinfo|connect to bus|AcceptAsync|p9io|Operation canceled|Exception:|WSL.*ERROR|unknown:.*$"

# 1. Check systemd failed units (not masked ones)
FAILED_UNITS=$(systemctl --failed --no-legend 2>/dev/null | grep -v "^$" | wc -l)
FAILED_UNITS=${FAILED_UNITS:-0}
if [ "$FAILED_UNITS" -gt 0 ]; then
    REAL_FAILS=$(systemctl --failed --no-legend 2>/dev/null | grep -v "masked" | wc -l)
    REAL_FAILS=${REAL_FAILS:-0}
    if [ "$REAL_FAILS" -gt 0 ]; then
        echo "[ERR] Failed systemd units: $REAL_FAILS"
        systemctl --failed --no-legend 2>/dev/null | grep -v "masked"
        ERROR_COUNT=$((ERROR_COUNT + REAL_FAILS))
    fi
fi

# 2. Check journal errors (excluding known WSL2 kernel messages)
JOURNAL_ERRS=$(journalctl -b -p err --no-pager 2>/dev/null | grep -v "^--" | grep -v "No entries" | grep -vE "$IGNORE_PATTERN" | wc -l)
JOURNAL_ERRS=${JOURNAL_ERRS:-0}
if [ "$JOURNAL_ERRS" -gt 3 ]; then
    echo "[WARN] Journal errors (filtered): $JOURNAL_ERRS"
    journalctl -b -p err --no-pager 2>/dev/null | grep -vE "$IGNORE_PATTERN" | head -10
    REAL_JOURNAL_ERRS=$(journalctl -b -p err --no-pager 2>/dev/null | grep -v "^--" | grep -v "No entries" | grep -vE "$IGNORE_PATTERN" | grep -v "kernel:" | wc -l)
    if [ "${REAL_JOURNAL_ERRS:-0}" -gt 3 ]; then
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
fi

# 3. Check dmesg errors (excluding known WSL2 kernel messages)
DMESG_ERRS=$(dmesg --level=err 2>/dev/null | grep -vE "$IGNORE_PATTERN" | wc -l)
DMESG_ERRS=${DMESG_ERRS:-0}
if [ "$DMESG_ERRS" -gt 3 ]; then
    echo "[WARN] Dmesg errors (filtered): $DMESG_ERRS"
    dmesg --level=err 2>/dev/null | grep -vE "$IGNORE_PATTERN" | head -10
    ERROR_COUNT=$((ERROR_COUNT + 1))
fi

# 4. Check DNS
if ! ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
    echo "[ERR] No internet connectivity"
    ERROR_COUNT=$((ERROR_COUNT + 1))
fi

if ! ping -c1 -W2 google.com >/dev/null 2>&1; then
    echo "[ERR] DNS resolution failed"
    ERROR_COUNT=$((ERROR_COUNT + 1))
fi

# 5. Check for broken packages (dpkg status)
BROKEN_PKGS=$(dpkg -l 2>/dev/null | grep -E "^iU|^rC|^iF|^..r" | wc -l)
BROKEN_PKGS=${BROKEN_PKGS:-0}
if [ "$BROKEN_PKGS" -gt 0 ]; then
    echo "[ERR] Broken packages (dpkg status): $BROKEN_PKGS"
    dpkg -l 2>/dev/null | grep -E "^iU|^rC|^iF|^..r"
    ERROR_COUNT=$((ERROR_COUNT + BROKEN_PKGS))
fi

# 6. NEW: Check for unmet dependencies
echo "[*] Checking apt dependency issues..."
APT_CHECK=$(apt-get check 2>&1)
if echo "$APT_CHECK" | grep -q "unmet dependencies\|broken packages"; then
    echo "[ERR] APT dependency issues detected:"
    echo "$APT_CHECK" | grep -A 20 "unmet dependencies\|broken packages"
    ERROR_COUNT=$((ERROR_COUNT + 1))
fi

# 7. NEW: Check for held packages
HELD_PKGS=$(dpkg --get-selections | grep -c "hold$" 2>/dev/null || echo 0)
if [ "$HELD_PKGS" -gt 0 ]; then
    echo "[WARN] Held packages found: $HELD_PKGS"
    dpkg --get-selections | grep "hold$"
    ERROR_COUNT=$((ERROR_COUNT + 1))
fi

# 8. NEW: Check for version conflicts
echo "[*] Checking for package version conflicts..."
CONFLICT_CHECK=$(apt-get -s install -f 2>&1 | grep -E "Depends:|but.*is to be installed|is not installable")
if [ -n "$CONFLICT_CHECK" ]; then
    echo "[ERR] Package version conflicts detected:"
    echo "$CONFLICT_CHECK"
    ERROR_COUNT=$((ERROR_COUNT + 1))
fi

# 9. NEW: Check Ubuntu release consistency
if [ -f /etc/os-release ]; then
    UBUNTU_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    echo "[INFO] Ubuntu version: $UBUNTU_VERSION"

    # Check for mixed package sources
    LIBC_VERSION=$(dpkg -l libc6 2>/dev/null | grep "^ii" | awk '{print $3}')
    echo "[INFO] libc6 version: $LIBC_VERSION"

    # Ubuntu 22.04 should have libc6 2.35.x, Ubuntu 24.04 should have 2.39.x
    if [ "$UBUNTU_VERSION" = "22.04" ] && echo "$LIBC_VERSION" | grep -q "^2.39"; then
        echo "[ERR] Version mismatch: Ubuntu 22.04 with libc6 from 24.04 ($LIBC_VERSION)"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    elif [ "$UBUNTU_VERSION" = "24.04" ] && echo "$LIBC_VERSION" | grep -q "^2.35"; then
        echo "[ERR] Version mismatch: Ubuntu 24.04 with libc6 from 22.04 ($LIBC_VERSION)"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
fi

# 10. Check if resolv.conf is properly configured
if [ ! -f /etc/resolv.conf ] || ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
    echo "[ERR] resolv.conf not configured"
    ERROR_COUNT=$((ERROR_COUNT + 1))
fi

# 11. Check if boot script exists
if [ ! -x /usr/local/bin/wsl-boot.sh ]; then
    echo "[ERR] Boot script missing or not executable"
    ERROR_COUNT=$((ERROR_COUNT + 1))
fi

# 12. Check if wsl.conf exists
if [ ! -f /etc/wsl.conf ]; then
    echo "[ERR] wsl.conf missing"
    ERROR_COUNT=$((ERROR_COUNT + 1))
fi

# Report ignored WSL2 kernel messages for info
IGNORED_COUNT=$(dmesg --level=err 2>/dev/null | grep -E "$IGNORE_PATTERN" | wc -l)
if [ "${IGNORED_COUNT:-0}" -gt 0 ]; then
    echo "[INFO] Ignored $IGNORED_COUNT known WSL2 kernel messages (harmless)"
fi

echo "=== TOTAL ACTIONABLE ERRORS: $ERROR_COUNT ==="
exit $ERROR_COUNT
