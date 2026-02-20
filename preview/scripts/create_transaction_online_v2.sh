#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  $0 register-pool --magic <n> --socket <path> --source-addr <addr> \
     --payment-skey <file> --stake-skey <file> --cold-skey <file> \
     --pool-cert <file> --deleg-cert <file> [--dry-run] [--yes]

Notes:
- Builds, signs, and submits (unless --dry-run) a transaction containing:
  - pool-registration certificate
  - delegation certificate
- Uses modern: cardano-cli latest transaction build
- Consumes JSON output from: cardano-cli latest query utxo --out-file
EOF
}

confirm() {
  local msg="$1"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then return 0; fi
  read -r -p "${msg} [y/N] " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

require_file() { [[ -f "$1" ]] || die "Missing: $1"; }
require_socket() { [[ -S "$1" ]] || die "Socket not found: $1"; }

[[ $# -ge 1 ]] || { usage; exit 2; }
CMD="$1"; shift
[[ "$CMD" == "register-pool" ]] || { usage; exit 2; }

ASSUME_YES=0
DRY_RUN=0
MAGIC=""
SOCKET=""
SOURCE_ADDR=""
PAYMENT_SKEY=""
STAKE_SKEY=""
COLD_SKEY=""
POOL_CERT=""
DELEG_CERT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --magic) MAGIC="${2:-}"; shift 2;;
    --socket) SOCKET="${2:-}"; shift 2;;
    --source-addr) SOURCE_ADDR="${2:-}"; shift 2;;
    --payment-skey) PAYMENT_SKEY="${2:-}"; shift 2;;
    --stake-skey) STAKE_SKEY="${2:-}"; shift 2;;
    --cold-skey) COLD_SKEY="${2:-}"; shift 2;;
    --pool-cert) POOL_CERT="${2:-}"; shift 2;;
    --deleg-cert) DELEG_CERT="${2:-}"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --yes|-y) ASSUME_YES=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

[[ -n "$MAGIC" ]] || die "--magic is required"
[[ -n "$SOCKET" ]] || die "--socket is required"
[[ -n "$SOURCE_ADDR" ]] || die "--source-addr is required"
require_file "$PAYMENT_SKEY"
require_file "$STAKE_SKEY"
require_file "$COLD_SKEY"
require_file "$POOL_CERT"
require_file "$DELEG_CERT"
require_socket "$SOCKET"

echo "=== CREATE TX: register-pool ==="
echo "MAGIC:      $MAGIC"
echo "SOCKET:     $SOCKET"
echo "SOURCE:     $SOURCE_ADDR"
echo "POOL_CERT:  $POOL_CERT"
echo "DELEG_CERT: $DELEG_CERT"
echo "DRY_RUN:    $DRY_RUN"
echo

confirm "Proceed to build & sign the tx?" || die "Aborted"

NOW="$(date +"%Y%m%d_%H%M%S")"
WORK_BASE="/home/cardano/transactions"
WORK_DIR="${WORK_BASE}/${NOW}"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
echo "Working dir: $WORK_DIR"

# Tip / TTL (validity interval upper bound)
CTIP="$(cardano-cli latest query tip --testnet-magic "$MAGIC" --socket-path "$SOCKET" | jq -r .slot)"
TTL=$((CTIP + 1200))
echo "CTIP: $CTIP"
echo "TTL:  $TTL"
echo

# --- Query UTxOs as JSON and build tx-ins ---
UTXO_JSON="utxo.json"
cardano-cli latest query utxo \
  --address "$SOURCE_ADDR" \
  --testnet-magic "$MAGIC" \
  --socket-path "$SOCKET" \
  --out-file "$UTXO_JSON"

UTXO_COUNT="$(jq 'keys | length' "$UTXO_JSON")"
[[ "$UTXO_COUNT" -gt 0 ]] || die "No UTXOs found at source addr (cannot pay fees): $SOURCE_ADDR"

# Build --tx-in array from JSON keys "txhash#ix"
mapfile -t TX_IN_KEYS < <(jq -r 'keys[]' "$UTXO_JSON")
TX_IN=()
for k in "${TX_IN_KEYS[@]}"; do
  TX_IN+=( --tx-in "$k" )
done

# Optional: show total lovelace (informational only)
TOTAL_LOVELACE="$(jq '[.[] | .value.lovelace // 0] | add' "$UTXO_JSON")"
echo "UTXO count:          $UTXO_COUNT"
echo "UTXO total lovelace: $TOTAL_LOVELACE"
echo "TX inputs:           ${#TX_IN_KEYS[@]}"
echo

# --- Build transaction body (modern build: fee + change computed automatically) ---
# witness override: payment + stake + cold = 3
#
# NOTE: We explicitly include all tx-ins from SOURCE_ADDR, which is simple and robust.
# If later you want smarter coin selection, we can add a UTxO selection policy.
cardano-cli latest transaction build \
  --testnet-magic "$MAGIC" \
  --socket-path "$SOCKET" \
  "${TX_IN[@]}" \
  --change-address "$SOURCE_ADDR" \
  --invalid-hereafter "$TTL" \
  --certificate-file "$POOL_CERT" \
  --certificate-file "$DELEG_CERT" \
  --witness-override 3 \
  --out-file tx.body

echo "Built tx body: $WORK_DIR/tx.body"

# --- Sign (3 witnesses) ---
cardano-cli latest transaction sign \
  --tx-body-file tx.body \
  --signing-key-file "$PAYMENT_SKEY" \
  --signing-key-file "$STAKE_SKEY" \
  --signing-key-file "$COLD_SKEY" \
  --testnet-magic "$MAGIC" \
  --out-file tx.signed

echo "Signed tx: $WORK_DIR/tx.signed"

# --- Dry-run support ---
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "DRY-RUN: NOT submitting transaction."
  echo "To submit manually:"
  echo "  cardano-cli latest transaction submit --testnet-magic $MAGIC --socket-path $SOCKET --tx-file $WORK_DIR/tx.signed"
  echo
  echo "To compute txid:"
  echo "  cardano-cli latest transaction txid --tx-file $WORK_DIR/tx.signed"
  exit 0
fi

confirm "Submit transaction now?" || die "Aborted before submit"

cardano-cli latest transaction submit \
  --testnet-magic "$MAGIC" \
  --socket-path "$SOCKET" \
  --tx-file tx.signed

TXID="$(cardano-cli latest transaction txid --tx-file tx.signed)"
echo "Submitted TXID: $TXID"
echo "Working dir: $WORK_DIR"
