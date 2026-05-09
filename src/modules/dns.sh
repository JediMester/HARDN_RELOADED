#!/usr/bin/env bash
# modules/dns.sh — secure DNS provider selection via interactive menu

setup_dns() {
    [[ "${OPT_DNS:-0}" -eq 0 ]] && { STATUS_SKIP "DNS configuration"; return; }
    STATUS_STEP "Secure DNS configuration"

    # DNS provider menu
    local choice
    choice=$(ui_menu \
        "DNS Provider Selection" \
        "Choose your DNS provider (all support DNSSEC):" \
        "quad9"      "Quad9          — DNSSEC, malware blocking, no logging (recommended)" \
        "cloudflare" "Cloudflare     — DNSSEC, privacy-first, fastest, minimal logging" \
        "google"     "Google         — DNSSEC, reliable, some logging" \
        "opendns"    "OpenDNS        — DNSSEC, customisable filtering" \
        "cleanbrowsing" "CleanBrowsing — DNSSEC, family-safe, malware blocking" \
        "uncensored" "UncensoredDNS  — DNSSEC, no logging, privacy-focused" \
        "skip"       "Skip           — keep current DNS settings" \
    )

    [[ "$choice" == "skip" || -z "$choice" ]] && { STATUS_SKIP "DNS (kept as-is)"; return; }

    local primary="" secondary=""
    case "$choice" in
        quad9)         primary="9.9.9.9";       secondary="149.112.112.112" ;;
        cloudflare)    primary="1.1.1.1";        secondary="1.0.0.1" ;;
        google)        primary="8.8.8.8";        secondary="8.8.4.4" ;;
        opendns)       primary="208.67.222.222"; secondary="208.67.220.220" ;;
        cleanbrowsing) primary="185.228.168.9";  secondary="185.228.169.9" ;;
        uncensored)    primary="91.239.100.100"; secondary="89.233.43.71" ;;
    esac

    STATUS_MSG "Applying DNS: primary=$primary secondary=$secondary"

    # ── systemd-resolved (systemd only — skipped gracefully on dinit/other) ────
    if svc_is_active systemd-resolved 2>/dev/null; then
        local resolved_conf="/etc/systemd/resolved.conf.d/hardn-dns.conf"
        mkdir -p /etc/systemd/resolved.conf.d
        cat > "$resolved_conf" <<EOF
[Resolve]
DNS=${primary} ${secondary}
FallbackDNS=9.9.9.9 1.1.1.1
DNSSEC=yes
DNSOverTLS=opportunistic
EOF
        svc_restart systemd-resolved
        STATUS_OK "systemd-resolved configured with $choice DNS."
        return
    fi

    # ── NetworkManager fallback ───────────────────────────────────────────────
    if command -v nmcli &>/dev/null; then
        local active_con
        active_con=$(nmcli -t -f NAME,DEVICE,STATE connection show --active \
            | grep -v "lo:" | head -1 | cut -d: -f1)
        if [[ -n "$active_con" ]]; then
            nmcli connection modify "$active_con" \
                ipv4.dns "${primary} ${secondary}" \
                ipv4.ignore-auto-dns yes &>/dev/null
            nmcli connection up "$active_con" &>/dev/null
            STATUS_OK "NetworkManager DNS set to $choice on connection: $active_con"
            return
        fi
    fi

    # ── Direct /etc/resolv.conf fallback ─────────────────────────────────────
    cp /etc/resolv.conf /etc/resolv.conf.hardn-bak.$(date +%s) 2>/dev/null || true
    # Remove immutable flag if set from a previous run
    chattr -i /etc/resolv.conf 2>/dev/null || true

    cat > /etc/resolv.conf <<EOF
# HARDN RELOADED — managed DNS (${choice})
nameserver ${primary}
nameserver ${secondary}
options edns0 trust-ad
EOF

    # Ask user if they want to lock resolv.conf against overwrites
    if ui_yesno "Lock resolv.conf" \
        "Make /etc/resolv.conf immutable to prevent DHCP from overwriting it?\n(Use 'chattr -i /etc/resolv.conf' to undo)"; then
        chattr +i /etc/resolv.conf
        STATUS_OK "resolv.conf locked (immutable)."
    fi

    STATUS_OK "DNS configured: $primary / $secondary ($choice)"
}
