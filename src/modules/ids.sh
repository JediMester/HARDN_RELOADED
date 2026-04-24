#!/usr/bin/env bash
# modules/ids.sh — fail2ban + Suricata IDS/IPS

setup_ids() {
    [[ "${OPT_IDS:-0}" -eq 0 ]] && { STATUS_SKIP "IDS/IPS"; return; }
    STATUS_STEP "IDS/IPS (fail2ban + Suricata)"

    _setup_fail2ban
    _setup_suricata
}

# ── fail2ban ─────────────────────────────────────────────────────────────────

_setup_fail2ban() {
    [[ "${OPT_FAIL2BAN:-1}" -eq 0 ]] && { STATUS_SKIP "fail2ban"; return; }

    install_pkg $PKG_FAIL2BAN

    local jail_local="/etc/fail2ban/jail.local"

    cat > "$jail_local" <<EOF
# HARDN RELOADED — fail2ban jail.local
# Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ") — profile: ${HARDN_PROFILE}

[DEFAULT]
bantime  = ${FAIL2BAN_BAN_TIME:-1800}
findtime = 600
maxretry = ${FAIL2BAN_MAX_RETRY:-5}
banaction = firewallcmd-ipset
backend   = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
maxretry = ${FAIL2BAN_MAX_RETRY:-5}
EOF

    # Use firewalld backend if available, otherwise iptables
    if [[ "$FIREWALLD_ACTIVE" -eq 1 ]]; then
        sed -i 's/^banaction.*/banaction = firewallcmd-ipset/' "$jail_local"
    else
        sed -i 's/^banaction.*/banaction = iptables-multiport/' "$jail_local"
    fi

    systemctl enable --now fail2ban
    STATUS_OK "fail2ban configured (maxretry=${FAIL2BAN_MAX_RETRY:-5}, bantime=${FAIL2BAN_BAN_TIME:-1800}s)."
}

# ── Suricata ──────────────────────────────────────────────────────────────────

_setup_suricata() {
    [[ "${OPT_SURICATA:-1}" -eq 0 ]] && { STATUS_SKIP "Suricata"; return; }

    # On Arch, Suricata is AUR-only; on Debian/RPM it is in the official repos
    if [[ "${PKG_SURICATA_AUR:-0}" -eq 1 ]]; then
        if [[ -z "$AUR_HELPER" ]]; then
            STATUS_WARN "Suricata is AUR-only on Arch and no AUR helper (yay/paru) was found."
            STATUS_WARN "Install yay or paru, then re-run to add Suricata."
            STATUS_WARN "Skipping Suricata — all other modules will continue."
            return
        fi
        install_aur_pkg "$PKG_SURICATA"
    else
        install_pkg "$PKG_SURICATA"
    fi

    # Detect primary external interface
    local iface
    iface=$(ip route | awk '/^default/{print $5; exit}')
    iface="${iface:-eth0}"

    # Configure Suricata to listen on the external interface
    local suricata_cfg="/etc/suricata/suricata.yaml"
    if [[ -f "$suricata_cfg" ]]; then
        # Set the interface
        sed -i "s/- interface: .*/- interface: ${iface}/" "$suricata_cfg"
        STATUS_MSG "Suricata configured on interface: $iface"
    fi

    # Update rules (suricata-update or suricata --update-sources)
    if command -v suricata-update &>/dev/null; then
        suricata-update &>/dev/null || true
        STATUS_MSG "Suricata rules updated."
    fi

    systemctl enable --now suricata
    STATUS_OK "Suricata IDS/IPS enabled on $iface."
}
