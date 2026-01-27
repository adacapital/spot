#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# init_ufw.sh
# Configure UFW firewall for Cardano BP/Relay nodes (idempotent)
#
# Requires:
#   - pool_topology file (default: $HOME/pool_topology)
#   - utils.sh with get_topo() in $SPOT_DIR/scripts/utils.sh
#
# Behaviour:
#   - Detects NODE_TYPE based on local IP vs pool_topology
#   - Applies baseline UFW policy (optionally reset)
#   - BP:
#       * Allow 3000/tcp only from relay LAN IPs
#       * SSH default: allow from LAN only (or restricted via env)
#   - Relay:
#       * Allow 3001/tcp from anywhere
#       * SSH default: allow from anywhere (or restricted via env)
#
# How to run:
#   sudo bash ./init_ufw.sh --apply
#   sudo bash ./init_ufw.sh --dry-run
#
# Optional env overrides:
#   TOPO_FILE=/path/to/pool_topology
#   SPOT_DIR=/path/to/spot
#   RESET_UFW=1|0         (default 1)
#   SSH_PORT=22           (default 22)
#   BP_PORT=3000          (default 3000)
#   RELAY_PORT=3001       (default 3001)
#
#   Restrict SSH (recommended later):
#     ALLOW_SSH_FROM="1.2.3.4/32,5.6.7.0/24"
#   Or allow from LAN only:
#     ALLOW_SSH_FROM="192.168.10.0/24"
# ------------------------------------------------------------

MODE="${1:-}"
[[ "$MODE" == "--apply" || "$MODE" == "--dry-run" ]] || {
  echo "Usage: sudo bash $0 --apply | --dry-run"
  exit 1
}

DRY_RUN=0
[[ "$MODE" == "--dry-run" ]] && DRY_RUN=1

log() { echo -e "\n[$(date +"%F %T")] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

run() {
  if (( DRY_RUN == 1 )); then
    echo "DRYRUN> $*"
  else
    eval "$@"
  fi
}

REAL_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"
TOPO_FILE="${TOPO_FILE:-$REAL_HOME/pool_topology}"

RESET_UFW="${RESET_UFW:-1}"

SSH_PORT="${SSH_PORT:-22}"
BP_PORT="${BP_PORT:-3000}"
RELAY_PORT="${RELAY_PORT:-3001}"

# If set, restrict SSH to these CIDRs (comma-separated)
ALLOW_SSH_FROM="${ALLOW_SSH_FROM:-}"

# Try to infer SPOT_DIR if not provided (similar to your init scripts)
if [[ -z "${SPOT_DIR:-}" ]]; then
  SCRIPT_DIR="$(realpath "$(dirname "$0")")"
  PARENT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
  SPOT_DIR="$(realpath "$(dirname "$PARENT_DIR")")"
fi
UTILS="$SPOT_DIR/scripts/utils.sh"

[[ -f "$TOPO_FILE" ]] || die "Topology file not found: $TOPO_FILE"
[[ -f "$UTILS" ]] || die "utils.sh not found: $UTILS"

# shellcheck source=/dev/null
source "$UTILS"

log "Detecting node type from $TOPO_FILE ..."
read -r ERROR NODE_TYPE BP_IP RELAYS < <(get_topo "$TOPO_FILE")
# shellcheck disable=SC2206
RELAYS=($RELAYS)

[[ "$ERROR" == "none" ]] || die "$ERROR"
[[ "$NODE_TYPE" == "bp" || "$NODE_TYPE" == "relay" ]] || die "NODE_TYPE not detected correctly (got '$NODE_TYPE')"

# RELAYS comes as triples: relay_ip relay_name relay_pub
cnt=${#RELAYS[@]}
RELAY_IPS=()
RELAY_NAMES=()
RELAY_IPS_PUB=()

if (( cnt > 0 )); then
  (( cnt % 3 == 0 )) || die "RELAYS list length ($cnt) not divisible by 3"
  n=$((cnt/3))
  RELAY_IPS=( "${RELAYS[@]:0:$n}" )
  RELAY_NAMES=( "${RELAYS[@]:$n:$n}" )
  RELAY_IPS_PUB=( "${RELAYS[@]:$((2*n)):$n}" )
fi

LOCAL_IP="$(hostname -I | awk '{print $1}')"

log "NODE_TYPE:   $NODE_TYPE"
log "LOCAL_IP:    $LOCAL_IP"
log "BP_IP:       $BP_IP"
log "RELAY_IPS:   ${RELAY_IPS[*]:-none}"

log "Ensuring ufw is installed..."
run "apt-get update -y >/dev/null 2>&1 || true"
run "apt-get install -y ufw >/dev/null 2>&1 || true"

# Baseline
if [[ "$RESET_UFW" == "1" ]]; then
  log "Resetting UFW (RESET_UFW=1) ..."
  run "ufw --force reset"
fi

log "Applying baseline defaults..."
run "ufw default deny incoming"
run "ufw default allow outgoing"

# Keep local services sane
run "ufw allow in on lo"
run "ufw allow out on lo"

# Logging (low is usually plenty)
run "ufw logging low"

# SSH rules
apply_ssh_rules() {
  local label="$1"   # text label for logs
  if [[ -n "$ALLOW_SSH_FROM" ]]; then
    log "SSH: restricting to ALLOW_SSH_FROM=$ALLOW_SSH_FROM ($label)"
    IFS=',' read -r -a cidrs <<< "$ALLOW_SSH_FROM"
    for c in "${cidrs[@]}"; do
      c="$(echo "$c" | xargs)"
      [[ -n "$c" ]] || continue
      run "ufw allow from $c to any port $SSH_PORT proto tcp"
    done
  else
    log "SSH: allowing from ANYWHERE (temporary) ($label)"
    run "ufw allow $SSH_PORT/tcp"
  fi
}

# Cardano rules
if [[ "$NODE_TYPE" == "relay" ]]; then
  log "Configuring RELAY rules..."
  # Relay inbound from WAN on 3001
  run "ufw allow $RELAY_PORT/tcp"
  apply_ssh_rules "relay"
else
  log "Configuring BP rules..."
  # BP should NOT be exposed; only relays may connect to BP port
  for rip in "${RELAY_IPS[@]}"; do
    run "ufw allow from $rip to any port $BP_PORT proto tcp"
  done

  # SSH on BP: default safer to LAN only if ALLOW_SSH_FROM not set
  if [[ -z "$ALLOW_SSH_FROM" ]]; then
    log "SSH: BP default to LAN-only (192.168.10.0/24). Override via ALLOW_SSH_FROM if needed."
    run "ufw allow from 192.168.10.0/24 to any port $SSH_PORT proto tcp"
  else
    apply_ssh_rules "bp"
  fi
fi

log "Enabling UFW..."
run "ufw --force enable"

log "UFW status:"
run "ufw status verbose"

log "Done."
if (( DRY_RUN == 1 )); then
  echo "Dry-run complete. Re-run with: sudo bash $0 --apply"
fi
