#!/bin/bash

# HARDN_RELOADED installer script
# Author of the original install.sh script: Christopher Bingham
# Creator of this script: Balazs Ujvari

readonly RED=$'\033[0;31m'    # Red
readonly YEL=$'\033[1;33m'    # Yellow
readonly LBL=$'\033[1;34m'    # Light blue
readonly LG=$'\033[1;32m'     # Light green
readonly NC=$'\033[0m'        # No Color --> color off

check_root () {
        [ "$(id -u)" -ne 0 ] && echo "${RED}Please run this script as root.${NC}" && exit 1
}

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
    echo "${YEL}[##] Running OS detection using the /etc/os-release file...${NC}"
    echo ""
    if [ ${PKGMGR} == "pacman" ]; then
            echo "${YEL}Detected OS: ${NAME} (${DISTRO}, ${BUILD})"
    else
            echo "${YEL}Detected OS: ${NAME} (${DISTRO})"
    fi
}

update_system() {
        printf "${YEL}[##] A system update will be performed now...${NC}"
        case ${PKGMGR} in
                apt)
                apt update && apt upgrade -y;;
                dnf)
                dnf update -y;;
                zypper)
                zypper update -y;;
                pacman)
                pacman -Syyu;;
        esac
}


check_git() {
        printf "${YEL}[##] Checking if git is installed, and installing it if not..${NC}"
        if [ -x "$(command -v git)" ]; then
                printf "${LG}Git is already installed.${NC}"
        else
           case ${PKGMGR} in
                apt)
                apt install git -y;;
                dnf)
                dnf install git -y;;
                zypper)
                zypper install git -y;;
                pacman)
                pacman -S git -y;;
           esac
           printf "${YEL}Git is now installed.${NC}"
        fi
}

# Git clone the repo, then cd into the repo and run the script hardn-main.sh
retrieve_repo() {
        echo "${YEL}[##] Cloning the HARDN_RELOADED git repo...${NC}"
        git clone https://github.com/JediMester/HARDN_RELOADED.git
        cd HARDN_RELOADED/src/setup &&  chmod +x hardn_reloaded.sh && sudo ./hardn_reloaded.sh
}

main() {
        check_root
        detect_os
        update_system
        check_git
        retrieve_repo
}

main
