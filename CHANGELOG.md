# Changelog

Chronological record of significant changes to spot scripts and pool infrastructure. Newest entries on top.

For per-host architectural details see [HOMELAB.md](HOMELAB.md). For open items see [TODO.md](TODO.md).

---

## 2026-05-20 — cardano-node 11.0.1 upgrade

**Versions landed:** cardano-node 11.0.1, cardano-cli 11.0.0.0
**Hosts:** athena-preprod (BP), hermes-preprod (relay), apollo-preview (hybrid)
**Toolchain:** GHC 9.6.7 / cabal 3.12.1.0 (IOG-recommended)

### Breaking changes in cardano-node 11.x

| Surface | Old | New | Action |
|---|---|---|---|
| Runtime dep | — | `libsnappy.so.1` | apt: `libsnappy-dev` |
| Runtime dep | — | `liburing.so.2` | apt: `liburing-dev` |
| `peer-snapshot.json` schema | `domain` field | `address` field | Replace from IOG: `https://book.play.dev.cardano.org/environments/<env>/peer-snapshot.json` |
| `libsecp256k1` SONAME | `.so.0` (ac83be33 pin) | `.so.2` (v0.3.2 pin) | Remove stale `.so.0` + `ldconfig` before rebuild |
| `libblst` | v0.3.10 | v0.3.15 | Rebuild (static, but kept in sync) |

### Scripts modernized in this release

- `preprod/install/homelab/init_node_binaries.sh` — full IOG apt list; ghcup 9.6.7/3.12.1.0 with `--set`; **dynamic C lib version resolution** via iohk-nix cascade (replaces hardcoded commits); modernized blst .pc generation
- `preprod/scripts/update_node_binaries.sh` — cabal exit-code checks, per-build log capture, `CABAL_JOBS=2` default, binary-exists verification before "Build complete?" prompt; hardened BP→relay distribution (id_ed25519 + NOPASSWD sudoers + IdentitiesOnly + ConnectTimeout); `cncli_sync` guarded with service-exists check; defensive IOG apt list install
- `preview/scripts/update_node_binaries.sh` — same hardening as preprod; parses preview's `BP_PORT` field + 4 sub-arrays from `get_topo`; accepts `NODE_TYPE=hybrid` for single-host bp+relay
- `preview/scripts/bin_path.sh` — aligned to canonical 2-arg signature (`{binaryName} {cardanoNodePath}`); was outdated 1-arg form with hardcoded `$HOME/download/cardano-node`
- `preprod/install/homelab/preprod_migration_runbook.md` — Step 7b documenting NOPASSWD sudoers prerequisite for BP→relay automation; added Common Pitfalls entry for silent-sudo failure mode

### Per-host operations performed

- **Hermes**: `/etc/sudoers.d/cardano-systemctl` NOPASSWD entry for `systemctl {stop,start,…} run.relay`; full IOG apt list installed; C lib rebuild; new binaries scp'd from athena; peer-snapshot.json refreshed
- **Apollo**: ssh key per-machine setup for adacapital (`~/.ssh/github_adacapital`); `~/.cabal` and `~/.ghcup` symlinked to `/data/.cabal` and `/data/.ghcup` (root partition was 100% full mid-build); systemd journal capped at 500M permanently; full IOG apt list + C lib rebuild + peer-snapshot.json refresh

### Gotchas hit (and now codified)

1. Each cardano-node release tends to add 1-2 new system C library deps. Adding `apt-get install -y <full IOG list>` to the upgrade script catches these in one shot rather than iterating per missing dep.
2. SONAME bumps on rebuilt C libs (like `libsecp256k1` 0→2) require *removing* the stale file before relinking — otherwise the new binary captures the old SONAME from a still-present old symlink.
3. peer-snapshot.json is now mandatory in Genesis sync mode (replaces deprecated `bootstrapPeers`). IOG publishes per-env at `book.play.dev.cardano.org`.
4. The BP→relay distribution loop only ships binaries; if the relay's apt deps are stale, the new binary fails to load. Pre-flight `ldd` check on the build artifact would catch this — see [TODO.md](TODO.md).

### Apollo private fork recovery (Van Rossem aftermath)

**Symptom**: After the 11.0.1 upgrade, apollo's BP forged 3 blocks at scheduled slots — `TraceForgedBlock` + `TraceAdoptedBlock` both logged cleanly, no rollback events, BP and relay agreed on the same tip hash, syncProgress 100%. But none of those blocks appeared on cexplorer or cardanoscan — cexplorer showed the pool's "last forged block" as 13 days ago.

**Root cause**: The Van Rossem hard fork activated on preview on **May 8, 2026**, lifting the network to Protocol Version 11. Apollo was offline at that point (had been down for ~10 days). When we brought it back up post-upgrade on May 20, its DB held pre-fork chain state. The relay tried to sync canonical history from public peers, but each peer's rollback message referenced a block from ~12 days ago (~slot 111542393, the fork point), which is past cardano-node's default **historicity cutoff** (37 hours / 133200 seconds) — a deliberate Genesis-consensus safety mechanism that prevents very-old-history attacks. The relay rejected all reconciliation attempts with `HistoricityError`. It stuck at its May 10 tip. The BP then synced from the stuck relay, inherited the fork-point state, and started forging at scheduled slots — but only locally, on a chain only it and its relay believed in. Both progressing in lockstep on a private fork.

**Why "mirror good DB from relay" didn't work**: standard recovery technique for a BP on the wrong chain. But here the relay was on the *same* private fork (identical tip hash). No local source of canonical chain data.

**Why "wipe DB + resync from public peers" would have worked but is slow**: full resync from genesis takes 4-8 hours on apollo's hardware.

**Fix recipe (~30 min total)**: Bootstrap both BP and relay from a **Mithril** snapshot with `--include-ancillary` for fast boot. Mithril provides cryptographically-verified DB snapshots; the ancillary flag includes the precomputed ledger state so cardano-node skips block replay from genesis on first start.

```bash
# Install + configure (preview-specific endpoints)
export AGGREGATOR_ENDPOINT="https://aggregator.pre-release-preview.api.mithril.network/aggregator"
export GENESIS_VERIFICATION_KEY=$(curl -s https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/genesis.vkey)
export ANCILLARY_VERIFICATION_KEY=$(curl -s https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/pre-release-preview/ancillary.vkey)

# Stop, move bad DBs aside, download Mithril snapshot, mirror to BP, restart
# (full procedure scripted at preview/scripts/node_sync_from_mithril.sh)
```

Full script: [`preview/scripts/node_sync_from_mithril.sh`](preview/scripts/node_sync_from_mithril.sh). Mithril details and trust model in [HOMELAB.md](HOMELAB.md) under "Mithril bootstrap."

**Critical missing parameter the first attempt**: without `--include-ancillary`, mithril-client only ships the immutable chain blocks and the node has to replay from genesis to rebuild ledger state — defeating the speed purpose. The warning "*The fast bootstrap of the Cardano node is not available with the current parameters*" was the giveaway. Always include ancillary for cardano-node bootstrap.

**Lessons (now codified in this changelog + the script header)**:
- If a node was offline across a hard fork, **always Mithril-bootstrap on restart**. Don't try to resync the stale DB — the historicity cutoff makes it un-reconcilable.
- The "BP + relay agree on a tip hash" check is necessary but not sufficient for "you're on the canonical chain." Always also check: does that tip hash appear on cexplorer? If not, you're on a private fork even though everything looks healthy locally.
- The community confirmed this is a recurring class of issue on SPO Discord ("just stuck on the fork with relays that didn't accept the hardfork tx … fix is re-bootstrap from mithril"). Worth incorporating into any future hard-fork-coverage runbook.

**Mainnet implication**: same procedure applies — but use mainnet endpoints (`release-mainnet`) instead of `pre-release-preview`. See [HOMELAB.md](HOMELAB.md).

---

## 2026-02-20 — Preprod migration from OCI to homelab

athena-preprod (BP) and hermes-preprod (relay) moved from OCI to LAN-resident VMs. Full procedure: [preprod/install/homelab/preprod_migration_runbook.md](preprod/install/homelab/preprod_migration_runbook.md).

---

## 2026-01-20 — Initial homelab install scripts

First commit of `/preprod/install/homelab/` (init_part1, init_part2, init_part3, init_node_binaries, init_namecheap_ddns, init_ufw).
