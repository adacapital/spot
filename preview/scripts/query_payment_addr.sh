#!/bin/bash

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"

# importing utility functions
source $NS_PATH/utils.sh
MAGIC=$(get_network_magic)

if [[ $# -ge 1 && ! $1 == "" ]]; then PAYMENT_ADDR=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 {payment_addr}"; exit 2; fi

cardano-cli query utxo --address $PAYMENT_ADDR --testnet-magic $MAGIC
