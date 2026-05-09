#!/usr/bin/env bash
# modules/services.sh — disable unnecessary/risky services and remove packages
# Profile flags (OPT_DISABLE_*) control what gets touched.

setup_services() {
    [[ "${OPT_DISABLE_SERVICES:-0}" -eq 0 ]] && { STATUS_SKIP "Service hardening"; return; }
    STATUS_STEP "Disabling unnecessary services"

    # Helper: stop + disable a service (non-fatal if not installed)
    _disable_svc() {
        local svc="$1"
        if svc_is_enabled "$svc" 2>/dev/null; then
            svc_disable "$svc"
            STATUS_MSG "Disabled: ${svc}"
        fi
    }

    # Helper: remove a package if installed
    _remove_pkg() {
        local pkg="$1"
        if pkg_installed "$pkg"; then
            case "$PKGMGR" in
                pacman) pacman -Rns --noconfirm "$pkg" 2>/dev/null ;;
                apt)    DEBIAN_FRONTEND=noninteractive apt purge -y "$pkg" 2>/dev/null ;;
                dnf)    dnf remove -y "$pkg" 2>/dev/null ;;
                zypper) zypper remove -y "$pkg" 2>/dev/null ;;
            esac
            STATUS_MSG "Removed package: $pkg"
        fi
    }

    # ── Printing ─────────────────────────────────────────────────────────────
    if [[ "${OPT_DISABLE_CUPS:-0}" -eq 1 ]]; then
        _disable_svc cups
        _disable_svc cups-browsed
    fi

    # ── mDNS / Avahi ────────────────────────────────────────────────────────
    # Only disable the daemon — avahi is a required dependency of cups, pipewire-pulse,
    # ostree and others on desktop systems, so removing the package would break them.
    if [[ "${OPT_DISABLE_AVAHI:-1}" -eq 1 ]]; then
        _disable_svc avahi-daemon
    fi

    # ── Bluetooth ────────────────────────────────────────────────────────────
    if [[ "${OPT_DISABLE_BLUETOOTH:-0}" -eq 1 ]]; then
        _disable_svc bluetooth
    fi

    # ── Remote procedure call / NFS ──────────────────────────────────────────
    if [[ "${OPT_DISABLE_RPCBIND:-1}" -eq 1 ]]; then
        _disable_svc rpcbind
        _disable_svc rpcbind.socket
    fi

    if [[ "${OPT_DISABLE_NFS:-1}" -eq 1 ]]; then
        _disable_svc nfs-server
        _disable_svc nfs-client.target
    fi

    # ── Samba ────────────────────────────────────────────────────────────────
    if [[ "${OPT_DISABLE_SMB:-0}" -eq 1 ]]; then
        _disable_svc smb
        _disable_svc nmb
        _remove_pkg samba
    fi

    # ── Always remove legacy / plaintext protocol tools ──────────────────────
    local always_remove_arch=(  inetutils-telnet )
    local always_remove_debian=( telnet vsftpd proftpd tftpd postfix exim4 )
    local always_remove_rpm=(   telnet vsftpd )

    case "$DISTRO_FAMILY" in
        arch)   for p in "${always_remove_arch[@]}";   do _remove_pkg "$p"; done ;;
        debian) for p in "${always_remove_debian[@]}"; do _remove_pkg "$p"; done ;;
        rpm)    for p in "${always_remove_rpm[@]}";    do _remove_pkg "$p"; done ;;
    esac

    # ── File permissions (STIG) ───────────────────────────────────────────────
    if [[ "${OPT_FILE_PERMISSIONS:-1}" -eq 1 ]]; then
        chmod 700 /root
        chmod 644 /etc/passwd /etc/group
        chmod 600 /etc/shadow /etc/gshadow
        [[ -f /etc/ssh/sshd_config ]] && chmod 644 /etc/ssh/sshd_config
        # Harden log directories
        find /var/log -type f -exec chmod 640 {} \; 2>/dev/null
        find /var/log -type d -exec chmod 750 {} \; 2>/dev/null
        # Sticky bit on /tmp and /var/tmp
        chmod 1777 /tmp /var/tmp 2>/dev/null
        STATUS_OK "STIG file permissions applied."
    fi

    # ── Compiler access restriction (server profile) ──────────────────────────
    if [[ "${OPT_RESTRICT_COMPILERS:-0}" -eq 1 ]]; then
        for bin in gcc g++ cc c++ make as ld; do
            local bin_path
            bin_path=$(command -v "$bin" 2>/dev/null)
            if [[ -n "$bin_path" ]]; then
                chown root:root "$bin_path"
                chmod 755 "$bin_path"
                STATUS_MSG "Compiler restricted: $bin_path"
            fi
        done
        STATUS_OK "Compiler access restricted to root."
    fi

    STATUS_OK "Service hardening complete."
}
