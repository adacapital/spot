# SPOT — Stake Pool Operator Tools

**See also**: [CHANGELOG.md](CHANGELOG.md) (recent changes + upgrade history), [HOMELAB.md](HOMELAB.md) (per-host layouts, SSH/sudo conventions, networking), [TODO.md](TODO.md) (open items).

## Repo Structure
- `{root}/spot/{network}/scripts/` — per-network operational scripts (preview, preprod, mainnet)
- `{root}/spot/{network}/install/` — installation and init scripts
- `utils.sh` per network provides shared functions: `derive_node_path_from_socket()`, `get_network_magic()`, `get_topo()`

The `{root}` is `/home/cardano` on most hosts but `/data` on apollo-preview (separate SSD). Scripts derive `ROOT_PATH` from their own location, so they're portable across both layouts. See [HOMELAB.md](HOMELAB.md) for per-host details.

## Script Conventions
- Source `utils.sh` early and use `derive_node_path_from_socket()` for all path derivation — never hardcode ROOT_PATH or NODE_PATH
- Use `cardano-cli latest` via a `cli()` wrapper function for forward compatibility
- BP systemd service name: `run.bp.service` (no network suffix)
- `CARDANO_NODE_SOCKET_PATH` is set in `.bashrc` on all Cardano VMs — scripts must not export or set it
- Scripts should be identical across networks where possible; derive network name from repo structure: `NETWORK="$(basename "$SPOT_DIR")"`
- Use `set -euo pipefail`, proper quoting, and confirmation prompts with `--yes` flag support

## Key Utility Functions (utils.sh)
- `derive_node_path_from_socket()` — derives NODE_DIR from CARDANO_NODE_SOCKET_PATH (up 2 dirname levels from socket path)
- `get_network_magic()` — reads protocolMagic from `{node_path}/config/bgenesis.json`
- `get_topo()` — parses pool_topology, returns: ERROR NODE_TYPE BP_IP BP_PORT RELAY_IPS RELAY_NAMES RELAY_IPS_PUB RELAY_PORTS

**Note**: only preview's `utils.sh` currently emits all 8 fields above (with `BP_PORT`, `RELAY_PORTS`, and `NODE_TYPE=hybrid` support). preprod and mainnet's `utils.sh` are older 6-field versions without ports or hybrid. Bringing them in line is tracked in [TODO.md](TODO.md).

## pool_topology Format
```
# Lines: IP[:PORT] NAME [PUBLIC_DNS]
# BP line:    192.168.10.190:3000  bp
# Relay line: 192.168.10.190:3002  relay1  adact.preview.relay1.adacapital.io
# Port is optional — defaults to 3000 (bp) / 3001 (relay)
```

## Port Planning
| Environment | BP Port | Relay Port |
|-------------|---------|------------|
| Preview     | 3000    | 3002       |
| Preprod     | 3000    | 3001       |

## Infrastructure
- Preview: homelab (apollo-preview, hybrid BP+relay on 192.168.10.190)
- Preprod: homelab (athena-preprod BP on 192.168.10.53, hermes-preprod relay on 192.168.10.172) — migrated from OCI Feb 2026
- Mainnet: not yet migrated to homelab

Per-host details (RAM, filesystem layout, SSH/sudo specifics) in [HOMELAB.md](HOMELAB.md).

## Important Gotchas
- **VRF key permissions**: cardano-node requires no "other" permissions on key files (chmod 600)
- **cardano-node 10.x**: Requires `checkpoints.json` in config
- **cardano-node 11.x**: New runtime deps (libsnappy, liburing); peer-snapshot.json schema changed (`domain` → `address`); libsecp256k1 SONAME bumped (.so.0 → .so.2). Full details in [CHANGELOG.md](CHANGELOG.md).
- **UniFi firewall rule ordering**: Rules evaluated by internal ID (creation order), NOT visual drag-order in UI
- **cncli only runs on mainnet** (block schedule). Cross-env scripts must guard `systemctl stop/start cncli_sync` with a service-exists check.
