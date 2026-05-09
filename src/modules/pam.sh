#!/usr/bin/env bash
# modules/pam.sh — PAM password quality, core dump disabling, shared memory

setup_pam() {
    [[ "${OPT_PAM_PWQUALITY:-0}" -eq 0 ]] && { STATUS_SKIP "PAM hardening"; return; }
    STATUS_STEP "PAM / authentication hardening"

    install_pkg $PKG_PAM_PWQUALITY

    # ── Password quality ─────────────────────────────────────────────────────
    local pwquality_conf="/etc/security/pwquality.conf"
    if [[ -f "$pwquality_conf" ]]; then
        cp "$pwquality_conf" "${pwquality_conf}.hardn-bak.$(date +%s)"
    fi

    cat > "$pwquality_conf" <<EOF
# HARDN RELOADED — password quality (profile: ${HARDN_PROFILE})
minlen   = ${PAM_MIN_PASSWORD_LEN:-12}
dcredit  = -1
ucredit  = -1
lcredit  = -1
ocredit  = -1
difok    = 3
retry    = ${PAM_PASSWORD_RETRY:-3}
EOF
    STATUS_OK "pwquality.conf written (minlen=${PAM_MIN_PASSWORD_LEN:-12})."

    # ── PAM common-password / system-auth ────────────────────────────────────
    # Apply per distro — ensure pam_pwquality is wired in
    case "$DISTRO_FAMILY" in
        debian)
            local pam_pw="/etc/pam.d/common-password"
            if [[ -f "$pam_pw" ]] && ! grep -q "pam_pwquality" "$pam_pw"; then
                sed -i '/pam_unix\.so/i password requisite pam_pwquality.so retry='"${PAM_PASSWORD_RETRY:-3}" \
                    "$pam_pw"
                STATUS_OK "pam_pwquality added to common-password."
            fi
            ;;
        arch|rpm)
            # On Arch/RPM, pwquality is typically wired via /etc/pam.d/system-auth
            local pam_sys="/etc/pam.d/system-auth"
            if [[ -f "$pam_sys" ]] && ! grep -q "pam_pwquality" "$pam_sys"; then
                sed -i '/pam_unix\.so/i password requisite pam_pwquality.so retry='"${PAM_PASSWORD_RETRY:-3}" \
                    "$pam_sys"
                STATUS_OK "pam_pwquality added to system-auth."
            fi
            ;;
    esac

    # ── Core dump hardening ───────────────────────────────────────────────────
    if [[ "${OPT_DISABLE_CORE_DUMPS:-1}" -eq 1 ]]; then
        # limits.conf
        local limits="/etc/security/limits.conf"
        grep -q "hard core" "$limits" 2>/dev/null \
            || echo "* hard core 0" >> "$limits"

        # sysctl (also set in kernel.sh but belt-and-suspenders)
        echo "fs.suid_dumpable = 0"    >  /etc/sysctl.d/98-hardn-coredump.conf
        echo "kernel.core_pattern = /dev/null" >> /etc/sysctl.d/98-hardn-coredump.conf
        sysctl -p /etc/sysctl.d/98-hardn-coredump.conf &>/dev/null

        # systemd coredump (systemd-only)
        if [[ "$INIT" == "systemd" ]]; then
            mkdir -p /etc/systemd/coredump.conf.d
            cat > /etc/systemd/coredump.conf.d/hardn.conf <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF
        fi
        STATUS_OK "Core dumps disabled."
    fi

    # ── Shared memory hardening ───────────────────────────────────────────────
    if [[ "${OPT_SHARED_MEMORY_HARDEN:-1}" -eq 1 ]]; then
        if ! grep -q "hardn-shm" /etc/fstab 2>/dev/null; then
            echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid,nodev 0 0  # hardn-shm" >> /etc/fstab
        fi
        mount -o remount /run/shm 2>/dev/null || true
        STATUS_OK "Shared memory hardened (noexec,nosuid,nodev)."
    fi
}
