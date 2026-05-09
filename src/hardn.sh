#!/usr/bin/env bash
# hardn.sh — HARDN RELOADED main entry point
#
# Usage:
#   sudo ./hardn.sh                    # interactive menu
#   sudo ./hardn.sh --profile gaming   # skip profile menu (server|work|gaming)
#   sudo ./hardn.sh --profile server --no-confirm   # fully non-interactive
#
# Requires: bash 4+, root privileges. Supports: systemd, dinit.

set -euo pipefail

HARDN_VERSION="3.0.0"
HARDN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Root check ───────────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: HARDN RELOADED must be run as root (use sudo)." >&2
    exit 1
fi

# ── Source libraries ─────────────────────────────────────────────────────────
# shellcheck source=lib/detect.sh
source "${HARDN_DIR}/lib/detect.sh"
# shellcheck source=lib/init-compat.sh
source "${HARDN_DIR}/lib/init-compat.sh"
# shellcheck source=lib/ui.sh
source "${HARDN_DIR}/lib/ui.sh"
# shellcheck source=lib/packages.sh
source "${HARDN_DIR}/lib/packages.sh"

# ── Source all modules ────────────────────────────────────────────────────────
for mod in "${HARDN_DIR}/modules/"*.sh; do
    # shellcheck source=/dev/null
    source "$mod"
done

# ── Parse arguments ───────────────────────────────────────────────────────────
ARG_PROFILE=""
ARG_NO_CONFIRM=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            ARG_PROFILE="${2:-}"
            shift 2
            ;;
        --no-confirm)
            ARG_NO_CONFIRM=1
            shift
            ;;
        --help|-h)
            echo "Usage: sudo $0 [--profile server|work|gaming] [--no-confirm]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ── Detect environment ───────────────────────────────────────────────────────
detect_os
detect_kernel_features
detect_existing_services
detect_browsers

# ── Package name maps (requires DISTRO_FAMILY from detect_os) ────────────────
setup_package_maps

# ── UI backend ───────────────────────────────────────────────────────────────
ensure_ui_backend

# ── Banner ───────────────────────────────────────────────────────────────────
clear
print_banner
echo -e "  System:  ${DISTRO_PRETTY}"
echo -e "  Family:  ${DISTRO_FAMILY}  |  Init: ${INIT}  |  VM: $([ $IS_VM -eq 1 ] && echo yes || echo no)"
echo -e "  Kernel:  $(uname -r)"
[[ "$IS_HARDENED_KERNEL" -eq 1 ]] && echo -e "  Hardened kernel detected."
echo ""

# ── Pre-flight warnings ───────────────────────────────────────────────────────
if [[ "$DFR_FWD_ACTIVE" -eq 1 ]]; then
    STATUS_SKIP "dfr_fwd dynamic firewall already running — firewall module will skip install."
fi

# ── Profile selection ────────────────────────────────────────────────────────
if [[ -n "$ARG_PROFILE" ]]; then
    HARDN_PROFILE="$ARG_PROFILE"
    export HARDN_PROFILE
else
    select_profile
fi

# Validate profile
profile_file="${HARDN_DIR}/profiles/${HARDN_PROFILE}.conf"
if [[ ! -f "$profile_file" ]]; then
    STATUS_ERR "Profile file not found: $profile_file"
    exit 1
fi

# Load profile defaults
# shellcheck source=/dev/null
source "$profile_file"

STATUS_MSG "Profile loaded: ${PROFILE_NAME}"

# ── Module toggle menu (fine-tune profile, unless --no-confirm) ───────────────
if [[ "$ARG_NO_CONFIRM" -eq 0 ]]; then
    if ui_yesno "Module Selection" \
        "Profile '${PROFILE_NAME}' loaded with sensible defaults.\n\nWould you like to review and toggle individual modules?"; then
        select_modules
    fi
fi

# ── Confirmation summary ──────────────────────────────────────────────────────
if [[ "$ARG_NO_CONFIRM" -eq 0 ]]; then
    summary="Profile: ${PROFILE_NAME}\n\nEnabled modules:"
    [[ "${OPT_KERNEL_HARDEN:-0}"    -eq 1 ]] && summary+="\n  ✓ Kernel hardening"
    [[ "${OPT_MODULE_BLACKLIST:-0}" -eq 1 ]] && summary+="\n  ✓ Kernel module blacklisting"
    [[ "${OPT_FIREWALL:-0}"         -eq 1 ]] && summary+="\n  ✓ Firewall (firewalld)"
    [[ "${OPT_DFR_FWD:-0}"          -eq 1 ]] && summary+="\n  ✓ Dynamic port-scan blocker (dfr_fwd)"
    [[ "${OPT_SSH_HARDEN:-0}"       -eq 1 ]] && summary+="\n  ✓ SSH hardening"
    [[ "${OPT_PAM_PWQUALITY:-0}"    -eq 1 ]] && summary+="\n  ✓ PAM / password quality"
    [[ "${OPT_AUDITD:-0}"           -eq 1 ]] && summary+="\n  ✓ auditd (STIG rules)"
    [[ "${OPT_IDS:-0}"              -eq 1 ]] && summary+="\n  ✓ IDS/IPS (fail2ban + Suricata)"
    [[ "${OPT_MALWARE:-0}"          -eq 1 ]] && summary+="\n  ✓ Malware detection (ClamAV + rkhunter)"
    [[ "${OPT_INTEGRITY:-0}"        -eq 1 ]] && summary+="\n  ✓ File integrity (AIDE)"
    [[ "${OPT_LOGGING:-0}"          -eq 1 ]] && summary+="\n  ✓ Centralised logging"
    [[ "${OPT_AUTO_UPDATES:-0}"     -eq 1 ]] && summary+="\n  ✓ Automatic security updates"
    [[ "${OPT_DNS:-0}"              -eq 1 ]] && summary+="\n  ✓ Secure DNS"
    [[ "${OPT_DISABLE_SERVICES:-0}" -eq 1 ]] && summary+="\n  ✓ Disable unnecessary services"
    [[ "${OPT_FIREJAIL:-0}"         -eq 1 ]] && summary+="\n  ✓ Firejail sandboxing"
    [[ "${OPT_BANNERS:-0}"          -eq 1 ]] && summary+="\n  ✓ STIG login banners"
    [[ "${OPT_HARDN_TUI:-0}"        -eq 1 ]] && summary+="\n  ✓ hardn-tui security dashboard"
    summary+="\n\nThis will modify system configuration. Continue?"

    if ! ui_yesno "Confirm Hardening" "$summary"; then
        STATUS_MSG "Aborted by user."
        exit 0
    fi
fi

# ── System update ─────────────────────────────────────────────────────────────
if [[ "$ARG_NO_CONFIRM" -eq 0 ]]; then
    if ui_yesno "System Update" "Update all system packages before hardening? (recommended)"; then
        update_system
    fi
else
    update_system
fi

# ── Run modules ───────────────────────────────────────────────────────────────
# Order matters: firewall before IDS (fail2ban needs firewalld), kernel before
# module blacklist, PAM before SSH (login policy depends on PAM).

setup_kernel
setup_module_blacklist
setup_firewall          # includes ensure_firewalld + ensure_dfr_fwd
setup_pam
setup_ssh
setup_audit
setup_ids
setup_malware
setup_integrity
setup_logging
setup_updates
setup_dns
setup_services
setup_firejail
setup_banners
setup_tui

# ── Lynis audit (post-hardening report) ──────────────────────────────────────
if [[ "${OPT_LYNIS:-1}" -eq 1 ]]; then
    STATUS_STEP "Lynis security audit"
    if ! command -v lynis &>/dev/null; then
        install_pkg $PKG_LYNIS
    fi
    lynis audit system --quiet 2>/dev/null | tee /var/log/hardn/lynis-$(date +%F).log \
        | grep -E "^(Warning|Suggestion|Hardening index)" || true
    STATUS_OK "Lynis report saved → /var/log/hardn/lynis-$(date +%F).log"
fi

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${_CLR_GREEN}${_CLR_BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║   HARDN RELOADED — hardening complete!        ║"
echo "  ║                                               ║"
echo "  ║   Profile : ${PROFILE_NAME}"
echo "  ║   Log     : /var/log/hardn/hardn.log          ║"
echo "  ║                                               ║"
echo "  ║   A reboot is recommended to apply:           ║"
echo "  ║    • kernel module blacklists                 ║"
echo "  ║    • sysctl changes (already live)            ║"
[[ "${OPT_AUDIT_IMMUTABLE:-0}" -eq 1 ]] && \
echo "  ║    • immutable audit rules                    ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${_CLR_RESET}"

if [[ "$ARG_NO_CONFIRM" -eq 0 ]]; then
    if ui_yesno "Reboot" "Reboot now to apply all changes?"; then
        sys_reboot
    fi
fi
