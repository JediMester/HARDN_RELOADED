#!/usr/bin/env bash
# modules/audit.sh — auditd installation and STIG-aligned audit rules

setup_audit() {
    [[ "${OPT_AUDITD:-0}" -eq 0 ]] && { STATUS_SKIP "auditd"; return; }
    STATUS_STEP "auditd (STIG audit rules)"

    install_pkg $PKG_AUDIT

    systemctl enable --now auditd 2>/dev/null || true

    local rules_file="/etc/audit/rules.d/hardn.rules"
    mkdir -p /etc/audit/rules.d

    cat > "$rules_file" <<EOF
## HARDN RELOADED — audit rules
## Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ") — profile: ${HARDN_PROFILE}
## Based on DISA STIG for Linux

-D                          # delete all existing rules
-b ${AUDIT_BUFFER_SIZE:-8192}
-f 1                        # failure mode: log (use 2 to panic on failure)

## ── Identity & authentication files ────────────────────────────────────────
-w /etc/passwd   -p wa -k identity
-w /etc/shadow   -p wa -k identity
-w /etc/group    -p wa -k identity
-w /etc/gshadow  -p wa -k identity
-w /etc/sudoers  -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

## ── System configuration ────────────────────────────────────────────────────
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/pam.d/           -p wa -k pam
-w /etc/security/        -p wa -k security
-w /etc/sysctl.conf      -p wa -k sysctl
-w /etc/sysctl.d/        -p wa -k sysctl
-w /etc/modprobe.d/      -p wa -k modules
-w /etc/crontab          -p wa -k cron
-w /etc/cron.d/          -p wa -k cron
-w /etc/cron.daily/      -p wa -k cron
-w /etc/cron.weekly/     -p wa -k cron
-w /etc/cron.monthly/    -p wa -k cron
-w /var/spool/cron/      -p wa -k cron
-w /etc/fstab            -p wa -k fstab
-w /etc/hosts            -p wa -k hosts
-w /etc/hostname         -p wa -k hostname

## ── Login & session tracking ────────────────────────────────────────────────
-w /var/log/faillog    -p wa -k logins
-w /var/log/lastlog    -p wa -k logins
-w /var/log/btmp       -p wa -k logins
-w /var/run/utmp       -p wa -k session
-w /var/log/wtmp       -p wa -k logins

## ── Privilege escalation ────────────────────────────────────────────────────
-w /usr/bin/sudo    -p x -k privilege_escalation
-w /usr/bin/su      -p x -k privilege_escalation
-w /usr/bin/newgrp  -p x -k privilege_escalation
-w /usr/bin/chsh    -p x -k privilege_escalation
-w /usr/bin/chfn    -p x -k privilege_escalation
-w /usr/sbin/visudo -p x -k privilege_escalation

## ── Kernel module activity ──────────────────────────────────────────────────
-w /sbin/insmod    -p x -k modules
-w /sbin/rmmod     -p x -k modules
-w /sbin/modprobe  -p x -k modules
-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k modules
-a always,exit -F arch=b32 -S init_module,finit_module,delete_module -k modules

## ── System calls: time changes ──────────────────────────────────────────────
-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time_change
-a always,exit -F arch=b32 -S adjtimex,settimeofday,stime,clock_settime -k time_change
-w /etc/localtime -p wa -k time_change

## ── System calls: network configuration ────────────────────────────────────
-a always,exit -F arch=b64 -S sethostname,setdomainname -k network_config
-a always,exit -F arch=b32 -S sethostname,setdomainname -k network_config
-w /etc/issue     -p wa -k network_config
-w /etc/issue.net -p wa -k network_config

## ── System calls: UID/GID changes ───────────────────────────────────────────
-a always,exit -F arch=b64 -S setuid,setreuid,setresuid,setfsuid -k uid_change
-a always,exit -F arch=b32 -S setuid,setreuid,setresuid,setfsuid -k uid_change
-a always,exit -F arch=b64 -S setgid,setregid,setresgid,setfsgid -k gid_change
-a always,exit -F arch=b32 -S setgid,setregid,setresgid,setfsgid -k gid_change

## ── System calls: ptrace (debugging / injection) ────────────────────────────
-a always,exit -F arch=b64 -S ptrace -k ptrace
-a always,exit -F arch=b32 -S ptrace -k ptrace

## ── Privileged commands (SUID/SGID) ─────────────────────────────────────────
-a always,exit -F path=/usr/bin/passwd   -F perm=x -F auid>=1000 -F auid!=-1 -k privileged
-a always,exit -F path=/usr/bin/gpasswd  -F perm=x -F auid>=1000 -F auid!=-1 -k privileged
-a always,exit -F path=/usr/bin/mount    -F perm=x -F auid>=1000 -F auid!=-1 -k privileged
-a always,exit -F path=/usr/bin/umount   -F perm=x -F auid>=1000 -F auid!=-1 -k privileged
-a always,exit -F path=/usr/bin/crontab  -F perm=x -F auid>=1000 -F auid!=-1 -k privileged
-a always,exit -F path=/usr/sbin/useradd -F perm=x -F auid>=1000 -F auid!=-1 -k account_mod
-a always,exit -F path=/usr/sbin/userdel -F perm=x -F auid>=1000 -F auid!=-1 -k account_mod
-a always,exit -F path=/usr/sbin/usermod -F perm=x -F auid>=1000 -F auid!=-1 -k account_mod
-a always,exit -F path=/usr/sbin/groupadd -F perm=x -F auid>=1000 -F auid!=-1 -k account_mod
-a always,exit -F path=/usr/sbin/groupdel -F perm=x -F auid>=1000 -F auid!=-1 -k account_mod

## ── Filesystem: mount/unmount ────────────────────────────────────────────────
-a always,exit -F arch=b64 -S mount,umount2 -k mount
-a always,exit -F arch=b32 -S mount,umount2 -k mount

## ── Namespace / container activity ──────────────────────────────────────────
-a always,exit -F arch=b64 -S unshare,clone -F a0&0x10000000 -k containers
-a always,exit -F arch=b32 -S unshare,clone -F a0&0x10000000 -k containers

## ── Chroot ───────────────────────────────────────────────────────────────────
-a always,exit -F arch=b64 -S chroot -k chroot
-a always,exit -F arch=b32 -S chroot -k chroot

## ── File deletion by non-root ────────────────────────────────────────────────
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=-1 -k delete
-a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=-1 -k delete

## ── Audit log file tampering ─────────────────────────────────────────────────
-w /var/log/audit/ -p wa -k audit_logs
-w /etc/audit/     -p wa -k audit_config

EOF

    # Immutable flag: must reboot to change rules (server & work profiles)
    if [[ "${OPT_AUDIT_IMMUTABLE:-1}" -eq 1 ]]; then
        echo "-e 2   # immutable — reboot required to modify rules" >> "$rules_file"
        STATUS_WARN "Audit rules set to immutable (-e 2). A reboot is required to change rules."
    fi

    # Load rules now (non-fatal if augenrules is unavailable)
    if command -v augenrules &>/dev/null; then
        augenrules --load &>/dev/null && STATUS_OK "Audit rules loaded via augenrules."
    else
        auditctl -R "$rules_file" &>/dev/null && STATUS_OK "Audit rules loaded via auditctl."
    fi

    systemctl restart auditd 2>/dev/null || true
    STATUS_OK "auditd configured → $rules_file"
}
