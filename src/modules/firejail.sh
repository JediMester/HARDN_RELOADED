#!/usr/bin/env bash
# modules/firejail.sh — Firejail sandboxing + optional SELinux setup
# Gaming profile: auto-sandboxes Steam and all detected browsers.
# All profiles: sandboxes browsers if OPT_FIREJAIL_BROWSERS=1.

setup_firejail() {
    [[ "${OPT_FIREJAIL:-0}" -eq 0 ]] && { STATUS_SKIP "Firejail sandboxing"; return; }
    STATUS_STEP "Firejail sandboxing"

    install_pkg $PKG_FIREJAIL

    # ── SELinux (if kernel supports it and profile requests it) ──────────────
    if [[ "${OPT_SELINUX:-0}" -eq 1 ]]; then
        _setup_selinux
    fi

    # ── Browser sandboxing ───────────────────────────────────────────────────
    if [[ "${OPT_FIREJAIL_BROWSERS:-0}" -eq 1 ]]; then
        detect_browsers
        if [[ ${#INSTALLED_BROWSERS[@]} -eq 0 ]]; then
            STATUS_WARN "No supported browsers detected — skipping browser sandboxing."
        else
            for browser in "${INSTALLED_BROWSERS[@]}"; do
                _firejail_wrap_app "$browser"
            done
        fi
    fi

    # ── Steam sandboxing ─────────────────────────────────────────────────────
    if [[ "${OPT_FIREJAIL_STEAM:-0}" -eq 1 ]]; then
        _firejail_wrap_steam
    fi

    STATUS_OK "Firejail sandboxing configured."
}

# ── Helper: create a .desktop override to launch an app through firejail ────

_firejail_wrap_app() {
    local app="$1"
    local bin_path
    bin_path=$(command -v "$app" 2>/dev/null)
    [[ -z "$bin_path" ]] && return

    # Find existing .desktop file
    local desktop_src
    desktop_src=$(find /usr/share/applications /usr/local/share/applications \
        -name "${app}.desktop" 2>/dev/null | head -1)

    if [[ -z "$desktop_src" ]]; then
        STATUS_WARN "No .desktop file found for $app — creating wrapper symlink only."
    else
        # Copy to /usr/local/share/applications (takes precedence) and patch Exec=
        mkdir -p /usr/local/share/applications
        local desktop_dst="/usr/local/share/applications/${app}.desktop"
        cp "$desktop_src" "$desktop_dst"
        # Replace Exec= lines to prepend firejail
        sed -i "s|^Exec=${bin_path}|Exec=firejail ${bin_path}|g" "$desktop_dst"
        sed -i "s|^Exec=${app}|Exec=firejail ${bin_path}|g"      "$desktop_dst"
        STATUS_OK "Browser sandboxed via .desktop override: $app"
    fi

    # Also create a wrapper script in /usr/local/bin so CLI launches are sandboxed
    if [[ "$bin_path" != /usr/local/bin/* ]]; then
        cat > "/usr/local/bin/${app}" <<EOF
#!/usr/bin/env bash
# HARDN RELOADED — firejail wrapper for ${app}
exec firejail --profile=/etc/firejail/${app}.profile ${bin_path} "\$@"
EOF
        chmod +x "/usr/local/bin/${app}"
        STATUS_MSG "CLI wrapper created: /usr/local/bin/${app}"
    fi
}

# ── Steam-specific sandboxing ─────────────────────────────────────────────────
# Firejail ships a steam.profile by default. We wrap the launcher so every
# Steam invocation — whether from a terminal or a desktop shortcut — goes
# through firejail without breaking Proton or game launching.

_firejail_wrap_steam() {
    local steam_bin
    steam_bin=$(command -v steam 2>/dev/null)
    if [[ -z "$steam_bin" ]]; then
        STATUS_WARN "Steam not found — skipping Steam sandboxing."
        return
    fi

    # Check that firejail has a steam profile
    if [[ ! -f /etc/firejail/steam.profile ]]; then
        STATUS_WARN "No /etc/firejail/steam.profile found — Steam will run unsandboxed."
        STATUS_WARN "Install a newer version of firejail or add the profile manually."
        return
    fi

    # .desktop override
    local steam_desktop
    steam_desktop=$(find /usr/share/applications -name "steam*.desktop" 2>/dev/null | head -1)
    if [[ -n "$steam_desktop" ]]; then
        mkdir -p /usr/local/share/applications
        local dst="/usr/local/share/applications/$(basename "$steam_desktop")"
        cp "$steam_desktop" "$dst"
        sed -i "s|^Exec=.*steam|Exec=firejail --profile=/etc/firejail/steam.profile ${steam_bin}|g" "$dst"
        STATUS_OK "Steam .desktop patched to launch via firejail."
    fi

    # CLI wrapper
    cat > /usr/local/bin/steam <<EOF
#!/usr/bin/env bash
# HARDN RELOADED — firejail wrapper for Steam
exec firejail --profile=/etc/firejail/steam.profile ${steam_bin} "\$@"
EOF
    chmod +x /usr/local/bin/steam
    STATUS_OK "Steam sandboxed via firejail (profile: /etc/firejail/steam.profile)."
    STATUS_MSG "Note: Proton and game launching work normally within the Steam profile."
}

# ── SELinux setup ─────────────────────────────────────────────────────────────

_setup_selinux() {
    STATUS_MSG "Configuring SELinux..."

    if [[ "$HAS_SELINUX" -eq 0 ]]; then
        STATUS_WARN "Kernel does not support SELinux — skipping."
        STATUS_WARN "For SELinux on Arch: install linux-hardened or enable CONFIG_SECURITY_SELINUX."
        return
    fi

    install_pkg $PKG_SELINUX

    case "$DISTRO_FAMILY" in
        arch)
            # Arch SELinux requires manual kernel flag or linux-hardened
            if [[ "$IS_HARDENED_KERNEL" -eq 0 ]]; then
                STATUS_WARN "SELinux on Arch requires linux-hardened kernel or custom build."
                STATUS_WARN "Install linux-hardened, update bootloader entry, and reboot."
                STATUS_WARN "Firejail will still provide sandboxing without SELinux."
                return
            fi
            # Set SELinux to permissive first (log but don't enforce) for testing
            if command -v setenforce &>/dev/null; then
                setenforce 0 2>/dev/null
            fi
            ;;
        debian)
            if command -v selinux-activate &>/dev/null; then
                selinux-activate &>/dev/null || true
            fi
            ;;
        rpm)
            # Fedora/RHEL typically ships SELinux enforcing by default
            local selinux_conf="/etc/selinux/config"
            if [[ -f "$selinux_conf" ]]; then
                sed -i 's/^SELINUX=.*/SELINUX=enforcing/' "$selinux_conf"
                STATUS_OK "SELinux set to enforcing in $selinux_conf (takes effect on reboot)."
            fi
            ;;
    esac

    STATUS_OK "SELinux configured (permissive mode — set to enforcing after testing)."
}
