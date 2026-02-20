#!/usr/bin/env bash
set -euo pipefail

# =========================
# Locate & source utils.sh early
# =========================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="${SPOT_DIR}/scripts"

# shellcheck source=/dev/null
source "${NS_PATH}/utils.sh"

# =========================
# Config — derive ROOT_PATH from CARDANO_NODE_SOCKET_PATH
# =========================
NODE_DIR="$(derive_node_path_from_socket)"
ROOT_PATH="$(dirname "$NODE_DIR")"
SOCKET_PATH="${CARDANO_NODE_SOCKET_PATH}"
TOPO_FILE="${ROOT_PATH}/pool_topology"

KEYS_DIR="${ROOT_PATH}/keys"
POOL_KEYS_DIR="${ROOT_PATH}/pool_keys"

PAYMENT_ADDR_FILE="${KEYS_DIR}/paymentwithstake.addr"
PAYMENT_SKEY_FILE="${KEYS_DIR}/payment.skey"
STAKE_SKEY_FILE="${KEYS_DIR}/stake.skey"
STAKE_VKEY_FILE="${KEYS_DIR}/stake.vkey"

COLD_SKEY_FILE="${POOL_KEYS_DIR}/cold.skey"
COLD_VKEY_FILE="${POOL_KEYS_DIR}/cold.vkey"
VRF_VKEY_FILE="${POOL_KEYS_DIR}/vrf.vkey"

POOL_REG_CERT="${POOL_KEYS_DIR}/pool-registration.cert"
DELEG_CERT="${POOL_KEYS_DIR}/delegation.cert"

# Pool metadata — derive network name from repo structure (e.g. /data/spot/preview/scripts -> preview)
NETWORK="$(basename "$SPOT_DIR")"
META_FILENAME_DEFAULT="adact_${NETWORK}.json"
META_URL_DEFAULT="https://adacapital.io/${META_FILENAME_DEFAULT}"

# =========================
# Helpers
# =========================
cli() {
  # Prefer new CLI grouping if present
  if cardano-cli latest --help >/dev/null 2>&1; then
    cardano-cli latest "$@"
  else
    cardano-cli "$@"
  fi
}

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  $0 [--magic <TESTNET_MAGIC>] [--yes] [--dry-run] [--margin 0.03] [--pledge <lovelace>] [--cost <lovelace>] [--meta-url <url>]

Examples:
  $0
  $0 --yes
  $0 --dry-run
  $0 --magic 1 --dry-run --yes
  $0 --pledge 1000000000000 --cost 340000000 --margin 0.1

Notes:
- Reads relays from: ${TOPO_FILE}
- Uses DNS relays via: --pool-relay-dns <dns> --pool-relay-port <port>
- Builds & signs tx via create_transaction_online.sh
- With --dry-run: does NOT submit the transaction
EOF
}

confirm() {
  local msg="$1"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then return 0; fi
  read -r -p "${msg} [y/N] " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# Parse pool_topology:
# - bp line:   <lan_ip[:port]> bp
# - relay line: <lan_ip[:port]> <relayName> <publicDNS>
read_topology() {
  [[ -f "$TOPO_FILE" ]] || die "Topology file not found: $TOPO_FILE"

  RELAY_DNS=()
  RELAY_PORTS=()
  BP_IP=""

  while IFS= read -r line; do
    line="${line%%#*}"                         # strip comments
    line="$(echo "$line" | awk '{$1=$1;print}')" # trim
    [[ -z "$line" ]] && continue

    read -r c1 c2 c3 _rest <<<"$line"

    # Parse IP:PORT from column 1
    local ip="${c1%%:*}"
    local port="${c1##*:}"
    [[ "$port" == "$ip" ]] && port=""  # no port specified

    if [[ "$c2" == "bp" ]]; then
      BP_IP="$ip"
      continue
    fi

    if [[ -n "${ip:-}" && -n "${c2:-}" && -n "${c3:-}" ]]; then
      RELAY_DNS+=("$c3")
      RELAY_PORTS+=("${port:-3001}")
      continue
    fi
  done <"$TOPO_FILE"

  [[ -n "$BP_IP" ]] || die "No BP line found in pool_topology (expected: '<ip> bp')"
  [[ "${#RELAY_DNS[@]}" -gt 0 ]] || die "No relay lines found in pool_topology (expected: '<ip> relayName publicDNS')"
}

# =========================
# Defaults
# =========================
ASSUME_YES=0
DRY_RUN=0

MAGIC_DEFAULT="$(get_network_magic)"
MAGIC="$MAGIC_DEFAULT"

POOL_MARGIN="0.03"
POOL_PLEDGE=""
POOL_COST=""
META_URL="$META_URL_DEFAULT"

# =========================
# Arg parsing
# =========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --magic) MAGIC="${2:-}"; shift 2;;
    --yes|-y) ASSUME_YES=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    --margin) POOL_MARGIN="${2:-}"; shift 2;;
    --pledge) POOL_PLEDGE="${2:-}"; shift 2;;
    --cost) POOL_COST="${2:-}"; shift 2;;
    --meta-url) META_URL="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown arg: $1 (use --help)";;
  esac
done

# =========================
# Main
# =========================
echo "=== UPDATE POOL REGISTRATION (ONLINE) ==="
echo "ROOT_PATH:     $ROOT_PATH"
echo "TOPO_FILE:     $TOPO_FILE"
echo "NODE_DIR:      $NODE_DIR"
echo "SOCKET_PATH:   $SOCKET_PATH"
echo "TESTNET_MAGIC: $MAGIC"
echo "DRY_RUN:       $DRY_RUN"
echo

# Sanity
[[ -S "$SOCKET_PATH" ]] || die "Socket not found: $SOCKET_PATH (is the BP node running?)"

[[ -f "$PAYMENT_ADDR_FILE" ]] || die "Missing: $PAYMENT_ADDR_FILE"
[[ -f "$PAYMENT_SKEY_FILE" ]] || die "Missing: $PAYMENT_SKEY_FILE"
[[ -f "$STAKE_SKEY_FILE" ]] || die "Missing: $STAKE_SKEY_FILE"
[[ -f "$STAKE_VKEY_FILE" ]] || die "Missing: $STAKE_VKEY_FILE"
[[ -f "$COLD_SKEY_FILE" ]] || die "Missing: $COLD_SKEY_FILE"
[[ -f "$COLD_VKEY_FILE" ]] || die "Missing: $COLD_VKEY_FILE"
[[ -f "$VRF_VKEY_FILE" ]] || die "Missing: $VRF_VKEY_FILE"

read_topology
echo "BP_IP:        $BP_IP"
echo "RELAY_DNS:    ${RELAY_DNS[*]}"
echo

# DNS resolve fail-fast
for dns in "${RELAY_DNS[@]}"; do
  getent ahosts "$dns" >/dev/null 2>&1 || die "Relay DNS does not resolve: $dns"
done
echo "DNS resolution: OK"
echo

# Download metadata and compute hash
cd "$POOL_KEYS_DIR"
NOW="$(date +"%Y%m%d_%H%M%S")"
META_FILENAME="${META_URL##*/}"
META_FILENAME="${META_FILENAME:-$META_FILENAME_DEFAULT}"

echo "Metadata URL:  $META_URL"
echo "Metadata file: $META_FILENAME"

if [[ -f "$META_FILENAME" ]]; then
  echo "Archiving existing metadata file -> ${META_FILENAME}.${NOW}"
  mv "$META_FILENAME" "${META_FILENAME}.${NOW}"
fi

wget -q "$META_URL" -O "$META_FILENAME" || die "Failed to download metadata from $META_URL"

META_HASH="$(cli stake-pool metadata-hash --pool-metadata-file "$META_FILENAME")"
echo "META_HASH:     $META_HASH"
echo

# minPoolCost default
MIN_POOL_COST=""
if [[ -f "${NODE_DIR}/config/sgenesis.json" ]]; then
  MIN_POOL_COST="$(jq -r '.protocolParams.minPoolCost // empty' "${NODE_DIR}/config/sgenesis.json" || true)"
fi

# Defaults
if [[ -z "$POOL_PLEDGE" ]]; then POOL_PLEDGE="1000000000"; fi
if [[ -z "$POOL_COST" ]]; then POOL_COST="${MIN_POOL_COST:-170000000}"; fi

echo "Will create registration certificate with:"
echo "  POOL_PLEDGE:  $POOL_PLEDGE"
echo "  POOL_COST:    $POOL_COST"
echo "  POOL_MARGIN:  $POOL_MARGIN"
echo "  META_URL:     $META_URL"
echo "  META_HASH:    $META_HASH"
echo "  RELAYS (DNS):"
for i in "${!RELAY_DNS[@]}"; do
  echo "    ${RELAY_DNS[$i]}:${RELAY_PORTS[$i]}"
done
echo

confirm "Proceed to create pool-registration.cert + delegation.cert?" || die "Aborted"

# Build relay params using DNS (cardano-cli latest syntax)
RELAY_PARAMS=()
for i in "${!RELAY_DNS[@]}"; do
  RELAY_PARAMS+=( --single-host-pool-relay "${RELAY_DNS[$i]}" --pool-relay-port "${RELAY_PORTS[$i]}" )
done

if [[ -f "$POOL_REG_CERT" ]]; then
  echo "Archiving existing pool-registration.cert -> ${POOL_REG_CERT}.${NOW}"
  mv "$POOL_REG_CERT" "${POOL_REG_CERT}.${NOW}"
fi
if [[ -f "$DELEG_CERT" ]]; then
  echo "Archiving existing delegation.cert -> ${DELEG_CERT}.${NOW}"
  mv "$DELEG_CERT" "${DELEG_CERT}.${NOW}"
fi

cli stake-pool registration-certificate \
  --cold-verification-key-file "$COLD_VKEY_FILE" \
  --vrf-verification-key-file "$VRF_VKEY_FILE" \
  --pool-pledge "$POOL_PLEDGE" \
  --pool-cost "$POOL_COST" \
  --pool-margin "$POOL_MARGIN" \
  --pool-reward-account-verification-key-file "$STAKE_VKEY_FILE" \
  --pool-owner-stake-verification-key-file "$STAKE_VKEY_FILE" \
  --testnet-magic "$MAGIC" \
  "${RELAY_PARAMS[@]}" \
  --metadata-url "$META_URL" \
  --metadata-hash "$META_HASH" \
  --out-file "$POOL_REG_CERT"

cli stake-address stake-delegation-certificate \
  --stake-verification-key-file "$STAKE_VKEY_FILE" \
  --cold-verification-key-file "$COLD_VKEY_FILE" \
  --out-file "$DELEG_CERT"

chmod 400 "$POOL_REG_CERT" "$DELEG_CERT" || true

echo
echo "Certificates created:"
echo "  $POOL_REG_CERT"
echo "  $DELEG_CERT"
echo

TX_SCRIPT="${SCRIPT_DIR}/create_transaction_online_v2.sh"
[[ -x "$TX_SCRIPT" ]] || die "Missing or not executable: $TX_SCRIPT"

SOURCE_ADDR="$(cat "$PAYMENT_ADDR_FILE")"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY-RUN enabled: will build+sign the transaction but NOT submit."
fi

confirm "Proceed to build/sign${DRY_RUN:+ (no submit)} the transaction?" || die "Aborted"

TX_ARGS=(
  register-pool
  --magic "$MAGIC"
  --socket "$SOCKET_PATH"
  --source-addr "$SOURCE_ADDR"
  --payment-skey "$PAYMENT_SKEY_FILE"
  --stake-skey "$STAKE_SKEY_FILE"
  --cold-skey "$COLD_SKEY_FILE"
  --pool-cert "$POOL_REG_CERT"
  --deleg-cert "$DELEG_CERT"
)

if [[ "$DRY_RUN" -eq 1 ]]; then
  TX_ARGS+=( --dry-run )
fi

"$TX_SCRIPT" "${TX_ARGS[@]}"

echo
echo "Done."
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry-run complete: transaction was NOT submitted."
  echo "Next: review the tx in the printed working directory, then re-run WITHOUT --dry-run to submit."
else
  echo "Next: query pool params and confirm relays are DNS-based."
fi
