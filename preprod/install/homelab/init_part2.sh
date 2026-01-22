#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# init_part2.sh
# Runtime configuration for Cardano preprod nodes (BP or Relay)
#
# What this script DOES:
# - Reads pool_topology to determine NODE_TYPE (bp|relay), BP_IP, relay list
# - Creates node directory structure under ~/node.bp or ~/node.relay
# - Downloads preprod config + genesis + default topology
# - Builds a node-appropriate topology.json
# - Applies minimal, safe config tweaks (genesis filenames + EKG ports per node type)
# - Writes run scripts (relay-like and bp-producing placeholder)
# - Installs systemd service for the node (enabled)
# - Installs/patches gLiveView
# - Sets SPOT_PATH and CARDANO_NODE_SOCKET_PATH via an idempotent .bashrc block
#
# What this script DOES NOT do (moved to init_part3.sh):
# - Copy binaries to relays
# - Copy/sync chain DB between nodes
# ------------------------------------------------------------

NOW="$(date +"%Y%m%d_%H%M%S")"
TOPO_FILE="${TOPO_FILE:-$HOME/pool_topology}"

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PARENT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
SPOT_DIR="$(realpath "$(dirname "$PARENT_DIR")")"
CONFIG_DIR="$SPOT_DIR/install/config"
NS_PATH="$SPOT_DIR/scripts"

ENV_NAME="${ENV_NAME:-preprod}"
# Your port convention:
BP_PORT="${BP_PORT:-3000}"
RELAY_PORT="${RELAY_PORT:-3001}"

# Preprod upstream URLs (Cardano developer portal / book)
BASE_URL="https://book.world.dev.cardano.org/environments/${ENV_NAME}"

ONLY_TOPOLOGY=0
for arg in "$@"; do
  case "$arg" in
    --topology-only) ONLY_TOPOLOGY=1 ;;
  esac
done


# ------------------------------------------------------------
# helpers
# ------------------------------------------------------------
die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo -e "\n[$(date +"%F %T")] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

apt_install_if_missing() {
  local pkgs=("$@")
  local missing=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if (( ${#missing[@]} > 0 )); then
    log "Installing packages: ${missing[*]}"
    sudo apt-get update -y
    sudo apt-get install -y "${missing[@]}"
  fi
}

fetch() {
  local url="$1"
  local out="$2"
  # curl is more predictable than wget for failures; follow redirects
  curl -fLsS "$url" -o "$out"
}

ensure_dir_layout() {
  local node_dir="$1"
  mkdir -p "$HOME/$node_dir"/{config,socket,logs,db}
}

ensure_bashrc_block() {
  local node_dir="$1"
  local marker_start="# >>> SPOT ENV >>>"
  local marker_end="# <<< SPOT ENV <<<"
  local tmp
  tmp="$(mktemp)"

  # Remove old block if present (idempotent)
  if [[ -f "$HOME/.bashrc" ]]; then
    awk -v s="$marker_start" -v e="$marker_end" '
      $0==s {inblock=1; next}
      $0==e {inblock=0; next}
      !inblock {print}
    ' "$HOME/.bashrc" > "$tmp"
  else
    : > "$tmp"
  fi

  cat >> "$tmp" <<EOF
$marker_start
export SPOT_PATH="$SPOT_DIR"
export CARDANO_NODE_SOCKET_PATH="\$HOME/$node_dir/socket/node.socket"
$marker_end
EOF

  mv "$tmp" "$HOME/.bashrc"

  # Export for current script execution too
  export SPOT_PATH="$SPOT_DIR"
  export CARDANO_NODE_SOCKET_PATH="$HOME/$node_dir/socket/node.socket"
}

discover_binaries() {
  # Prefer user's PATH; fallback to common locations if needed
  local node_bin
  local cli_bin
  node_bin="$(command -v cardano-node || true)"
  cli_bin="$(command -v cardano-cli || true)"

  if [[ -z "$node_bin" || -z "$cli_bin" ]]; then
    # common homelab install locations
    [[ -x "$HOME/.local/bin/cardano-node" ]] && node_bin="$HOME/.local/bin/cardano-node"
    [[ -x "$HOME/.local/bin/cardano-cli"  ]] && cli_bin="$HOME/.local/bin/cardano-cli"
  fi

  [[ -n "$node_bin" && -x "$node_bin" ]] || die "cardano-node not found in PATH or ~/.local/bin"
  [[ -n "$cli_bin"  && -x "$cli_bin"  ]] || die "cardano-cli not found in PATH or ~/.local/bin"

  echo "$node_bin" "$cli_bin"
}

patch_config_minimal() {
  local node_dir="$1"      # node.bp or node.relay
  local node_type="$2"     # bp or relay
  local cfg="$HOME/$node_dir/config/config.json"

  # ---- 1) Ensure genesis filenames match our downloaded local names ----
  sed -i \
    -e 's/"ByronGenesisFile"[[:space:]]*:[[:space:]]*"[^"]*byron-genesis[^"]*"/"ByronGenesisFile": "bgenesis.json"/' \
    -e 's/"ShelleyGenesisFile"[[:space:]]*:[[:space:]]*"[^"]*shelley-genesis[^"]*"/"ShelleyGenesisFile": "sgenesis.json"/' \
    -e 's/"AlonzoGenesisFile"[[:space:]]*:[[:space:]]*"[^"]*alonzo-genesis[^"]*"/"AlonzoGenesisFile": "agenesis.json"/' \
    -e 's/"ConwayGenesisFile"[[:space:]]*:[[:space:]]*"[^"]*conway-genesis[^"]*"/"ConwayGenesisFile": "cgenesis.json"/' \
    "$cfg"

  # ---- 2) Ports and log scribe paths per node type ----
  local ekg_port prometheus_port log_path

  if [[ "$node_type" == "bp" ]]; then
    ekg_port=12789
    prometheus_port=12799
    log_path="$HOME/node.bp/logs/node0.json"
  else
    ekg_port=12788
    prometheus_port=12798
    log_path="$HOME/node.relay/logs/node0.json"
  fi

  # ---- 3) Patch JSON safely with jq using a heredoc filter ----
  local tmp
  tmp="$(mktemp)"

  jq \
    --argjson ekg "$ekg_port" \
    --argjson pport "$prometheus_port" \
    --arg logPath "$log_path" \
    -f <(cat <<'JQFILTER'
# --- hasEKG ---
(if has("hasEKG") then .hasEKG = $ekg else . end)

# --- hasPrometheus ---
| .hasPrometheus = ["127.0.0.1", $pport]

# --- defaultScribes: ensure Stdout + canonical FileSK(logPath) ---
| .defaultScribes =
    (
      (.defaultScribes // [])
      | map(select(type=="array" and length==2))
      | ( if any(.[]; .[0]=="StdoutSK" and .[1]=="stdout")
          then .
          else . + [["StdoutSK","stdout"]]
        end
        )
      | ( map(select(.[0]!="FileSK"))
          + [["FileSK",$logPath]]
        )
    )

# --- setupScribes: ensure Stdout + canonical FileSK(logPath) with ScJson ---
| .setupScribes =
    (
      (.setupScribes // [])
      | map(select(type=="object"))
      | ( if any(.[]; .scKind=="StdoutSK" and .scName=="stdout")
          then .
          else . + [{
            scFormat: "ScText",
            scKind: "StdoutSK",
            scName: "stdout",
            scRotation: null
          }]
        end
        )
      | ( map(select(.scKind!="FileSK"))
          + [{
            scKind: "FileSK",
            scName: $logPath,
            scFormat: "ScJson",
            scRotation: null
          }]
        )
    )
JQFILTER
) "$cfg" > "$tmp"

  mv "$tmp" "$cfg"
}

build_topology() {
  local node_dir="$1"
  local node_type="$2"
  local bp_ip="$3"
  shift 3

  # Next arguments: relay_ips array, then a literal marker, then relay_names array
  # Usage: build_topology "$NODE_DIR" "$NODE_TYPE" "$BP_IP" "${RELAY_IPS[@]}" --names "${RELAY_NAMES[@]}"
  local relay_ips=()
  local relay_names=()
  local parsing_names=0
  for arg in "$@"; do
    if [[ "$arg" == "--names" ]]; then
      parsing_names=1
      continue
    fi
    if (( parsing_names == 0 )); then
      relay_ips+=("$arg")
    else
      relay_names+=("$arg")
    fi
  done

  local topo="$HOME/$node_dir/config/topology_test.json"

  if [[ "$node_type" == "bp" ]]; then
    # Build localRoots.accessPoints from relay list
    local n="${#relay_ips[@]}"
    (( n > 0 )) || die "BP topology: no relays provided in pool_topology"

    # If relay_names missing, generate default names
    if (( ${#relay_names[@]} != n )); then
      relay_names=()
      for ((i=0; i<n; i++)); do relay_names+=("Relay$((i+1))"); done
    fi

    # Build accessPoints array
    local access_points
    access_points="$(
      for ((i=0; i<n; i++)); do
        jq -n --arg a "${relay_ips[$i]}" --arg n "${relay_names[$i]}" --argjson p "$RELAY_PORT" \
          '{address:$a, port:$p, name:$n}'
      done | jq -s .
    )"

    jq -n \
      --argjson ap "$access_points" \
      --argjson val "$n" \
      '{
        localRoots: [
          {
            accessPoints: $ap,
            advertise: false,
            trustable: true,
            valency: $val
          }
        ],
        publicRoots: [
          {
            accessPoints: [],
            advertise: false
          }
        ]
      }' > "$topo"

  else
    # Relay topology: put BP in localRoots.
    # Keep publicRoots empty for now (you can later add bootstrap peers if desired).
    local access_points
    access_points="$(jq -n --arg a "$bp_ip" --arg n "BP" --argjson p "$BP_PORT" \
      '[{address:$a, port:$p, name:$n}]'
    )"

    jq -n \
      --argjson ap "$access_points" \
      '{
        localRoots: [
          {
            accessPoints: $ap,
            advertise: false,
            trustable: true,
            valency: 1
          }
        ],
        publicRoots: [
          {
            accessPoints: [],
            advertise: false
          }
        ]
      }' > "$topo"
  fi

  jq . "$topo" >/dev/null
}


write_run_scripts() {
  local node_dir="$1"
  local node_type="$2"
  local node_bin="$3"
  local env_name="$4"
  local port="$5"

  local run_relaylike="$HOME/$node_dir/run.relaylike.sh"
  local run_bp="$HOME/$node_dir/run.bp.sh"

  # Relay-like runner (safe for BP sync as well because it has no KES/VRF/opcert args)
  cat > "$run_relaylike" <<EOF
#!/bin/bash
set -euo pipefail

NODE_HOME="\$HOME/$node_dir"
export CARDANO_NODE_SOCKET_PATH="\$NODE_HOME/socket/node.socket"

exec "$node_bin" run \\
  --topology "\$NODE_HOME/config/topology.json" \\
  --database-path "\$NODE_HOME/db" \\
  --socket-path "\$NODE_HOME/socket/node.socket" \\
  --host-addr 0.0.0.0 \\
  --port $port \\
  --config "\$NODE_HOME/config/config.json"
EOF
  chmod +x "$run_relaylike"

  # BP runner placeholder (producing mode): kept but NOT used until you add KES/VRF/opcert
  # We keep it as a template so you can "promote" later safely.
  cat > "$run_bp" <<'EOF'
#!/bin/bash
set -euo pipefail

NODE_HOME="$(cd "$(dirname "$0")" && pwd)"
export CARDANO_NODE_SOCKET_PATH="$NODE_HOME/socket/node.socket"

# TODO: Promote to producing BP by adding:
# --shelley-kes-key <kes.skey>
# --shelley-vrf-key <vrf.skey>
# --shelley-operational-certificate <node.cert>
# Keep cold keys OFF this machine.

exec cardano-node run \
  --topology "$NODE_HOME/config/topology.json" \
  --database-path "$NODE_HOME/db" \
  --socket-path "$NODE_HOME/socket/node.socket" \
  --host-addr 0.0.0.0 \
  --port __BP_PORT__ \
  --config "$NODE_HOME/config/config.json"
EOF
  # Patch placeholders
  sed -i "s|exec cardano-node|exec $node_bin|g" "$run_bp"
  sed -i "s|__BP_PORT__|$BP_PORT|g" "$run_bp"
  chmod +x "$run_bp"
}

install_systemd_unit() {
  local node_dir="$1"
  local node_type="$2"
  local svc_name="$3"
  local run_script="$4"

  local unit_path="/etc/systemd/system/${svc_name}.service"

  log "Installing systemd unit: ${svc_name}.service"

  cat > "/tmp/${svc_name}.service" <<EOF
[Unit]
Description=Cardano ${node_type} Node (${ENV_NAME})
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/$node_dir
Environment=SPOT_PATH=$SPOT_DIR
Environment=CARDANO_NODE_SOCKET_PATH=$HOME/$node_dir/socket/node.socket
Restart=always
RestartSec=5
LimitNOFILE=131072
ExecStart=/bin/bash -lc '$run_script'
KillSignal=SIGTERM
TimeoutStopSec=60
SuccessExitStatus=143
SyslogIdentifier=${svc_name}

[Install]
WantedBy=multi-user.target
EOF

  sudo mv "/tmp/${svc_name}.service" "$unit_path"
  sudo systemctl daemon-reload
  sudo systemctl enable "$svc_name"
}

install_gliveview() {
  local node_dir="$1"
  local port="$2"

  local home="$HOME/$node_dir"
  log "Installing gLiveView into $home"

  ( cd "$home" && \
    curl -fLsS -o gLiveView.sh "https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/gLiveView.sh" && \
    curl -fLsS -o env "https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/env" && \
    chmod 755 gLiveView.sh
  )

  # Patch env file robustly: replace line if exists, else append
  set_kv() {
    local key="$1"
    local value="$2"
    local file="$3"
    if grep -qE "^${key}=" "$file"; then
      sed -i "s|^${key}=.*|${key}=${value}|g" "$file"
    else
      echo "${key}=${value}" >> "$file"
    fi
  }

  local envf="$home/env"
  set_kv "CNODE_HOME" "\"\${HOME}/$node_dir\"" "$envf"
  set_kv "CNODE_PORT" "$port" "$envf"
  set_kv "CONFIG" "\"\${CNODE_HOME}/config/config.json\"" "$envf"
  set_kv "SOCKET" "\"\${CNODE_HOME}/socket/node.socket\"" "$envf"
  set_kv "TOPOLOGY" "\"\${CNODE_HOME}/config/topology.json\"" "$envf"
  set_kv "LOG_DIR" "\"\${CNODE_HOME}/logs\"" "$envf"
  set_kv "DB_DIR" "\"\${CNODE_HOME}/db\"" "$envf"
}

# ------------------------------------------------------------
# main
# ------------------------------------------------------------
log "INIT_PART2 STARTING..."
log "SCRIPT_DIR:  $SCRIPT_DIR"
log "SPOT_DIR:    $SPOT_DIR"
log "CONFIG_DIR:  $CONFIG_DIR"
log "NS_PATH:     $NS_PATH"

[[ -f "$TOPO_FILE" ]] || die "Topology file not found: $TOPO_FILE"
[[ -f "$NS_PATH/utils.sh" ]] || die "utils.sh not found: $NS_PATH/utils.sh"

# Import utilities (expects get_topo)
# shellcheck source=/dev/null
source "$NS_PATH/utils.sh"

# Ensure dependencies for JSON + fetch + basic tooling
apt_install_if_missing jq curl bc tcptraceroute

log "Reading pool topology and node identity..."
read -r ERROR NODE_TYPE BP_IP RELAYS < <(get_topo "$TOPO_FILE")
# shellcheck disable=SC2206
RELAYS=($RELAYS)

if [[ "$ERROR" != "none" ]]; then
  die "$ERROR"
fi
[[ -n "${NODE_TYPE:-}" ]] || die "NODE_TYPE not identified by get_topo()"

log "Local IP detected as: $(hostname -I | awk '{print $1}')"
log "Topology file contents:"
sed 's/^/  /' "$TOPO_FILE"

[[ "$NODE_TYPE" == "bp" || "$NODE_TYPE" == "relay" ]] \
  || die "This host IP does not match any bp/relay entry in $TOPO_FILE (NODE_TYPE=$NODE_TYPE). Check pool_topology vs hostname -I"

[[ -n "${BP_IP:-}" ]] || die "BP_IP empty; check pool_topology format"

# get_topo output format:
# echo "$ERROR $NODE_TYPE $BP_IP ${RELAY_IPS[@]} ${RELAY_NAMES[@]} ${RELAY_IPS_PUB[@]}"
#
# So RELAYS contains 3 concatenated lists: [all relay IPs][all relay names][all relay pub IPs]

cnt=${#RELAYS[@]}

# If there are no relays, cnt can be 0; that's valid (though not recommended).
if (( cnt == 0 )); then
  RELAY_IPS=()
  RELAY_NAMES=()
  RELAY_IPS_PUB=()
else
  (( cnt % 3 == 0 )) || die "RELAYS list length ($cnt) is not divisible by 3. pool_topology or get_topo output may be inconsistent."

  n=$((cnt/3))
  RELAY_IPS=( "${RELAYS[@]:0:$n}" )
  RELAY_NAMES=( "${RELAYS[@]:$n:$n}" )
  RELAY_IPS_PUB=( "${RELAYS[@]:$((2*n)):$n}" )

  # sanity check: each relay should have IP+NAME+PUBIP
  (( ${#RELAY_IPS[@]} == ${#RELAY_NAMES[@]} )) || die "Relay IP/name count mismatch"
  (( ${#RELAY_IPS[@]} == ${#RELAY_IPS_PUB[@]} )) || die "Relay IP/pubIP count mismatch"
fi

log "NODE_TYPE:     $NODE_TYPE"
log "BP_IP:         $BP_IP"
log "RELAY_IPS:     ${RELAY_IPS[*]:-none}"
log "RELAY_NAMES:   ${RELAY_NAMES[*]:-none}"
log "RELAY_IPS_PUB: ${RELAY_IPS_PUB[*]:-none}"

NODE_DIR="node.bp"
NODE_PORT="$BP_PORT"
if [[ "$NODE_TYPE" == "relay" ]]; then
  NODE_DIR="node.relay"
  NODE_PORT="$RELAY_PORT"
fi

if (( ONLY_TOPOLOGY == 1 )); then
  log "Topology-only mode enabled: regenerating topology.json and exiting."
  build_topology "$NODE_DIR" "$NODE_TYPE" "$BP_IP" "${RELAY_IPS[@]}" --names "${RELAY_NAMES[@]}"
  log "Done. Wrote: $HOME/$NODE_DIR/config/topology.json"
  exit 0
fi


log "Preparing directories under ~/$NODE_DIR ..."
ensure_dir_layout "$NODE_DIR"
ensure_bashrc_block "$NODE_DIR"

log "Discovering cardano binaries..."
read -r CARDANO_NODE_BIN CARDANO_CLI_BIN < <(discover_binaries)
log "cardano-node: $CARDANO_NODE_BIN"
log "cardano-cli:  $CARDANO_CLI_BIN"
log "Versions:"
"$CARDANO_NODE_BIN" --version || true
"$CARDANO_CLI_BIN" --version || true

log "Downloading preprod config/genesis/topology..."
cd "$HOME/$NODE_DIR/config"

if [[ "$NODE_TYPE" == "bp" ]]; then
  fetch "$BASE_URL/config-bp.json" "config.json"
else
  fetch "$BASE_URL/config.json" "config.json"
fi
fetch "$BASE_URL/byron-genesis.json" "bgenesis.json"
fetch "$BASE_URL/shelley-genesis.json" "sgenesis.json"
fetch "$BASE_URL/alonzo-genesis.json" "agenesis.json"
fetch "$BASE_URL/conway-genesis.json" "cgenesis.json"
fetch "$BASE_URL/topology.json" "topology.json"

# Minimal safe config patches (genesis names + EKG ports)
log "Patching config.json (minimal)..."
patch_config_minimal "$NODE_DIR" "$NODE_TYPE"

# Build node-specific topology.json
log "Building node-specific topology.json..."
build_topology "$NODE_DIR" "$NODE_TYPE" "$BP_IP" "${RELAY_IPS[@]}" --names "${RELAY_NAMES[@]}"


# Write run scripts
log "Writing run scripts..."
write_run_scripts "$NODE_DIR" "$NODE_TYPE" "$CARDANO_NODE_BIN" "$ENV_NAME" "$NODE_PORT"

# Install systemd unit
if [[ "$NODE_TYPE" == "relay" ]]; then
  install_systemd_unit "$NODE_DIR" "$NODE_TYPE" "run.relay" "$HOME/$NODE_DIR/run.relaylike.sh"
else
  # For BP we initially use relaylike runner to sync safely
  install_systemd_unit "$NODE_DIR" "$NODE_TYPE" "run.bp" "$HOME/$NODE_DIR/run.relaylike.sh"
fi

# Install gLiveView (optional but useful)
log "Installing gLiveView..."
install_gliveview "$NODE_DIR" "$NODE_PORT"

log "INIT_PART2 COMPLETED."

echo
echo "Next:"
if [[ "$NODE_TYPE" == "bp" ]]; then
  echo "  Start BP (sync-safe relay-like mode):  sudo systemctl start run.bp"
  echo "  View logs:                            journalctl -u run.bp -f"
  echo "  gLiveView:                            cd ~/$NODE_DIR && ./gLiveView.sh"
else
  echo "  Start relay:                           sudo systemctl start run.relay"
  echo "  View logs:                             journalctl -u run.relay -f"
  echo "  gLiveView:                             cd ~/$NODE_DIR && ./gLiveView.sh"
fi
echo
echo "Note: chain DB copying + binary distribution is handled in init_part3.sh (not here)."
