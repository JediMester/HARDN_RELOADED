#!/usr/bin/env bash
# modules/firewall.sh — firewalld configuration
# Calls ensure_firewalld (detect.sh) first so it's always safe to run even
# if firewalld wasn't installed before HARDN ran.
# Skips entirely if dfr_fwd + firewalld are already configured and active.

setup_firewall() {
    [[ "${OPT_FIREWALL:-0}" -eq 0 ]] && { STATUS_SKIP "Firewall"; return; }
    STATUS_STEP "Firewall (firewalld)"

    # ensure_firewalld handles install + start if not present
    ensure_firewalld

    if [[ "$FIREWALLD_ACTIVE" -eq 0 ]]; then
        STATUS_ERR "firewalld is still not active after install attempt — skipping firewall config."
        return 1
    fi

    # ── Base policy ──────────────────────────────────────────────────────────
    firewall-cmd --set-default-zone=public &>/dev/null

    # Remove services that may have been added by previous runs or defaults
    for svc in ssh http https; do
        firewall-cmd --permanent --zone=public --remove-service="$svc" &>/dev/null || true
    done

    # Always allow SSH so we don't lock ourselves out
    [[ "${FIREWALL_ALLOW_SSH:-1}"   -eq 1 ]] && firewall-cmd --permanent --zone=public --add-service=ssh
    [[ "${FIREWALL_ALLOW_HTTP:-1}"  -eq 1 ]] && firewall-cmd --permanent --zone=public --add-service=http
    [[ "${FIREWALL_ALLOW_HTTPS:-1}" -eq 1 ]] && firewall-cmd --permanent --zone=public --add-service=https

    # ── Steam ports (gaming profile) ─────────────────────────────────────────
    if [[ "${OPT_ALLOW_STEAM_PORTS:-0}" -eq 1 ]]; then
        STATUS_MSG "Opening Steam / Valve ports..."
        # TCP
        for port in 27015-27050 27036; do
            firewall-cmd --permanent --zone=public --add-port="${port}/tcp" &>/dev/null
        done
        # UDP
        for port in 27000-27100 4380 3478 4379; do
            firewall-cmd --permanent --zone=public --add-port="${port}/udp" &>/dev/null
        done
        STATUS_OK "Steam ports opened."
    fi

    # ── Generic game ports (gaming profile) ──────────────────────────────────
    if [[ "${OPT_ALLOW_GAME_PORTS:-0}" -eq 1 ]]; then
        STATUS_MSG "Opening common game ports..."
        # Many multiplayer games use these ranges
        firewall-cmd --permanent --zone=public --add-port="7000-7999/udp"   &>/dev/null
        firewall-cmd --permanent --zone=public --add-port="9000-9100/udp"   &>/dev/null
        STATUS_OK "Common game ports opened."
    fi

    firewall-cmd --reload &>/dev/null
    STATUS_OK "Firewall configured (default zone: public, deny inbound)."

    # ── dfr_fwd dynamic port-scan blocker ────────────────────────────────────
    if [[ "${OPT_DFR_FWD:-0}" -eq 1 ]]; then
        ensure_dfr_fwd
    else
        STATUS_SKIP "dfr_fwd dynamic scanner blocker (disabled by profile)"
    fi
}
