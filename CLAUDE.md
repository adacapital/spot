# SPOT — Stake Pool Operator Tools

## Repo Structure
- `/data/spot/{network}/scripts/` — per-network operational scripts (preview, preprod, mainnet)
- `/data/spot/{network}/install/` — installation and init scripts
- `utils.sh` per network provides shared functions: `derive_node_path_from_socket()`, `get_network_magic()`, `get_topo()`

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
- Preprod: OCI (athena-preprod BP, hermes-preprod relay1)

## Important Gotchas
- **VRF key permissions**: cardano-node requires no "other" permissions on key files (chmod 600)
- **cardano-node 10.x**: Requires `checkpoints.json` in config
- **UniFi firewall rule ordering**: Rules evaluated by internal ID (creation order), NOT visual drag-order in UI
