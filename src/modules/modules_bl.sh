#!/usr/bin/env bash
# modules/modules_bl.sh — kernel module blacklisting
# Writes /etc/modprobe.d/hardn-blacklist.conf and unloads modules live.

setup_module_blacklist() {
    [[ "${OPT_MODULE_BLACKLIST:-0}" -eq 0 ]] && { STATUS_SKIP "Kernel module blacklist"; return; }
    STATUS_STEP "Kernel module blacklisting"

    local bl_file="/etc/modprobe.d/hardn-blacklist.conf"
    : > "$bl_file"    # truncate / create

    _bl() { echo "install $1 /bin/true" >> "$bl_file"; }
    _bl_comment() { echo -e "\n# $*" >> "$bl_file"; }

    echo "# HARDN RELOADED — kernel module blacklist" >> "$bl_file"
    echo "# Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ") — profile: ${HARDN_PROFILE}" >> "$bl_file"

    # ── USB storage ──────────────────────────────────────────────────────────
    if [[ "${OPT_BLACKLIST_USB_STORAGE:-0}" -eq 1 ]]; then
        _bl_comment "USB mass storage (HID/keyboard/mouse still allowed)"
        _bl usb-storage
        _bl uas
        # udev rule to block USB storage class (08) while keeping HID (03)
        cat > /etc/udev/rules.d/99-hardn-usb.rules <<'UDEV'
# HARDN: block USB mass storage, allow HID
ACTION=="add", ATTR{bInterfaceClass}=="08", RUN+="/bin/sh -c 'echo 0 > /sys$DEVPATH/../authorized'"
UDEV
        udevadm control --reload-rules 2>/dev/null
        # Attempt live unload (non-fatal if in use)
        modprobe -r usb-storage 2>/dev/null || true
        STATUS_MSG "USB storage blacklisted."
    else
        STATUS_SKIP "USB storage blacklist (disabled by profile)"
    fi

    # ── FireWire ─────────────────────────────────────────────────────────────
    if [[ "${OPT_BLACKLIST_FIREWIRE:-1}" -eq 1 ]]; then
        _bl_comment "FireWire (DMA attack vector)"
        _bl firewire_core
        _bl firewire_ohci
        _bl firewire_sbp2
        STATUS_MSG "FireWire blacklisted."
    fi

    # ── Thunderbolt DMA ──────────────────────────────────────────────────────
    if [[ "${OPT_BLACKLIST_THUNDERBOLT:-0}" -eq 1 ]]; then
        _bl_comment "Thunderbolt (DMA — only block if no Thunderbolt devices used)"
        _bl thunderbolt
        STATUS_MSG "Thunderbolt blacklisted."
    fi

    # ── binfmt_misc ──────────────────────────────────────────────────────────
    if [[ "${OPT_DISABLE_BINFMT_MISC:-0}" -eq 1 ]]; then
        _bl_comment "binfmt_misc (disable non-native binary format support)"
        _bl binfmt_misc
        modprobe -r binfmt_misc 2>/dev/null || true
        STATUS_MSG "binfmt_misc disabled."
    else
        STATUS_SKIP "binfmt_misc blacklist (kept for Proton/Wine per profile)"
    fi

    # ── Rare / unused network protocols ─────────────────────────────────────
    if [[ "${OPT_BLACKLIST_RARE_PROTOCOLS:-1}" -eq 1 ]]; then
        _bl_comment "Uncommon / legacy network protocols"
        for mod in dccp sctp rds tipc ax25 netrom rose decnet econet \
                   ipx appletalk x25 atm can irda token_ring fddi; do
            _bl "$mod"
        done
        # Also disable CIFS/NFS if service hardening left them off
        _bl_comment "Network filesystems (disable if NFS/SMB services are off)"
        for mod in cifs nfs nfsv3 nfsv4; do
            _bl "$mod"
        done
        STATUS_MSG "Rare network protocols blacklisted."
    fi

    STATUS_OK "Module blacklist written → $bl_file"
    STATUS_MSG "Changes take full effect on next boot (or after modprobe -r <module>)."
}
