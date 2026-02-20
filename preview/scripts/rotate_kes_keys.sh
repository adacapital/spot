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
# Config — derive paths from CARDANO_NODE_SOCKET_PATH
# =========================
NODE_DIR="$(derive_node_path_from_socket)"
ROOT_PATH="$(dirname "$NODE_DIR")"
SOCKET_PATH="${CARDANO_NODE_SOCKET_PATH}"

POOL_KEYS_DIR="${ROOT_PATH}/pool_keys"
COLD_SKEY_FILE="${POOL_KEYS_DIR}/cold.skey"
COLD_COUNTER_FILE="${POOL_KEYS_DIR}/cold.counter"
KES_VKEY_FILE="${POOL_KEYS_DIR}/kes.vkey"
KES_SKEY_FILE="${POOL_KEYS_DIR}/kes.skey"
NODE_CERT_FILE="${POOL_KEYS_DIR}/node.cert"

SGENESIS="${NODE_DIR}/config/sgenesis.json"

BP_SERVICE="run.bp.service"

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

confirm() {
  local msg="$1"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then return 0; fi
  read -r -p "${msg} [y/N] " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# =========================
# Arg parsing
# =========================
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift;;
    -h|--help)
      echo "Usage: $0 [--yes]"
      echo "Rotates KES keys, issues new operational certificate, and restarts the BP service."
      exit 0;;
    *) die "Unknown arg: $1 (use --help)";;
  esac
done

# =========================
# Sanity checks
# =========================
echo "=== ROTATE KES KEYS ==="
echo "NODE_DIR:      $NODE_DIR"
echo "ROOT_PATH:     $ROOT_PATH"
echo "POOL_KEYS_DIR: $POOL_KEYS_DIR"
echo "BP_SERVICE:    $BP_SERVICE"
echo

[[ -S "$SOCKET_PATH" ]]    || die "Socket not found: $SOCKET_PATH (is the BP node running?)"
[[ -f "$COLD_SKEY_FILE" ]] || die "Missing: $COLD_SKEY_FILE"
[[ -f "$COLD_COUNTER_FILE" ]] || die "Missing: $COLD_COUNTER_FILE"
[[ -f "$SGENESIS" ]]       || die "Missing: $SGENESIS"

MAGIC="$(get_network_magic)"
echo "NETWORK_MAGIC: $MAGIC"

# =========================
# Compute current KES period
# =========================
SLOTS_PER_KES_PERIOD="$(jq -r '.slotsPerKESPeriod' "$SGENESIS")"
CTIP="$(cli query tip --testnet-magic "$MAGIC" --socket-path "$SOCKET_PATH" | jq -r .slot)"
KES_PERIOD=$((CTIP / SLOTS_PER_KES_PERIOD))

echo "SLOTS_PER_KES_PERIOD: $SLOTS_PER_KES_PERIOD"
echo "Current slot:         $CTIP"
echo "KES_PERIOD:           $KES_PERIOD"
echo

confirm "Proceed to rotate KES keys and issue new operational certificate?" || die "Aborted"

# =========================
# Backup existing keys
# =========================
NOW="$(date +"%Y%m%d_%H%M%S")"

if [[ -f "$KES_SKEY_FILE" ]]; then
  echo "Backing up kes.skey -> kes.skey.${NOW}"
  chmod 644 "$KES_SKEY_FILE" || true
  mv "$KES_SKEY_FILE" "${KES_SKEY_FILE}.${NOW}"
  chmod 400 "${KES_SKEY_FILE}.${NOW}"
fi

if [[ -f "$KES_VKEY_FILE" ]]; then
  echo "Backing up kes.vkey -> kes.vkey.${NOW}"
  chmod 644 "$KES_VKEY_FILE" || true
  mv "$KES_VKEY_FILE" "${KES_VKEY_FILE}.${NOW}"
  chmod 400 "${KES_VKEY_FILE}.${NOW}"
fi

if [[ -f "$NODE_CERT_FILE" ]]; then
  echo "Backing up node.cert -> node.cert.${NOW}"
  chmod 644 "$NODE_CERT_FILE" || true
  mv "$NODE_CERT_FILE" "${NODE_CERT_FILE}.${NOW}"
  chmod 400 "${NODE_CERT_FILE}.${NOW}"
fi
echo

# =========================
# Generate new KES key pair
# =========================
echo "Generating new KES key pair..."
cli node key-gen-KES \
  --verification-key-file "$KES_VKEY_FILE" \
  --signing-key-file "$KES_SKEY_FILE"

chmod 400 "$KES_SKEY_FILE"
echo "  $KES_VKEY_FILE"
echo "  $KES_SKEY_FILE"
echo

# =========================
# Issue new operational certificate
# =========================
echo "Issuing new operational certificate (KES period: $KES_PERIOD)..."
cli node issue-op-cert \
  --kes-verification-key-file "$KES_VKEY_FILE" \
  --cold-signing-key-file "$COLD_SKEY_FILE" \
  --operational-certificate-issue-counter "$COLD_COUNTER_FILE" \
  --kes-period "$KES_PERIOD" \
  --out-file "$NODE_CERT_FILE"

chmod 400 "$NODE_CERT_FILE"
echo "  $NODE_CERT_FILE"
echo

# =========================
# Restart BP service
# =========================
confirm "Restart ${BP_SERVICE} now?" || die "Aborted before restart"

echo "Restarting ${BP_SERVICE}..."
sudo systemctl restart "$BP_SERVICE"

echo
echo "Done. KES keys rotated and BP service restarted."
echo "Verify with: sudo systemctl status $BP_SERVICE"
