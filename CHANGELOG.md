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

---

## 2026-02-20 — Preprod migration from OCI to homelab

athena-preprod (BP) and hermes-preprod (relay) moved from OCI to LAN-resident VMs. Full procedure: [preprod/install/homelab/preprod_migration_runbook.md](preprod/install/homelab/preprod_migration_runbook.md).

---

## 2026-01-20 — Initial homelab install scripts

First commit of `/preprod/install/homelab/` (init_part1, init_part2, init_part3, init_node_binaries, init_namecheap_ddns, init_ufw).
