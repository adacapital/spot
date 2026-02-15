#!/bin/bash
set -euo pipefail

NOW="$(date +"%Y%m%d_%H%M%S")"
TOPO_FILE="${TOPO_FILE:-$HOME/pool_topology}"

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PARENT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
SPOT_DIR="$(realpath "$(dirname "$PARENT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"

echo "INIT_PART3 STARTING..."
echo "SCRIPT_DIR:  $SCRIPT_DIR"
echo "SPOT_DIR:    $SPOT_DIR"
echo "NS_PATH:     $NS_PATH"

# shellcheck source=/dev/null
source "$NS_PATH/utils.sh"

echo
echo '---------------- Reading pool topology file... ----------------'

read -r ERROR NODE_TYPE BP_IP RELAYS < <(get_topo "$TOPO_FILE")
# shellcheck disable=SC2206
RELAYS=($RELAYS)

if [[ "$ERROR" != "none" ]]; then
  echo "ERROR: $ERROR"
  exit 1
fi
if [[ -z "${NODE_TYPE:-}" ]]; then
  echo "Node type not identified (NODE_TYPE empty). Fix pool_topology/get_topo and retry."
  exit 1
fi

cnt=${#RELAYS[@]}
if (( cnt == 0 )); then
  echo "No relays listed in pool_topology. Nothing to distribute."
  exit 0
fi
if (( cnt % 3 != 0 )); then
  echo "ERROR: RELAYS list length ($cnt) not divisible by 3. pool_topology/get_topo mismatch."
  exit 1
fi

n=$((cnt/3))
RELAY_IPS=( "${RELAYS[@]:0:$n}" )
RELAY_NAMES=( "${RELAYS[@]:$n:$n}" )
RELAY_IPS_PUB=( "${RELAYS[@]:$((2*n)):$n}" )

echo "NODE_TYPE:     $NODE_TYPE"
echo "BP_IP:         $BP_IP"
echo "RELAY_IPS:     ${RELAY_IPS[*]}"
echo "RELAY_NAMES:   ${RELAY_NAMES[*]}"
echo "RELAY_IPS_PUB: ${RELAY_IPS_PUB[*]}"

# -------------------- configuration --------------------
BP_NODE_DIR="$HOME/node.bp"
RELAY_NODE_DIR="$HOME/node.relay"

BP_SERVICE="run.bp"
RELAY_SERVICE="run.relay"

# binaries to distribute (explicit)
NODE_BIN_SRC="$HOME/.local/bin/cardano-node"
CLI_BIN_SRC="$HOME/.local/bin/cardano-cli"

# tarball names
DB_TAR_NAME="bp.db.${NOW}.tar.gz"

# Use the VM's local SSH identity (default: id_ed25519)
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

# ssh/scp options
# - IdentitiesOnly=yes avoids trying other keys/agent and hitting "too many auth failures"
# - StrictHostKeyChecking=accept-new is convenient for homelab automation
SSH_OPTS="-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
SCP_OPTS="-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

# -------------------- helpers --------------------
die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo -e "\n[$(date +"%F %T")] $*"; }

require_file() { [[ -f "$1" ]] || die "Missing file: $1"; }
require_dir() { [[ -d "$1" ]] || die "Missing directory: $1"; }

remote() {
  local ip="$1" cmd="$2"
  ssh $SSH_OPTS -i "$SSH_KEY" "cardano@${ip}" "$cmd"
}

remote_scp_to() {
  local ip="$1" src="$2" dst="$3"
  scp $SCP_OPTS -i "$SSH_KEY" "$src" "cardano@${ip}:${dst}"
}

# -------------------- main logic --------------------
if [[ "$NODE_TYPE" != "bp" && "$NODE_TYPE" != "hybrid" ]]; then
  echo
  echo "This host is not BP (NODE_TYPE=$NODE_TYPE)."
  echo "init_part3.sh is designed to be run on the BP to distribute binaries and DB to relays."
  echo "Nothing to do here."
  exit 0
fi

log "Validating BP prerequisites..."
require_file "$TOPO_FILE"
require_file "$NODE_BIN_SRC"
require_file "$CLI_BIN_SRC"

# SSH key is only needed if there are remote relays
LOCAL_IP="$(hostname -I | awk '{print $1}')"
HAS_REMOTE_RELAY=0
for rip in "${RELAY_IPS[@]}"; do
  [[ "$rip" != "$LOCAL_IP" ]] && HAS_REMOTE_RELAY=1
done
if (( HAS_REMOTE_RELAY == 1 )); then
  require_file "$SSH_KEY"
fi

require_dir  "$BP_NODE_DIR/db"

log "Stopping BP node to take a clean DB snapshot..."
# Stop if running; don't fail if already stopped
sudo -n systemctl stop "$BP_SERVICE" || true

# Give it a moment to flush (journal/systemd stop should SIGTERM cleanly)
sleep 3

log "Creating tarball of BP db (relative paths)..."
# Create tar in BP home dir (node.bp)
# This results in an archive containing "db/..."
tar -C "$BP_NODE_DIR" -czf "$BP_NODE_DIR/$DB_TAR_NAME" db

log "DB tarball created: $BP_NODE_DIR/$DB_TAR_NAME"
ls -lh "$BP_NODE_DIR/$DB_TAR_NAME" || true

# DB_TAR_NAME="bp.db.20260122_122158.tar.gz"

log "Distributing files to relays..."
RELAYS_COUNT=${#RELAY_IPS[@]}

for (( i=0; i<RELAYS_COUNT; i++ )); do
  ip="${RELAY_IPS[$i]}"
  name="${RELAY_NAMES[$i]}"

  echo
  if [[ "$ip" == "$LOCAL_IP" ]]; then
    # ----- HYBRID: local relay (same VM as BP) -----
    log "Relay $name ($ip): LOCAL (hybrid) -- no SSH needed."

    log "Relay $name: ensuring directories exist..."
    mkdir -p "$HOME/.local/bin" "$RELAY_NODE_DIR" "$RELAY_NODE_DIR/db"

    # Binaries are already in ~/.local/bin (same machine as BP); no copy needed.
    log "Relay $name: binaries already available locally."

    log "Relay $name: stopping relay service before DB replace..."
    sudo -n systemctl stop "$RELAY_SERVICE" || true
    sleep 1

    log "Relay $name: wiping old relay db directory..."
    rm -rf "$RELAY_NODE_DIR/db"
    mkdir -p "$RELAY_NODE_DIR/db"

    log "Relay $name: extracting DB into $RELAY_NODE_DIR ..."
    tar -C "$RELAY_NODE_DIR" -xzf "$BP_NODE_DIR/$DB_TAR_NAME"

    log "Relay $name: DB seeded locally."
  else
    # ----- REMOTE relay (existing SSH-based logic) -----
    log "Relay $name ($ip): checking SSH connectivity..."

    # quick connectivity check
    if ! remote "$ip" "echo ok >/dev/null"; then
      log "Relay $name ($ip): unreachable via SSH (with $SSH_KEY), skipping."
      continue
    fi

    log "Relay $name ($ip): ensuring directories exist..."
    remote "$ip" "mkdir -p ~/.local/bin $RELAY_NODE_DIR && mkdir -p $RELAY_NODE_DIR/db"

    log "Relay $name ($ip): copying pool_topology..."
    remote_scp_to "$ip" "$TOPO_FILE" "/home/cardano/pool_topology"

    log "Relay $name ($ip): copying cardano binaries..."
    remote_scp_to "$ip" "$NODE_BIN_SRC" "/home/cardano/.local/bin/cardano-node"
    remote_scp_to "$ip" "$CLI_BIN_SRC"  "/home/cardano/.local/bin/cardano-cli"
    remote "$ip" "chmod 755 ~/.local/bin/cardano-node ~/.local/bin/cardano-cli && ~/.local/bin/cardano-node --version && ~/.local/bin/cardano-cli --version"

    log "Relay $name ($ip): stopping relay service before DB replace (if exists)..."
    remote "$ip" "sudo -n systemctl stop $RELAY_SERVICE || true"
    sleep 1

    log "Relay $name ($ip): wiping old relay db directory..."
    remote "$ip" "rm -rf $RELAY_NODE_DIR/db && mkdir -p $RELAY_NODE_DIR/db"

    log "Relay $name ($ip): copying BP DB tarball..."
    remote_scp_to "$ip" "$BP_NODE_DIR/$DB_TAR_NAME" "$RELAY_NODE_DIR/$DB_TAR_NAME"

    log "Relay $name ($ip): extracting DB into $RELAY_NODE_DIR ..."
    remote "$ip" "tar -C $RELAY_NODE_DIR -xzf $RELAY_NODE_DIR/$DB_TAR_NAME && rm -f $RELAY_NODE_DIR/$DB_TAR_NAME"

    log "Relay $name ($ip): DB seeded."
  fi
done

log "Starting BP node again..."
sudo -n systemctl start "$BP_SERVICE" || true

if [[ "$NODE_TYPE" == "hybrid" ]]; then
  log "Starting local relay node..."
  sudo -n systemctl start "$RELAY_SERVICE" || true
fi

echo
echo "INIT_PART3 COMPLETED."
echo
echo "Next:"
if [[ "$NODE_TYPE" == "hybrid" ]]; then
  echo "  Hybrid setup: both BP and relay are local."
  echo "  BP service:    sudo systemctl status run.bp"
  echo "  Relay service: sudo systemctl status run.relay"
else
  echo "  - On each relay, run:  ~/spot/preview/install/homelab/init_part2.sh   (no flags)"
  echo "    to install systemd unit + gLiveView now that binaries exist."
  echo "  - Then start relays:   sudo systemctl start run.relay"
fi
echo "  - Validate relays follow tip; then proceed to Part 4 hardening."
