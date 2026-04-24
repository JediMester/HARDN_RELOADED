#!/usr/bin/env bash
# modules/banners.sh — STIG-compliant login banners (/etc/issue, /etc/issue.net)

setup_banners() {
    [[ "${OPT_BANNERS:-0}" -eq 0 ]] && { STATUS_SKIP "Login banners"; return; }
    STATUS_STEP "STIG login banners"

    local banner_text
    # read -d '' exits non-zero on EOF (no null byte) — absorb with || true
    read -r -d '' banner_text <<'BANNER' || true
╔══════════════════════════════════════════════════════════════════╗
║                    AUTHORISED ACCESS ONLY                        ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  This system is for authorised users only. Individuals using     ║
║  this system without authority, or in excess of their authority, ║
║  are subject to having all of their activities on this system    ║
║  monitored and recorded.                                         ║
║                                                                  ║
║  Anyone using this system expressly consents to such monitoring  ║
║  and is advised that if such monitoring reveals possible         ║
║  evidence of criminal activity, evidence may be provided to      ║
║  law enforcement officials.                                      ║
║                                                                  ║
║  DISCONNECT IMMEDIATELY if you are not an authorised user.       ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
BANNER

    echo "$banner_text" > /etc/issue
    echo "$banner_text" > /etc/issue.net

    chmod 644 /etc/issue /etc/issue.net

    STATUS_OK "STIG login banners written to /etc/issue and /etc/issue.net."
}
