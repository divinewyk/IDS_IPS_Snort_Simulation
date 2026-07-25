# QUICKSTART — Network IDS/IPS Lab (Snort, inline bridge)

Condensed, battle-tested path from a fresh Ubuntu VM to a working live
detect-then-block demo. Full detail is in `IDS_IPS_Setup_Runbook.docx`.

---

## 0. Two machines — know which is which (the #1 source of mistakes)

- **Your host** (Mac / Windows): ONLY used for `ssh` and `scp`.
  Prompt looks like `Mac:~ user$` or `PS C:\Users\you>`.
- **The Ubuntu VM**: runs EVERYTHING else — `apt`, `ip`, `snort`, `timedatectl`,
  all `scripts/*.sh`. Prompt looks like `user@ubuntu-server:~$`.

If you see `ip: command not found` or `snort: command not found`, you're on the
host by mistake. SSH into the VM and run it there.

---

## 1. Fix the VM clock (do this first — fresh VMs are often hours behind)

    sudo timedatectl set-ntp true
    sleep 5 && timedatectl        # want: System clock synchronized: yes

Still wrong? Set manually (get real UTC on your host with `date -u`):

    sudo timedatectl set-ntp false
    sudo timedatectl set-time "2026-07-20 02:12:00"   # replace with real UTC

A wrong clock breaks `apt` ("Release file not valid yet") AND source-build git
clones — fix it before anything else.

---

## 2. Enable SSH and get the VM's IP (at the VM console)

    sudo apt install -y openssh-server
    sudo systemctl enable --now ssh
    ip a        # find the enp0s1 / enp0s3 / ens160 line, note the inet address

Can't reach that IP from your host? Switch the VM's network adapter to
**Bridged** in your hypervisor (UTM/VirtualBox/VMware) and re-check `ip a`.

---

## 3. Copy the package to the VM (run on your HOST)

scp needs BOTH a source and a destination:

    scp /path/to/Network_IDS_IPS_Package.zip <vm-username>@<vm-ip>:~/

Then on the VM:

    unzip Network_IDS_IPS_Package.zip
    cd Network_IDS_IPS_Package

---

## 4. Install Snort + tools (on the VM, one time)

    sudo bash scripts/00_install_snort.sh

- Tries `apt install snort` first (Ubuntu 22.04/24.04 LTS).
- If that package is missing (newer Ubuntu), it **automatically builds Snort 3
  from source** — 20-40 minutes, let it run.

If nmap/hping3 didn't get installed, add them:

    sudo apt install -y nmap hping3 curl iproute2 net-tools ethtool tcpdump

Verify:

    snort -V              # Snort++ 3.x (or Version 2.9.x)
    snort --daq-list      # afpacket should show "inline"

---

## 5. THE DEMO — one command, one terminal  (recommended)

    sudo bash scripts/run_demo.sh

That's it. The script builds the lab, starts the victim + Snort in the
background, launches each attack itself, and prints a plain-English result
after every one — first DETECTED (Phase 1), then BLOCKED (Phase 2). No
terminal-switching, no reading raw Snort output.

Add `--step` to pause between attacks while you talk:

    sudo bash scripts/run_demo.sh --step

Sample output:

    PHASE 1 — DETECTION (IDS): Snort ALERTS but lets traffic pass
      SQL injection (web attack)
         Snort : DETECTED [sid 1000020]
         Victim: got the request (HTTP 200)  <- allowed through
      ICMP flood (denial-of-service)
         Snort : DETECTED [sid 1000003/1000010]
         Victim: 0% packet loss  <- allowed through

    PHASE 2 — PREVENTION (IPS): same attacks, Snort DROPS them
      SQL injection (web attack)
         Snort : BLOCKED [sid 1000020]
         Victim: no response — request dropped on the wire
      ICMP flood (denial-of-service)
         Snort : BLOCKED [sid 1000003/1000010]
         Victim: 75% packet loss — flood dropped on the wire

That single screen IS the demo: detect, then block, side by side.
Do one dry run before you present so you know it fires on your VM.

Cleanup afterward:

    sudo bash scripts/teardown.sh

---

## 6. MANUAL run (optional — only if you want to show the moving parts)

Four SSH windows, each in `~/Network_IDS_IPS_Package`:

- Terminal 1: `sudo bash scripts/01_build_lab_topology.sh`
- Terminal 2: `sudo bash scripts/02_start_victim_server.sh`   (leave running)
- Terminal 3: `sudo bash scripts/03_run_ids_mode.sh`          (alerts appear here)
- Terminal 4: `sudo bash scripts/attack_demo.sh scan`         (then icmp, sqli, eicar)

Then Ctrl+C in Terminal 3, `sudo bash scripts/04_run_ips_mode.sh`, and re-run the
attacks to show them blocked.

---

## Notes for graders / teammates

- `run_demo.sh` and the manual scripts auto-detect Snort 2.9 vs Snort 3 and use
  the right config syntax (Snort 2: `.conf`; Snort 3: bundled `snort.lua` +
  `-R rules/... --lua HOME_NET=...`).
- Rules load on BOTH Snort versions: they use `detection_filter` (not the removed
  Snort 2 `threshold`) and avoid standalone `nocase`.
- Custom SIDs are 1000001-1000040, inside Snort's reserved local range (>=1,000,000).
- All attack traffic is synthetic or the harmless industry-standard EICAR test
  string — nothing is real malware, and it never leaves the VM's isolated network.

See `IDS_IPS_Setup_Runbook.docx` §10 for the full troubleshooting list.
