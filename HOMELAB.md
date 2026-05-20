# Homelab Architecture & Per-Host Notes

Reference doc for the LAN-resident pool infrastructure. Captures host-specific layouts, SSH/sudo conventions, and operational facts that aren't obvious from the code alone.

For chronological upgrade history see [CHANGELOG.md](CHANGELOG.md). For preprod migration history specifically see [preprod/install/homelab/preprod_migration_runbook.md](preprod/install/homelab/preprod_migration_runbook.md).

---

## Hosts

| Env | Host | Role | LAN IP | RAM | Layout |
|---|---|---|---|---|---|
| preprod | athena-preprod | BP | 192.168.10.53 | 8 GB | `/home/cardano`-rooted |
| preprod | hermes-preprod | Relay | 192.168.10.172 | (?) | `/home/cardano`-rooted |
| preview | apollo-preview | Hybrid BP+Relay | 192.168.10.190 | 10 GB | **`/data`-rooted** (separate SSD) |
| mainnet | TBD | TBD | TBD | TBD | not yet migrated to homelab |

## Filesystem layout convention

The spot scripts derive `ROOT_PATH` from their own location (4 dirname levels up from `scripts/`), so the *same* script works whichever root it's deployed under.

**athena, hermes (`/home/cardano` rooted):**
- Spot repo: `/home/cardano/spot/`
- Node data: `/home/cardano/node.bp/`, `/home/cardano/node.relay/`
- Pool topology: `/home/cardano/pool_topology`
- Cardano-node source (during build): `/home/cardano/cardano-node/`

**apollo (`/data` rooted):**
- Spot repo: `/data/spot/`
- Node data: `/data/node.bp/`, `/data/node.relay/`
- Pool topology: `/data/pool_topology`
- Cardano-node source (during build): `/data/cardano-node/`
- C lib source clones: `/data/download/`
- **Binaries: still `/home/cardano/.local/bin/`** (hardcoded `~` in scripts; small files, fine on `/`)
- **`~/.cabal` symlinked → `/data/.cabal`** (5+ GB off `/`)
- **`~/.ghcup` symlinked → `/data/.ghcup`** (3+ GB off `/`)
- Root partition (`/`) is only 40 GB; this matters for builds
- Systemd journal capped at 500M (`/etc/systemd/journald.conf` → `SystemMaxUse=500M`)

## SSH key conventions

Per-host keys, one per identity. No key reuse across machines (each VM has its own private key registered separately on GitHub / between hosts). Rationale: blast radius — if a single VM is compromised, revoking that key affects only one machine.

**Inter-host (BP ↔ relay):** default `~/.ssh/id_ed25519`, with `IdentitiesOnly=yes`, `StrictHostKeyChecking=accept-new`, `ConnectTimeout=5`. Pattern lifted from `preprod/install/homelab/init_part3.sh`.

**GitHub (spot repo on adacapital account):** each VM has its own `~/.ssh/github_adacapital` key, registered as `adacapital-<hostname>` on the adacapital GitHub account. SSH config uses host alias `github.com-adacapital` to disambiguate from any other github identities on the same machine:

```ssh-config
Host github.com-adacapital
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_adacapital
  IdentitiesOnly yes
```

Spot remote URL: `git@github.com-adacapital:adacapital/spot.git`.

## BP → relay sudo

For BP-driven automation (binary distribution via `update_node_binaries.sh`, DB seeding via `init_part3.sh`), the relay needs **passwordless sudo for `systemctl` operations on `run.relay`**. Configured per relay host at `/etc/sudoers.d/cardano-systemctl`:

```
cardano ALL=(root) NOPASSWD: /usr/bin/systemctl stop run.relay, /usr/bin/systemctl start run.relay, /usr/bin/systemctl restart run.relay, /usr/bin/systemctl status run.relay, /usr/bin/systemctl is-active run.relay
```

**Currently configured on:** hermes-preprod.
**Not needed on:** apollo-preview (hybrid host — no remote relay; both services run locally).

Without this, `sudo -n systemctl stop run.relay` fails silently in scripts, the relay keeps running the old binary, and downstream updates appear to succeed but don't actually take effect. See `preprod/install/homelab/preprod_migration_runbook.md` Step 7b.

## Networking

Per-env port allocation (avoids conflict on shared LAN, allows multi-env relay coexistence):

| Env | BP port | Relay port |
|---|---|---|
| Preprod | 3000 | 3001 |
| Preview | 3000 | 3002 |
| Mainnet | TBD | TBD |

Public DNS via Namecheap A records (auto-updated by `init_namecheap_ddns.sh`). UniFi Express handles gateway/firewall/NAT. Detailed networking and firewall setup in `preprod/install/homelab/preprod_migration_runbook.md` (Steps 1-7).

**Gotcha:** UniFi firewall rules are evaluated by *internal creation order ID*, NOT visual UI drag-order. See runbook Step 4.

## cncli

Only deployed on the **mainnet** BP, used for block schedule. Not in preprod or preview. All cross-env scripts must guard `cncli_sync` `systemctl` calls with a service-exists check (e.g. `systemctl cat cncli_sync.service &>/dev/null && ...`).

## VRF key permissions

cardano-node requires no "other" permissions on key files. Always `chmod 600`. If you see startup failures referencing VRF keys, check permissions first.
