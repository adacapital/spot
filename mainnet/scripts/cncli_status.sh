#!/bin/bash
# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT1="$(realpath "$(dirname "$SPOT_DIR")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT1")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE="$ROOT_PATH/pool_topology"

# echo "SCRIPT_DIR: $SCRIPT_DIR"
# echo "SPOT_DIR: $SPOT_DIR"
# echo "PARENT1: $PARENT1"
# echo "NS_PATH: $NS_PATH"
# echo "ROOT_PATH: $ROOT_PATH"
# echo

cncli status --byron-genesis $ROOT_PATH/node.bp/config/bgenesis.json --shelley-genesis $ROOT_PATH/node.bp/config/sgenesis.json --db $ROOT_PATH/node.bp/cncli/cncli.db