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

## Mithril bootstrap

**When to use it**: any time a node has been offline across a hard fork (or for more than ~37 hours through any significant chain event), the on-restart resync may fail with `HistoricityError` — cardano-node refuses to rollback that far for safety. Symptom: forged blocks invisible on cexplorer despite local `TraceAdoptedBlock` events; BP and relay agree on a tip hash that doesn't appear on explorers. Don't fight it — Mithril-bootstrap and move on.

Mithril is IOG's stake-based threshold signature scheme that produces cryptographically-verified DB snapshots. The `mithril-client` CLI verifies the snapshot's Mithril certificate against on-chain stake, then extracts to your node's DB directory. With `--include-ancillary`, the snapshot also ships the precomputed ledger state, so cardano-node skips block replay from genesis on first start — making the total recovery time ~30 minutes instead of 4-8 hours.

**Per-network endpoints**:

| Env | AGGREGATOR_ENDPOINT | Verification keys |
|---|---|---|
| Preview | `https://aggregator.pre-release-preview.api.mithril.network/aggregator` | `…/configuration/pre-release-preview/{genesis,ancillary}.vkey` |
| Preprod | `https://aggregator.release-preprod.api.mithril.network/aggregator` | `…/configuration/release-preprod/{genesis,ancillary}.vkey` |
| Mainnet | `https://aggregator.release-mainnet.api.mithril.network/aggregator` | `…/configuration/release-mainnet/{genesis,ancillary}.vkey` |

Verification key base URL: `https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra`.

**Trust model**: the Mithril certificate (chain blocks) is verified via stake-based threshold signatures — no central trust. The ancillary files (ledger state) are signed by IOG keys, *not* the stake-based certificate. mithril-client prints a warning to that effect. Consistent with our existing trust of IOG-published genesis files and configs; documented at <https://mithril.network/doc/manual/getting-started/network-configurations>.

**Script reference**: a complete preview bootstrap procedure is checked in at [`preview/scripts/node_sync_from_mithril.sh`](preview/scripts/node_sync_from_mithril.sh). When generalizing to preprod or mainnet, swap the network name in all three endpoint URLs (search for `pre-release-preview`) and adjust paths (`/data/...` → `/home/cardano/...` for athena/hermes; mainnet host TBD).

**Important flags**:
- `--include-ancillary` is **mandatory** for fast boot. Without it the node replays from genesis (hours).
- `--download-dir <path>` should point at your node's directory (the script extracts a `db/` subdirectory there).
- Run with `sudo -E` so the AGGREGATOR_ENDPOINT, GENESIS_VERIFICATION_KEY, and ANCILLARY_VERIFICATION_KEY env vars are preserved.

**After bootstrap**: start the relay first (gives BP somewhere to peer to), let it briefly replay the snapshot (`Replayed block: ... 99.xx%` progressing), then start the BP. No `HistoricityError` should appear — that's the success indicator.

Full chronological account of the 2026-05-20 apollo recovery in [CHANGELOG.md](CHANGELOG.md) under "Apollo private fork recovery (Van Rossem aftermath)."
