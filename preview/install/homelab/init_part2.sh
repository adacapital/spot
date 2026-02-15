#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# init_part2.sh
# Runtime configuration for Cardano preview nodes (BP, Relay, or Hybrid)
#
# What this script DOES:
# - Reads pool_topology to determine NODE_TYPE (bp|relay|hybrid), BP_IP, relay list
# - For hybrid: sets up BOTH ~/node.bp AND ~/node.relay on the same VM
# - Creates node directory structure under ~/node.bp or ~/node.relay
# - Downloads env config + genesis + book topology (+ peer-snapshot.json)
# - Patches config.json minimally (genesis filenames + EKG/Prometheus + scribes)
# - Patches book topology.json (useLedgerAfterSlot -> 0)
# - Builds node-specific topology behaviour:
#   - BP: keep book topology.json (relay-like) + generate topology_bp.json (local-only)
#   - Relay: keep book topology.json + inject SPOT_LOCAL localRoots (BP + other relays)
# - Writes run scripts
#   - BP: run.relaylike.sh (sync-safe) + run.bp.sh placeholder
#   - Relay: run.relay.sh (normal)
# - Installs systemd service + gLiveView (when binaries exist)
# - Sets SPOT_PATH and CARDANO_NODE_SOCKET_PATH in ~/.bashrc (idempotent block)
#
# Added modes:
#   --topology-only : downloads/patches env files + regenerates topology, then exits
#   --prepare-only  : prepares dirs + downloads/patches env files + regenerates topology, then exits
#                    (skips binary discovery + run scripts + systemd + gLiveView)
#
# What this script DOES NOT do (init_part3.sh / part4):
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

ENV_NAME="${ENV_NAME:-preview}"
# Your port convention:
BP_PORT="${BP_PORT:-3000}"
RELAY_PORT="${RELAY_PORT:-3001}"

# Preprod upstream URLs (Cardano developer portal / book)
BASE_URL="https://book.world.dev.cardano.org/environments/${ENV_NAME}"

ONLY_TOPOLOGY=0
PREPARE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --topology-only) ONLY_TOPOLOGY=1 ;;
    --prepare-only)  PREPARE_ONLY=1 ;;
  esac
done

# ------------------------------------------------------------
# helpers
# ------------------------------------------------------------
die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo -e "\n[$(date +"%F %T")] $*"; }

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

  export SPOT_PATH="$SPOT_DIR"
  export CARDANO_NODE_SOCKET_PATH="$HOME/$node_dir/socket/node.socket"
}

discover_binaries() {
  local node_bin cli_bin
  node_bin="$(command -v cardano-node || true)"
  cli_bin="$(command -v cardano-cli || true)"

  if [[ -z "$node_bin" || -z "$cli_bin" ]]; then
    [[ -x "$HOME/.local/bin/cardano-node" ]] && node_bin="$HOME/.local/bin/cardano-node"
    [[ -x "$HOME/.local/bin/cardano-cli"  ]] && cli_bin="$HOME/.local/bin/cardano-cli"
  fi

  [[ -n "$node_bin" && -x "$node_bin" ]] || die "cardano-node not found in PATH or ~/.local/bin"
  [[ -n "$cli_bin"  && -x "$cli_bin"  ]] || die "cardano-cli not found in PATH or ~/.local/bin"

  echo "$node_bin" "$cli_bin"
}

patch_config_minimal() {
  local node_dir="$1"
  local node_type="$2"
  local cfg="$HOME/$node_dir/config/config.json"

  [[ -f "$cfg" ]] || die "config.json not found at: $cfg (download step failed?)"

  # Ensure genesis filenames match our downloaded local names
  sed -i \
    -e 's/"ByronGenesisFile"[[:space:]]*:[[:space:]]*"[^"]*byron-genesis[^"]*"/"ByronGenesisFile": "bgenesis.json"/' \
    -e 's/"ShelleyGenesisFile"[[:space:]]*:[[:space:]]*"[^"]*shelley-genesis[^"]*"/"ShelleyGenesisFile": "sgenesis.json"/' \
    -e 's/"AlonzoGenesisFile"[[:space:]]*:[[:space:]]*"[^"]*alonzo-genesis[^"]*"/"AlonzoGenesisFile": "agenesis.json"/' \
    -e 's/"ConwayGenesisFile"[[:space:]]*:[[:space:]]*"[^"]*conway-genesis[^"]*"/"ConwayGenesisFile": "cgenesis.json"/' \
    "$cfg"

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

  local tmp
  tmp="$(mktemp)"

  jq \
    --argjson ekg "$ekg_port" \
    --argjson pport "$prometheus_port" \
    --arg logPath "$log_path" \
    -f <(cat <<'JQFILTER'
(if has("hasEKG") then .hasEKG = $ekg else . end)
| .hasPrometheus = ["127.0.0.1", $pport]
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

patch_topology_useLedgerAfterSlot() {
  local topo="$1"
  local new_value="${2:-0}"
  [[ -f "$topo" ]] || die "Topology file not found: $topo"

  local tmp
  tmp="$(mktemp)"
  jq --argjson v "$new_value" '.useLedgerAfterSlot = $v' "$topo" > "$tmp"
  mv "$tmp" "$topo"
}

build_topology() {
  local node_dir="$1"
  local node_type="$2"
  local bp_ip="$3"
  shift 3

  # Args: relay_ips... --names relay_names...
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

  local cfg_dir="$HOME/$node_dir/config"
  local topo_main="$cfg_dir/topology.json"
  local topo_bp="$cfg_dir/topology_bp.json"
  local peer_snapshot="$cfg_dir/peer-snapshot.json"

  mkdir -p "$cfg_dir"

  build_access_points_array() {
    local -n _ips=$1
    local -n _names=$2
    local _port=$3
    local n="${#_ips[@]}"

    if (( ${#_names[@]} != n )); then
      _names=()
      for ((i=0; i<n; i++)); do _names+=("Node$((i+1))"); done
    fi

    (
      for ((i=0; i<n; i++)); do
        jq -n --arg a "${_ips[$i]}" --arg n "${_names[$i]}" --argjson p "$_port" \
          '{address:$a, port:$p, name:$n}'
      done
    ) | jq -s .
  }

  if [[ "$node_type" == "bp" ]]; then
    # BP:
    # - Keep topo_main as BOOK (relay-like) topology.json
    # - Ensure peer-snapshot.json exists
    # - Generate topology_bp.json (local-only relays)
    [[ -f "$peer_snapshot" ]] || fetch "$BASE_URL/peer-snapshot.json" "$peer_snapshot"
    [[ -f "$topo_main" ]] || die "BP: missing $topo_main (download step didn't fetch book topology.json)"

    local n="${#relay_ips[@]}"
    (( n > 0 )) || die "BP topology_bp.json: no relays provided in pool_topology"

    local access_points
    access_points="$(build_access_points_array relay_ips relay_names "$RELAY_PORT")"

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
      }' > "$topo_bp"

    jq . "$topo_bp" >/dev/null
    log "BP: kept book relay-like topology at: $topo_main"
    log "BP: generated true-BP topology at:        $topo_bp"
  else
    # Relay:
    # - Ensure peer-snapshot.json exists
    # - Merge SPOT_LOCAL into book topology localRoots with BP + other relays (excluding self)
    [[ -f "$peer_snapshot" ]] || fetch "$BASE_URL/peer-snapshot.json" "$peer_snapshot"
    [[ -f "$topo_main" ]] || die "Relay: missing $topo_main (download step didn't fetch book topology.json)"

    local self_ip
    self_ip="$(hostname -I | awk '{print $1}')"

    local bp_only_ips=("$bp_ip")
    local bp_only_names=("BP")

    local relay_only_ips=()
    local relay_only_names=()

    for i in "${!relay_ips[@]}"; do
      local rip="${relay_ips[$i]}"
      local rname="${relay_names[$i]:-Relay$((i+1))}"
      [[ "$rip" == "$self_ip" ]] && continue
      relay_only_ips+=("$rip")
      relay_only_names+=("$rname")
    done

    local bp_ap relay_ap local_access_points
    bp_ap="$(build_access_points_array bp_only_ips bp_only_names "$BP_PORT")"
    if (( ${#relay_only_ips[@]} > 0 )); then
      relay_ap="$(build_access_points_array relay_only_ips relay_only_names "$RELAY_PORT")"
      local_access_points="$(jq -n --argjson a "$bp_ap" --argjson b "$relay_ap" '$a + $b')"
    else
      local_access_points="$bp_ap"
    fi

    local tmp
    tmp="$(mktemp)"
    jq \
      --argjson ap "$local_access_points" \
      '
      .localRoots = (.localRoots // []) |
      # Remove prior SPOT_LOCAL blocks (idempotent)
      .localRoots = (.localRoots | map(select((.name? // "") != "SPOT_LOCAL"))) |
      .localRoots += [
        {
          name: "SPOT_LOCAL",
          accessPoints: $ap,
          advertise: false,
          trustable: true,
          valency: ($ap | length)
        }
      ]
      ' "$topo_main" > "$tmp"
    mv "$tmp" "$topo_main"

    jq . "$topo_main" >/dev/null
    log "Relay: updated topology (book template + local peers) at: $topo_main"
  fi
}

write_run_scripts() {
  local node_dir="$1"
  local node_type="$2"
  local node_bin="$3"
  local port="$4"

  local run_relay="$HOME/$node_dir/run.relay.sh"
  local run_relaylike="$HOME/$node_dir/run.relaylike.sh"
  local run_bp="$HOME/$node_dir/run.bp.sh"

  if [[ "$node_type" == "relay" ]]; then
    # Real relay runner
    cat > "$run_relay" <<EOF
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
    chmod +x "$run_relay"
    return 0
  fi

  # BP runners
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
  local node_dir="$1"      # node.bp or node.relay
  local port="$2"          # 3000 or 3001
  local node_type="$3"     # bp or relay

  local home="$HOME/$node_dir"
  log "Installing gLiveView into $home"

  ( cd "$home" && \
    curl -fLsS -o gLiveView.sh "https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/gLiveView.sh" && \
    curl -fLsS -o env         "https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/env" && \
    chmod 755 gLiveView.sh
  )

  # -----------------------
  # Patch env file values (SAFE)
  # Only replace commented defaults "#KEY=..." to avoid breaking jq blocks etc.
  # If the commented default doesn't exist, append KEY=VALUE at end.
  # -----------------------
  set_kv() {
    local key="$1"
    local value="$2"
    local file="$3"

    # Replace ONLY commented template defaults:  ^#\s*KEY=
    if grep -qE "^[[:space:]]*#[[:space:]]*${key}=" "$file"; then
      sed -i -E "s|^[[:space:]]*#[[:space:]]*${key}=.*|${key}=${value}|g" "$file"
    elif grep -qE "^[[:space:]]*${key}=" "$file"; then
      # If there is already an active KEY=... line (rare for these), replace it
      # BUT: this still won’t match PROM_PORT=$(jq...) because we will NOT call set_kv for PROM_* below unless you explicitly want it.
      sed -i -E "s|^[[:space:]]*${key}=.*|${key}=${value}|g" "$file"
    else
      echo "${key}=${value}" >> "$file"
    fi
  }

  local envf="$home/env"

  # CNODE paths
  set_kv "CNODE_HOME" "\"\${HOME}/${node_dir}\"" "$envf"
  set_kv "CNODE_PORT" "${port}"                  "$envf"
  set_kv "CONFIG"     "\"\${CNODE_HOME}/config/config.json\"" "$envf"
  set_kv "SOCKET"     "\"\${CNODE_HOME}/socket/node.socket\"" "$envf"
  set_kv "TOPOLOGY"   "\"\${CNODE_HOME}/config/topology.json\"" "$envf"
  set_kv "LOG_DIR"    "\"\${CNODE_HOME}/logs\"" "$envf"
  set_kv "DB_DIR"     "\"\${CNODE_HOME}/db\""   "$envf"

  # Disable update checks
  set_kv "UPDATE_CHECK" "\"N\"" "$envf"

  # Prometheus: RECOMMENDED to set explicitly to avoid jq auto-detect edge cases
  # IMPORTANT: set_kv as written only targets commented defaults; it won't touch PROM_PORT=$(jq...)
  local prom_port="12798"
  if [[ "$node_type" == "bp" ]]; then
    prom_port="12799"
  fi
  set_kv "PROM_HOST" "127.0.0.1" "$envf"
  set_kv "PROM_PORT" "${prom_port}" "$envf"

  # -----------------------
  # Patch gLiveView.sh defaults
  # -----------------------
  local glive="$home/gLiveView.sh"

  set_glive_var() {
    local key="$1"
    local val="$2"
    if grep -qE "^[[:space:]]*#?[[:space:]]*${key}=" "$glive"; then
      sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}=.*|${key}=${val}|g" "$glive"
    else
      echo "${key}=${val}" >> "$glive"
    fi
  }

  set_glive_var "NODE_NAME" "\"ADACT Node\""
  set_glive_var "REFRESH_RATE" "2"
  set_glive_var "LEGACY_MODE" "false"
  set_glive_var "RETRIES" "3"
  set_glive_var "PEER_LIST_CNT" "10"
  set_glive_var "THEME" "\"dark\""
}

download_env_files() {
  local node_dir="$1"
  local node_type="$2"

  log "Downloading ${ENV_NAME} config/genesis/topology..."
  cd "$HOME/$node_dir/config"

  # Correct templates:
  # - BP uses config-bp.json
  # - Relay uses config.json
  if [[ "$node_type" == "bp" ]]; then
    fetch "$BASE_URL/config-bp.json" "config.json"
  else
    fetch "$BASE_URL/config.json" "config.json"
  fi

  fetch "$BASE_URL/byron-genesis.json" "bgenesis.json"
  fetch "$BASE_URL/shelley-genesis.json" "sgenesis.json"
  fetch "$BASE_URL/alonzo-genesis.json" "agenesis.json"
  fetch "$BASE_URL/conway-genesis.json" "cgenesis.json"
  fetch "$BASE_URL/topology.json" "topology.json"

  # Book topology references peer-snapshot; ensure it's present too
  fetch "$BASE_URL/peer-snapshot.json" "peer-snapshot.json"
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

# shellcheck source=/dev/null
source "$NS_PATH/utils.sh"

apt_install_if_missing jq curl bc tcptraceroute

log "Reading pool topology and node identity..."
read -r ERROR NODE_TYPE BP_IP RELAYS < <(get_topo "$TOPO_FILE")
# shellcheck disable=SC2206
RELAYS=($RELAYS)

[[ "$ERROR" == "none" ]] || die "$ERROR"
[[ -n "${NODE_TYPE:-}" ]] || die "NODE_TYPE not identified by get_topo()"

log "Local IP detected as: $(hostname -I | awk '{print $1}')"
log "Topology file contents:"
sed 's/^/  /' "$TOPO_FILE"

[[ "$NODE_TYPE" == "bp" || "$NODE_TYPE" == "relay" || "$NODE_TYPE" == "hybrid" ]] \
  || die "This host IP does not match any bp/relay entry in $TOPO_FILE (NODE_TYPE=$NODE_TYPE). Check pool_topology vs hostname -I"

[[ -n "${BP_IP:-}" ]] || die "BP_IP empty; check pool_topology format"

cnt=${#RELAYS[@]}
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

  (( ${#RELAY_IPS[@]} == ${#RELAY_NAMES[@]} )) || die "Relay IP/name count mismatch"
  (( ${#RELAY_IPS[@]} == ${#RELAY_IPS_PUB[@]} )) || die "Relay IP/pubIP count mismatch"
fi

log "NODE_TYPE:     $NODE_TYPE"
log "BP_IP:         $BP_IP"
log "RELAY_IPS:     ${RELAY_IPS[*]:-none}"
log "RELAY_NAMES:   ${RELAY_NAMES[*]:-none}"
log "RELAY_IPS_PUB: ${RELAY_IPS_PUB[*]:-none}"

# Set bashrc SOCKET_PATH. For hybrid, default to BP socket (for cardano-cli).
if [[ "$NODE_TYPE" == "hybrid" ]]; then
  ensure_bashrc_block "node.bp"
  log "Hybrid mode: CARDANO_NODE_SOCKET_PATH defaults to node.bp"
  log "WARNING: Hybrid mode runs TWO cardano-node processes on this VM."
  log "Ensure sufficient RAM (minimum 16 GB recommended, 32 GB preferred)."
else
  NODE_DIR_BASHRC="node.bp"
  [[ "$NODE_TYPE" == "relay" ]] && NODE_DIR_BASHRC="node.relay"
  ensure_bashrc_block "$NODE_DIR_BASHRC"
fi

# Determine which node types to set up
SETUP_TYPES=()
if [[ "$NODE_TYPE" == "hybrid" ]]; then
  SETUP_TYPES=("bp" "relay")
else
  SETUP_TYPES=("$NODE_TYPE")
fi

SELF_IP="$(hostname -I | awk '{print $1}')"

for CURRENT_TYPE in "${SETUP_TYPES[@]}"; do
  if [[ "$CURRENT_TYPE" == "bp" ]]; then
    NODE_DIR="node.bp"
    NODE_PORT="$BP_PORT"
  else
    NODE_DIR="node.relay"
    NODE_PORT="$RELAY_PORT"
  fi

  log "====== Setting up $CURRENT_TYPE node in ~/$NODE_DIR ======"

  log "Preparing directories under ~/$NODE_DIR ..."
  ensure_dir_layout "$NODE_DIR"

  # For --topology-only, we still want the book files present and patched consistently.
  download_env_files "$NODE_DIR" "$CURRENT_TYPE"
  log "Patching topology.json (useLedgerAfterSlot -> 0)..."
  patch_topology_useLedgerAfterSlot "$HOME/$NODE_DIR/config/topology.json" 0

  # For hybrid, substitute loopback for local IPs in topology
  TOPO_BP_IP="$BP_IP"
  TOPO_RELAY_IPS=("${RELAY_IPS[@]}")
  if [[ "$NODE_TYPE" == "hybrid" ]]; then
    if [[ "$CURRENT_TYPE" == "relay" ]]; then
      # Relay should reach BP via loopback
      TOPO_BP_IP="127.0.0.1"
    elif [[ "$CURRENT_TYPE" == "bp" ]]; then
      # BP should reach local relay via loopback
      for idx in "${!TOPO_RELAY_IPS[@]}"; do
        if [[ "${TOPO_RELAY_IPS[$idx]}" == "$SELF_IP" ]]; then
          TOPO_RELAY_IPS[$idx]="127.0.0.1"
        fi
      done
    fi
  fi

  if (( ONLY_TOPOLOGY == 1 )); then
    log "Topology-only mode: regenerating topology for $CURRENT_TYPE..."
    build_topology "$NODE_DIR" "$CURRENT_TYPE" "$TOPO_BP_IP" "${TOPO_RELAY_IPS[@]}" --names "${RELAY_NAMES[@]}"
    log "Done. Wrote: $HOME/$NODE_DIR/config/topology.json"
    continue
  fi

  log "Patching config.json (minimal)..."
  patch_config_minimal "$NODE_DIR" "$CURRENT_TYPE"

  log "Building node-specific topology.json..."
  build_topology "$NODE_DIR" "$CURRENT_TYPE" "$TOPO_BP_IP" "${TOPO_RELAY_IPS[@]}" --names "${RELAY_NAMES[@]}"

  if (( PREPARE_ONLY == 1 )); then
    log "Prepare-only mode: skipping binary discovery, run scripts, systemd, gLiveView for $CURRENT_TYPE."
    continue
  fi

  log "Discovering cardano binaries..."
  read -r CARDANO_NODE_BIN CARDANO_CLI_BIN < <(discover_binaries)
  log "cardano-node: $CARDANO_NODE_BIN"
  log "cardano-cli:  $CARDANO_CLI_BIN"
  log "Versions:"
  "$CARDANO_NODE_BIN" --version || true
  "$CARDANO_CLI_BIN" --version || true

  log "Writing run scripts for $CURRENT_TYPE..."
  write_run_scripts "$NODE_DIR" "$CURRENT_TYPE" "$CARDANO_NODE_BIN" "$NODE_PORT"

  if [[ "$CURRENT_TYPE" == "relay" ]]; then
    install_systemd_unit "$NODE_DIR" "$CURRENT_TYPE" "run.relay" "$HOME/$NODE_DIR/run.relay.sh"
  else
    # For BP we initially use relaylike runner to sync safely
    install_systemd_unit "$NODE_DIR" "$CURRENT_TYPE" "run.bp" "$HOME/$NODE_DIR/run.relaylike.sh"
  fi

  log "Installing gLiveView for $CURRENT_TYPE..."
  install_gliveview "$NODE_DIR" "$NODE_PORT" "$CURRENT_TYPE"
done

if (( ONLY_TOPOLOGY == 1 )); then
  log "Topology-only mode complete."
  exit 0
fi

if (( PREPARE_ONLY == 1 )); then
  log "Prepare-only mode complete."
  echo
  echo "Next:"
  echo "  - Run init_part3.sh on BP to distribute binaries (and later DB)."
  echo "  - Then re-run init_part2.sh (without flags) on this host to install systemd + gLiveView."
  echo
  exit 0
fi

log "INIT_PART2 COMPLETED."

echo
echo "Next:"
if [[ "$NODE_TYPE" == "hybrid" ]]; then
  echo "  Start BP  (sync-safe relay-like mode):  sudo systemctl start run.bp"
  echo "  Start Relay:                             sudo systemctl start run.relay"
  echo "  View BP logs:                            journalctl -u run.bp -f"
  echo "  View Relay logs:                         journalctl -u run.relay -f"
  echo "  gLiveView BP:                            cd ~/node.bp && ./gLiveView.sh"
  echo "  gLiveView Relay:                         cd ~/node.relay && ./gLiveView.sh"
elif [[ "$NODE_TYPE" == "bp" ]]; then
  echo "  Start BP (sync-safe relay-like mode):  sudo systemctl start run.bp"
  echo "  View logs:                            journalctl -u run.bp -f"
  echo "  gLiveView:                            cd ~/node.bp && ./gLiveView.sh"
else
  echo "  Start relay:                           sudo systemctl start run.relay"
  echo "  View logs:                             journalctl -u run.relay -f"
  echo "  gLiveView:                             cd ~/node.relay && ./gLiveView.sh"
fi
echo
echo "Note: binary distribution + chain DB copying is handled in init_part3.sh / part4."
