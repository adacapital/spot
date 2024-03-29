#!/bin/bash

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
TOPO_FILE=~/pool_topology
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"

echo "INIT SCRIPT STARTING..."
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "NS_PATH: $NS_PATH"
echo

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

# starting binaries update script if we are on the bp node
if [[ $NODE_TYPE == "bp" ]]; then
    sudo unattended-upgrade -d
    sudo apt-get update -y
    sudo apt-get upgrade -y

    cardano-cli --version

    echo
    echo '---------------- Updating the node from source ---------------- '

    CARDANO_NODE_CLONE_DIR=~/download/cardano-node
    if [ ! -d "$CARDANO_NODE_CLONE_DIR" ]; then
        echo "Cloning cardano-node source."
        cd ~/download
        git clone https://github.com/input-output-hk/cardano-node.git
        cd ~/download/cardano-node
    else
        echo "Updating cardano-node source."
        cd ~/download/cardano-node
        git fetch --all --recurse-submodules --tags
    fi

    # git fetch --all --tags
    # git checkout "tags/$1"
    # git checkout p2p-master-1.31.0
    # git checkout karknu/blockfetch_order
    git checkout "$1"

    echo
    git describe --tags

    echo
    if ! promptyn "Is this the correct tag? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi

    cabal clean
    cabal update
    cabal build all

    echo
    if ! promptyn "Build complete, ready to stop/restart services? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi

    echo
    echo '---------------- Stopping node services ---------------- '
    sudo systemctl stop cncli_sync
    sudo systemctl stop run.relay
    sudo systemctl stop run.bp

    cp -p "$($SPOT_PATH/scripts/bin_path.sh cardano-cli)" ~/.local/bin/
    cp -p "$($SPOT_PATH/scripts/bin_path.sh cardano-node)" ~/.local/bin/
    cardano-cli --version

    echo
    echo '---------------- Starting node services ---------------- '
    sudo systemctl start run.relay
    sudo systemctl start run.bp
    sudo systemctl start cncli_sync

    echo 'Node binaries update completed!'
else
    echo "Node binaries update should be run from the BP node! Bye for now..."
fi