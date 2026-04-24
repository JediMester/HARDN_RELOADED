#!/usr/bin/env bash
# modules/logging.sh — centralised rsyslog routing + logrotate

setup_logging() {
    [[ "${OPT_LOGGING:-0}" -eq 0 ]] && { STATUS_SKIP "Centralised logging"; return; }
    STATUS_STEP "Centralised logging (rsyslog + logrotate)"

    install_pkg $PKG_RSYSLOG $PKG_LOGROTATE

    # ── Log directory ─────────────────────────────────────────────────────────
    local log_dir="/var/log/hardn"
    mkdir -p "$log_dir"
    chmod 750 "$log_dir"

    # ── rsyslog routing ───────────────────────────────────────────────────────
    cat > /etc/rsyslog.d/30-hardn.conf <<EOF
# HARDN RELOADED — security tool log routing
# Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Route logs from known security tools into one consolidated file
:programname, isequal, "suricata"    -${log_dir}/hardn.log
:programname, isequal, "aide"        -${log_dir}/hardn.log
:programname, isequal, "fail2ban"    -${log_dir}/hardn.log
:programname, isequal, "apparmor"    -${log_dir}/hardn.log
:programname, isequal, "audit"       -${log_dir}/hardn.log
:programname, isequal, "auditd"      -${log_dir}/hardn.log
:programname, isequal, "rkhunter"    -${log_dir}/hardn.log
:programname, isequal, "chkrootkit"  -${log_dir}/hardn.log
:programname, isequal, "clamav"      -${log_dir}/hardn.log
:programname, isequal, "debsums"     -${log_dir}/hardn.log
:programname, isequal, "paccheck"    -${log_dir}/hardn.log
:programname, isequal, "rpmverify"   -${log_dir}/hardn.log
:programname, isequal, "dynamic_firewalld_rules" -${log_dir}/hardn.log
EOF

    # ── logrotate ────────────────────────────────────────────────────────────
    cat > /etc/logrotate.d/hardn <<EOF
${log_dir}/hardn.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    postrotate
        systemctl kill --kill-who=main --signal=HUP rsyslog.service 2>/dev/null || true
    endscript
}
EOF

    # ── Process accounting ────────────────────────────────────────────────────
    if [[ "${OPT_PROCESS_ACCOUNTING:-1}" -eq 1 ]]; then
        install_pkg $PKG_ACCT $PKG_SYSSTAT

        systemctl enable --now acct  2>/dev/null \
            || systemctl enable --now psacct 2>/dev/null || true

        # Enable sysstat data collection
        local sysstat_default="/etc/default/sysstat"
        if [[ -f "$sysstat_default" ]]; then
            sed -i 's/ENABLED=.*/ENABLED="true"/' "$sysstat_default"
        fi
        systemctl enable --now sysstat 2>/dev/null || true
        STATUS_OK "Process accounting (acct + sysstat) enabled."
    fi

    # Reload rsyslog
    systemctl restart rsyslog 2>/dev/null || true
    STATUS_OK "Centralised logging active → ${log_dir}/hardn.log"
}
