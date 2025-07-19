#!/usr/bin/env bash

############################################################################################################
# HARDN_RELOADED                                                                                           #
# Developed by Balazs Ujvari                                                                               #
# Original project: HARDN-XDR - The Linux Security Hardening Sentinel                                      #
# The original script was developed and built by Christopher Bingham and Tim Burns, huge kudos to them! :) #
# About this script (as well as the original):                                                             #
# STIG Compliance: Security Technical Implementation Guide.                                                #
############################################################################################################

# Colour codes
readonly RED=$'\033[0;31m'    # Red
readonly GRE=$'\033[0;32m'    # Green
readonly YEL=$'\033[1;33m'    # Yellow
readonly LBL=$'\033[1;34m'    # Light blue
readonly LG=$'\033[1;32m'	  # Light green
readonly NC=$'\033[0m'        # No Color --> color off

VERSION="0.1.0"
PKGMGR=""

print_ascii_banner() { 

    local terminal_width
    terminal_width=$(tput cols)
    local banner
    banner=$(cat << "EOF"

 @@@  @@@   @@@@@@   @@@@@@@   @@@@@@@   @@@  @@@          @@@@@@@   @@@@@@@@  @@@        @@@@@@    @@@@@@   @@@@@@@   @@@@@@@@  @@@@@@@   
@@@  @@@  @@@@@@@@  @@@@@@@@  @@@@@@@@  @@@@ @@@          @@@@@@@@  @@@@@@@@  @@@       @@@@@@@@  @@@@@@@@  @@@@@@@@  @@@@@@@@  @@@@@@@@  
@@!  @@@  @@!  @@@  @@!  @@@  @@!  @@@  @@!@!@@@          @@!  @@@  @@!       @@!       @@!  @@@  @@!  @@@  @@!  @@@  @@!       @@!  @@@  
!@!  @!@  !@!  @!@  !@!  @!@  !@!  @!@  !@!!@!@!          !@!  @!@  !@!       !@!       !@!  @!@  !@!  @!@  !@!  @!@  !@!       !@!  @!@  
@!@!@!@!  @!@!@!@!  @!@!!@!   @!@  !@!  @!@ !!@!          @!@!!@!   @!!!:!    @!!       @!@  !@!  @!@!@!@!  @!@  !@!  @!!!:!    @!@  !@!  
!!!@!!!!  !!!@!!!!  !!@!@!    !@!  !!!  !@!  !!!          !!@!@!    !!!!!:    !!!       !@!  !!!  !!!@!!!!  !@!  !!!  !!!!!:    !@!  !!!  
!!:  !!!  !!:  !!!  !!: :!!   !!:  !!!  !!:  !!!          !!: :!!   !!:       !!:       !!:  !!!  !!:  !!!  !!:  !!!  !!:       !!:  !!!  
:!:  !:!  :!:  !:!  :!:  !:!  :!:  !:!  :!:  !:!          :!:  !:!  :!:        :!:      :!:  !:!  :!:  !:!  :!:  !:!  :!:       :!:  !:!  
::   :::  ::   :::  ::   :::   :::: ::   ::   ::  ::::::  ::   :::   :: ::::   :: ::::  ::::: ::  ::   :::   :::: ::   :: ::::   :::: ::  
 :   : :   :   : :   :   : :  :: :  :   ::    :   ::::::   :   : :  : :: ::   : :: : :   : :  :    :   : :  :: :  :   : :: ::   :: :  :
 
 A distro agnostic fork of HARDN-XDR by Security International Group
                                  
EOF
)
    local banner_width
    banner_width=$(echo "$banner" | awk '{print length($0)}' | sort -n | tail -1)
    local padding=$(( (terminal_width - banner_width) / 2 ))
    local i
    while IFS= read -r line; do
        for ((i=0; i<padding; i++)); do
            printf " "
        done
        printf "%s\n" "$line"
    done <<< "$banner"
    sleep 2

}

STATUS_MSG() {
    local status="$1"
    local message="$2"
    case "$status" in
        "pass")
            echo "${LG}[PASS] $message${NC}"
            ;;
        "warning")
            echo "${YEL}[WARNING] $message${NC}"
            ;;
        "error")
            echo "${RED}[ERROR] $message${NC}"
            ;;
        "info")
            echo "${LB}[INFO] $message${NC}"
            ;;
        *)
            echo "${GRE}[UNKNOWN] $message${NC}"
            ;;
    esac
}

# 1. OS DETECTION
detect_os() {
    . /etc/os-release
    DISTRO="$ID"
    NAME="$PRETTY_NAME"
    BUILD="$BUILD_ID"
    case "$DISTRO" in
        arch|manjaro|endeavouros|cachyos) PKGMGR="pacman";;
        fedora|rhel|centos|rocky) PKGMGR="dnf";;
        opensuse*) PKGMGR="zypper";;
        debian|ubuntu|pop|linuxmint) PKGMGR="apt";;
        *) echo "Not supported distro!"; exit 1;;
    esac
}

detect_os

system_info() {
    printf "%s\n" \
    "===================================================================" \
    "HARDN_RELOADED - The distro agnostic security tool --- System Info:" \
    "===================================================================" \
    "Current script version: ${VERSION}" \
    "Target systems: Debian-based, Arch-based and RPM-based operating systems"
    echo ""
    if [[ "${PKGMGR}" == "pacman" ]]; then
        echo "Detected OS: ${NAME} ${BUILD}"
    else
        echo "Detected OS: ${NAME}"
    fi
    echo ""
    printf "%s\n" \
    "Features: STIG Compliance, Malware Detection, System Hardening" \
    "Security Tools: Firewalld, Fail2Ban, AppArmor, AIDE, clamAV, and more"
    echo ""
}


# 2. PACKAGE INSTALL
install_pkg() {
    PKG="$1"
    case "$PKGMGR" in
        pacman) sudo pacman -Sy --needed --noconfirm "$PKG";;
        dnf) sudo dnf install -y "$PKG";;
        zypper) sudo zypper install -y "$PKG";;
        apt) sudo apt install -y "$PKG";;
    esac
}

# 3. FIREWALLD
setup_firewalld() {
    install_pkg firewalld
    sudo systemctl enable --now firewalld
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --permanent --add-service=http
    sudo firewall-cmd --permanent --add-service=https
    sudo firewall-cmd --reload
}

# 4. CLAMAV
setup_clamav() {
    install_pkg clamav
    # service name might/can differ: arch=clamav-daemon, fedora/fedora=clamd@scan, debian=clamav-daemon
    sudo systemctl enable --now clamav-freshclam 2>/dev/null || sudo systemctl enable --now freshclam 2>/dev/null
    sudo systemctl enable --now clamav-daemon 2>/dev/null || sudo systemctl enable --now clamd@scan 2>/dev/null
}

# 5. AUDITD
setup_auditd() {
    install_pkg audit
    sudo systemctl enable --now auditd
}

# 6. LYNIS
setup_lynis() {
    install_pkg lynis
}

# 7. FAIL2BAN
setup_fail2ban() {
    install_pkg fail2ban
    sudo systemctl enable --now fail2ban
}

# 8. APPARMOR (available on RPM-based distros, on Arch-base it's optional)
setup_apparmor() {
    install_pkg apparmor
    sudo systemctl enable --now apparmor 2>/dev/null
}

# 9. AIDE
setup_aide() {
    install_pkg aide
    sudo aide --init
    sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
}

# 10. SYSCTL HARDENING (only for servers, optinal for desktop envs)
setup_sysctl() {
    cat <<EOF | sudo tee /etc/sysctl.d/99-hardening.conf
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
fs.suid_dumpable = 0
net.ipv4.tcp_syncookies = 1
EOF
    sudo sysctl --system
}

# 11. DISABLE KERNEL MODULES (optional)
setup_kernel_module_blacklist() {
    cat <<EOF | sudo tee /etc/modprobe.d/hardened-blacklist.conf
# Példa: tiltsd le storage-t ha nem kell
# blacklist usb-storage
# blacklist firewire_core
EOF
}

# 12. LOGGING/LOGROTATE
setup_logging() {
    install_pkg rsyslog
    install_pkg logrotate
    sudo systemctl enable --now rsyslog
}

# 13. "DESKTOP SAFE" LOGIC
prompt_desktop_mode() {
    echo "Are you using this in desktop mode? (yes: kernel modules won't be disabled) [y/N]"
    read -r ANS
    if [[ "$ANS" =~ ^([iI][gG][eE][nN]|[yY])$ ]]; then
        DESKTOP_SAFE=1
    else
        DESKTOP_SAFE=0
    fi
}

# 14. MAIN FUNCTION
main() {
    detect_os
    prompt_desktop_mode
    setup_firewalld
    setup_clamav
    setup_auditd
    setup_lynis
    setup_fail2ban
    setup_apparmor
    setup_aide
    setup_logging
    # Only if we are NOT in desktop safe mode!
    if [ "$DESKTOP_SAFE" -eq 0 ]; then
        setup_sysctl
        setup_kernel_module_blacklist
    else
        echo "[INFO] Desktop mode active: SKIPPING kernel modul disabling and sysctl hardening."
    fi
    echo "[INFO] Security toolkit installation complete!"
}

main
