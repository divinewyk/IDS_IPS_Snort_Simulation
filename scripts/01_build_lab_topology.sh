#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 01_build_lab_topology.sh
# Builds an isolated, self-contained "wire" entirely inside your VM
# using Linux network namespaces — no second VM, no Wi-Fi/router
# dependency, so the live demo can't be broken by conference-room
# network flakiness.
#
# Topology:
#
#   [ns-attacker]  10.0.0.1/24
#         | veth-a  <---->  veth-ida |
#                        [ns-ids]  (no IP — pure L2 bridge, Snort runs
#                        here inline, "on the wire")
#         | veth-idv <---->  veth-v  |
#                                          10.0.0.2/24  [ns-victim]
#
# Run with: sudo bash 01_build_lab_topology.sh
# Undo with: sudo bash teardown.sh
# ---------------------------------------------------------------------
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

echo "[1/5] Cleaning up any previous lab namespaces..."
for ns in ns-attacker ns-ids ns-victim; do
    ip netns del "$ns" 2>/dev/null || true
done

echo "[2/5] Creating namespaces..."
ip netns add ns-attacker
ip netns add ns-ids
ip netns add ns-victim

echo "[3/5] Creating veth pairs..."
ip link add veth-a  type veth peer name veth-ida
ip link add veth-idv type veth peer name veth-v

ip link set veth-a   netns ns-attacker
ip link set veth-ida netns ns-ids
ip link set veth-idv netns ns-ids
ip link set veth-v   netns ns-victim

echo "[4/5] Configuring attacker + victim interfaces (10.0.0.0/24)..."
ip netns exec ns-attacker ip addr add 10.0.0.1/24 dev veth-a
ip netns exec ns-attacker ip link set veth-a up
ip netns exec ns-attacker ip link set lo up

ip netns exec ns-victim ip addr add 10.0.0.2/24 dev veth-v
ip netns exec ns-victim ip link set veth-v up
ip netns exec ns-victim ip link set lo up

# CRITICAL: disable checksum + segmentation offloading on the attacker and
# victim veths. On virtual interfaces the kernel leaves TCP/UDP checksums
# blank (hardware would normally fill them). Once Snort forwards a packet
# across the afpacket bridge, that blank checksum arrives WRONG at the far
# end and the receiver silently drops the segment — so TCP (HTTP, etc.)
# fails to connect even though ICMP works. Turning offloading off forces
# real checksums into the packets.
ip netns exec ns-attacker ethtool -K veth-a tx off rx off gso off gro off tso off 2>/dev/null || true
ip netns exec ns-victim   ethtool -K veth-v tx off rx off gso off gro off tso off 2>/dev/null || true

echo "[5/5] Configuring ns-ids as a transparent inline bridge (no IPs)..."
ip netns exec ns-ids ip link set veth-ida up promisc on
ip netns exec ns-ids ip link set veth-idv up promisc on
ip netns exec ns-ids ip link set lo up
# Disable offloading so Snort's afpacket DAQ sees every packet cleanly
for intf in veth-ida veth-idv; do
    ip netns exec ns-ids ethtool -K "$intf" tx off rx off gro off gso off tso off 2>/dev/null || true
done

echo
echo "Lab topology is up."
echo "  Attacker : 10.0.0.1  (ip netns exec ns-attacker bash)"
echo "  Victim   : 10.0.0.2  (ip netns exec ns-victim bash)"
echo "  IDS/IPS  : ns-ids, bridging veth-ida <-> veth-idv (no IP, invisible on the wire)"
echo
echo "Sanity check (should NOT work yet — Snort/bridge isn't running):"
echo "  sudo ip netns exec ns-attacker ping -c1 10.0.0.2"
echo
echo "Next: start the victim's test server, then run Snort in IDS or IPS mode."
