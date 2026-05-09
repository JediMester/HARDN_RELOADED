#!/usr/bin/env bash
# lib/packages.sh — per-distro package name maps and install helpers.
# Sourced after detect.sh (requires $DISTRO_FAMILY and $PKGMGR to be set).

# ---------------------------------------------------------------------------
# Package name maps
# Each PKG_* variable holds the space-separated package list for the current
# distro family.  Modules reference these instead of hard-coding names.
# ---------------------------------------------------------------------------

setup_package_maps() {
    case "$DISTRO_FAMILY" in

        # ── Arch Linux ───────────────────────────────────────────────────────
        arch)
            PKG_AUDIT="audit"
            PKG_CLAMAV="clamav"
            PKG_FAIL2BAN="fail2ban"
            PKG_CRON="cronie"
            PKG_RKHUNTER="rkhunter"
            PKG_CHKROOTKIT="chkrootkit"          # AUR
            PKG_AIDE="aide"
            PKG_AIDE_AUR=1                       # flag: AUR-only on Arch
            PKG_LYNIS="lynis"
            PKG_SURICATA="suricata"              # AUR on Arch
            PKG_SURICATA_AUR=1                   # flag: install via AUR helper
            PKG_FIREJAIL="firejail"
            PKG_RSYSLOG="rsyslog"
            PKG_RSYSLOG_AUR=1                    # flag: AUR-only on Arch
            PKG_LOGROTATE="logrotate"
            PKG_FIREWALL="firewalld"
            PKG_PAM_PWQUALITY="libpwquality"
            PKG_YARA="yara"
            PKG_UNHIDE="unhide"                  # AUR
            PKG_SYSSTAT="sysstat"
            PKG_WHIPTAIL="libnewt"
            PKG_TCPDUMP="tcpdump"
            PKG_NMAP="nmap"
            PKG_CURL="curl"
            PKG_WGET="wget"
            PKG_GIT="git"
            PKG_LSOF="lsof"
            PKG_PROCPS="procps-ng"
            # Integrity checking: pacman -Qk / paccheck (pacman-contrib)
            PKG_INTEGRITY="pacman-contrib"
            # MAC: SELinux userspace tools (kernel must have selinux enabled)
            PKG_SELINUX="libselinux selinux-utils policycoreutils"
            # Auto-updates via systemd timer + pacman hook
            PKG_AUTO_UPDATES="pacman-contrib"
            ;;

        # ── Debian / Ubuntu / Mint / Pop!_OS ─────────────────────────────────
        debian)
            PKG_AUDIT="auditd audispd-plugins"
            PKG_CLAMAV="clamav clamav-daemon clamav-freshclam"
            PKG_FAIL2BAN="fail2ban"
            PKG_CRON="cron"
            PKG_RKHUNTER="rkhunter"
            PKG_CHKROOTKIT="chkrootkit"
            PKG_AIDE="aide aide-common"
            PKG_LYNIS="lynis"
            PKG_SURICATA="suricata"
            PKG_FIREJAIL="firejail"
            PKG_RSYSLOG="rsyslog"
            PKG_LOGROTATE="logrotate"
            PKG_FIREWALL="firewalld"
            PKG_PAM_PWQUALITY="libpam-pwquality"
            PKG_YARA="yara"
            PKG_UNHIDE="unhide"
            PKG_ACCT="acct"
            PKG_SYSSTAT="sysstat"
            PKG_WHIPTAIL="whiptail"
            PKG_TCPDUMP="tcpdump"
            PKG_NMAP="nmap"
            PKG_CURL="curl"
            PKG_WGET="wget"
            PKG_GIT="git"
            PKG_LSOF="lsof"
            PKG_PROCPS="procps"
            # Integrity: verify installed package files against dpkg database
            PKG_INTEGRITY="debsums"
            PKG_SELINUX="selinux-basics selinux-policy-default"
            PKG_AUTO_UPDATES="unattended-upgrades apt-listchanges"
            ;;

        # ── Fedora / openSUSE / RHEL-family ──────────────────────────────────
        rpm)
            PKG_AUDIT="audit"
            PKG_CLAMAV="clamav clamav-update"
            PKG_FAIL2BAN="fail2ban"
            PKG_CRON="cronie"
            PKG_RKHUNTER="rkhunter"
            PKG_CHKROOTKIT="chkrootkit"
            PKG_AIDE="aide"
            PKG_LYNIS="lynis"
            PKG_SURICATA="suricata"
            PKG_FIREJAIL="firejail"
            PKG_RSYSLOG="rsyslog"
            PKG_LOGROTATE="logrotate"
            PKG_FIREWALL="firewalld"
            PKG_PAM_PWQUALITY="libpwquality"
            PKG_YARA="yara"
            PKG_UNHIDE="unhide"
            PKG_ACCT="psacct"
            PKG_SYSSTAT="sysstat"
            PKG_WHIPTAIL="newt"
            PKG_TCPDUMP="tcpdump"
            PKG_NMAP="nmap"
            PKG_CURL="curl"
            PKG_WGET="wget"
            PKG_GIT="git"
            PKG_LSOF="lsof"
            PKG_PROCPS="procps-ng"
            PKG_INTEGRITY="aide"   # rpm -Va also available
            PKG_SELINUX="selinux-policy selinux-policy-targeted"
            PKG_AUTO_UPDATES="dnf-automatic"
            ;;
    esac

    export PKG_AUDIT PKG_CLAMAV PKG_FAIL2BAN PKG_RKHUNTER PKG_CHKROOTKIT
    export PKG_AIDE PKG_LYNIS PKG_SURICATA PKG_FIREJAIL PKG_RSYSLOG
    export PKG_LOGROTATE PKG_FIREWALL PKG_PAM_PWQUALITY PKG_YARA PKG_UNHIDE
    export PKG_ACCT PKG_SYSSTAT PKG_WHIPTAIL PKG_TCPDUMP PKG_NMAP
    export PKG_CURL PKG_WGET PKG_GIT PKG_LSOF PKG_PROCPS
    export PKG_INTEGRITY PKG_SELINUX PKG_AUTO_UPDATES PKG_CRON PKG_AIDE_AUR PKG_RSYSLOG_AUR
}

# ---------------------------------------------------------------------------
# install_pkg — unified package installer
# Usage:  install_pkg curl wget git
# ---------------------------------------------------------------------------

install_pkg() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -eq 0 ]] && return 0
    STATUS_MSG "Installing packages: ${pkgs[*]}"
    case "$PKGMGR" in
        pacman) pacman -S --noconfirm --needed "${pkgs[@]}" ;;
        apt)    DEBIAN_FRONTEND=noninteractive apt install -y "${pkgs[@]}" ;;
        dnf)    dnf install -y "${pkgs[@]}" ;;
        zypper) zypper install -y "${pkgs[@]}" ;;
    esac
}

# ---------------------------------------------------------------------------
# install_aur_pkg — AUR packages via yay/paru (Arch only, non-root user)
# Usage:  install_aur_pkg chkrootkit unhide
# ---------------------------------------------------------------------------

install_aur_pkg() {
    [[ "$DISTRO_FAMILY" != "arch" ]] && return 0
    local pkgs=("$@")
    [[ ${#pkgs[@]} -eq 0 ]] && return 0

    if [[ -z "$AUR_HELPER" ]]; then
        STATUS_WARN "No AUR helper (yay/paru) found — skipping AUR packages: ${pkgs[*]}"
        STATUS_WARN "Install yay or paru, then re-run to add: ${pkgs[*]}"
        return 1
    fi

    # AUR helpers must NOT run as root
    local run_as="${SUDO_USER:-}"
    if [[ -z "$run_as" ]]; then
        STATUS_WARN "Cannot determine non-root user for AUR install — skipping: ${pkgs[*]}"
        return 1
    fi

    # Filter out already-installed packages to avoid rebuilding every run
    local to_install=()
    for p in "${pkgs[@]}"; do
        pkg_installed "$p" || to_install+=("$p")
    done
    [[ ${#to_install[@]} -eq 0 ]] && { STATUS_MSG "AUR packages already installed: ${pkgs[*]}"; return 0; }

    STATUS_MSG "Installing AUR packages as $run_as: ${to_install[*]}"
    # --answerdiff None --answerclean None suppress yay's interactive build prompts
    # even when --noconfirm is passed (yay has its own prompt layer above pacman)
    sudo -u "$run_as" "$AUR_HELPER" -S --noconfirm \
        --answerdiff None --answerclean None \
        "${to_install[@]}"
}

# ---------------------------------------------------------------------------
# pkg_installed — check if a package is installed
# Usage:  pkg_installed curl && echo "found"
# ---------------------------------------------------------------------------

pkg_installed() {
    local pkg="$1"
    case "$PKGMGR" in
        pacman)       pacman -Q "$pkg" &>/dev/null ;;
        apt)          dpkg -s "$pkg" &>/dev/null 2>&1 ;;
        dnf|zypper)   rpm -q "$pkg" &>/dev/null ;;
    esac
}

# ---------------------------------------------------------------------------
# update_system — full system update before hardening
# ---------------------------------------------------------------------------

update_system() {
    STATUS_STEP "Updating system packages"
    case "$PKGMGR" in
        pacman) pacman -Syu --noconfirm ;;
        apt)    apt update && DEBIAN_FRONTEND=noninteractive apt upgrade -y ;;
        dnf)    dnf upgrade -y ;;
        zypper) zypper update -y ;;
    esac
}

# ---------------------------------------------------------------------------
# ensure_cron_dir — install a cron daemon if needed and create /etc/cron.d
# Arch ships no cron daemon by default; cronie provides one.
# Safe to call multiple times (idempotent).
# ---------------------------------------------------------------------------

ensure_cron_dir() {
    if [[ ! -d /etc/cron.d ]]; then
        STATUS_MSG "No /etc/cron.d found — installing cron daemon (${PKG_CRON})."
        install_pkg $PKG_CRON
        mkdir -p /etc/cron.d
        case "$DISTRO_FAMILY" in
            arch|rpm) svc_enable cronie ;;
            debian)   svc_enable cron ;;
        esac
    else
        mkdir -p /etc/cron.d   # safety net — already exists but make sure
    fi
}
