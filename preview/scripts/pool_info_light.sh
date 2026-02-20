#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config — derive ROOT_PATH from CARDANO_NODE_SOCKET_PATH
# =========================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="${SPOT_DIR}/scripts"

# shellcheck source=/dev/null
source "${NS_PATH}/utils.sh"

NODE_DIR="$(derive_node_path_from_socket)"
ROOT_PATH="$(dirname "$NODE_DIR")"
SOCKET_PATH="${CARDANO_NODE_SOCKET_PATH}"
POOL_KEYS_DIR="${ROOT_PATH}/pool_keys"
COLD_VKEY_FILE="${POOL_KEYS_DIR}/cold.vkey"

# =========================
# Helpers
# =========================
cli() {
  if cardano-cli latest --help >/dev/null 2>&1; then
    cardano-cli latest "$@"
  else
    cardano-cli "$@"
  fi
}

die() { echo "ERROR: $*" >&2; exit 1; }

# =========================
# Main
# =========================
[[ -S "$SOCKET_PATH" ]] || die "Socket not found: $SOCKET_PATH (is the BP node running?)"
[[ -f "$COLD_VKEY_FILE" ]] || die "Missing: $COLD_VKEY_FILE"

MAGIC="$(get_network_magic)"
echo "NETWORK_MAGIC: $MAGIC"

# Derive pool IDs from cold verification key
POOL_ID_HEX="$(cli stake-pool id --cold-verification-key-file "$COLD_VKEY_FILE" --output-format hex)"
POOL_ID_BECH32="$(cli stake-pool id --cold-verification-key-file "$COLD_VKEY_FILE" --output-format bech32)"
echo "POOL_ID_HEX:   $POOL_ID_HEX"
echo "POOL_ID_BECH32: $POOL_ID_BECH32"
echo

# Query pool params
POOL_PARAMS="$(cli query pool-params \
  --testnet-magic "$MAGIC" \
  --socket-path "$SOCKET_PATH" \
  --stake-pool-id "$POOL_ID_HEX")"

# Query stake distribution and rank
STAKE_DIST="$(cli query stake-distribution \
  --testnet-magic "$MAGIC" \
  --socket-path "$SOCKET_PATH" \
  | sort -rgk2 | head -n -2 | nl | grep "$POOL_ID_BECH32" || true)"

if [[ -n "$STAKE_DIST" ]]; then
  STAKE_DIST_RANK="$(echo "$STAKE_DIST" | awk '{print $1}')"
  STAKE_DIST_FRACTION_DEC="$(echo "$STAKE_DIST" | awk '{print $3}' | awk -F"E" 'BEGIN{OFMT="%10.10f"} {print $1 * (10 ^ $2)}')"
  STAKE_DIST_FRACTION_PCT="$(echo "${STAKE_DIST_FRACTION_DEC}*100" | bc)"
else
  STAKE_DIST_RANK="N/A"
  STAKE_DIST_FRACTION_PCT="N/A"
fi

# Build pool info JSON
OUTPUT_FILE="${NODE_DIR}/pool_info.json"

jq -n \
  --arg pid_bech32 "$POOL_ID_BECH32" \
  --arg pid_hex "$POOL_ID_HEX" \
  --argjson params "$POOL_PARAMS" \
  --arg rank "$STAKE_DIST_RANK" \
  --arg stake_pct "$STAKE_DIST_FRACTION_PCT" \
  '{
    pool_id_bech32: $pid_bech32,
    pool_id_hex: $pid_hex,
    "pool-params": $params,
    stake_distribution_rank: $rank,
    stake_distribution_fraction_pct: $stake_pct
  }' > "$OUTPUT_FILE"

echo "$OUTPUT_FILE"
cat "$OUTPUT_FILE"
