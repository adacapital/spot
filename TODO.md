# TODO

Open items for the spot repo and homelab infrastructure. Add entries with a one-line description, optional rationale, and (if applicable) "Discovered: YYYY-MM-DD". Strike them through when done; clean up periodically.

## High-value script improvements

- **Pre-flight `ldd` check on relay before binary distribution.**
  *Discovered: 2026-05-20.* When `update_node_binaries.sh` ships a new cardano-node binary to a relay via scp, the relay may be missing newly-introduced system libs (e.g., `libsnappy.so.1` in 11.x). Today's behavior: scp succeeds, restart fails silently (or in restart loop), relay stays down. Improvement: before stopping the relay's service, ssh in and run `ldd /tmp/cardano-node-new | grep 'not found'`. Abort the relay loop with a clear "install X on relay first" message if anything's missing.

- **Run full IOG apt list on the relay too.**
  *Discovered: 2026-05-20.* `update_node_binaries.sh` currently runs `apt-get install -y <IOG list>` only on the BP. Relay is assumed to be in sync, which isn't true when IOG adds new deps. Either (a) push the apt install to the relay over ssh (needs broader NOPASSWD scope — security trade-off), or (b) document that the relay must have the apt list installed independently before any binary upgrade. (b) is simpler.

- **Consolidate preprod and preview `update_node_binaries.sh`.**
  They're now ~95% identical. Differences: preview parses `BP_PORT` + 4 sub-arrays from `get_topo` and accepts `NODE_TYPE=hybrid`; preprod doesn't (because preprod's `utils.sh` doesn't emit `BP_PORT`). Real fix: bring preprod's `utils.sh` up to match preview's (add `BP_PORT` + hybrid detection), then a single script works for both. Mainnet would inherit the same. See CLAUDE.md "Scripts should be identical across networks where possible."

- **Per-network utils.sh divergence.**
  preview's `utils.sh` has hybrid detection + BP_PORT/RELAY_PORTS fields. preprod and mainnet don't. Brought it back to one canonical version when consolidating the update scripts.

## Migration / setup pending

- **Mainnet not yet on homelab.**
  When migrating, follow `preprod/install/homelab/preprod_migration_runbook.md` adapted for mainnet (mainnet relay port TBD; check existing pool registration). Will need: new VM(s) (mainnet BP, mainnet relay), NOPASSWD sudoers on the relay(s), per-host SSH keys.

- **Athena: migrate spot remote from HTTPS+PAT to SSH.**
  *Discovered: 2026-05-20.* Apollo done, athena still uses classic PAT. Pattern: generate `~/.ssh/github_adacapital` on athena, register on adacapital account, add `github.com-adacapital` SSH config alias, `git remote set-url`. Same as apollo. Classic PATs are deprecated by GitHub.

- **Apollo: confirm `git pull` of bin_path.sh fix.**
  Commit `9dceb39` aligned preview's bin_path.sh to the canonical 2-arg signature. Apollo may not have pulled it yet — non-blocking for current state but worth syncing.

## Documentation gaps

- **Mainnet migration runbook.**
  When mainnet moves to homelab, draft `mainnet/install/homelab/mainnet_migration_runbook.md` based on the preprod template.

- **CHANGELOG entries for pre-2026-05-20 changes.**
  Only the most recent two events (preprod migration + 11.0.1 upgrade) are recorded. Earlier changes (initial homelab install, namecheap DDNS, UFW) are summarized in one line. Backfill if useful for future audits.

## Hygiene

- **Old GHC versions on athena/hermes (if any).**
  Check `~/.ghcup/ghc/` for non-9.6.7 directories. Each ~2 GB. Remove with `ghcup rm ghc <version>`.

- **Old C lib source clones in `/home/cardano/download/`** (athena/hermes' default location) — kept around since Jan install; not actively used (the rebuild creates fresh clones via `init_node_binaries.sh`'s logic). Optional cleanup.
