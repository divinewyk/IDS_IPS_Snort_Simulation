#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 04_run_ips_mode.sh  —  DEMO PART 2: DETECTION + PREVENTION
#
# Stop 03_run_ids_mode.sh first (Ctrl+C), then run this. Same inline
# bridge, but loaded with local_ips.rules (action = drop). Matching
# packets are now dropped by Snort before they ever reach the victim.
#
# Works with either Snort 2.9 (apt) or Snort 3 (source build) — see
# 03_run_ids_mode.sh for details on how the two paths differ.
#
# How to PROVE it's blocked, live:
#   - Keep 02_start_victim_server.sh running: its access log will show
#     NO new request for the blocked attack.
#   - Or run, from ns-attacker: ping -c 20 -i 0.2 10.0.0.2
#     against the ICMP flood rule and watch it stop responding once
#     the flood threshold trips.
#
# Run with: sudo bash scripts/04_run_ips_mode.sh
# ---------------------------------------------------------------------
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
RULES_FILE="$SCRIPT_DIR/../rules/local_ips.rules"

mkdir -p /var/log/snort

# Detect Snort major version robustly. Snort 3's -V banner reads
# "Snort++ 3.12.2.0" (no "Version" word) on newer builds and
# "Version 3.x" on older ones, so just pull the first x.y.z and take
# the major number. Snort 2.9 gives "2".
SNORT_VERSION="$(snort -V 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)"

echo "Starting Snort in IPS (inline, DROP-enforcing) mode..."
echo "Bridge: veth-ida <-> veth-idv inside ns-ids"
echo "Ruleset: local_ips.rules (matching traffic is DROPPED on the wire)"
echo "Press Ctrl+C to stop."
echo

if [[ "$SNORT_VERSION" == "3" ]]; then
    # --- Snort 3 (built from source) ---
    BASE_LUA="$(find /usr/local -name snort.lua 2>/dev/null | head -1)"
    if [[ -z "$BASE_LUA" ]]; then
        echo "Could not find snort.lua under /usr/local — check the Snort 3 build completed." >&2
        exit 1
    fi
    echo "Using base config: $BASE_LUA"
    ip netns exec ns-ids snort \
        -c "$BASE_LUA" \
        -R "$RULES_FILE" \
        --lua 'HOME_NET="10.0.0.0/24"' \
        --daq afpacket \
        -i veth-ida:veth-idv \
        -Q \
        -l /var/log/snort \
        -A alert_fast
else
    # --- Snort 2.9 (apt) ---
    cd "$CONFIG_DIR"
    ip netns exec ns-ids snort \
        -Q --daq afpacket \
        -i veth-ida:veth-idv \
        -c lab_snort_ips.conf \
        -l /var/log/snort \
        -A console
fi
