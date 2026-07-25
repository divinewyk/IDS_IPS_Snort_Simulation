#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 03_run_ids_mode.sh  —  DEMO PART 1: DETECTION ONLY
#
# Runs Snort INLINE (bridging veth-ida <-> veth-idv inside ns-ids) but
# loaded with local_ids.rules (action = alert). Traffic still reaches
# the victim — you're proving Snort SEES and CLASSIFIES the attack
# in real time, without yet blocking it.
#
# Works with either Snort 2.9 (apt) or Snort 3 (source build) —
# whichever 00_install_snort.sh installed. Snort 3 uses its bundled
# default snort.lua as a base config plus -R to load our custom rules
# and --lua to set HOME_NET; Snort 2.9 uses our hand-written .conf.
#
# Run in its own terminal, then in a second terminal run
# attack_demo.sh from ns-attacker. Watch the alerts print live here.
#
# Run with: sudo bash scripts/03_run_ids_mode.sh
# ---------------------------------------------------------------------
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
RULES_FILE="$SCRIPT_DIR/../rules/local_ids.rules"

mkdir -p /var/log/snort

# Detect Snort major version robustly. Snort 3's -V banner reads
# "Snort++ 3.12.2.0" (no "Version" word) on newer builds and
# "Version 3.x" on older ones, so just pull the first x.y.z and take
# the major number. Snort 2.9 gives "2".
SNORT_VERSION="$(snort -V 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)"

echo "Starting Snort in IDS (alert-only, inline-bridge) mode..."
echo "Bridge: veth-ida <-> veth-idv inside ns-ids"
echo "Ruleset: local_ids.rules (nothing will be blocked)"
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
        -c lab_snort_ids.conf \
        -l /var/log/snort \
        -A console
fi
