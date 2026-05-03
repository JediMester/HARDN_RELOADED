
## IMPORTANT NOTE
This is a fork of the original project: https://github.com/subhaniminhas/HARDN1.0  
Huge kudos to Tim Burns and Christopher Bingham for their amazing and invaluable work, and also to Razvan Alexandru Ionica for spreading the word! :) ❤️  
Please check it out!

---

# HARDN_RELOADED v3.0.0

A distro-agnostic Linux security hardening toolkit. Applies STIG-aligned hardening across Arch-, Debian-, and RPM-based systems through a modular, profile-driven architecture. Ships with three pre-configured security profiles, a real-time terminal dashboard (**hardn-tui**), and a dynamic firewall port-scan blocker (**dfr_fwd**).

---

## Supported Distributions

| Family | Tested Distros |
|--------|---------------|
| Arch-based | Arch Linux, Manjaro, EndeavourOS |
| Debian-based | Debian 12+, Ubuntu 24.04+ |
| RPM-based | Fedora, openSUSE |

Bare-metal and VM installs are both supported.

---

## Features

- **3 security profiles**: Server/VM (strictest), Workstation, Gaming/Daily Driver
- **16 modular hardening steps** — each independently toggleable
- **SSH hardening**: custom port, key-only auth, no root login, modern ciphers/algos, VERBOSE logging, all forwarding disabled
- **fail2ban integration**: SSH jail tracks the custom port; `mode = aggressive` catches pre-auth failures
- **Dynamic Firewall (dfr_fwd)**: nftables rate-limiting + Python/tcpdump port-scan detection and auto-blocking
- **hardn-tui**: Real-time Textual-based security dashboard
- **STIG compliance**: login banners, file permissions, audit rules, compiler restrictions
- **Rollback capability**: all configs are backed up before modification

---

## Security Profiles

### Server / VM — strictest
Designed for production servers, headless VMs, and cloud instances.
- IPv6 disabled
- SSH: port 719, key-only, no root login, MaxAuthTries 3, grace time 30s
- Auto-updates with optional auto-reboot
- Audit rules locked immutable at boot
- No GUI/TUI (headless)

### Workstation — balanced
Strong security with developer comfort.
- Compilers and USB storage allowed
- Browsers sandboxed via firejail
- SSH: port 719, key-only, no root login, MaxAuthTries 3
- hardn-tui enabled

### Gaming / Daily Driver — full features
Full security stack without breaking Steam, Proton, Wine, controllers, or peripherals.
- Steam ports open (TCP 27015–27050, UDP 27000–27100); generic game port ranges included
- Thunderbolt, Bluetooth, USB storage, binfmt_misc (Proton/Wine) enabled
- SSH: port 719, key-only, no root login, MaxAuthTries 3
- hardn-tui enabled

---

## Installation

### Prerequisites: deploy SSH keys first

If you plan to use key-only SSH auth (all profiles do by default), deploy your public key **before** running the hardening script or you will be locked out.

```bash
# On the client machine
ssh-keygen -t ed25519 -C "your@email"

# Copy to the target host (use the current port — 22 before hardening)
ssh-copy-id -p 22 user@target-host
```

After hardening, the SSH port changes to 719. Update your `~/.ssh/config`:

```
Host myserver
    HostName target-host
    User     your-user
    Port     719
    IdentityFile ~/.ssh/id_ed25519
```

### One-line install

```bash
curl -LO https://raw.githubusercontent.com/JediMester/HARDN_RELOADED/main/install.sh && chmod +x install.sh && sudo ./install.sh
```

### Manual (clone and run)

```bash
git clone https://github.com/JediMester/HARDN_RELOADED.git ~/.scripts/HARDN_RELOADED
cd ~/.scripts/HARDN_RELOADED
sudo bash src/hardn.sh
```

You will be prompted to select a profile and optionally toggle individual modules.

### What gets changed

- Security-focused packages are installed
- sysctl kernel parameters are hardened (ASLR, ptrace scope, kptr_restrict, network hardening)
- SSH daemon is reconfigured (see SSH Hardening section below)
- Firewall (firewalld) is configured with dfr_fwd dynamic port-scan blocker
- fail2ban is configured with an SSH jail on the custom port
- auditd is set up with STIG-aligned rules
- PAM password quality policy is applied
- Malware scanning (ClamAV, rkhunter, chkrootkit, YARA) is set up with daily cron jobs
- File integrity monitoring (AIDE) is initialized
- Centralized logging (rsyslog) is configured with logrotate
- Unnecessary services are disabled
- Login banners (STIG) are applied
- hardn-tui dashboard is installed (Work/Gaming profiles)

---

## SSH Hardening

All profiles apply the following sshd_config settings:

| Setting | Value |
|---------|-------|
| `Port` | 719 (configurable via `SSH_PORT` in profile) |
| `PermitRootLogin` | `no` |
| `PasswordAuthentication` | `no` |
| `AuthenticationMethods` | `publickey` |
| `PubkeyAuthentication` | `yes` |
| `StrictModes` | `yes` |
| `MaxAuthTries` | `3` |
| `LoginGraceTime` | `30` |
| `MaxSessions` | `2–4` (per profile) |
| `MaxStartups` | `10:30:60` |
| `LogLevel` | `VERBOSE` |
| `SyslogFacility` | `AUTH` |
| `X11Forwarding` | `no` |
| `AllowTcpForwarding` | `no` |
| `AllowAgentForwarding` | `no` |
| `GatewayPorts` | `no` |
| `PermitTunnel` | `no` |
| `Compression` | `no` |
| `TCPKeepAlive` | `no` (ClientAlive used instead) |
| `KbdInteractiveAuthentication` | `no` |
| `UsePAM` | `yes` |
| `PermitEmptyPasswords` | `no` |
| `KexAlgorithms` | curve25519-sha256, dh-group16/18-sha512 |
| `Ciphers` | chacha20-poly1305, aes256-gcm, aes128-gcm |
| `MACs` | hmac-sha2-512-etm, hmac-sha2-256-etm |
| `HostKeyAlgorithms` | ssh-ed25519, rsa-sha2-512, rsa-sha2-256 |

The firewall is automatically updated to open the custom port (instead of the default `ssh` service).  
fail2ban's `[sshd]` jail is configured to watch the same custom port with `mode = aggressive`.

The config is validated with `sshd -t` before the daemon is restarted; if validation fails, the original config is automatically restored from backup.

---

## hardn-tui

A real-time terminal security dashboard built with Python Textual.

```
Tab 1 — Overview:   service status table, active fail2ban bans, last scan results
Tab 2 — Audit:      live auditd event stream (last 200 events via ausearch)
Tab 3 — Suricata:   IDS alert stream — timestamp, source IP, signature
Tab 4 — dfr_fwd:    dynamically blocked IPs, port-scan events, rate-limit hits
```

**Keys**: `1`–`4` switch tabs · `r` force-refresh · `q` quit  
Auto-refreshes every 30 seconds.

```bash
sudo hardn-tui
```

---

## Dynamic Firewall (dfr_fwd)

A two-layer port-scan detection and auto-blocking daemon.

1. **nftables rate-limiting** (hook priority -1, before firewalld):  
   Drops TCP SYN floods > 10/s and UDP floods > 15/s per source IP.  
   Whitelists loopback, link-local, and RFC 1918 ranges.

2. **Python/tcpdump detection layer**:  
   Flags any source IP scanning 8+ unique service ports (< 1024) within 5 seconds.  
   Blocks the source via `firewall-cmd --zone=drop_zone --add-source`.

3. **Auto-unblock**: blocked IPs are released after 30 minutes.

Runs as a systemd service: `dynamic_firewalld_rules.service`

---

## Modules

| Module | What it does |
|--------|-------------|
| `kernel.sh` | sysctl: ASLR, ptrace scope, kptr/dmesg restrict, TCP/ICMP hardening |
| `modules_bl.sh` | modprobe.d blacklist: USB storage, FireWire, rare protocols, binfmt_misc |
| `firewall.sh` | firewalld setup + custom SSH port rule + dfr_fwd |
| `ssh.sh` | sshd_config: full hardening, key-only, custom port, modern algos |
| `pam.sh` | libpwquality policy, core dump disable, shared memory hardening |
| `audit.sh` | auditd + STIG rules (identity, syscalls, privilege escalation, modules) |
| `ids.sh` | fail2ban (SSH jail + custom port) + Suricata IDS/IPS |
| `malware.sh` | ClamAV, rkhunter, chkrootkit, YARA — daily cron scans |
| `integrity.sh` | AIDE file integrity DB + package-level integrity (paccheck/debsums/rpm -Va) |
| `logging.sh` | rsyslog routing to /var/log/hardn/ + logrotate (30-day, compressed) |
| `updates.sh` | Distro-native auto-updates (pacman timer / unattended-upgrades / dnf-automatic) |
| `dns.sh` | Secure DNS selection menu (Quad9, Cloudflare, etc.) via resolved/NM |
| `services.sh` | Disable CUPS, Avahi, Bluetooth, NFS, SMB, rpcbind; remove telnet/vsftpd |
| `firejail.sh` | Browser sandboxing + optional SELinux activation |
| `banners.sh` | STIG-compliant login banners (/etc/issue, /etc/issue.net) |
| `tui.sh` | hardn-tui dashboard installer |

---

## File Structure

```
HARDN_RELOADED/
├── install.sh
├── README.md
├── changelog.md
├── LICENSE
├── progs.csv
├── docs/
│   ├── assets/
│   ├── CODE_OF_CONDUCT.md
│   ├── HARDN.md
│   ├── hardn-security-tools.md
│   └── deb_stig.md
└── src/
    ├── hardn.sh               # Main entry point (v3.0.0)
    ├── hardn-tui              # Security dashboard (Python/Textual)
    ├── lib/
    │   ├── detect.sh          # OS/distro/service detection
    │   ├── ui.sh              # Color output, whiptail/dialog wrappers
    │   └── packages.sh        # Per-distro package name maps
    ├── profiles/
    │   ├── server.conf        # Server/VM profile
    │   ├── work.conf          # Workstation profile
    │   └── gaming.conf        # Gaming/Daily Driver profile
    ├── modules/               # 16 hardening modules
    │   ├── kernel.sh
    │   ├── modules_bl.sh
    │   ├── firewall.sh
    │   ├── ssh.sh
    │   ├── pam.sh
    │   ├── audit.sh
    │   ├── ids.sh
    │   ├── malware.sh
    │   ├── integrity.sh
    │   ├── logging.sh
    │   ├── updates.sh
    │   ├── dns.sh
    │   ├── services.sh
    │   ├── firejail.sh
    │   ├── banners.sh
    │   └── tui.sh
    ├── setup/                 # Legacy installers (v0.1.0 / v2.0.0)
    │   ├── hardn_reloaded.sh
    │   └── hardn-main.sh
    └── tools/
        └── dfr_fwd.py         # Dynamic firewall port-scan blocker
```

---

## Actions

[![Validate](https://github.com/OpenSource-For-Freedom/HARDN-XDR/actions/workflows/validate.yml/badge.svg)](https://github.com/OpenSource-For-Freedom/HARDN-XDR/actions/workflows/validate.yml)

---

## Credits

- Original HARDN-XDR: **Tim Burns** and **Christopher Bingham**
- Community spread: **Razvan Alexandru Ionica**
- Partner: office@cybersynapse.ro

---

This project is licensed under the **MIT License** — see [LICENSE](LICENSE).
