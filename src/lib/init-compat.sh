#!/usr/bin/env bash
# lib/init-compat.sh — init system abstraction layer for HARDN RELOADED
#
# Supports: systemd, dinit  (runit/other: best-effort)
# Sourced by hardn.sh after detect.sh so $INIT is already exported.
#
# Public API:
#   svc_enable   SERVICE    — enable at boot and start now
#   svc_disable  SERVICE    — disable at boot and stop now
#   svc_restart  SERVICE    — restart a running service
#   svc_reload   SERVICE    — reload config (HUP where possible)
#   svc_is_active  SERVICE  — return 0 if running
#   svc_is_enabled SERVICE  — return 0 if enabled at boot
#   svc_daemon_reload       — reload manager unit registry (no-op for dinit)
#   svc_write_unit NAME DESC EXEC [RESTART] [AFTER] [TYPE]
#                           — write a service unit for the current init
#   sys_reboot              — reboot the system cleanly

# ---------------------------------------------------------------------------
# Internal: return the active init system name
# Uses $INIT if already exported by detect.sh; falls back to auto-detection.
# ---------------------------------------------------------------------------
_hardn_init() {
    local init="${INIT:-}"
    if [[ -z "$init" ]]; then
        if   systemctl --version &>/dev/null 2>&1; then init="systemd"
        elif dinitctl --version  &>/dev/null 2>&1; then init="dinit"
        else init="other"
        fi
    fi
    printf '%s' "$init"
}

# ---------------------------------------------------------------------------
# svc_enable SERVICE — enable at boot + start immediately
# ---------------------------------------------------------------------------
svc_enable() {
    local svc="$1"
    case "$(_hardn_init)" in
        systemd)
            systemctl enable --now "${svc}" 2>/dev/null || true
            ;;
        dinit)
            local svc_file=""
            for dir in /etc/dinit.d /usr/lib/dinit.d /lib/dinit.d; do
                [[ -f "${dir}/${svc}" ]] && { svc_file="${dir}/${svc}"; break; }
            done
            if [[ -z "$svc_file" ]]; then
                echo "  [WARN] dinit: no service file found for '${svc}'" >&2
                return 1
            fi
            mkdir -p /etc/dinit.d/boot.d
            ln -sf "$svc_file" "/etc/dinit.d/boot.d/${svc}"
            dinitctl start "${svc}" 2>/dev/null || true
            ;;
        *)
            echo "  [WARN] Unsupported init — cannot enable '${svc}'" >&2
            ;;
    esac
}

# ---------------------------------------------------------------------------
# svc_disable SERVICE — remove from boot and stop immediately
# ---------------------------------------------------------------------------
svc_disable() {
    local svc="$1"
    case "$(_hardn_init)" in
        systemd)
            systemctl disable --now "${svc}" 2>/dev/null || true
            ;;
        dinit)
            rm -f "/etc/dinit.d/boot.d/${svc}"
            dinitctl stop "${svc}" 2>/dev/null || true
            ;;
        *)
            echo "  [WARN] Unsupported init — cannot disable '${svc}'" >&2
            ;;
    esac
}

# ---------------------------------------------------------------------------
# svc_restart SERVICE
# ---------------------------------------------------------------------------
svc_restart() {
    local svc="$1"
    case "$(_hardn_init)" in
        systemd) systemctl restart  "${svc}" 2>/dev/null || true ;;
        dinit)   dinitctl  restart  "${svc}" 2>/dev/null || true ;;
        *)       echo "  [WARN] Unsupported init — cannot restart '${svc}'" >&2 ;;
    esac
}

# ---------------------------------------------------------------------------
# svc_reload SERVICE — reload config without full restart where possible
# ---------------------------------------------------------------------------
svc_reload() {
    local svc="$1"
    case "$(_hardn_init)" in
        systemd)
            systemctl reload-or-restart "${svc}" 2>/dev/null || true
            ;;
        dinit)
            # dinit has no native reload signal; send HUP to the main pid
            local pid
            pid=$(dinitctl status "${svc}" 2>/dev/null \
                  | grep -oP 'pid: \K[0-9]+' | head -1)
            if [[ -n "$pid" ]]; then
                kill -HUP "$pid" 2>/dev/null || svc_restart "${svc}"
            else
                svc_restart "${svc}"
            fi
            ;;
        *)
            svc_restart "${svc}"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# svc_is_active SERVICE — returns 0 if the service is currently running
# ---------------------------------------------------------------------------
svc_is_active() {
    local svc="$1"
    case "$(_hardn_init)" in
        systemd) systemctl is-active --quiet "${svc}" 2>/dev/null ;;
        dinit)   dinitctl status "${svc}" 2>/dev/null | grep -q "STARTED" ;;
        *)       return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# svc_is_enabled SERVICE — returns 0 if enabled at boot
# ---------------------------------------------------------------------------
svc_is_enabled() {
    local svc="$1"
    case "$(_hardn_init)" in
        systemd) systemctl is-enabled --quiet "${svc}" 2>/dev/null ;;
        dinit)   [[ -L "/etc/dinit.d/boot.d/${svc}" ]] ;;
        *)       return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# svc_daemon_reload — flush the init manager's unit cache after writing files
# dinit reads service files on-demand so this is a no-op there.
# ---------------------------------------------------------------------------
svc_daemon_reload() {
    case "$(_hardn_init)" in
        systemd) systemctl daemon-reload 2>/dev/null || true ;;
        dinit)   : ;;
    esac
}

# ---------------------------------------------------------------------------
# svc_write_unit — write a service definition for the current init system
#
# Args:
#   $1  name         Service name (no extension)
#   $2  description  Human-readable description
#   $3  exec_start   Full command string to execute
#   $4  restart      Restart policy: always | on-failure | no  (default: always)
#   $5  after        Space-separated dependencies (e.g. "network firewalld")
#                    Note: systemd .target names are stripped for dinit
#   $6  type         process | oneshot  (default: process)
#
# Systemd: writes /etc/systemd/system/<name>.service
# Dinit:   writes /etc/dinit.d/<name>
# Caller should call svc_enable afterwards.
# ---------------------------------------------------------------------------
svc_write_unit() {
    local name="$1"
    local description="$2"
    local exec_start="$3"
    local restart="${4:-always}"
    local after="${5:-}"
    local type="${6:-process}"

    case "$(_hardn_init)" in
        systemd)
            local systemd_restart="$restart"
            [[ "$restart" == "no" ]] && systemd_restart="no"
            local systemd_type="simple"
            [[ "$type" == "oneshot" ]] && systemd_type="oneshot"

            local unit_file="/etc/systemd/system/${name}.service"
            {
                echo "[Unit]"
                echo "Description=${description}"
                for dep in $after; do
                    echo "After=${dep}"
                    # Only add Requires= for real services, not targets
                    [[ "$dep" != *.target ]] && echo "Requires=${dep}"
                done
                echo ""
                echo "[Service]"
                echo "Type=${systemd_type}"
                echo "ExecStart=${exec_start}"
                echo "Restart=${systemd_restart}"
                echo "User=root"
                echo "RestartSec=5s"
                echo "StandardOutput=journal"
                echo "StandardError=journal"
                echo "SyslogIdentifier=${name}"
                echo ""
                echo "[Install]"
                echo "WantedBy=multi-user.target"
            } > "$unit_file"
            svc_daemon_reload
            ;;

        dinit)
            local dinit_type="process"
            [[ "$type" == "oneshot" ]] && dinit_type="scripted"

            local svc_file="/etc/dinit.d/${name}"
            {
                echo "type = ${dinit_type}"
                echo "command = ${exec_start}"
                [[ "$restart" == "always" ]] && echo "restart = true"
                for dep in $after; do
                    # Skip systemd-specific target units — no dinit equivalent
                    [[ "$dep" == *.target ]] && continue
                    # Strip .service suffix if present
                    local dep_name="${dep%.service}"
                    echo "waits-for = ${dep_name}"
                    echo "after = ${dep_name}"
                done
            } > "$svc_file"
            ;;

        *)
            echo "  [WARN] Unsupported init — cannot write unit for '${name}'" >&2
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# sys_reboot — reboot cleanly via whatever mechanism is appropriate
# ---------------------------------------------------------------------------
sys_reboot() {
    case "$(_hardn_init)" in
        systemd) systemctl reboot ;;
        *)       reboot ;;
    esac
}
