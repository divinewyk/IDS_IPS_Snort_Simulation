#!/usr/bin/env bash
# ---------------------------------------------------------------------
# teardown.sh — removes the lab namespaces/veth pairs cleanly.
# Run with: sudo bash teardown.sh
# ---------------------------------------------------------------------
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

for ns in ns-attacker ns-ids ns-victim; do
    ip netns del "$ns" 2>/dev/null || true
done

echo "Lab namespaces removed."
