#!/usr/bin/env bash
set -euo pipefail

# =========================
# KES Key Rotation — Airgap version (2-phase)
#
# Phase 1: Run on BP node (online)
#   - Generates new KES keypair
#   - Computes current KES period
#   - Saves state for airgap phase
#   - Tells user which files to move to airgap machine
#
# Phase 2: Run on airgap machine (offline)
#   - Signs operational certificate with cold keys
#   - Copies node.cert to USB key
#   - Generates apply_state.sh for the BP node
#
# Phase 3: On BP node, run apply_state.sh from USB
#   - Installs node.cert and restarts BP service
# =========================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="${SPOT_DIR}/scripts"

# shellcheck source=/dev/null
source "${NS_PATH}/utils.sh"

NOW="$(date +"%Y%m%d_%H%M%S")"
STATE_FILE="$HOME/spot.state"

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
  read -r -p "${msg} [y/N] " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# =========================
# Detect environment
# =========================
if [[ -n "${CARDANO_NODE_SOCKET_PATH:-}" ]] && [[ -S "${CARDANO_NODE_SOCKET_PATH}" ]]; then
  PHASE="bp"
elif ! ping -q -c 1 -W 1 google.com >/dev/null 2>&1; then
  PHASE="airgap"
else
  die "Cannot determine environment: no socket (not BP) but network is up (not airgap)."
fi

echo "=== ROTATE KES KEYS (airgap workflow) ==="
echo "PHASE: $PHASE"
echo

# =============================================================================
# PHASE 1 — BP node (online): generate KES keys, compute KES period, save state
# =============================================================================
if [[ "$PHASE" == "bp" ]]; then
  NODE_DIR="$(derive_node_path_from_socket)"
  ROOT_PATH="$(dirname "$NODE_DIR")"
  SOCKET_PATH="${CARDANO_NODE_SOCKET_PATH}"
  POOL_KEYS_DIR="${ROOT_PATH}/pool_keys"
  SGENESIS="${NODE_DIR}/config/sgenesis.json"

  KES_VKEY_FILE="${POOL_KEYS_DIR}/kes.vkey"
  KES_SKEY_FILE="${POOL_KEYS_DIR}/kes.skey"

  echo "NODE_DIR:      $NODE_DIR"
  echo "ROOT_PATH:     $ROOT_PATH"
  echo "POOL_KEYS_DIR: $POOL_KEYS_DIR"
  echo

  [[ -f "$SGENESIS" ]] || die "Missing: $SGENESIS"

  MAGIC="$(get_network_magic)"
  echo "NETWORK_MAGIC: $MAGIC"

  # Compute KES period
  SLOTS_PER_KES_PERIOD="$(jq -r '.slotsPerKESPeriod' "$SGENESIS")"
  CTIP="$(cli query tip --testnet-magic "$MAGIC" --socket-path "$SOCKET_PATH" | jq -r .slot)"
  KES_PERIOD=$((CTIP / SLOTS_PER_KES_PERIOD))

  echo "SLOTS_PER_KES_PERIOD: $SLOTS_PER_KES_PERIOD"
  echo "Current slot:         $CTIP"
  echo "KES_PERIOD:           $KES_PERIOD"
  echo

  confirm "Proceed to generate new KES keypair?" || die "Aborted"

  # Backup existing KES keys
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

  # Generate new KES keypair
  echo "Generating new KES key pair..."
  cli node key-gen-KES \
    --verification-key-file "$KES_VKEY_FILE" \
    --signing-key-file "$KES_SKEY_FILE"

  chmod 400 "$KES_SKEY_FILE"
  echo "  $KES_VKEY_FILE"
  echo "  $KES_SKEY_FILE"
  echo

  # Save state for airgap phase
  STATE_STEP_ID=4
  STATE_SUB_STEP_ID="rotate_kes_keys_opcert_gen"
  STATE_LAST_DATE="$NOW"
  save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE SLOTS_PER_KES_PERIOD CTIP KES_PERIOD

  echo "State saved to: $STATE_FILE"
  echo
  echo "============================================"
  echo "Phase 1 complete. Now move these files to"
  echo "your airgap machine's home directory:"
  echo "  1. $STATE_FILE"
  echo "  2. $KES_VKEY_FILE"
  echo "Then run this same script on the airgap machine."
  echo "============================================"

# =============================================================================
# PHASE 2 — Airgap machine: sign op cert with cold keys
# =============================================================================
elif [[ "$PHASE" == "airgap" ]]; then
  POOL_KEYS_DIR="$HOME/pool_keys"
  COLD_KEYS_DIR="$HOME/cold_keys"
  COLD_SKEY_FILE="${COLD_KEYS_DIR}/cold.skey"
  COLD_COUNTER_FILE="${COLD_KEYS_DIR}/cold.counter"
  KES_VKEY_FILE="${POOL_KEYS_DIR}/kes.vkey"
  NODE_CERT_FILE="${POOL_KEYS_DIR}/node.cert"

  echo "POOL_KEYS_DIR: $POOL_KEYS_DIR"
  echo "COLD_KEYS_DIR: $COLD_KEYS_DIR"
  echo

  # Load state from BP phase
  [[ -f "$STATE_FILE" ]] || die "State file not found: $STATE_FILE (did you copy it from the BP node?)"
  # shellcheck source=/dev/null
  . "$STATE_FILE" 2>/dev/null || die "Failed to source state file: $STATE_FILE"

  [[ "${STATE_SUB_STEP_ID:-}" == "rotate_kes_keys_opcert_gen" ]] || \
    die "Unexpected state: ${STATE_SUB_STEP_ID:-empty}. Expected: rotate_kes_keys_opcert_gen"

  echo "KES_PERIOD (from state): $KES_PERIOD"
  echo

  # Sanity checks
  [[ -f "$COLD_SKEY_FILE" ]]   || die "Missing: $COLD_SKEY_FILE"
  [[ -f "$COLD_COUNTER_FILE" ]] || die "Missing: $COLD_COUNTER_FILE"
  [[ -f "$KES_VKEY_FILE" ]]    || die "Missing: $KES_VKEY_FILE (did you copy it from the BP node?)"

  # Backup existing node.cert
  if [[ -f "$NODE_CERT_FILE" ]]; then
    echo "Backing up node.cert -> node.cert.${NOW}"
    chmod 644 "$NODE_CERT_FILE" || true
    mv "$NODE_CERT_FILE" "${NODE_CERT_FILE}.${NOW}"
    chmod 400 "${NODE_CERT_FILE}.${NOW}"
  fi

  confirm "Issue operational certificate with KES period $KES_PERIOD?" || die "Aborted"

  # Issue operational certificate
  echo "Issuing operational certificate..."
  cli node issue-op-cert \
    --kes-verification-key-file "$KES_VKEY_FILE" \
    --cold-signing-key-file "$COLD_SKEY_FILE" \
    --operational-certificate-issue-counter "$COLD_COUNTER_FILE" \
    --kes-period "$KES_PERIOD" \
    --out-file "$NODE_CERT_FILE"

  chmod 400 "$NODE_CERT_FILE"
  echo "  $NODE_CERT_FILE"
  echo

  # Update state
  STATE_SUB_STEP_ID="rotate_kes_keys_opcert_install"
  STATE_LAST_DATE="$NOW"
  save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE

  # Copy to USB key
  if [[ -z "${SPOT_USB_KEY:-}" ]]; then
    read -r -p "Enter path to USB key directory: " SPOT_USB_KEY
    # Persist for future use
    if ! grep -q 'SPOT_USB_KEY' ~/.bashrc 2>/dev/null; then
      echo "export SPOT_USB_KEY=\"$SPOT_USB_KEY\"" >> ~/.bashrc
    fi
  fi

  [[ -d "$SPOT_USB_KEY" ]] || die "USB key directory not found: $SPOT_USB_KEY"

  cp "$STATE_FILE" "$SPOT_USB_KEY/"
  cp "$NODE_CERT_FILE" "$SPOT_USB_KEY/"

  # Generate apply_state.sh for the BP node
  cat > "${SPOT_USB_KEY}/apply_state.sh" <<'APPLY_EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE_CERT_SRC="${SCRIPT_DIR}/node.cert"

# Derive pool_keys dir from CARDANO_NODE_SOCKET_PATH
if [[ -z "${CARDANO_NODE_SOCKET_PATH:-}" ]]; then
  echo "ERROR: CARDANO_NODE_SOCKET_PATH is not set" >&2
  exit 1
fi
SOCKET_PATH="$(realpath "$CARDANO_NODE_SOCKET_PATH")"
NODE_DIR="$(dirname "$(dirname "$SOCKET_PATH")")"
ROOT_PATH="$(dirname "$NODE_DIR")"
POOL_KEYS_DIR="${ROOT_PATH}/pool_keys"
NODE_CERT_DST="${POOL_KEYS_DIR}/node.cert"

[[ -f "$NODE_CERT_SRC" ]] || { echo "ERROR: node.cert not found next to this script" >&2; exit 1; }

echo "Installing node.cert..."
echo "  From: $NODE_CERT_SRC"
echo "  To:   $NODE_CERT_DST"

NOW="$(date +"%Y%m%d_%H%M%S")"
if [[ -f "$NODE_CERT_DST" ]]; then
  chmod 644 "$NODE_CERT_DST" || true
  mv "$NODE_CERT_DST" "${NODE_CERT_DST}.${NOW}"
  chmod 400 "${NODE_CERT_DST}.${NOW}"
fi

cp "$NODE_CERT_SRC" "$NODE_CERT_DST"
chmod 400 "$NODE_CERT_DST"

echo "Restarting BP service..."
sudo systemctl restart run.bp.service

echo
echo "Done. KES rotation complete."
echo "Verify with: sudo systemctl status run.bp.service"
APPLY_EOF

  chmod +x "${SPOT_USB_KEY}/apply_state.sh"

  echo "============================================"
  echo "Phase 2 complete. Files on USB key:"
  echo "  ${SPOT_USB_KEY}/node.cert"
  echo "  ${SPOT_USB_KEY}/apply_state.sh"
  echo "  ${SPOT_USB_KEY}/spot.state"
  echo
  echo "Now move the USB to the BP node and run:"
  echo "  bash /path/to/usb/apply_state.sh"
  echo "============================================"
fi
