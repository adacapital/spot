# Preprod Relay Migration Runbook (OCI → Homelab)

## Executive Summary

This document captures the **manual and infrastructure steps** required to migrate the Preprod Cardano infrastructure from OCI to the homelab environment.

It complements the automated scripts and records:

* DNS configuration
* Router and UniFi networking setup
* Port forwarding and firewall rules
* Pool registration changes
* Validation steps

This document serves as a template for:

* Preview migration
* Mainnet migration
* Midnight infrastructure deployment

---

# High-Level Architecture

```
Internet
   ↓
Virgin Media Hub
   ↓
UniFi Express (Gateway / Firewall / NAT)
   ↓
LAN 192.168.10.0/24
   ↓
Relay VM (hermes-preprod)
   ↓
BP VM (athena-preprod)
```

---

# Step 1 — Static IP Assignment (Homelab)

Each VM must have a stable LAN IP.

Example:

| Host           | Role  | IP             |
| -------------- | ----- | -------------- |
| athena-preprod | BP    | 192.168.10.53  |
| hermes-preprod | Relay | 192.168.10.172 |

Configured either via:

* DHCP reservation (recommended)
* Static netplan config

---

# Step 2 — Public DNS Configuration (Namecheap)

Create an A record:

```
adact.preprod.relay1.adacapital.io → <home public IP>
```

Verification:

```
dig adact.preprod.relay1.adacapital.io
```

Expected:
Public WAN IP returned.

---

# Step 3a — Virgin Media Hub Port Forwarding

Virgin Media Hub Port Forwarding (Pre-Modem Mode Only)

During the migration of the preprod relay to the homelab, the network was operating in router mode on the Virgin Media Hub. This required a first layer of port forwarding from the public internet to the UniFi gateway.

Configuration

Virgin Media Hub (https://192.168.0.1/):

Setting	Value
External Port	3001
Protocol	TCP
Destination IP	192.168.0.80
Destination Port	3001
Purpose	Forward Cardano relay traffic to UniFi gateway

This forwarded inbound connections to the UniFi Express gateway WAN interface.

---

# Step 3b — Unifi Port Forwarding

Configured on UniFi gateway.

Example:

| Setting      | Value                    |
| ------------ | ------------------------ |
| Name         | adact.preprod.relay-3001 |
| Protocol     | TCP                      |
| WAN Port     | 3001                     |
| Forward IP   | 192.168.10.172           |
| Forward Port | 3001                     |

Purpose:
Allow inbound relay peers.

Verification from external host:

```
nc -vz adact.preprod.relay1.adacapital.io 3001
```

Expected:
Connection succeeded.

---

# Step 4 — UniFi Firewall Rules

Inbound rule required:

| Parameter   | Value          |
| ----------- | -------------- |
| Action      | Allow          |
| Protocol    | TCP            |
| Source      | External       |
| Destination | 192.168.10.172 |
| Port        | 3001           |

Purpose:
Permit inbound relay traffic from WAN.

Without this rule:
Port forwarding alone may not work.

**CRITICAL — Rule Ordering Gotcha:**

UniFi firewall rules are evaluated by **internal rule ID** (creation order), **NOT** by the
visual drag-order in the UI. If you create an ALLOW rule *after* a BLOCK rule, the ALLOW
rule gets a higher ID and is evaluated *after* the BLOCK rule — even if the UI shows it above.

To ensure a new ALLOW rule is evaluated before an existing BLOCK-all rule:

1. Delete the BLOCK-WAN-ALL-EXCEPT-EXPLICIT rule
2. Create the new ALLOW rule (it gets the next available ID)
3. Recreate the BLOCK rule (it now gets a higher ID than the ALLOW rule)

Alternatively, delete and recreate the BLOCK rule after adding any new ALLOW rules.
This forces the BLOCK rule to get a new, higher ID.

**Verification:** Check the firewall security logs for "Blocked by Firewall" entries
targeting your relay IP/port. If traffic is being blocked despite an ALLOW rule appearing
above the BLOCK rule in the UI, this ID ordering issue is the cause.

---

# Step 5 — NAT Configuration

Default UniFi masquerade rule is sufficient.

Example:

```
Source: Core Network
Interface: Internet1
Action: Masquerade
```

No custom NAT rules required for Cardano nodes.

---

# Step 6 — UniFi DNS Records

Local DNS is not used for relay discovery.

Relay DNS is public and hosted externally (Namecheap).

Example local DNS entry present:

```
hestia → 192.168.10.89
```

No local DNS entries required for relays.

---

# Step 7 — Relay Configuration

Relay topology must reference:

```
0.0.0.0
port 3001
```

Ensure relay listens on all interfaces:

Verification:

```
ss -tulnp | grep 3001
```

---

# Step 8 — Pool Registration Update

Pool registration updated to DNS relay.

Example relay entry:

```
--single-host-pool-relay adact.preprod.relay1.adacapital.io
--pool-relay-port 3001
```

Submitted via:

```
update_pool_registration_online_v2.sh
```

Verification:

```
pool_info_light.sh
```

Expected:

```
"dnsName": "adact.preprod.relay1.adacapital.io"
```

---

# Step 9 — BP Migration

Steps:

1. Stop OCI BP
2. Start homelab BP
3. Monitor forging

Verification:

```
journalctl -u run.bp | grep TraceForgedBlock
```

---

# Step 10 — Relay Health Verification

Monitor:

```
gLiveView
```

Expected:

* Peers > 10
* In/Out traffic stable
* At tip

---

# Step 11 — External Connectivity Test

From external VM:

```
nc -vz adact.preprod.relay1.adacapital.io 3001
```

Expected:
Connection succeeded.

---

# Step 12 — OCI Decommission

Steps:

1. Stop OCI BP
2. Stop OCI Relay
3. Confirm new relay stable
4. Terminate OCI instances
5. Delete boot volumes (if not auto-deleted)

---

# Operational Checklist

Before deleting OCI:

* BP forging successfully
* Relay has peers
* Pool registration updated
* DNS resolving correctly
* External connectivity verified

---

# Failure Recovery

If relay fails:

1. Restart relay
2. Verify port forwarding
3. Verify DNS resolution
4. Verify firewall rule
5. Temporarily start OCI relay

---

# Common Pitfalls

| Issue                          | Cause                   |
| ------------------------------ | ----------------------- |
| Relay has 0 peers              | Port forwarding missing |
| BP not forging                 | Relay unreachable       |
| DNS resolves but no connection | Firewall rule missing   |
| Firewall ALLOW rule ignored    | Rule ID higher than BLOCK rule (see Step 4 gotcha) |
| Transaction submission fails   | No usable UTXO          |

---

# Environment Port Planning

| Environment | Relay Port |
| ----------- | ---------- |
| Preprod     | 3001       |
| Preview     | 3002       |
| Mainnet     | 3001       |
| Midnight    | TBD        |

Avoid port conflicts.

---

# Network Dependency Model

Relay connectivity depends on:

1. DNS resolves to correct public IP
2. Virgin Hub forwards traffic (or modem mode active)
    - If Virgin Hub is in router mode: Step 3a must be true.
    - If Virgin Hub is in modem mode: Step 3a disappears.
3. UniFi port forwarding configured
4. UniFi firewall allows traffic
5. Relay listening on port

All five must be true.

---

# Planned Future Improvements

* Switch Virgin Hub to modem mode
* UniFi becomes sole router
* Multi-relay architecture
* Dedicated Midnight nodes
* NAS-backed storage

---

# Estimated Migration Time (Future Nodes)

| Step             | Time          |
| ---------------- | ------------- |
| VM deployment    | 30–60 min     |
| Sync time        | Several hours |
| Networking setup | 10–20 min     |
| Validation       | 10 min        |

Total operational time:
~1 hour active work.

---

# Appendix — Quick Verification Commands

Check peers:

```
gLiveView
```

Check relay port:

```
ss -tulnp | grep 3001
```

Check DNS:

```
dig adact.preprod.relay1.adacapital.io
```

Check external reachability:

```
nc -vz adact.preprod.relay1.adacapital.io 3001
```

---

# Final Notes

This runbook documents:

* Infrastructure steps
* Networking setup
* Pool registration workflow
* Validation procedures

It should be reused and adapted for:

* Preview migration
* Mainnet migration
* Midnight deployment
