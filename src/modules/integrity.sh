#!/usr/bin/env bash
# modules/integrity.sh — AIDE file integrity monitoring + package-level checks

setup_integrity() {
    [[ "${OPT_INTEGRITY:-0}" -eq 0 ]] && { STATUS_SKIP "File integrity"; return; }
    STATUS_STEP "File integrity monitoring (AIDE)"

    install_pkg $PKG_INTEGRITY

    # ── AIDE ──────────────────────────────────────────────────────────────────
    if [[ "${OPT_AIDE:-1}" -eq 1 ]]; then
        # Arch: config at /etc/aide.conf; Debian: /etc/aide/aide.conf
        local aide_conf
        aide_conf=$(find /etc/aide* -name "aide.conf" 2>/dev/null | head -1)
        aide_conf="${aide_conf:-/etc/aide.conf}"

        if [[ -f "$aide_conf" ]]; then
            cp "$aide_conf" "${aide_conf}.hardn-bak.$(date +%s)"
        fi

        # Initialise database (can take several minutes on first run)
        STATUS_MSG "Initialising AIDE database (this may take a few minutes)..."
        if command -v aideinit &>/dev/null; then
            # Debian-style
            aideinit --yes &>/dev/null \
                && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db 2>/dev/null || true
        else
            # Arch/RPM-style
            aide --init &>/dev/null \
                && mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz 2>/dev/null || true
        fi

        # Daily check cron (05:00)
        cat > /etc/cron.d/hardn-aide <<'EOF'
# HARDN: daily AIDE integrity check
0 5 * * * root aide --check 2>&1 | logger -t aide
EOF
        STATUS_OK "AIDE initialised with daily check cron (05:00)."
    fi

    # ── Package-level integrity ───────────────────────────────────────────────
    # Verify installed file checksums against package database
    case "$DISTRO_FAMILY" in
        arch)
            # paccheck --sha256sum checks file hashes (from pacman-contrib)
            if command -v paccheck &>/dev/null; then
                cat > /etc/cron.d/hardn-paccheck <<'EOF'
# HARDN: weekly package file integrity check
0 4 * * 0 root paccheck --sha256sum --quiet 2>&1 | logger -t paccheck
EOF
                STATUS_OK "paccheck weekly cron added (Sun 04:00)."
            fi
            ;;
        debian)
            # debsums verifies Debian package MD5 checksums
            if command -v debsums &>/dev/null; then
                cat > /etc/cron.d/hardn-debsums <<'EOF'
# HARDN: daily debsums package integrity check
0 4 * * * root debsums -s 2>&1 | logger -t debsums
EOF
                STATUS_OK "debsums daily cron added (04:00)."
            fi
            ;;
        rpm)
            # rpm -Va verifies all installed packages
            cat > /etc/cron.d/hardn-rpmverify <<'EOF'
# HARDN: weekly RPM package verification
0 4 * * 0 root rpm -Va 2>&1 | logger -t rpmverify
EOF
            STATUS_OK "rpm -Va weekly cron added (Sun 04:00)."
            ;;
    esac
}
