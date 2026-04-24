#!/usr/bin/env python3

import signal
import subprocess
import time
import re
from collections import defaultdict
from datetime import datetime, timedelta
from threading import Thread, Event, Lock
import ipaddress


# Configuration
# Combined BPF filter: TCP SYN packets (connection-initiation probes) + all UDP.
# FIN packets are dropped from the filter — they appear in normal teardowns and
# would inflate counts against legitimate peers.
TCPDUMP_FILTER = "(tcp[tcpflags] & tcp-syn != 0) or udp"
BLOCK_TIMEOUT = 30          # minutes before auto-unblock

# Python-layer detection threshold (second line of defence → permanent block).
# Keep this low so the permanent firewalld block catches anything the nft rate
# limiter didn't already stop.
PORT_SCAN_THRESHOLD = 8     # unique destination ports from one IP within window
PORT_SCAN_WINDOW = 5        # seconds

# nftables kernel-level rate limiting (first line of defence — fires before
# Python even sees the packet).  Tune to taste; values below allow a short
# burst for legitimate multi-connection clients (browsers, curl, etc.) while
# slamming a port scanner that sends hundreds of SYNs per second.
NFT_TABLE       = "dfr_scanner_block"   # separate table; never touches firewalld
SYN_RATE_LIMIT  = "10/second"           # max new TCP SYNs per source IP
#SYN_RATE_LIMIT  = "15/second"
SYN_BURST       = 12                    # initial token-bucket allowance (packets)
#SYN_BURST       = 18
UDP_RATE_LIMIT  = "15/second"           # max UDP packets per source IP
#UDP_RATE_LIMIT  = "20/second"
UDP_BURST       = 20
#UDP_BURST       = 25

# IPs/CIDRs that will never be blocked (loopback + link-local + all RFC 1918
# private ranges by default).  Private ranges are included because tcpdump
# captures outbound traffic too: when your machine opens connections to many
# servers, your own LAN IP appears as the source and would otherwise be
# falsely flagged as a port scanner.
WHITELIST_NETWORKS = [
    "127.0.0.0/8",
    "::1/128",
    "fe80::/10",
    # RFC 1918 private ranges — covers typical LAN addresses so your own
    # machine and local devices are never accidentally blocked.
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",

]

# Destination ports at or above this value are NOT counted toward scan
# detection.  High/ephemeral ports (typically 1024–65535) are usually
# responses to connections your machine initiated, not attacker probes.
# Only low-numbered service ports (SSH :22, HTTP :80, etc.) are meaningful
# scan indicators.  Set to 65536 to disable the filter entirely.
PORT_SCAN_DST_PORT_MAX = 1024

# Global state
blocked_ips = {}            # ip -> datetime when blocked
stop_event = Event()        # signal to stop all threads
state_lock = Lock()         # protects blocked_ips and scan_events
# Stores (timestamp, dst_port) tuples per source IP for the rolling window.
scan_events = defaultdict(list)


#def block_ip_firewalld(ip):
#    """ Block the IP address using firewalld. """
#    if not is_valid_ip(ip):
#        print(f"Invalid IP format: {ip}")
#        return
#    try:
#        # Ensure drop zone exists
#        result = subprocess.run(
#            ["firewall-cmd", "--list-zones"],
#            capture_output=True, text=True, check=False
#        )
#        zones = result.stdout.strip().split()
#        if "drop" not in zones:
#            print("Creating firewalld 'drop' zone...")
#            subprocess.run(["firewall-cmd", "--permanent", "--new-zone=drop"], check=True)
#            # Add default rules: drop all incoming traffic
#            for rule in [
#                "--add-rich-rule='rule family=\"ipv4\" source address=\"0.0.0.0/0\" accept'",
#                "--add-rich-rule='rule family=\"ipv6\" source address=\"::/0\" accept'",
#                "--set-target=drop",
#                "--set-default-zone=drop"
#            ]:
#                subprocess.run(["firewall-cmd", "--permanent"] + rule.split(), check=True)
#
#        # Add IP to drop zone
#        print(f"Blocking IP: {ip}")
#        subprocess.run(
#            ["firewall-cmd", "--zone=drop", "--add-source", ip, "--permanent"],
#            check=True
#        )
#        subprocess.run(["firewall-cmd", "--reload"], check=True)
#        blocked_ips[ip] = datetime.now()
#
#    except subprocess.CalledProcessError as e:
#        print(f"Failed to block IP {ip}: {e}")

def ensure_drop_zone():
    """Ensure the custom drop_zone exists in firewalld and has DROP as its target."""
    # --permanent --get-zones lists ALL defined zones, including inactive ones.
    # --list-zones only lists active zones (those with an interface/source assigned),
    # so a freshly created drop_zone with no sources would be invisible there and
    # trigger a false "zone missing" → NAME_CONFLICT on the very next restart.
    result = subprocess.run(
        ["firewall-cmd", "--permanent", "--get-zones"],
        capture_output=True, text=True, check=False
    )
    zones = result.stdout.strip().split()

    if "drop_zone" not in zones:
        print("Drop zone does not exist. Creating...")
        subprocess.run(
            ["firewall-cmd", "--permanent", "--new-zone=drop_zone"],
            check=True
        )
        # Set the zone target to DROP so any source routed into it is silently dropped.
        # Do NOT touch --set-default-zone; the default zone should stay as-is.
        subprocess.run(
            ["firewall-cmd", "--permanent", "--zone=drop_zone", "--set-target=DROP"],
            check=True
        )
        subprocess.run(["firewall-cmd", "--reload"], check=True)
        print("Drop zone created and configured.")
    else:
        print("Drop zone already exists.")


def setup_nft_ratelimit():
    """
    Install a nftables table that rate-limits incoming TCP SYN and UDP packets
    per source IP at kernel speed — before Python even sees the packet.

    Architecture
    ============
    We create our own table 'dfr_scanner_block' at hook priority -1, which
    makes it run BEFORE firewalld's chains (priority 0).  This means a port
    scanner's SYN flood is stopped at the first kernel hook, not after Python
    has processed it.

    Two meters (nftables' per-element token buckets) enforce the limits:
      synlimit  — caps new TCP SYN packets per source IP
      udplimit  — caps UDP packets per source IP

    On restart we flush the chain first so we never accumulate duplicate rules.
    """
    nft_script = (
        f"add table ip {NFT_TABLE}\n"
        f"add chain ip {NFT_TABLE} input {{ type filter hook input priority -1; policy accept; }}\n"
        f"flush chain ip {NFT_TABLE} input\n"
        # Loopback: never rate-limit inter-process traffic on lo (Steam's web
        # helper, CEF, and other local sub-processes open many connections fast).
        f"add rule ip {NFT_TABLE} input iif lo accept\n"
        # RFC 1918 private ranges: skip rate-limiting for LAN traffic.
        # Also prevents our own machine's IP from being falsely throttled.
        f"add rule ip {NFT_TABLE} input ip saddr 10.0.0.0/8 accept\n"
        f"add rule ip {NFT_TABLE} input ip saddr 172.16.0.0/12 accept\n"
        f"add rule ip {NFT_TABLE} input ip saddr 192.168.0.0/16 accept\n"
        # Let through responses to connections we initiated (SYN-ACK, DNS replies, QUIC, etc.)
        f"add rule ip {NFT_TABLE} input ct state established,related accept\n"
        # Rate-limit only pure inbound SYN (new connection attempts from outside).
        # "fin|syn|rst|ack) == syn" ensures SYN-ACK packets are NOT matched.
        f"add rule ip {NFT_TABLE} input tcp flags & (fin|syn|rst|ack) == syn "
        f"meter synlimit {{ ip saddr limit rate {SYN_RATE_LIMIT} burst {SYN_BURST} packets }} drop\n"
        # Rate-limit only new inbound UDP flows, not responses to our own queries.
        f"add rule ip {NFT_TABLE} input ip protocol udp ct state new "
        f"meter udplimit {{ ip saddr limit rate {UDP_RATE_LIMIT} burst {UDP_BURST} packets }} drop\n"
    )
    try:
        subprocess.run(
            ["nft", "-f", "/dev/stdin"],
            input=nft_script, text=True, check=True,
            capture_output=True,
        )
        print(
            f"nftables rate-limiting active: "
            f"TCP SYN <= {SYN_RATE_LIMIT} (burst {SYN_BURST}), "
            f"UDP <= {UDP_RATE_LIMIT} (burst {UDP_BURST}) per source IP."
        )
    except subprocess.CalledProcessError as e:
        print(
            f"Warning: nftables rate-limiting could not be installed: "
            f"{e.stderr.strip()}\n"
            f"Python-layer detection will still run, but kernel-level "
            f"throttling is disabled."
        )


def teardown_nft_ratelimit():
    """Remove the dfr_scanner_block nftables table on service shutdown."""
    try:
        subprocess.run(
            ["nft", "delete", "table", "ip", NFT_TABLE],
            check=True, capture_output=True,
        )
        print("nftables rate-limiting rules removed.")
    except subprocess.CalledProcessError:
        pass  # table may not exist if setup failed; silently ignore


def block_ip_firewalld(ip):
    """Add ip to drop_zone so firewalld silently drops all its packets."""
    if not is_valid_ip(ip):
        print(f"Invalid IP format: {ip}")
        return

    with state_lock:
        if ip in blocked_ips:
            return  # already blocked; nothing to do

    try:
        print(f"Blocking IP: {ip}")
        subprocess.run(
            ["firewall-cmd", "--zone=drop_zone", "--add-source", ip, "--permanent"],
            check=True
        )
        subprocess.run(["firewall-cmd", "--reload"], check=True)
        with state_lock:
            blocked_ips[ip] = datetime.now()

    except subprocess.CalledProcessError as e:
        print(f"Failed to block IP {ip}: {e}")


def unblock_ip_firewalld(ip):
    """Remove ip from drop_zone and delete it from the blocked set."""
    try:
        print(f"Unblocking IP: {ip}")
        subprocess.run(
            ["firewall-cmd", "--zone=drop_zone", "--remove-source", ip, "--permanent"],
            check=True
        )
        subprocess.run(["firewall-cmd", "--reload"], check=True)
        with state_lock:
            blocked_ips.pop(ip, None)
    except subprocess.CalledProcessError as e:
        print(f"Failed to unblock IP {ip}: {e}")


def cleanup_expired_blocks():
    """Remove IPs whose block timeout has elapsed."""
    now = datetime.now()
    with state_lock:
        expired_ips = [
            ip for ip, block_time in blocked_ips.items()
            if now - block_time > timedelta(minutes=BLOCK_TIMEOUT)
        ]
    for ip in expired_ips:
        unblock_ip_firewalld(ip)


def is_valid_ip(ip_str):
    """ Validate IP address (IPv4 or IPv6). """
    try:
        ipaddress.ip_address(ip_str)
        return True
    except ValueError:
        return False


def _is_whitelisted(ip_str):
    """Return True if ip_str falls inside any WHITELIST_NETWORKS entry."""
    try:
        addr = ipaddress.ip_address(ip_str)
        return any(addr in ipaddress.ip_network(net, strict=False)
                   for net in WHITELIST_NETWORKS)
    except ValueError:
        return False


def _parse_packet(line):
    """
    Parse one tcpdump -n output line and return (src_ip, dst_port) or None.

    tcpdump formats IPv4 addresses with the port glued on as a dotted suffix:
        IP 1.2.3.4.54321 > 192.168.100.5.80: Flags [S] ...
        IP 1.2.3.4.54321 > 192.168.100.5.161: UDP, length 0
    We strip the trailing port segment from each side.
    """
    m = re.search(r"IP\s+([\d\.]+)\s+>\s+([\d\.]+):", line)
    if not m:
        return None

    def _dotted_to_ip_port(token):
        parts = token.split(".")
        # IPv4 is always 4 octets; anything beyond is the port
        for split in (4, 3):  # try 4-octet address first, then 3 (malformed)
            try:
                ip = str(ipaddress.ip_address(".".join(parts[:split])))
                port = int(parts[split]) if len(parts) > split else 0
                return ip, port
            except (ValueError, IndexError):
                continue
        return None, 0

    src_ip, _ = _dotted_to_ip_port(m.group(1))
    _, dst_port = _dotted_to_ip_port(m.group(2))
    return (src_ip, dst_port) if src_ip else None


def _is_scan_detected(ip, dst_port):
    """
    Record that ip probed dst_port and return True when the number of *unique*
    destination ports probed within PORT_SCAN_WINDOW exceeds PORT_SCAN_THRESHOLD.

    Tracking unique ports (not raw packet counts) is the key distinction:
    - A port scanner hits many different ports → unique count climbs fast.
    - A heavy legitimate user opens many connections to the same port(s) → stays low.
    - Normal UDP traffic (DNS → :53, mDNS → :5353) always targets the same port → stays low.
    """
    # High/ephemeral ports are responses to our own outbound connections —
    # not meaningful probe targets for a scanner.  Skip them to avoid
    # false positives (e.g. Steam opening many connections on startup).
    if dst_port >= PORT_SCAN_DST_PORT_MAX:
        return False

    now = time.monotonic()
    cutoff = now - PORT_SCAN_WINDOW
    with state_lock:
        # Evict events outside the rolling window
        scan_events[ip] = [(t, p) for t, p in scan_events[ip] if t > cutoff]
        # Record this port only if not already seen in the current window
        ports_seen = {p for _, p in scan_events[ip]}
        if dst_port not in ports_seen:
            scan_events[ip].append((now, dst_port))
        unique_count = len(ports_seen | {dst_port})
    return unique_count >= PORT_SCAN_THRESHOLD


def detect_scans():
    """
    Single tcpdump thread that detects both TCP SYN and UDP port scans.

    Both scan types share the same unique-destination-port metric:
    block an IP once it probes PORT_SCAN_THRESHOLD distinct ports within
    PORT_SCAN_WINDOW seconds.

    TCP SYN filter keeps false positives low — only connection-opening packets
    are counted, not data or FIN packets from normal sessions.
    UDP filter catches nmap -sU / rustscan UDP mode which probes many ports
    rapidly; normal UDP traffic (DNS, mDNS, DHCP) uses a handful of fixed ports
    and will not reach the threshold.
    """
    print(
        f"Monitoring TCP SYN + UDP for port scans "
        f"(threshold: {PORT_SCAN_THRESHOLD} unique ports / {PORT_SCAN_WINDOW}s)..."
    )
    while not stop_event.is_set():
        try:
            # -i any : all interfaces (catches scans arriving on any NIC)
            # -n     : no hostname resolution (speed)
            # -l     : line-buffer stdout for real-time processing
            # -c 1000: restart after 1000 packets so the process stays fresh
            process = subprocess.Popen(
                ["tcpdump", "-i", "any", "-n", "-l", "-c", "1000", TCPDUMP_FILTER],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )

            for line in process.stdout:
                if stop_event.is_set():
                    process.terminate()
                    break
                line = line.strip()
                if not line or "IP" not in line:
                    continue

                parsed = _parse_packet(line)
                if not parsed:
                    continue
                src_ip, dst_port = parsed

                if _is_whitelisted(src_ip):
                    continue

                with state_lock:
                    already_blocked = src_ip in blocked_ips
                if already_blocked:
                    continue

                if _is_scan_detected(src_ip, dst_port):
                    proto = "UDP" if "UDP" in line else "TCP"
                    print(f"{proto} port scan from {src_ip} ({PORT_SCAN_THRESHOLD} unique ports) — blocking.")
                    block_ip_firewalld(src_ip)

            process.wait()
        except Exception as e:
            print(f"tcpdump error: {e}")

        if not stop_event.is_set():
            time.sleep(1)


def monitor_logs():
    """
    Tail the kernel/syslog for explicit port-scan markers (e.g. from an iptables
    LOG rule) and block the source IP.

    On a pure-journald Arch system /var/log/messages may not exist.  If it is
    missing we skip this thread gracefully — tcpdump-based detection still runs.
    """
    import os
    log_file = "/var/log/messages"
    if not os.path.exists(log_file):
        print(f"Log file {log_file} not found — log monitoring disabled. "
              "Install a syslog daemon (e.g. syslog-ng) or add an iptables LOG rule "
              "that writes to this file if you want log-based detection.")
        return

    print(f"Monitoring {log_file} for port scan markers...")
    SCAN_PATTERN = re.compile(r"Port Scan Detected.*SRC=([\d\.]+)")
    try:
        with open(log_file, "r") as f:
            f.seek(0, 2)  # start at the end; don't replay old entries
            while not stop_event.is_set():
                line = f.readline()
                if not line:
                    time.sleep(1)
                    continue

                match = SCAN_PATTERN.search(line)
                if match:
                    ip = match.group(1)
                    print(f"Port scan log marker from {ip}")
                    block_ip_firewalld(ip)
    except Exception as e:
        print(f"Error in log monitoring: {e}")


def cleanup_loop():
    """Periodically unblock IPs whose timeout has elapsed."""
    while not stop_event.is_set():
        cleanup_expired_blocks()
        # Sleep in short intervals so we respond to stop_event promptly
        for _ in range(60):
            if stop_event.is_set():
                break
            time.sleep(1)


def main():
    """Main entry point."""
    # Handle both Ctrl-C (SIGINT) and systemd stop (SIGTERM) the same way.
    def _shutdown(signum, frame):
        print(f"\nReceived signal {signum} — shutting down...")
        stop_event.set()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    print("Ensuring drop zone is configured...")
    ensure_drop_zone()

    print("Installing kernel-level rate-limiting rules...")
    setup_nft_ratelimit()

    logs_thread = Thread(target=monitor_logs, daemon=True)
    scan_thread = Thread(target=detect_scans, daemon=True)
    cleanup_thread = Thread(target=cleanup_loop, daemon=True)

    logs_thread.start()
    scan_thread.start()
    cleanup_thread.start()

    print("Dynamic Firewall Rules service started.")

    # Park the main thread; _shutdown() will set stop_event when a signal arrives.
    while not stop_event.is_set():
        time.sleep(1)

    logs_thread.join(timeout=5)
    scan_thread.join(timeout=5)
    cleanup_thread.join(timeout=5)

    print("Removing kernel-level rate-limiting rules...")
    teardown_nft_ratelimit()
    print("Dynamic firewall rules service stopped.")


if __name__ == "__main__":
    main()
