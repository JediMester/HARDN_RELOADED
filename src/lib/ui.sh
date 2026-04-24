#!/usr/bin/env bash
# lib/ui.sh — colour output, banners, whiptail/dialog wrappers
# Sourced by hardn.sh.

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------

_CLR_RESET="\033[0m"
_CLR_BOLD="\033[1m"
_CLR_GREEN="\033[0;32m"
_CLR_YELLOW="\033[1;33m"
_CLR_RED="\033[0;31m"
_CLR_CYAN="\033[0;36m"
_CLR_BLUE="\033[0;34m"

STATUS_OK()   { echo -e "${_CLR_GREEN}${_CLR_BOLD}  [OK]${_CLR_RESET}   $*"; }
STATUS_MSG()  { echo -e "${_CLR_CYAN}${_CLR_BOLD}  [-->]${_CLR_RESET}  $*"; }
STATUS_WARN() { echo -e "${_CLR_YELLOW}${_CLR_BOLD}  [WARN]${_CLR_RESET} $*"; }
STATUS_ERR()  { echo -e "${_CLR_RED}${_CLR_BOLD}  [ERR]${_CLR_RESET}  $*" >&2; }
STATUS_SKIP() { echo -e "${_CLR_BLUE}${_CLR_BOLD}  [SKIP]${_CLR_RESET} $*"; }
STATUS_STEP() { echo -e "\n${_CLR_BOLD}${_CLR_CYAN}══╡ $* ╞══${_CLR_RESET}"; }

# ---------------------------------------------------------------------------
# ASCII banner
# ---------------------------------------------------------------------------

print_banner() {
    echo -e "${_CLR_CYAN}${_CLR_BOLD}"
    cat <<'EOF'

  ██╗  ██╗ █████╗ ██████╗ ██████╗ ███╗   ██╗
  ██║  ██║██╔══██╗██╔══██╗██╔══██╗████╗  ██║
  ███████║███████║██████╔╝██║  ██║██╔██╗ ██║
  ██╔══██║██╔══██║██╔══██╗██║  ██║██║╚██╗██║
  ██║  ██║██║  ██║██║  ██║██████╔╝██║ ╚████║
  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═══╝
        R E L O A D E D  —  v3.0.0
   Distro-Agnostic Linux Security Hardening
EOF
    echo -e "${_CLR_RESET}"
}

# ---------------------------------------------------------------------------
# Dialog/whiptail backend detection
# ---------------------------------------------------------------------------

# Sets UI_BACKEND to "whiptail", "dialog", or "plain"
detect_ui_backend() {
    if command -v whiptail &>/dev/null; then
        UI_BACKEND="whiptail"
    elif command -v dialog &>/dev/null; then
        UI_BACKEND="dialog"
    else
        UI_BACKEND="plain"
    fi
    export UI_BACKEND
}

# Ensure a TUI backend is available; install whiptail if missing.
ensure_ui_backend() {
    detect_ui_backend
    if [[ "$UI_BACKEND" == "plain" ]]; then
        STATUS_MSG "Installing whiptail for interactive menus..."
        case "$PKGMGR" in
            pacman) pacman -S --noconfirm --needed libnewt ;;
            apt)    DEBIAN_FRONTEND=noninteractive apt install -y whiptail ;;
            dnf)    dnf install -y newt ;;
            zypper) zypper install -y whiptail ;;
        esac
        detect_ui_backend
    fi
}

# ---------------------------------------------------------------------------
# Unified wrappers  (call whiptail or dialog transparently)
# ---------------------------------------------------------------------------

# ui_msgbox TITLE TEXT
ui_msgbox() {
    local title="$1" text="$2"
    case "$UI_BACKEND" in
        whiptail) whiptail --title "$title" --msgbox "$text" 12 70 ;;
        dialog)   dialog  --title "$title" --msgbox "$text" 12 70 ;;
        *)        echo -e "\n=== $title ===\n$text\n"; read -rp "Press Enter to continue..." ;;
    esac
}

# ui_yesno TITLE TEXT  → returns 0 for Yes, 1 for No
ui_yesno() {
    local title="$1" text="$2"
    case "$UI_BACKEND" in
        whiptail) whiptail --title "$title" --yesno "$text" 12 70 ;;
        dialog)   dialog  --title "$title" --yesno "$text" 12 70 ;;
        *)
            echo -e "\n=== $title ===\n$text"
            read -rp "  [y/N] " ans
            [[ "${ans,,}" == "y" ]]
            ;;
    esac
}

# ui_menu TITLE TEXT TAG1 ITEM1 TAG2 ITEM2 ...
# Prints the selected TAG to stdout.
ui_menu() {
    local title="$1" text="$2"
    shift 2
    local items=("$@")
    case "$UI_BACKEND" in
        whiptail)
            whiptail --title "$title" --menu "$text" 20 70 10 \
                "${items[@]}" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --title "$title" --menu "$text" 20 70 10 \
                "${items[@]}" 3>&1 1>&2 2>&3
            ;;
        *)
            echo -e "\n=== $title ===\n$text\n"
            local i=0
            while [[ $i -lt ${#items[@]} ]]; do
                echo "  ${items[$i]}) ${items[$((i+1))]}"
                ((i+=2))
            done
            read -rp "  Choice: " ans
            echo "$ans"
            ;;
    esac
}

# ui_checklist TITLE TEXT TAG1 ITEM1 STATUS1 TAG2 ITEM2 STATUS2 ...
# Prints space-separated selected TAGs to stdout.
ui_checklist() {
    local title="$1" text="$2"
    shift 2
    local items=("$@")
    case "$UI_BACKEND" in
        whiptail)
            whiptail --title "$title" --checklist "$text" 24 78 16 \
                "${items[@]}" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --title "$title" --checklist "$text" 24 78 16 \
                "${items[@]}" 3>&1 1>&2 2>&3
            ;;
        *)
            echo -e "\n=== $title ===\n$text\n"
            local i=0 selected=()
            while [[ $i -lt ${#items[@]} ]]; do
                local tag="${items[$i]}" desc="${items[$((i+1))]}" state="${items[$((i+2))]}"
                local default="n"; [[ "${state,,}" == "on" ]] && default="y"
                read -rp "  Enable $desc? [${default}] " ans
                ans="${ans:-$default}"
                [[ "${ans,,}" == "y" ]] && selected+=("$tag")
                ((i+=3))
            done
            echo "${selected[*]}"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Profile selection menu  → sets HARDN_PROFILE
# ---------------------------------------------------------------------------

select_profile() {
    local choice
    choice=$(ui_menu \
        "HARDN RELOADED — Profile Selection" \
        "Choose the hardening profile that matches this system's role:" \
        "server"  "Server / VM            — strictest security, no GUI assumptions" \
        "work"    "Workstation / Work PC   — strong security, developer-friendly" \
        "gaming"  "Daily Driver / Gaming   — full security, gaming & Steam support" \
    )

    case "$choice" in
        server|work|gaming) HARDN_PROFILE="$choice" ;;
        *)
            STATUS_ERR "No profile selected — aborting."
            exit 1
            ;;
    esac
    export HARDN_PROFILE
}

# ---------------------------------------------------------------------------
# Module toggle menu  (shown after profile selection for fine-tuning)
# ---------------------------------------------------------------------------

select_modules() {
    # Build checklist from profile defaults (OPT_* variables already loaded)
    local _s; _s() { [[ "${!1:-0}" -eq 1 ]] && echo "ON" || echo "OFF"; }

    local choices
    choices=$(ui_checklist \
        "HARDN RELOADED — Module Selection" \
        "Space = toggle  |  Tab = move to OK/Cancel  |  Enter = confirm
Toggle individual modules (profile defaults are pre-selected):" \
        "kernel"    "Kernel / sysctl hardening"            "$(_s OPT_KERNEL_HARDEN)" \
        "modules_bl" "Kernel module blacklisting"          "$(_s OPT_MODULE_BLACKLIST)" \
        "firewall"  "Firewall (firewalld)"                 "$(_s OPT_FIREWALL)" \
        "dfr_fwd"   "Dynamic port-scan blocker (dfr_fwd)"  "$(_s OPT_DFR_FWD)" \
        "ssh"       "SSH hardening"                        "$(_s OPT_SSH_HARDEN)" \
        "pam"       "PAM password quality & limits"        "$(_s OPT_PAM_PWQUALITY)" \
        "audit"     "auditd (STIG audit rules)"            "$(_s OPT_AUDITD)" \
        "ids"       "IDS/IPS (fail2ban + Suricata)"        "$(_s OPT_IDS)" \
        "malware"   "Malware detection (ClamAV + rkhunter)" "$(_s OPT_MALWARE)" \
        "integrity" "File integrity (AIDE + pkg check)"    "$(_s OPT_INTEGRITY)" \
        "logging"   "Centralised logging (rsyslog)"        "$(_s OPT_LOGGING)" \
        "updates"   "Automatic security updates"           "$(_s OPT_AUTO_UPDATES)" \
        "dns"       "Secure DNS provider selection"        "$(_s OPT_DNS)" \
        "services"  "Disable unnecessary services"         "$(_s OPT_DISABLE_SERVICES)" \
        "firejail"  "Firejail sandboxing"                  "$(_s OPT_FIREJAIL)" \
        "banners"   "STIG login banners"                   "$(_s OPT_BANNERS)" \
    )

    # Reset all OPT_ flags then re-enable selected ones
    for flag in OPT_KERNEL_HARDEN OPT_MODULE_BLACKLIST OPT_FIREWALL OPT_DFR_FWD \
                OPT_SSH_HARDEN OPT_PAM_PWQUALITY OPT_AUDITD OPT_IDS OPT_MALWARE \
                OPT_INTEGRITY OPT_LOGGING OPT_AUTO_UPDATES OPT_DNS \
                OPT_DISABLE_SERVICES OPT_FIREJAIL OPT_BANNERS; do
        export "$flag"=0
    done

    for sel in $choices; do
        sel="${sel//\"/}"   # strip whiptail quotes
        case "$sel" in
            kernel)     OPT_KERNEL_HARDEN=1 ;;
            modules_bl) OPT_MODULE_BLACKLIST=1 ;;
            firewall)   OPT_FIREWALL=1 ;;
            dfr_fwd)    OPT_DFR_FWD=1 ;;
            ssh)        OPT_SSH_HARDEN=1 ;;
            pam)        OPT_PAM_PWQUALITY=1 ;;
            audit)      OPT_AUDITD=1 ;;
            ids)        OPT_IDS=1 ;;
            malware)    OPT_MALWARE=1 ;;
            integrity)  OPT_INTEGRITY=1 ;;
            logging)    OPT_LOGGING=1 ;;
            updates)    OPT_AUTO_UPDATES=1 ;;
            dns)        OPT_DNS=1 ;;
            services)   OPT_DISABLE_SERVICES=1 ;;
            firejail)   OPT_FIREJAIL=1 ;;
            banners)    OPT_BANNERS=1 ;;
        esac
    done

    export OPT_KERNEL_HARDEN OPT_MODULE_BLACKLIST OPT_FIREWALL OPT_DFR_FWD \
           OPT_SSH_HARDEN OPT_PAM_PWQUALITY OPT_AUDITD OPT_IDS OPT_MALWARE \
           OPT_INTEGRITY OPT_LOGGING OPT_AUTO_UPDATES OPT_DNS \
           OPT_DISABLE_SERVICES OPT_FIREJAIL OPT_BANNERS
}
