# QuickBite IDS/IPS Live Demo Script

**Run command:** `sudo bash scripts/run_demo.sh --step`

**Delivery note:** Text in brackets is a screen or keyboard cue; do not read it aloud.
This demonstration is entirely contained inside one Ubuntu virtual machine. It
does not contact the Internet, real restaurants, payment systems, or customer
accounts.

---

## 1. Opening: the QuickBite scenario

Good [morning/afternoon]. Our fictional company is **QuickBite**, a food-ordering
service. Customers sign in, place orders, and pay online. Restaurant partners
also send menu and order-related uploads to the platform.

That makes QuickBite a useful security example: it holds customer accounts,
addresses, orders, and payment-related information, and it must remain
available during busy meal times.

Our question is: if an attacker targets that service, can we first see the
attack, and then stop it before it reaches the service? We answer that question
with Snort running as both an IDS and an IPS.

---

## 2. Why we test on an Ubuntu server VM

[POINT AT THE VIRTUALBOX WINDOW]

We run the demonstration in an Ubuntu virtual machine instead of directly in
Windows. This is important for three reasons.

First, the lab scripts use Linux networking tools such as `ip`, network
namespaces, virtual Ethernet interfaces, and Snort's inline AFPacket mode.
Those are Linux features, so Ubuntu gives us the correct environment.

Second, the virtual machine provides a controlled and repeatable server
environment. We can start from the same clean topology every time, regardless
of the laptop's Wi-Fi or the room's network.

Third, it isolates the exercise. The attacker, victim, and Snort sensor all
exist inside this one VM. No demonstration traffic leaves the VM, so it cannot
scan or attack real devices.

---

## 3. How one VM becomes three machines

[EXPLAIN THE TOPOLOGY ON SCREEN]

Inside Ubuntu, Script 01 creates three Linux **network namespaces**. A namespace
is like a lightweight isolated computer: it has its own network interfaces, IP
addresses, routes, and running programs.

The three namespaces are:

```text
ns-attacker  — 10.0.0.1 — simulated attacker
ns-ids       — no IP     — inline Snort sensor
ns-victim    — 10.0.0.2 — simulated QuickBite server
```

The command `ip netns exec` runs a program inside one of those isolated
machines. For example:

```bash
ip netns exec ns-victim python3 ...
```

starts the small Python HTTP server **inside the victim**, where it listens on
`10.0.0.2:80`. It is not a real public website; it only receives the controlled
test requests used by this demonstration.

Likewise, `ip netns exec ns-attacker` runs Nmap, curl, or ping from the
attacker's side of the lab.

Script 01 also creates two *veth pairs*. A veth pair behaves like two ends of
an Ethernet cable: anything sent into one end appears at the other end. The
two virtual cables form this path:

```text
Attacker 10.0.0.1 → virtual Ethernet cable → Snort → virtual Ethernet cable → Victim 10.0.0.2
```

Snort sits in the middle as a transparent bridge. It has no IP address because
it is not the destination; it is the security appliance every packet must pass
through. In IDS mode it alerts and forwards traffic. In IPS mode it alerts and
drops matching traffic.

---

## 4. What the demo is about to show

The script first runs every scenario in **IDS mode**. The rules use `alert`, so
Snort identifies suspicious traffic but lets it reach QuickBite.

It then repeats the same scenarios in **IPS mode**. The matching rules use
`drop`, so Snort prevents the traffic from reaching the victim.

The first four are the original core scenarios:

1. Port scan — reconnaissance against QuickBite.
2. SQL-injection-style login request — attempted login bypass.
3. EICAR test-string upload — safe malware-signature test.
4. ICMP traffic burst — simulated service disruption.

The final two extend the story specifically for a food-ordering business:

5. Credential stuffing — attempted account takeover.
6. Order-total tampering — attempted checkout fraud.

[RUN: `sudo bash scripts/run_demo.sh --step`]

---

## 5. Phase 1: IDS detection

We are now in IDS mode. Notice that Snort reports each alert, but the victim
can still receive the traffic. This shows why detection is valuable for
visibility, but is not by itself prevention.

[PRESS ENTER THROUGH PORT SCAN]

The scan represents an attacker discovering which QuickBite services are
available before choosing a target.

[PRESS ENTER THROUGH SQL INJECTION]

The SQL-injection-style request represents an attempt to bypass a login form.
Snort identifies the suspicious content, but in IDS mode the test server still
responds.

[PRESS ENTER THROUGH EICAR]

The EICAR value is a harmless industry-standard test signature. It is not real
malware. It represents abuse of a restaurant-partner upload workflow.

[PRESS ENTER THROUGH ICMP]

The ICMP burst represents an attempt to make ordering or dispatch services slow
or unavailable during peak demand.

### Credential stuffing: account takeover

[PRESS ENTER]

**Why we simulate it:** Credential stuffing is a realistic risk for any service
with customer accounts. Attackers commonly try passwords leaked from another
service against many accounts. We simulate that pattern without using real
credentials, real users, or a real login system.

**What the attacker sends:** The attacker namespace sends fifteen fake HTTP
login requests. Each contains the controlled lab-only value
`password=quickbite-demo-guess`. It is not a real password and cannot log into
anything; it is simply a clear marker for the demonstration.

**How Snort detects it:** Our QuickBite rule watches HTTP traffic going to the
victim's port 80. When it sees the exact lab marker
`password=quickbite-demo-guess`, it raises Snort rule **SID 1000050**. This
shows how an IDS/IPS can recognize a known suspicious request pattern.

**What IDS proves:** In IDS mode, the rule action is `alert`. Snort prints the
credential-stuffing alert, but allows the request through. The victim still
returns HTTP responses. That represents visibility without prevention.

**What IPS proves:** In IPS mode, the matching rule action is `drop`. Snort
sees the same marker and discards the request while it is on the virtual
Ethernet path. The victim application does not receive the dropped attempts.

The business risk is account takeover: exposed saved addresses, order history,
and payment-related account data. In a real service, this network control would
also be combined with rate limits, multi-factor authentication, account-lockout
policies, and application-side failed-login monitoring.

### Order-total tampering: checkout fraud

[PRESS ENTER]

**Why we simulate it:** A food-ordering service must never trust a price sent by
the customer's browser or mobile app. If an attacker changes a checkout value
before it reaches the server, the business could lose money or create incorrect
order records. We simulate this safely rather than altering a real payment.

**What the attacker sends:** The attacker sends a controlled test checkout
request containing `item=burger&quantity=1&total=0.01`. No order is created,
no payment occurs, and the value exists only in this isolated lab.

**How Snort detects it:** The QuickBite rule inspects HTTP traffic and matches
the literal test marker `total=0.01`. When it appears, Snort raises rule
**SID 1000051**, labelled "Order-total tampering attempt detected."

**What IDS proves:** In IDS mode, Snort alerts but forwards the test request.
The victim returns HTTP 200, which visibly demonstrates that detection alone
does not stop the attempted fraud.

**What IPS proves:** In IPS mode, the rule uses `drop`. Snort detects the same
marker and discards the packet before it reaches the victim. The attacker sees
no successful response for that request, which is our proof that the inline
prevention control acted.

This is an additional network safeguard, not a substitute for secure design.
The real QuickBite application must independently calculate prices and validate
totals on the server, because a production system must never accept a client-
supplied price as authoritative.

---

## 6. Phase 2: IPS prevention

[PRESS ENTER TO START PHASE 2]

Now we repeat the exact same six stages. The topology and detection logic are
the same. The only change is the rule action: `alert` becomes `drop`.

For the first four scenarios, watch for Snort's `[drop]` action and the victim
showing no response or packet loss. The traffic is stopped at the inline sensor,
before QuickBite receives it.

### Credential stuffing blocked

[PRESS ENTER THROUGH THE FIRST FOUR, THEN CREDENTIAL STUFFING]

Here are the fifteen fake login attempts again. This time Snort detects the
marker and drops the matching requests. The attacker receives fewer or no HTTP
responses for those dropped requests, proving that the QuickBite application did
not receive them.

### Checkout fraud blocked

[PRESS ENTER]

Finally, the attacker submits the controlled `total=0.01` checkout request.
Snort reports the order-total tampering rule with a `drop` action. The victim
does not receive the request. This is the key IPS result: the prevention device
acts before the fraudulent request reaches the ordering application.

---

## 7. Scoreboard and conclusion

[POINT AT THE RESULTS SCOREBOARD]

The scoreboard summarizes six simulated attack stages. In the Detected column,
we prove that Snort recognized the suspicious traffic in IDS mode. In the
Blocked column, we prove that the same rules prevented the matching traffic in
IPS mode.

This is not a claim that signatures replace secure software design. QuickBite
still needs secure authentication, rate limiting, multi-factor authentication,
server-side price validation, secure upload handling, and monitoring. What our
lab proves is that an inline IDS/IPS provides an additional network control:
it can see suspicious traffic on the wire and stop known patterns before they
reach the service.

Thank you.

---

## Short answers for Q&A

- **Why Ubuntu?** Linux supplies the namespaces, veth interfaces, and inline
  Snort networking mode used by the lab.
- **Why `ip netns exec`?** It starts each program inside its correct isolated
  attacker or victim network environment.
- **Are these real attacks?** No. All traffic is controlled, harmless test
  traffic inside one VM.
- **Why does IPS block while IDS does not?** IDS rules use `alert`; IPS rules
  use `drop` while Snort is inline on the virtual Ethernet path.
- **Does Snort validate real payments?** No. The fraud test is a controlled
  network signature. The real application must validate prices server-side.
