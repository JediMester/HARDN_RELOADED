#!/usr/bin/env bash
# modules/updates.sh — automatic security updates
# Arch: pacman-based systemd timer; Debian: unattended-upgrades; RPM: dnf-automatic

setup_updates() {
    [[ "${OPT_AUTO_UPDATES:-0}" -eq 0 ]] && { STATUS_SKIP "Automatic updates"; return; }
    STATUS_STEP "Automatic security updates"

    case "$DISTRO_FAMILY" in
        arch)   _setup_updates_arch ;;
        debian) _setup_updates_debian ;;
        rpm)    _setup_updates_rpm ;;
    esac
}

# ── Arch ──────────────────────────────────────────────────────────────────────
_setup_updates_arch() {
    install_pkg $PKG_AUTO_UPDATES   # pacman-contrib (provides checkupdates)

    # systemd timer: check and apply updates nightly at 02:00
    cat > /etc/systemd/system/hardn-autoupdate.service <<EOF
[Unit]
Description=HARDN automatic security update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/pacman -Syu --noconfirm
StandardOutput=journal
StandardError=journal
SyslogIdentifier=hardn-autoupdate
EOF

    cat > /etc/systemd/system/hardn-autoupdate.timer <<'EOF'
[Unit]
Description=HARDN automatic update timer

[Timer]
OnCalendar=*-*-* 02:00:00
RandomizedDelaySec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now hardn-autoupdate.timer
    STATUS_OK "Arch auto-update timer enabled (nightly 02:00 ±30min)."

    if [[ "${OPT_AUTO_REBOOT:-0}" -eq 1 ]]; then
        # Append reboot after update
        sed -i '/ExecStart=.*pacman/a ExecStartPost=/usr/bin/systemctl reboot' \
            /etc/systemd/system/hardn-autoupdate.service
        systemctl daemon-reload
        STATUS_WARN "Auto-reboot enabled — system will reboot after updates."
    fi
}

# ── Debian ────────────────────────────────────────────────────────────────────
_setup_updates_debian() {
    install_pkg $PKG_AUTO_UPDATES

    # Detect if Debian or Ubuntu (different origin patterns)
    local origin_debian='o=Debian,a=stable,l=Debian-Security";'
    local origin_ubuntu='o=Ubuntu,a=${distro_codename}-security";'
    local origins="$origin_debian"
    grep -qi ubuntu /etc/os-release 2>/dev/null && origins="$origin_ubuntu"

    cat > /etc/apt/apt.conf.d/50hardn-unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "${origins}
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "$([ "${OPT_AUTO_REBOOT:-0}" -eq 1 ] && echo true || echo false)";
Unattended-Upgrade::Automatic-Reboot-Time "02:30";
EOF

    cat > /etc/apt/apt.conf.d/20hardn-auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    systemctl enable --now unattended-upgrades
    STATUS_OK "unattended-upgrades configured (security-only)."
}

# ── RPM ──────────────────────────────────────────────────────────────────────
_setup_updates_rpm() {
    install_pkg $PKG_AUTO_UPDATES   # dnf-automatic

    local dnf_auto="/etc/dnf/automatic.conf"
    if [[ -f "$dnf_auto" ]]; then
        sed -i 's/^upgrade_type.*/upgrade_type = security/' "$dnf_auto"
        sed -i 's/^apply_updates.*/apply_updates = yes/'    "$dnf_auto"

        if [[ "${OPT_AUTO_REBOOT:-0}" -eq 1 ]]; then
            sed -i 's/^reboot =.*/reboot = when-needed/' "$dnf_auto"
        fi
    fi

    systemctl enable --now dnf-automatic-install.timer
    STATUS_OK "dnf-automatic configured (security updates)."
}
