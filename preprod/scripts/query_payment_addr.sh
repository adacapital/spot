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

# echo "MAGIC: $MAGIC"

if [[ $# -eq 1 && ! $1 == "" ]]; then PAYMENT_ADDR=$1; ADV_FLAG="N"; 
elif [[ $# -eq 2 && ! $1 == "" && ! $2 == "" ]]; then 
    PAYMENT_ADDR=$1; 
    ADV_FLAG="N";
    if [[ $2 == "-a" ]]; then
        ADV_FLAG="Y";
    fi
else echo -e "This script requires input parameters:\n\tUsage: $0 {payment_addr} -a {advanced flag:optional}"; exit 2; fi

if [[ $ADV_FLAG == "N" ]]; then
    cardano-cli query utxo --address $PAYMENT_ADDR --testnet-magic $MAGIC
else
    rm -f /tmp/query_payment_addr.out /tmp/utxos.out
    cardano-cli query utxo --address $PAYMENT_ADDR --testnet-magic $MAGIC > /tmp/query_payment_addr.out
    cat /tmp/query_payment_addr.out

    tail -n +3 /tmp/query_payment_addr.out | sort -k3 -nr > /tmp/utxos.out

    TX_IN=""
    TOTAL_BALANCE=0
    while read -r UTXO; do
        UTXO_HASH=$(awk '{ print $1 }' <<< "${UTXO}")
        UTXO_TXIX=$(awk '{ print $2 }' <<< "${UTXO}")
        UTXO_BALANCE=$(awk '{ print $3 }' <<< "${UTXO}")
        TOTAL_BALANCE=$((${TOTAL_BALANCE}+${UTXO_BALANCE}))
        # echo "TxIn: ${UTXO_HASH}#${UTXO_TXIX}"
        # echo "Lovelace: ${UTXO_BALANCE}"
    done < /tmp/utxos.out
    TXCNT=$(cat /tmp/utxos.out | wc -l)
    TOTAL_BALANCE_FORMATED=`echo $TOTAL_BALANCE | sed -r ':a;s/([0-9])([0-9]{3}([^0-9]|$))/\1,\2/;ta'`
    echo
    echo "Total lovelace balance: $TOTAL_BALANCE_FORMATED"
    echo "UTXO count: $TXCNT"
fi
