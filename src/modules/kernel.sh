#!/usr/bin/env bash
# modules/kernel.sh — sysctl kernel hardening
# Respects profile flags: OPT_KERNEL_HARDEN, OPT_DISABLE_IPV6, etc.

setup_kernel() {
    [[ "${OPT_KERNEL_HARDEN:-0}" -eq 0 ]] && { STATUS_SKIP "Kernel hardening"; return; }
    STATUS_STEP "Kernel / sysctl hardening"

    local sysctl_file="/etc/sysctl.d/99-hardn.conf"

    cat > "$sysctl_file" <<EOF
# HARDN RELOADED — kernel hardening
# Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ") by profile: ${HARDN_PROFILE}

# ── Memory & address space ───────────────────────────────────────────────────
kernel.randomize_va_space = 2          # Full ASLR
fs.suid_dumpable = 0                   # No core dumps from SUID binaries
kernel.core_uses_pid = 1
kernel.core_pattern = /dev/null

# ── Information leak prevention ─────────────────────────────────────────────
kernel.kptr_restrict = ${OPT_KPTR_RESTRICT:+2}${OPT_KPTR_RESTRICT:-0}
kernel.dmesg_restrict = ${OPT_DMESG_RESTRICT:+1}${OPT_DMESG_RESTRICT:-0}
kernel.perf_event_paranoid = ${OPT_PERF_RESTRICT:+3}${OPT_PERF_RESTRICT:-1}
kernel.unprivileged_bpf_disabled = ${OPT_BPF_HARDEN:+1}${OPT_BPF_HARDEN:-0}
net.core.bpf_jit_harden = ${OPT_BPF_HARDEN:+2}${OPT_BPF_HARDEN:-0}

# ── Ptrace scope ────────────────────────────────────────────────────────────
kernel.yama.ptrace_scope = 1           # Restrict ptrace to parent processes

# ── Ctrl-Alt-Del ─────────────────────────────────────────────────────────────
kernel.ctrl-alt-del = 0

# ── Filesystem protections ───────────────────────────────────────────────────
fs.protected_fifos = 2
fs.protected_hardlinks = 1
fs.protected_regular = 2
fs.protected_symlinks = 1

# ── Network — IPv4 ───────────────────────────────────────────────────────────
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.all.bootp_relay = 0
net.ipv4.conf.all.proxy_arp = 0
net.ipv4.conf.all.forwarding = 0

EOF

    # ── IPv6 ────────────────────────────────────────────────────────────────
    if [[ "${OPT_DISABLE_IPV6:-0}" -eq 1 ]]; then
        cat >> "$sysctl_file" <<'EOF'
# IPv6 disabled by profile
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
        STATUS_MSG "IPv6 disabled."
    else
        cat >> "$sysctl_file" <<'EOF'
# IPv6 hardening (kept enabled per profile)
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.all.forwarding = 0
EOF
        STATUS_MSG "IPv6 hardened (kept enabled)."
    fi

    # Apply immediately
    sysctl --system &>/dev/null
    STATUS_OK "Kernel sysctl hardening applied → $sysctl_file"
}
