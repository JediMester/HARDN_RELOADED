#!/usr/bin/env bash
# lib/detect.sh — OS/package-manager detection + ensure helpers for firewalld
#                 and dfr_fwd (the dynamic port-scan blocker service).
#
# Sourced early by hardn.sh; sets exported variables used by every module.
# Rule: detect_* functions are pure (no side effects).
#       ensure_* functions detect first, then act only if something is missing.

# ---------------------------------------------------------------------------
# OS / package-manager detection
# ---------------------------------------------------------------------------

detect_os() {
    [[ ! -f /etc/os-release ]] && { echo "ERROR: /etc/os-release not found." >&2; exit 1; }
    # shellcheck source=/dev/null
    source /etc/os-release

    DISTRO_ID="${ID,,}"
    DISTRO_LIKE="${ID_LIKE,,}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    DISTRO_PRETTY="${PRETTY_NAME:-$ID}"

    if   command -v pacman &>/dev/null; then PKGMGR="pacman"; DISTRO_FAMILY="arch"
    elif command -v apt    &>/dev/null; then PKGMGR="apt";    DISTRO_FAMILY="debian"
    elif command -v dnf    &>/dev/null; then PKGMGR="dnf";    DISTRO_FAMILY="rpm"
    elif command -v zypper &>/dev/null; then PKGMGR="zypper"; DISTRO_FAMILY="rpm"
    else echo "ERROR: No supported package manager found (pacman/apt/dnf/zypper)." >&2; exit 1
    fi

    INIT="other"
    systemctl --version &>/dev/null 2>&1 && INIT="systemd"

    IS_VM=0
    command -v systemd-detect-virt &>/dev/null \
        && systemd-detect-virt --vm &>/dev/null && IS_VM=1

    IS_EFI=0
    [[ -d /sys/firmware/efi ]] && IS_EFI=1

    AUR_HELPER=""
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        if   command -v yay  &>/dev/null; then AUR_HELPER="yay"
        elif command -v paru &>/dev/null; then AUR_HELPER="paru"
        fi
    fi

    export DISTRO_ID DISTRO_LIKE DISTRO_VERSION DISTRO_PRETTY
    export DISTRO_FAMILY PKGMGR INIT IS_VM IS_EFI AUR_HELPER
}

# ---------------------------------------------------------------------------
# Kernel feature detection
# ---------------------------------------------------------------------------

detect_kernel_features() {
    HAS_APPARMOR=0
    if [[ -d /sys/kernel/security/apparmor ]]; then
        HAS_APPARMOR=1
    elif grep -q "^CONFIG_SECURITY_APPARMOR=y" "/boot/config-$(uname -r)" 2>/dev/null; then
        HAS_APPARMOR=1
    fi

    HAS_SELINUX=0
    if [[ -d /sys/fs/selinux ]] || command -v getenforce &>/dev/null; then
        HAS_SELINUX=1
    fi

    IS_HARDENED_KERNEL=0
    uname -r | grep -qi "hardened" && IS_HARDENED_KERNEL=1

    export HAS_APPARMOR HAS_SELINUX IS_HARDENED_KERNEL
}

# ---------------------------------------------------------------------------
# Service presence detection  (pure — no side effects)
# ---------------------------------------------------------------------------

detect_existing_services() {
    DFR_FWD_ACTIVE=0
    systemctl is-active --quiet dynamic_firewalld_rules.service 2>/dev/null \
        && DFR_FWD_ACTIVE=1

    DFR_FWD_INSTALLED=0
    [[ -f /usr/bin/dfr_fwd.py \
       && -f /etc/systemd/system/dynamic_firewalld_rules.service ]] \
        && DFR_FWD_INSTALLED=1

    FIREWALLD_ACTIVE=0
    systemctl is-active --quiet firewalld.service 2>/dev/null \
        && FIREWALLD_ACTIVE=1

    FIREWALLD_INSTALLED=0
    command -v firewall-cmd &>/dev/null && FIREWALLD_INSTALLED=1

    UFW_ACTIVE=0
    if command -v ufw &>/dev/null; then
        ufw status 2>/dev/null | grep -q "Status: active" && UFW_ACTIVE=1
    fi

    export DFR_FWD_ACTIVE DFR_FWD_INSTALLED
    export FIREWALLD_ACTIVE FIREWALLD_INSTALLED UFW_ACTIVE
}

# ---------------------------------------------------------------------------
# Internal helper: install a package using whatever manager is present.
# Only used by the ensure_* functions below so detect.sh stays self-contained.
# ---------------------------------------------------------------------------

_detect_pkg_install() {
    local pkgs=("$@")
    STATUS_MSG "Installing: ${pkgs[*]}" 2>/dev/null || echo "  → Installing: ${pkgs[*]}"
    case "$PKGMGR" in
        pacman) pacman -S --noconfirm --needed "${pkgs[@]}" ;;
        apt)    DEBIAN_FRONTEND=noninteractive apt install -y "${pkgs[@]}" ;;
        dnf)    dnf install -y "${pkgs[@]}" ;;
        zypper) zypper install -y "${pkgs[@]}" ;;
    esac
}

# ---------------------------------------------------------------------------
# ensure_firewalld — install + enable firewalld if not already present/active
# ---------------------------------------------------------------------------

ensure_firewalld() {
    detect_existing_services

    if [[ "$FIREWALLD_ACTIVE" -eq 1 ]]; then
        echo "  [SKIP] firewalld is already active."
        return 0
    fi

    echo "  [INFO] firewalld not active — installing and configuring..."

    if [[ "$FIREWALLD_INSTALLED" -eq 0 ]]; then
        case "$DISTRO_FAMILY" in
            arch)   _detect_pkg_install firewalld ;;
            debian) _detect_pkg_install firewalld ;;
            rpm)    _detect_pkg_install firewalld ;;
        esac
    fi

    # Enable and start
    systemctl enable --now firewalld.service

    # Sensible defaults: deny all inbound, allow outbound, keep SSH
    firewall-cmd --set-default-zone=public         &>/dev/null
    firewall-cmd --permanent --add-service=ssh     &>/dev/null
    firewall-cmd --permanent --add-service=http    &>/dev/null
    firewall-cmd --permanent --add-service=https   &>/dev/null
    firewall-cmd --reload                          &>/dev/null

    # Re-detect to update exported flags
    detect_existing_services

    if [[ "$FIREWALLD_ACTIVE" -eq 1 ]]; then
        echo "  [OK]   firewalld installed and active."
    else
        echo "  [WARN] firewalld did not start correctly — check journalctl -xe." >&2
    fi
}

# ---------------------------------------------------------------------------
# ensure_dfr_fwd — deploy dfr_fwd.py and its systemd unit if not present/active
#
# Requires:  ensure_firewalld() to have been called first (dfr_fwd depends on
#            firewalld).  Requires Python 3 and tcpdump.
# Source:    The bundled copy at  <project_root>/src/tools/dfr_fwd.py
#            is installed to /usr/bin/dfr_fwd.py.
# ---------------------------------------------------------------------------

ensure_dfr_fwd() {
    detect_existing_services

    if [[ "$DFR_FWD_ACTIVE" -eq 1 ]]; then
        echo "  [SKIP] dynamic_firewalld_rules service is already active."
        return 0
    fi

    # Resolve project root relative to this file's location
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root
    project_root="$(cd "$script_dir/../.." && pwd)"
    local src_script="$project_root/src/tools/dfr_fwd.py"

    if [[ ! -f "$src_script" ]]; then
        echo "  [ERROR] Bundled dfr_fwd.py not found at: $src_script" >&2
        return 1
    fi

    echo "  [INFO] dynamic_firewalld_rules not active — installing..."

    # Install runtime dependencies
    if ! command -v python3 &>/dev/null; then
        case "$DISTRO_FAMILY" in
            arch)   _detect_pkg_install python ;;
            debian) _detect_pkg_install python3 ;;
            rpm)    _detect_pkg_install python3 ;;
        esac
    fi

    if ! command -v tcpdump &>/dev/null; then
        _detect_pkg_install tcpdump
    fi

    # firewalld must be running before we deploy dfr_fwd
    if [[ "$FIREWALLD_ACTIVE" -eq 0 ]]; then
        echo "  [INFO] firewalld not active — running ensure_firewalld first..."
        ensure_firewalld
    fi

    # Deploy the script
    install -m 0755 -o root -g root "$src_script" /usr/bin/dfr_fwd.py

    # Write the systemd unit (matches the known-good unit from the original setup)
    cat > /etc/systemd/system/dynamic_firewalld_rules.service <<'UNIT'
[Unit]
Description=Dynamic Firewall Rules for TCP/UDP Scans
After=network.target firewalld.service
Requires=firewalld.service

[Service]
ExecStart=/usr/bin/python3 /usr/bin/dfr_fwd.py
Restart=always
User=root
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dynamic_firewalld_rules

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable --now dynamic_firewalld_rules.service

    # Re-detect
    detect_existing_services

    if [[ "$DFR_FWD_ACTIVE" -eq 1 ]]; then
        echo "  [OK]   dynamic_firewalld_rules installed and active."
    else
        echo "  [WARN] Service did not start — check: journalctl -xe -u dynamic_firewalld_rules" >&2
    fi
}

# ---------------------------------------------------------------------------
# Browser detection  (used by firejail module)
# ---------------------------------------------------------------------------

detect_browsers() {
    INSTALLED_BROWSERS=()
    local candidates=(firefox firefox-esr chromium brave google-chrome-stable
                      opera vivaldi librewolf)
    for b in "${candidates[@]}"; do
        command -v "$b" &>/dev/null && INSTALLED_BROWSERS+=("$b")
    done
    export INSTALLED_BROWSERS
}
