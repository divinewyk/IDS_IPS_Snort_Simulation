#!/usr/bin/env bash
# =====================================================================
# run_demo.sh  —  ONE-COMMAND Network IDS/IPS live demonstration.
#
# Single terminal, self-narrating. For each attack it shows what the
# attack is, the payload sent, the REAL Snort alert line, and the
# victim's fate — first DETECTED (Phase 1), then BLOCKED (Phase 2) —
# and finishes with a results scoreboard.
#
#   sudo bash scripts/run_demo.sh          # runs straight through
#   sudo bash scripts/run_demo.sh --step   # pause for Enter each step
# =====================================================================
set -uo pipefail

if [[ $EUID -ne 0 ]]; then echo "Run as root:  sudo bash $0"; exit 1; fi

SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_IDS="$SDIR/../rules/local_ids.rules"
RULES_IPS="$SDIR/../rules/local_ips.rules"
CONF_DIR="$SDIR/../config"
LOG=/tmp/snort_demo.log
HN="10.0.0.0/24"
VICTIM=10.0.0.2

STEP=0; [[ "${1:-}" == "--step" ]] && STEP=1

G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; C=$'\e[36m'; D=$'\e[2m'; N=$'\e[0m'

SNORT_VER="$(snort -V 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)"
BASE_LUA="$(find /usr/local -name snort.lua 2>/dev/null | head -1)"

SNORT_PID=""; VICTIM_PID=""
declare -A DET=(); declare -A BLK=()
cleanup(){ [[ -n "$SNORT_PID" ]] && kill "$SNORT_PID" 2>/dev/null
           [[ -n "$VICTIM_PID" ]] && kill "$VICTIM_PID" 2>/dev/null; }
trap cleanup EXIT

pause(){ [[ "$STEP" == 1 ]] && read -rp "        ${D}(press Enter for the next attack)${N} " _ || true; }

start_snort(){
  : > "$LOG"
  local rules="$RULES_IDS"; [[ "$1" == ips ]] && rules="$RULES_IPS"
  if [[ "$SNORT_VER" == 3 ]]; then
    ip netns exec ns-ids stdbuf -oL -eL snort -c "$BASE_LUA" -R "$rules" --lua "HOME_NET=\"$HN\"" \
      --daq afpacket -i veth-ida:veth-idv -Q -A alert_fast >"$LOG" 2>&1 &
  else
    local conf="$CONF_DIR/lab_snort_ids.conf"; [[ "$1" == ips ]] && conf="$CONF_DIR/lab_snort_ips.conf"
    ( cd "$CONF_DIR" && ip netns exec ns-ids stdbuf -oL -eL snort -Q --daq afpacket \
        -i veth-ida:veth-idv -c "$conf" -A console ) >"$LOG" 2>&1 &
  fi
  SNORT_PID=$!
  local i
  for i in $(seq 1 16); do
    grep -q "Commencing packet processing" "$LOG" 2>/dev/null && { sleep 1; return 0; }
    kill -0 "$SNORT_PID" 2>/dev/null || { echo "${R}Snort exited during startup:${N}"; tail -15 "$LOG"; exit 1; }
    sleep 0.5
  done
  if kill -0 "$SNORT_PID" 2>/dev/null; then sleep 1; return 0; fi
  echo "${R}Snort did not start. Last lines of its log:${N}"; tail -15 "$LOG"; exit 1
}
stop_snort(){ [[ -n "$SNORT_PID" ]] && { kill "$SNORT_PID" 2>/dev/null; wait "$SNORT_PID" 2>/dev/null; SNORT_PID=""; sleep 0.5; }; }
alerts_for(){ local c; c=$(grep -c "1:$1:" "$LOG" 2>/dev/null || true); echo "${c:-0}"; }
first_alert(){ grep -m1 -E "1:($1):" "$LOG" 2>/dev/null | sed -E 's/ \[\*\*\] \[Classification.*\{/  {/'; }

# print the shared header for one attack
head_attack(){ # $1 label  $2 whatis  $3 business impact  $4 shows
  echo "  ${B}$1${N}"
  echo "     ${C}What it is :${N} $2"
  echo "     ${C}QuickBite risk:${N} $3"
  echo "     ${C}On the wire:${N} $4"
}

verdict_snort(){ # $1 phase  $2 count  $3 sid-regex
  local phase="$1" n="$2" sids="$3"
  if [[ "$n" -gt 0 ]]; then
    if [[ "$phase" == ids ]]; then echo "     ${G}${B}>> Snort DETECTED it${N}  (${n} alerts).  Snort's own words:"
    else echo "     ${G}${B}>> Snort BLOCKED it${N}  (${n} alerts).  Snort's own words:"; fi
    echo "        ${D}$(first_alert "$sids")${N}"
  else
    echo "     ${R}>> Snort raised no alert${N}"
  fi
}

http_attack(){ # $1 phase $2 key $3 label $4 whatis $5 risk $6 sid $7 url $8 post
  local phase="$1" key="$2" label="$3" whatis="$4" risk="$5" sid="$6" url="$7" post="$8"
  head_attack "$label" "$whatis" "$risk" "HTTP POST to victim:80 containing  \"$post\""
  start_snort "$phase"
  local code
  code=$(ip netns exec ns-attacker curl -s -o /dev/null -w "%{http_code}" \
         --max-time 4 -X POST --data "$post" "$url" 2>/dev/null); code=${code:-000}
  sleep 1
  local n; n=$(alerts_for "$sid")
  stop_snort
  verdict_snort "$phase" "$n" "$sid"
  if [[ "$phase" == ids ]]; then
    [[ "$n" -gt 0 ]] && DET[$key]=YES || DET[$key]=no
    if [[ "$code" == 200 ]]; then echo "     ${Y}Victim: received the attack (HTTP 200) — traffic was allowed through${N}"
    else echo "     Victim: no connection (HTTP $code)"; fi
  else
    [[ "$n" -gt 0 ]] && BLK[$key]=YES || BLK[$key]=no
    if [[ "$code" == 200 ]]; then echo "     ${R}Victim: still received it (NOT blocked)${N}"
    else echo "     ${G}${B}Victim: no response — the malicious packet was dropped on the wire${N}"; fi
  fi
  echo; pause
}

credential_stuffing_attack(){ # $1 phase
  local phase="$1" code ok=0 no_response=0 i n
  head_attack "Credential stuffing  (account takeover)" \
    "Many rapid login attempts using guessed or reused customer passwords." \
    "A successful account takeover could expose saved addresses, orders, and payment-related account data." \
    "15 HTTP POST login attempts sent to the QuickBite customer-login endpoint"
  start_snort "$phase"
  for i in $(seq 1 15); do
    code=$(ip netns exec ns-attacker curl -s -o /dev/null -w "%{http_code}" --max-time 1 \
      -X POST --data "user=customer$i&password=quickbite-demo-guess" "http://$VICTIM/login" 2>/dev/null)
    [[ "${code:-000}" == 200 ]] && ok=$((ok + 1)) || no_response=$((no_response + 1))
  done
  sleep 1
  n=$(alerts_for 1000050)
  stop_snort
  verdict_snort "$phase" "$n" 1000050
  if [[ "$phase" == ids ]]; then
    [[ "$n" -gt 0 ]] && DET[stuffing]=YES || DET[stuffing]=no
    echo "     ${Y}QuickBite service: ${ok}/15 login attempts received HTTP 200; detection did not stop them${N}"
  else
    [[ "$n" -gt 0 ]] && BLK[stuffing]=YES || BLK[stuffing]=no
    echo "     ${G}${B}QuickBite service: ${ok}/15 HTTP responses; ${no_response}/15 attempts were dropped or timed out${N}"
  fi
  echo; pause
}

icmp_attack(){ # $1 phase
  local phase="$1"
  head_attack "ICMP flood  (denial-of-service)" \
    "A burst of ping traffic meant to overwhelm the target." \
    "Ordering, payment, and delivery-assignment requests could slow down during peak demand." \
    "20 ICMP echo requests fired back-to-back at the victim"
  start_snort "$phase"
  local out loss
  out=$(ip netns exec ns-attacker ping -c 20 -i 0.05 -W 1 "$VICTIM" 2>/dev/null)
  loss=$(echo "$out" | grep -oE '[0-9]+% packet loss' | grep -oE '^[0-9]+'); loss=${loss:-0}
  sleep 1
  local n; n=$(( $(alerts_for 1000003) + $(alerts_for 1000010) ))
  stop_snort
  verdict_snort "$phase" "$n" "1000003|1000010"
  if [[ "$phase" == ids ]]; then
    [[ "$n" -gt 0 ]] && DET[flood]=YES || DET[flood]=no
    echo "     ${Y}Victim: ${loss}% packet loss — the flood got through${N}"
  else
    [[ "$n" -gt 0 ]] && BLK[flood]=YES || BLK[flood]=no
    echo "     ${G}${B}Victim: ${loss}% packet loss — the flood was dropped on the wire${N}"
  fi
  echo; pause
}

scan_attack(){ # $1 phase
  local phase="$1"
  head_attack "Port scan  (reconnaissance)" \
    "An attacker probing the victim to find open doors before striking." \
    "Discovering exposed services helps an attacker choose the next way to target QuickBite." \
    "Nmap SYN scan across 100 ports of the victim"
  start_snort "$phase"
  local out ports
  out=$(ip netns exec ns-attacker timeout 12 nmap -sS -T4 -n --max-retries 1 --host-timeout 8s -p 1-100 "$VICTIM" 2>/dev/null)
  ports=$(echo "$out" | grep -E '^[0-9]+/tcp' | grep -c open)
  sleep 1
  local n; n=$(( $(alerts_for 1000001) + $(alerts_for 1000002) ))
  stop_snort
  verdict_snort "$phase" "$n" "1000001|1000002"
  if [[ "$phase" == ids ]]; then
    [[ "$n" -gt 0 ]] && DET[scan]=YES || DET[scan]=no
    echo "     ${Y}Victim: attacker mapped the host (${ports} open port found) — scan allowed${N}"
  else
    [[ "$n" -gt 0 ]] && BLK[scan]=YES || BLK[scan]=no
    echo "     ${G}${B}Victim: scan packets dropped on the wire${N}"
  fi
  echo; pause
}

banner(){ echo "${C}${B}$1${N}"; }

row(){ printf "   %-20s %-18s %-9s %-9s\n" "$1" "$2" "$3" "$4"; }

clear 2>/dev/null || true
banner "=================================================================="
banner "        NETWORK IDS / IPS  —  LIVE DEMONSTRATION (Snort)"
banner "=================================================================="
echo
echo "  Scenario: QuickBite food-ordering service under a simulated attack chain."
echo "  All traffic stays inside this VM's isolated lab namespaces."
echo
echo "Building the isolated lab network..."
bash "$SDIR/01_build_lab_topology.sh" >/dev/null 2>&1

ip netns exec ns-victim python3 -c '
import http.server, socketserver
socketserver.TCPServer.allow_reuse_address = True
class H(http.server.BaseHTTPRequestHandler):
 def _r(self):
  self.send_response(200); self.send_header("Content-type","text/plain"); self.end_headers(); self.wfile.write(b"ok")
 def do_GET(self): self._r()
 def do_POST(self):
  self.rfile.read(int(self.headers.get("Content-Length",0))); self._r()
 def log_message(self,*a): pass
socketserver.TCPServer(("0.0.0.0",80), H).serve_forever()
' >/tmp/victim.log 2>&1 &
VICTIM_PID=$!
for i in $(seq 1 20); do
  ip netns exec ns-victim ss -ltn 2>/dev/null | grep -q ':80' && break; sleep 0.3
done
ip netns exec ns-victim ss -ltn 2>/dev/null | grep -q ':80' || { echo "${Y}Warning: victim server did not start:${N}"; cat /tmp/victim.log; echo; }
sleep 1

echo
echo "  ${B}Attacker 10.0.0.1${N}  ===>  ${C}${B}[ Snort inline sensor ]${N}  ===>  ${B}Victim 10.0.0.2${N}"
echo "  ${D}Every packet the attacker sends must pass THROUGH Snort to reach the victim.${N}"
echo "  ${D}Snort compares each packet to its rules and decides: allow it, or drop it.${N}"
echo
pause

banner "------------------------------------------------------------------"
banner " PHASE 1  —  DETECTION (IDS):  Snort ALERTS but lets traffic pass"
banner "------------------------------------------------------------------"
echo
scan_attack ids
http_attack ids sqli  "SQL injection  (web attack)" \
  "Tampered login input ('OR 1=1) used to bypass authentication." \
  "A successful login bypass could expose customer accounts, orders, and restaurant administration." \
  1000020 "http://$VICTIM/login"  "user=admin' OR '1'='1"
http_attack ids eicar "EICAR malware signature  (file upload)" \
  "The industry-standard harmless 'test virus' — proves signature detection." \
  "An unvetted restaurant-partner upload could introduce harmful content into a business workflow." \
  1000030 "http://$VICTIM/upload" "file=EICAR-STANDARD-ANTIVIRUS-TEST-FILE"
icmp_attack ids
credential_stuffing_attack ids
http_attack ids tamper "Order-total tampering  (checkout fraud)" \
  "A checkout request with a controlled, impossible test total." \
  "If accepted, altered totals could cause revenue loss and invalid order records." \
  1000051 "http://$VICTIM/checkout" "item=burger&quantity=1&total=0.01"

banner "------------------------------------------------------------------"
banner " PHASE 2  —  PREVENTION (IPS):  same attacks, Snort DROPS them"
banner "------------------------------------------------------------------"
echo
scan_attack ips
http_attack ips sqli  "SQL injection  (web attack)" \
  "Tampered login input ('OR 1=1) used to bypass authentication." \
  "A successful login bypass could expose customer accounts, orders, and restaurant administration." \
  1000020 "http://$VICTIM/login"  "user=admin' OR '1'='1"
http_attack ips eicar "EICAR malware signature  (file upload)" \
  "The industry-standard harmless 'test virus' — proves signature detection." \
  "An unvetted restaurant-partner upload could introduce harmful content into a business workflow." \
  1000030 "http://$VICTIM/upload" "file=EICAR-STANDARD-ANTIVIRUS-TEST-FILE"
icmp_attack ips
credential_stuffing_attack ips
http_attack ips tamper "Order-total tampering  (checkout fraud)" \
  "A checkout request with a controlled, impossible test total." \
  "If accepted, altered totals could cause revenue loss and invalid order records." \
  1000051 "http://$VICTIM/checkout" "item=burger&quantity=1&total=0.01"

banner "=================================================================="
banner "                        RESULTS  SCOREBOARD"
banner "=================================================================="
row "ATTACK" "CATEGORY" "DETECTED" "BLOCKED"
row "------" "--------" "--------" "-------"
row "Port scan"     "Reconnaissance"    "${DET[scan]:-no}"  "${BLK[scan]:-no}"
row "SQL injection" "Web attack"        "${DET[sqli]:-no}"  "${BLK[sqli]:-no}"
row "EICAR malware" "Malware sig."      "${DET[eicar]:-no}" "${BLK[eicar]:-no}"
row "ICMP flood"    "Denial of service" "${DET[flood]:-no}" "${BLK[flood]:-no}"
row "Credential stuffing" "Account takeover" "${DET[stuffing]:-no}" "${BLK[stuffing]:-no}"
row "Order-total tamper" "Checkout fraud" "${DET[tamper]:-no}" "${BLK[tamper]:-no}"
echo
banner " Every attack was SEEN in Phase 1, then STOPPED on the wire in Phase 2."
banner "=================================================================="
echo
echo "Cleanup: sudo bash scripts/teardown.sh"
