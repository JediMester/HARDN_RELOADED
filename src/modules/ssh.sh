#!/usr/bin/env bash
# modules/ssh.sh — sshd_config hardening
# All tunable values come from profile variables (SSH_*).

setup_ssh() {
    [[ "${OPT_SSH_HARDEN:-0}" -eq 0 ]] && { STATUS_SKIP "SSH hardening"; return; }
    STATUS_STEP "SSH hardening"

    local sshd_cfg="/etc/ssh/sshd_config"

    if [[ ! -f "$sshd_cfg" ]]; then
        STATUS_WARN "sshd_config not found — installing openssh..."
        case "$DISTRO_FAMILY" in
            arch)   install_pkg openssh ;;
            debian) install_pkg openssh-server ;;
            rpm)    install_pkg openssh-server ;;
        esac
    fi

    # Backup original
    local backup="${sshd_cfg}.hardn-bak.$(date +%s)"
    cp "$sshd_cfg" "$backup"
    STATUS_MSG "Original sshd_config backed up → $backup"

    # Helper: set or replace a directive
    _sshd_set() {
        local key="$1" val="$2"
        if grep -qE "^#?\s*${key}\s" "$sshd_cfg"; then
            sed -i "s|^#\?\s*${key}\s.*|${key} ${val}|" "$sshd_cfg"
        else
            echo "${key} ${val}" >> "$sshd_cfg"
        fi
    }

    _sshd_set Protocol                  2
    _sshd_set PermitRootLogin           "${SSH_PERMIT_ROOT_LOGIN:-prohibit-password}"
    _sshd_set PasswordAuthentication    "${SSH_PASSWORD_AUTH:-yes}"
    _sshd_set PermitEmptyPasswords      no
    _sshd_set X11Forwarding             "${SSH_X11_FORWARDING:-no}"
    _sshd_set MaxAuthTries              "${SSH_MAX_AUTH_TRIES:-4}"
    _sshd_set LoginGraceTime            "${SSH_LOGIN_GRACE_TIME:-60}"
    _sshd_set ClientAliveInterval       "${SSH_CLIENT_ALIVE_INTERVAL:-300}"
    _sshd_set ClientAliveCountMax       "${SSH_CLIENT_ALIVE_COUNT_MAX:-0}"
    _sshd_set MaxStartups               "10:30:60"
    _sshd_set MaxSessions               "${SSH_MAX_SESSIONS:-4}"
    _sshd_set UsePAM                    yes
    _sshd_set IgnoreRhosts              yes
    _sshd_set HostbasedAuthentication   no
    _sshd_set PrintLastLog              yes
    _sshd_set Banner                    /etc/issue.net

    # Restrict allowed algorithms to modern standards
    _sshd_set KexAlgorithms             "curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512"
    _sshd_set Ciphers                   "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com"
    _sshd_set MACs                      "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com"

    # Set secure permissions on sshd_config
    chmod 644 "$sshd_cfg"

    # Validate config before restarting
    if sshd -t &>/dev/null; then
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
        STATUS_OK "SSH hardened and daemon restarted."
    else
        STATUS_ERR "sshd config validation failed — reverting to backup."
        cp "$backup" "$sshd_cfg"
        return 1
    fi
}
