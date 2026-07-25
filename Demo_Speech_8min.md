# Network IDS/IPS — Demo Speech (≈ 8–9 minutes)

**Delivery notes:** Speak at a relaxed pace. Bracketed lines like `[RUN]` and
`[PRESS ENTER]` are cues for the keyboard — don't read them aloud. Run the demo
in step mode so you control the pace: `sudo bash scripts/run_demo.sh --step`.
The demo now covers FOUR attack categories — reconnaissance, web attack,
malware, and denial-of-service — first detected, then blocked, with a results
scoreboard at the end.

---

## 1. Opening  (≈ 30 sec)

Good [morning/afternoon], everyone. Our project answers a simple but serious
question: when malicious traffic is moving across a network, can we catch it —
and can we stop it — in real time, right there on the wire?

To do that, we built a working Network Intrusion Detection and Prevention System
using Snort, an open-source engine that's one of the most widely deployed and
widely taught tools in the security industry. In the next few minutes we're
going to launch four different kinds of attacks against a live machine, and
watch our system first *detect* every one of them, and then *block* every one of
them, as it happens.

---

## 2. The problem — why this matters  (≈ 1 min)

First, why do we even need this. Most people assume a firewall keeps them safe.
A firewall is important, but it makes decisions based on ports and addresses —
it decides *who* is allowed to talk to *whom*. What it does not do is look
*inside* that allowed conversation.

So if an attacker sends a web request that's technically allowed through on
port 80, but that request contains a SQL injection payload, the firewall waves
it right through. It never inspects the content.

That's the gap an IDS/IPS fills. It inspects the actual content and behavior of
the traffic crossing the network, recognizes the signatures of known attacks —
port scans, floods, injection attempts, malware — and reacts to them. And this
matters more every year: a large majority of organizations now report rising
intrusion attempts, and advanced IDS/IPS has become a frontline control in most
enterprises.

---

## 3. IDS vs IPS — the key concept  (≈ 1 min)

There are two modes to this, and the difference is the heart of our project.

An **IDS** — Intrusion *Detection* System — is passive. It watches the traffic,
recognizes an attack, and raises an alert. But it does not stop it. Think of it
like a security camera: it records the break-in and sounds the alarm, but the
door is still open.

An **IPS** — Intrusion *Prevention* System — sits directly *in* the path of the
traffic. When it recognizes an attack, it drops those packets before they ever
reach the target. That's the locked door that actually refuses to open.

The clever part is that it's the *same* detection logic in both cases. The only
thing that changes is the rule's action: **alert**, versus **drop**. And that's
exactly what we'll show you — the same four attacks, first detected, then
blocked, just by changing that one word.

---

## 4. Our setup — the architecture  (≈ 1.5 min)

Here's how our lab is built. Everything you're about to see runs inside a single
virtual machine on this laptop — no external network, nothing that can break on
conference Wi-Fi.

Inside that VM we've built three isolated machines using Linux networking:

- An **attacker** at address 10.0.0.1 — where the malicious traffic comes from.
- A **victim** at 10.0.0.2 — a small web server, our target.
- And in between them sits **Snort**, running *inline* on the wire.

[POINT AT SCREEN] The important part: Snort bridges the two sides. Every single
packet the attacker sends has to physically pass *through* Snort to reach the
victim. Snort inspects each packet, compares it against a set of rules we wrote,
and issues a verdict — allow it through, or drop it. Snort itself has no IP
address; it's invisible on the wire, exactly like a real inline security
appliance sitting between a router and a protected network.

We wrote ten custom detection rules. Some match on packet *behavior* — for
example, "alert if one source sends more than twenty connection attempts in ten
seconds," which is how you catch a scan or a flood. Others match on packet
*content* — the actual text of a SQL injection string, or the signature of a
known malware file. Today we'll trigger four of them, one from each major attack
category. Let's run it.

---

## 5. LIVE DEMO — Phase 1: Detection  (≈ 2 min)

[RUN: `sudo bash scripts/run_demo.sh --step`]

The lab is building... and there's our topology on screen: attacker on the left,
Snort in the middle, victim on the right. We're now in **Phase 1 — Detection
mode**, where Snort only raises alerts; it won't block anything yet. Watch each
attack.

[PRESS ENTER — Port scan]

**Attack one: reconnaissance — a port scan.** Before a real attacker strikes,
they probe the target to find open doors. We're running an Nmap scan across a
hundred ports. Look at the screen — Snort says **DETECTED**, and it shows us its
own alert line: rule 1000001, "Nmap SYN scan detected," coming from 10.0.0.1.
That's Snort recognizing the *pattern* of a scan — dozens of connection attempts
in a couple of seconds. But notice: the attacker still successfully mapped the
host and found our open port. We saw it, but we didn't stop it.

[PRESS ENTER — SQL injection]

**Attack two: a web attack — SQL injection.** This is the classic `OR 1=1`
payload an attacker uses to bypass a login form. Snort — **DETECTED** — rule
1000020, it matched the malicious string inside the web request. But look at the
victim line: HTTP 200. The request still reached the server. The attack landed.

[PRESS ENTER — EICAR malware]

**Attack three: malware.** We're sending the EICAR test string — an industry-
standard, harmless file used specifically to test antivirus and intrusion
systems. Snort — **DETECTED** — rule 1000030, it recognized the malware
signature in transit. But once again, it still reached the victim.

[PRESS ENTER — ICMP flood]

**Attack four: denial-of-service — a flood.** A burst of traffic meant to
overwhelm the target. **DETECTED** — and notice the victim took the full flood:
zero percent packet loss. Everything got through.

So that's detection. We now have complete visibility — Snort saw and named every
single attack. But every attack still succeeded. That's the limitation of
detection alone, and it's exactly why we need prevention.

---

## 6. LIVE DEMO — Phase 2: Prevention  (≈ 2 min)

[PRESS ENTER — Phase 2 begins]

Now we're in **Phase 2 — Prevention mode.** Same Snort, same rules, one change:
the action is now *drop* instead of *alert*. We run the exact same four attacks.

[PRESS ENTER — Port scan blocked]

The port scan again. Snort says **BLOCKED** — and see the alert now reads
`[drop]` and "Nmap SYN scan detected - BLOCKED." The scan packets were dropped on
the wire. The attacker's probe comes back empty.

[PRESS ENTER — SQL injection blocked]

The SQL injection — **BLOCKED.** And look at the victim line: *no response, the
malicious packet was dropped on the wire.* Compare that to a moment ago, when the
exact same request sailed through with an HTTP 200. This time it never reached
the server.

[PRESS ENTER — EICAR blocked]

The malware — **BLOCKED.** The victim never received the payload. Snort killed it
in transit.

[PRESS ENTER — ICMP flood blocked]

And the flood — **BLOCKED.** Look at the packet loss now: most of the flood is
being dropped on the wire. The target stays up.

[PRESS ENTER — Scoreboard]

And here's our scoreboard. Four attack categories — reconnaissance, web attack,
malware, denial-of-service. Every one was **detected** in Phase 1, and every one
was **blocked** in Phase 2. Same engine, same rules — we just told it to act.

---

## 7. What we proved & honest limitations  (≈ 45 sec)

So, to sum up what you just saw: one engine, sitting on the wire, catching four
completely different classes of attack — a scan, a web exploit, a piece of
malware, and a flood — first alerting on them, then actively blocking them before
they reach the target.

We'll be honest about the limits, too. This is signature- and behavior-based
detection, so it catches *known* attack patterns — it wouldn't, on its own, catch
a brand-new, never-seen-before exploit. In production you'd pair it with
anomaly-based tools and feed the alerts into a central monitoring system. That's
the natural next step for this work.

---

## 8. Close  (≈ 30 sec)

But the core goal is done and demonstrated: a real intrusion prevention system,
inspecting live traffic on the wire, that detects malicious activity and stops it
in real time — running entirely on a student laptop.

Thank you. We're happy to take any questions.

---

### Timing map
| Section | Time | Running total |
|---|---|---|
| Opening | 0:30 | 0:30 |
| The problem | 1:00 | 1:30 |
| IDS vs IPS | 1:00 | 2:30 |
| Architecture | 1:30 | 4:00 |
| Demo — detection (4 attacks) | 2:00 | 6:00 |
| Demo — prevention (4 attacks) | 2:00 | 8:00 |
| Results & limits | 0:45 | 8:45 |
| Close | 0:30 | 9:15 |

**If you need to hit 8:00 exactly:** trim the statistics in Section 2, shorten
the architecture rules explanation in Section 4, and in the demo describe the
port scan and flood quickly while spending your detail on the SQL injection and
EICAR (those are the most impressive "it read the payload" moments).

### Handy facts to have ready for Q&A
- **Rule IDs (SIDs):** scan = 1000001/1000002, ICMP = 1000003/1000010,
  SQL injection = 1000020, EICAR malware = 1000030. All in Snort's reserved
  local range (1,000,000+), so they never clash with built-in rules.
- **How behavior rules work:** `detection_filter: track by_src, count N,
  seconds S` — Snort alerts once one source crosses N events in S seconds. That's
  how a scan (many connections) or a flood (many pings) is distinguished from
  normal traffic.
- **How content rules work:** they match the literal bytes in the packet — e.g.
  the string `' OR '1'='1` or `EICAR-STANDARD-ANTIVIRUS-TEST-FILE`.
- **Why detection vs prevention is one word:** the rule action — `alert` (log
  only) vs `drop` (discard the packet). Prevention only works because Snort runs
  *inline*, physically in the traffic path.
- **Is it real malware?** No — EICAR is a harmless standard test string, and all
  traffic stays inside the VM's isolated virtual network.
