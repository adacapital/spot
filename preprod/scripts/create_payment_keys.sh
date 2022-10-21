#!/bin/bash
# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=~/pool_topology

# importing utility functions
source $NS_PATH/utils.sh
MAGIC=$(get_network_magic)
echo "NETWORK_MAGIC: $MAGIC"

if [[ $# -eq 1 && ! $1 == "" ]]; then key_name=$1; key_dir="$HOME/keys" else echo -e "This script requires input parameters:\n\tUsage: $0 {key_name} {out_dir:optional}"; exit 2; 
elif [[ $# -eq 2 && ! $1 == "" && ! $2 == "" ]]; then key_name=$1; key_dir=$2; else echo -e "This script requires input parameters:\n\tUsage: $0 {key_name} {out_dir:optional}"; exit 2; fi

cd $key_dir

# generate payment key pair
cardano-cli address key-gen \
--verification-key-file $key_name.vkey \
--signing-key-file $key_name.skey

chmod 400 $key_name.vkey $key_name.skey

# generate payment address
cardano-cli address build \
--payment-verification-key-file $key_name.vkey \
--out-file $key_name.addr \
--testnet-magic $MAGIC

chmod 400 $key_name.addr