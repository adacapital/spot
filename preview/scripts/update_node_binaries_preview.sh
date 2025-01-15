#!/bin/bash

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT1="$(realpath "$(dirname "$SPOT_DIR")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT1")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=$ROOT_PATH/preview/pool_topology


echo "UPDATE NODE BINARIES STARTING..."
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "ROOT_PATH: $ROOT_PATH"
echo "NS_PATH: $NS_PATH"
echo "TOPO_FILE: $TOPO_FILE"

# exit 1

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

NODE_PATH="$ROOT_PATH/preview/node.bp"
MAGIC=$(get_network_magic)
echo "NODE_PATH: $NODE_PATH"
echo "NETWORK_MAGIC: $MAGIC"
echo "NODE_TYPE: $NODE_TYPE"

# exit 1

# starting binaries update script if we are on the bp node
if [[ $NODE_TYPE == "unknown" ]]; then
    # sudo unattended-upgrade -d
    # sudo apt-get update -y
    # sudo apt-get upgrade -y

    cardano-cli --version

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

    # echo "with-compiler: ghc-8.10.7" >> cabal.project.local
    echo "with-compiler: ghc-9.6.3" >> cabal.project.local

    cabal clean
    cabal update
    # cabal build all
    cabal build cardano-node
    cabal build cardano-cli

    echo
    if ! promptyn "Build complete, ready to stop/restart services? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi

    # echo
    # echo '---------------- Stopping node services ---------------- '
    # sudo systemctl stop cncli_sync
    # sudo systemctl stop run.bp

    # cp -p "$($NS_PATH/bin_path.sh cardano-cli $ROOT_PATH/cardano-node)" ~/.local/bin/
    # cp -p "$($NS_PATH/bin_path.sh cardano-node $ROOT_PATH/cardano-node)" ~/.local/bin/
    # cardano-cli --version
    # cardano-node --version

    # echo
    # echo '---------------- Starting node services ---------------- '
    # sudo systemctl start run.bp
    # sudo systemctl start cncli_sync

    # echo 'Node binaries update completed on BP node!'

    echo
    echo 'Node binaries update complete!'
else
    echo "Node binaries update should be run from the BP node! Bye for now..."
fi