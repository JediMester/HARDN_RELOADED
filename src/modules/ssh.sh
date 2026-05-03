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

    # Helper: set or replace a directive (handles commented-out lines too)
    _sshd_set() {
        local key="$1" val="$2"
        if grep -qE "^#?\s*${key}\s" "$sshd_cfg"; then
            sed -i "s|^#\?\s*${key}\s.*|${key} ${val}|" "$sshd_cfg"
        else
            echo "${key} ${val}" >> "$sshd_cfg"
        fi
    }

    # ── Pre-flight: warn if key-only is enabled but no keys exist ────────────
    if [[ "${SSH_PASSWORD_AUTH:-no}" == "no" ]]; then
        local found_keys=0
        while IFS=: read -r _u _p _uid _gid _gecos home _shell; do
            [[ -f "${home}/.ssh/authorized_keys" ]] && found_keys=1 && break
        done < /etc/passwd
        if [[ "$found_keys" -eq 0 ]]; then
            STATUS_WARN "────────────────────────────────────────────────────"
            STATUS_WARN "KEY-ONLY AUTH ENABLED — no authorized_keys found!"
            STATUS_WARN "Deploy your public key BEFORE logging out or you"
            STATUS_WARN "will be locked out of SSH."
            STATUS_WARN ""
            STATUS_WARN "  # On your client machine:"
            STATUS_WARN "  ssh-keygen -t ed25519 -C 'your@email'"
            STATUS_WARN "  ssh-copy-id -p ${SSH_PORT:-22} user@$(hostname)"
            STATUS_WARN "────────────────────────────────────────────────────"
        fi
    fi

    # ── Protocol & network ───────────────────────────────────────────────────
    _sshd_set Protocol              2
    _sshd_set Port                  "${SSH_PORT:-22}"
    _sshd_set AddressFamily         any
    _sshd_set ListenAddress         0.0.0.0

    # ── Logging ──────────────────────────────────────────────────────────────
    _sshd_set SyslogFacility        AUTH
    _sshd_set LogLevel              "${SSH_LOG_LEVEL:-VERBOSE}"

    # ── Authentication ───────────────────────────────────────────────────────
    _sshd_set PermitRootLogin           "${SSH_PERMIT_ROOT_LOGIN:-no}"
    _sshd_set StrictModes               yes
    _sshd_set PubkeyAuthentication      yes
    _sshd_set AuthorizedKeysFile        ".ssh/authorized_keys"
    _sshd_set PasswordAuthentication    "${SSH_PASSWORD_AUTH:-no}"
    _sshd_set PermitEmptyPasswords      no
    # KbdInteractiveAuthentication is the modern name (OpenSSH >= 8.7).
    # ChallengeResponseAuthentication was removed in OpenSSH 9.8; only set it
    # if the directive already exists in the config so sshd -t doesn't reject it.
    _sshd_set KbdInteractiveAuthentication no
    if grep -qE "^#?\s*ChallengeResponseAuthentication\s" "$sshd_cfg"; then
        _sshd_set ChallengeResponseAuthentication no
    fi

    # Enforce publickey-only when password auth is disabled
    if [[ "${SSH_PASSWORD_AUTH:-no}" == "no" ]]; then
        _sshd_set AuthenticationMethods    publickey
    fi

    # Legacy / enterprise auth methods — always disabled
    _sshd_set HostbasedAuthentication   no
    _sshd_set IgnoreRhosts             yes
    _sshd_set IgnoreUserKnownHosts     no
    _sshd_set PermitUserEnvironment    no
    _sshd_set KerberosAuthentication   no
    _sshd_set GSSAPIAuthentication     no

    # ── Session limits ───────────────────────────────────────────────────────
    _sshd_set MaxAuthTries          "${SSH_MAX_AUTH_TRIES:-3}"
    _sshd_set MaxSessions           "${SSH_MAX_SESSIONS:-4}"
    _sshd_set LoginGraceTime        "${SSH_LOGIN_GRACE_TIME:-30}"
    _sshd_set MaxStartups           "10:30:60"

    # ── Connection keepalive (ClientAlive preferred over TCPKeepAlive) ───────
    _sshd_set TCPKeepAlive          no
    _sshd_set ClientAliveInterval   "${SSH_CLIENT_ALIVE_INTERVAL:-300}"
    _sshd_set ClientAliveCountMax   "${SSH_CLIENT_ALIVE_COUNT_MAX:-0}"

    # ── Forwarding & tunnelling ───────────────────────────────────────────────
    _sshd_set X11Forwarding         "${SSH_X11_FORWARDING:-no}"
    _sshd_set AllowTcpForwarding    "${SSH_TCP_FORWARDING:-no}"
    _sshd_set AllowAgentForwarding  "${SSH_AGENT_FORWARDING:-no}"
    _sshd_set GatewayPorts          no
    _sshd_set PermitTunnel          no
    _sshd_set Compression           no

    # ── PAM & system integration ─────────────────────────────────────────────
    _sshd_set UsePAM                yes
    _sshd_set PrintLastLog          yes
    _sshd_set PrintMotd             no
    _sshd_set Banner                /etc/issue.net
    _sshd_set AcceptEnv             "LANG LC_*"

    # ── Cryptographic algorithms — modern only ───────────────────────────────
    _sshd_set HostKeyAlgorithms     "ssh-ed25519,rsa-sha2-512,rsa-sha2-256"
    _sshd_set KexAlgorithms         "curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512"
    _sshd_set Ciphers               "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com"
    _sshd_set MACs                  "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com"

    # ── Secure permissions on sshd_config (root read-only) ───────────────────
    chown root:root "$sshd_cfg"
    chmod 600 "$sshd_cfg"

    # Validate config before restarting — revert on failure
    if sshd -t &>/dev/null; then
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
        STATUS_OK "SSH hardened — port=${SSH_PORT:-22}, root=${SSH_PERMIT_ROOT_LOGIN:-no}, key-only=$([ "${SSH_PASSWORD_AUTH:-no}" = "no" ] && echo yes || echo no), loglevel=${SSH_LOG_LEVEL:-VERBOSE}"
    else
        STATUS_ERR "sshd config validation failed — reverting to backup."
        cp "$backup" "$sshd_cfg"
        chmod 644 "$sshd_cfg"
        return 1
    fi
}
