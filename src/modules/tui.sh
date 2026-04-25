#!/usr/bin/env bash
# modules/tui.sh — optional hardn-tui security dashboard install
# Installs python-textual and symlinks hardn-tui into /usr/local/bin.

setup_tui() {
    [[ "${OPT_HARDN_TUI:-0}" -eq 0 ]] && { STATUS_SKIP "hardn-tui dashboard"; return; }
    STATUS_STEP "hardn-tui security dashboard"

    # ── Install python-textual ────────────────────────────────────────────────
    case "$DISTRO_FAMILY" in
        arch)
            install_pkg python-textual
            ;;
        debian)
            # python3-textual is available in Ubuntu 23.04+ / Debian 13+;
            # fall back to pip3 on older releases.
            if DEBIAN_FRONTEND=noninteractive apt-get install -y python3-textual \
                    &>/dev/null 2>&1; then
                STATUS_OK "python3-textual installed via apt."
            elif command -v pip3 &>/dev/null; then
                STATUS_MSG "python3-textual not in apt — installing via pip3..."
                pip3 install --quiet textual || \
                    STATUS_WARN "pip3 install textual failed — install manually."
            else
                STATUS_WARN "Neither python3-textual (apt) nor pip3 found."
                STATUS_WARN "Install textual manually: pip3 install textual"
            fi
            ;;
        rpm)
            # textual is not in standard RPM repos; use pip3.
            if command -v pip3 &>/dev/null; then
                STATUS_MSG "Installing textual via pip3..."
                pip3 install --quiet textual || \
                    STATUS_WARN "pip3 install textual failed — install manually."
            else
                STATUS_WARN "pip3 not found — install textual manually: pip3 install textual"
            fi
            ;;
    esac

    # ── Symlink hardn-tui into PATH ───────────────────────────────────────────
    local tui_src="${HARDN_DIR}/hardn-tui"
    local tui_dst="/usr/local/bin/hardn-tui"

    if [[ ! -f "$tui_src" ]]; then
        STATUS_WARN "hardn-tui not found at $tui_src — skipping PATH install."
        return
    fi

    chmod +x "$tui_src"
    ln -sf "$tui_src" "$tui_dst"
    STATUS_OK "hardn-tui installed → $tui_dst"
    STATUS_MSG "Launch the dashboard with: sudo hardn-tui"
}
