#!/bin/bash

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT1="$(realpath "$(dirname "$SPOT_DIR")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT1")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=$ROOT_PATH/pool_topology
NODE_PATH="$ROOT_PATH/node.bp"

# echo "SCRIPT_DIR: $SCRIPT_DIR"
# echo "SPOT_DIR: $SPOT_DIR"
# echo "ROOT_PATH: $ROOT_PATH"
# echo "NS_PATH: $NS_PATH"
# echo "TOPO_FILE: $TOPO_FILE"

# importing utility functions
source $NS_PATH/utils.sh
MAGIC=$(get_network_magic)

if [[ $# -ge 1 && ! $1 == "" ]]; then STAKE_ADDR=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 {stake_addr}"; exit 2; fi

cardano-cli query stake-address-info --address $STAKE_ADDR --testnet-magic $MAGIC
