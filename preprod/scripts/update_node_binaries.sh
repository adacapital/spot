#!/bin/bash

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT1="$(realpath "$(dirname "$SPOT_DIR")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT1")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=$ROOT_PATH/pool_topology


echo "UPDATE NODE BINARIES STARTING..."
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "ROOT_PATH: $ROOT_PATH"
echo "NS_PATH: $NS_PATH"
echo "TOPO_FILE: $TOPO_FILE"

# importing utility functions
source $NS_PATH/utils.sh

if [[ $# -eq 1 && ! $1 == "" ]]; then nodeName=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 \"{versionTag}\""; exit 2; fi

echo
echo '---------------- Reading pool topology file and preparing a few things... ----------------'

read ERROR NODE_TYPE BP_IP RELAYS < <(get_topo $TOPO_FILE)
RELAYS=($RELAYS)
cnt=${#RELAYS[@]}
let cnt1="$cnt/3"
let cnt2="$cnt1 + $cnt1"
let cnt3="$cnt2 + $cnt1"

RELAY_IPS=( "${RELAYS[@]:0:$cnt1}" )
RELAY_NAMES=( "${RELAYS[@]:$cnt1:$cnt1}" )
RELAY_IPS_PUB=( "${RELAYS[@]:$cnt2:$cnt1}" )

if [[ $ERROR == "none" ]]; then
    if [[ $NODE_TYPE == "" ]]; then
        echo "Node type not identified, something went wrong."
        echo "Please fix the underlying issue and run init.sh again."
        exit 1
    else
        echo "NODE_TYPE: $NODE_TYPE"
        echo "RELAY_IPS: ${RELAY_IPS[@]}"
        echo "RELAY_NAMES: ${RELAY_NAMES[@]}"
            echo "RELAY_IPS_PUB: ${RELAY_IPS_PUB[@]}"
    fi
else
    echo "ERROR: $ERROR"
    exit 1
fi

NODE_PATH="$ROOT_PATH/node.bp"
MAGIC=$(get_network_magic)
echo "NODE_PATH: $NODE_PATH"
echo "NETWORK_MAGIC: $MAGIC"

# starting binaries update script if we are on the bp node
if [[ $NODE_TYPE == "bp" ]]; then
    sudo unattended-upgrade -d
    sudo apt-get update -y
    sudo apt-get upgrade -y

    # Per IOG: https://developers.cardano.org/docs/get-started/infrastructure/node/installing-cardano-node/
    # Idempotent — already-installed pkgs are skipped. Catches new deps IOG adds between releases.
    sudo apt-get install -y automake build-essential pkg-config libffi-dev libgmp-dev libssl-dev libncurses-dev libsystemd-dev zlib1g-dev make g++ tmux git jq wget libtool autoconf liblmdb-dev libsnappy-dev protobuf-compiler liburing-dev

    cardano-cli --version

    echo
    echo '---------------- Ensuring GHC and cabal versions (IOG recommended) ----------------'
    ghcup install ghc 9.6.7 --set
    ghcup install cabal 3.12.1.0 --set
    ghc --version
    cabal --version

    echo
    echo '---------------- Updating the node from source ---------------- '
    
    CARDANO_NODE_CLONE_DIR=$ROOT_PATH/cardano-node
    if [ ! -d "$CARDANO_NODE_CLONE_DIR" ]; then
        echo "Cloning cardano-node source."
        cd $ROOT_PATH
        git clone https://github.com/IntersectMBO/cardano-node.git 
        cd $ROOT_PATH/cardano-node
    else
        echo "Updating cardano-node source."
        cd $ROOT_PATH/cardano-node
        git fetch --all --recurse-submodules --tags
    fi


    git fetch --all --recurse-submodules --tags
    git tag | sort -V
    git checkout tags/$1
    

    echo
    git describe --tags

    echo
    if ! promptyn "Is this the correct tag? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi

    echo "with-compiler: ghc-9.6.7" >> cabal.project.local

    cabal clean
    cabal update

    # CABAL_JOBS throttles concurrent ghc workers — defaults to 2 to keep memory
    # use sane on 8GB hosts (cardano-node has been observed to OOM at -j auto).
    # Override with: CABAL_JOBS=4 ./update_node_binaries.sh ...
    CABAL_JOBS="${CABAL_JOBS:-2}"
    BUILD_LOG_NODE="/tmp/build.cardano-node.${NOW}.log"
    BUILD_LOG_CLI="/tmp/build.cardano-cli.${NOW}.log"

    echo
    echo "Building cardano-node (-j$CABAL_JOBS, log: $BUILD_LOG_NODE)..."
    set -o pipefail
    cabal build cardano-node -j"$CABAL_JOBS" 2>&1 | tee "$BUILD_LOG_NODE"
    rc=$?
    set +o pipefail
    if [[ $rc -ne 0 ]]; then
        echo "ERROR: cabal build cardano-node failed (rc=$rc). See $BUILD_LOG_NODE"
        exit 1
    fi

    echo
    echo "Building cardano-cli (-j$CABAL_JOBS, log: $BUILD_LOG_CLI)..."
    set -o pipefail
    cabal build cardano-cli -j"$CABAL_JOBS" 2>&1 | tee "$BUILD_LOG_CLI"
    rc=$?
    set +o pipefail
    if [[ $rc -ne 0 ]]; then
        echo "ERROR: cabal build cardano-cli failed (rc=$rc). See $BUILD_LOG_CLI"
        exit 1
    fi

    # Verify the binaries cabal claimed to build actually exist on disk.
    # plan.json can list a path even if the build step never produced it.
    NODE_BIN_PATH=$("$NS_PATH/bin_path.sh" cardano-node "$ROOT_PATH/cardano-node")
    CLI_BIN_PATH=$("$NS_PATH/bin_path.sh" cardano-cli "$ROOT_PATH/cardano-node")
    for f in "$NODE_BIN_PATH" "$CLI_BIN_PATH"; do
        if [[ ! -x "$f" ]]; then
            echo "ERROR: expected built binary not found or not executable: $f"
            echo "       Logs: $BUILD_LOG_NODE, $BUILD_LOG_CLI"
            exit 1
        fi
    done

    echo
    echo "Build verified:"
    echo "  cardano-node: $NODE_BIN_PATH"
    echo "  cardano-cli:  $CLI_BIN_PATH"
    echo
    if ! promptyn "Build complete, ready to stop/restart services? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi

    echo
    echo '---------------- Stopping node services ---------------- '
    if systemctl cat cncli_sync.service &>/dev/null; then
        echo "Stopping cncli_sync service..."
        sudo systemctl stop cncli_sync
    else
        echo "cncli_sync service not installed on this host — skipping."
    fi
    sudo systemctl stop run.bp

    cp -p "$CLI_BIN_PATH" ~/.local/bin/
    cp -p "$NODE_BIN_PATH" ~/.local/bin/
    cardano-cli --version
    cardano-node --version

    echo
    echo '---------------- Starting node services ---------------- '
    sudo systemctl start run.bp
    if systemctl cat cncli_sync.service &>/dev/null; then
        echo "Starting cncli_sync service..."
        sudo systemctl start cncli_sync
    else
        echo "cncli_sync service not installed on this host — skipping."
    fi

    echo 'Node binaries update completed on BP node!'

    echo
    if ! promptyn "Ready to update binaries for peers? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi

    echo
    echo '---------------- Getting other peers ready... ----------------'

    # Use the BP VM's local SSH identity (default: id_ed25519)
    SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
    SSH_OPTS="-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
    SCP_OPTS="-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

    remote() {
        local ip="$1" cmd="$2"
        ssh $SSH_OPTS -i "$SSH_KEY" "cardano@${ip}" "$cmd"
    }

    remote_scp_to() {
        local ip="$1" src="$2" dst="$3"
        scp $SCP_OPTS -i "$SSH_KEY" "$src" "cardano@${ip}:${dst}"
    }

    RELAYS_COUNT=${#RELAY_IPS[@]}

    for (( i=0; i<${RELAYS_COUNT}; i++ )); do
        ip="${RELAY_IPS[$i]}"
        name="${RELAY_NAMES[$i]}"

        echo
        echo "Relay $name ($ip): checking SSH connectivity..."
        if ! remote "$ip" "echo ok >/dev/null"; then
            echo "Relay $name ($ip): unreachable via SSH (with $SSH_KEY), skipping."
            continue
        fi

        echo "Relay $name ($ip): stopping relay service..."
        remote "$ip" "sudo -n systemctl stop run.relay"

        echo "Relay $name ($ip): copying cardano binaries..."
        remote_scp_to "$ip" "$HOME/.local/bin/cardano-node" "/home/cardano/.local/bin/cardano-node"
        remote_scp_to "$ip" "$HOME/.local/bin/cardano-cli"  "/home/cardano/.local/bin/cardano-cli"
        remote "$ip" "chmod 755 ~/.local/bin/cardano-node ~/.local/bin/cardano-cli && ~/.local/bin/cardano-node --version && ~/.local/bin/cardano-cli --version"

        echo "Relay $name ($ip): starting relay service..."
        remote "$ip" "sudo -n systemctl start run.relay"

        echo "Node binaries update completed on $name node!"
    done

    echo
    echo 'Node binaries update complete!'
else
    echo "Node binaries update should be run from the BP node! Bye for now..."
fi